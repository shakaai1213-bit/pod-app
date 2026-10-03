//
//  SIWASignInService.swift
//  pod
//
//  Sign in with Apple → backend code-exchange → JWT in Keychain.
//  Per Pod Phase 1 (DDS-POD-AS-VIEW-2026-05-08) primary mission.
//
//  FLOW:
//    1. User taps SignInWithAppleButton in OnboardingView
//    2. ASAuthorizationAppleIDProvider returns identity token + authorization code
//    3. POST identity_token to /api/v1/auth/apple/callback (backend verifies w/ Apple, returns JWT)
//    4. Store JWT + user profile in AuthManager (Keychain)
//    5. Subsequent APIClient calls use Bearer JWT automatically
//
//  Backend endpoint VERIFIED EXISTING 2026-05-09: POST /api/v1/auth/apple/callback
//  in app.api.auth.py. Returns {access_token, refresh_token, token_type, expires_in}
//  with 1h access TTL + 30d refresh TTL (rotation supported).
//
//  Reference: Starfish Sprint 20 — mobile-app-auth.md (architectural decision).
//
//  Owner: Maui 🪝 | Created: 2026-05-09 | Conformance fix: 2026-05-09 04:35 PDT
//

import Foundation
import AuthenticationServices

// MARK: - Errors

enum SIWASignInError: Error, LocalizedError {
    case userCancelled
    case appleAuthFailed(Error)
    case noIdentityToken
    case backendExchangeFailed(statusCode: Int)
    case responseUnreadable
    case connectionFailed
    case keychainStoreFailed

    var errorDescription: String? {
        switch self {
        case .userCancelled:                          return "Sign in cancelled."
        case .appleAuthFailed(let e):                 return "Apple sign-in failed: \(e.localizedDescription)"
        case .noIdentityToken:                        return "No identity token from Apple."
        case .backendExchangeFailed(let code):        return "ORCA rejected sign-in (HTTP \(code))."
        case .responseUnreadable:                     return "Pod could not read ORCA's sign-in reply."
        case .connectionFailed:                       return "Pod could not reach ORCA after Apple sign-in."
        case .keychainStoreFailed:                    return "Pod could not save sign-in on this device."
        }
    }
}

// MARK: - Backend exchange payload
//
// Conforms to backend AppleCallbackRequest / TokenResponse shapes
// (app/api/auth.py and app/services/apple_auth.py). Snake_case field
// names match backend pydantic models exactly.

// APIClient encodes request keys as snake_case. Its response decoder uses
// Swift's default key strategy, so the token response maps keys explicitly.
private struct AppleCallbackRequest: Codable {
    let identityToken: String           // Apple JWS → identity_token
    let appleUserId: String             // Apple's stable sub → apple_user_id
    let deviceId: String
    let clientId: String
    let devicePublicKey: String
    let challengeNonce: String
    let deviceSignature: String
}

struct AppleCallbackResponse: Codable {
    let accessToken: String             // ORCA JWT, 1h TTL ← access_token
    let refreshToken: String            // 30d TTL, rotated ← refresh_token
    let tokenType: String               // "bearer" ← token_type
    let expiresIn: Int                  // Seconds ← expires_in
    let organizationId: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case organizationId = "organization_id"
    }
}

private struct NativeChallengeRequest: Codable {
    let clientId: String
    let deviceId: String
    let devicePublicKey: String
    let operation: String
}

private struct NativeChallengeResponse: Codable { let nonce: String }

// MARK: - Service

@MainActor
final class SIWASignInService: NSObject {
    private static let clientID = "com.orcamc.pod"
    private let tokenManager: any TokenManaging
    private let apiClient: APIClient

    /// Backend endpoint that verifies Apple's identity_token + returns ORCA JWT pair.
    /// Verified live in `openclaw-mission-control-backend-1` 2026-05-09.
    private let exchangeEndpoint = "/api/v1/auth/apple/callback"

    /// Active continuation for the in-flight Apple sign-in.
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    init(tokenManager: any TokenManaging, apiClient: APIClient) {
        self.tokenManager = tokenManager
        self.apiClient = apiClient
        super.init()
    }

    // MARK: - Public flow

    /// Start the full sign-in flow. Call from a button tap.
    /// On success, JWT is in Keychain and AuthManager has the active user set.
    func signIn() async throws -> StoredToken {
        // 1. Apple authorization
        let credential = try await requestAppleCredential()

        // 2. Extract identity token + authorization code
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw SIWASignInError.noIdentityToken
        }
        let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        // 3. Exchange with backend (note: authCode + fullName captured but not sent —
        //    backend doesn't currently use them; kept here in case Sprint C
        //    audit recommends capturing for first-sign-in name backfill.)
        _ = authCode
        _ = credential.fullName
        return try await completeSignIn(
            identityToken: identityToken,
            appleUserId: credential.user
        )
    }

    /// The production path after Apple's sheet returns. Tests call this with
    /// synthetic Apple claims to exercise the backend exchange and token store.
    func completeSignIn(identityToken: String, appleUserId: String) async throws -> StoredToken {
        let response = try await exchangeWithBackend(
            identityToken: identityToken,
            appleUserId: appleUserId,
            deviceId: OrcaDeviceIdentity.current()
        )

        // 4. Store JWT pair in Keychain. We don't yet have a userId from this
        //    response (backend's TokenResponse omits it); decode the access_token
        //    `sub` claim or call /auth/validate to resolve. For now use a
        //    deterministic UUID-from-apple-sub until Sprint C settles this.
        let now = Date()
        let userId = userIdFromAppleSub(appleUserId)
        let token = StoredToken(
            userId: userId,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(response.expiresIn)),
            issuedAt: now
        )
        do {
            try await tokenManager.storeToken(token, for: userId)
            await tokenManager.setActiveUser(userId)
        } catch {
            throw SIWASignInError.keychainStoreFailed
        }

        return token
    }

    /// Deterministic UUID derived from Apple's stable sub.
    /// Temporary until backend's TokenResponse exposes user_id (Sprint C decision).
    private func userIdFromAppleSub(_ sub: String) -> UUID {
        let bytes = Array(sub.utf8)
        var uuidBytes: [UInt8] = Array(repeating: 0, count: 16)
        for (i, b) in bytes.prefix(16).enumerated() { uuidBytes[i] = b }
        return UUID(uuid: (uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                           uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                           uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                           uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]))
    }

    // MARK: - Apple authorization

    private func requestAppleCredential() async throws -> ASAuthorizationAppleIDCredential {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Backend exchange

    private func exchangeWithBackend(
        identityToken: String,
        appleUserId: String,
        deviceId: String
    ) async throws -> AppleCallbackResponse {
        let challenge: NativeChallengeResponse
        do {
            challenge = try await apiClient.unauthenticatedPost(
                path: "/api/v1/auth/native/challenge",
                body: NativeChallengeRequest(
                    clientId: Self.clientID,
                    deviceId: deviceId,
                    devicePublicKey: OrcaDeviceIdentity.publicKey(),
                    operation: "apple_callback"
                )
            )
        } catch {
            throw Self.mapExchangeError(error)
        }
        let body = AppleCallbackRequest(
            identityToken: identityToken,
            appleUserId: appleUserId,
            deviceId: deviceId,
            clientId: Self.clientID,
            devicePublicKey: OrcaDeviceIdentity.publicKey(),
            challengeNonce: challenge.nonce,
            deviceSignature: try OrcaDeviceIdentity.proof(
                operation: "apple_callback",
                clientID: Self.clientID,
                nonce: challenge.nonce,
                token: identityToken
            )
        )

        // Use unauthenticatedPost — the SIWA exchange itself has no bearer yet.
        do {
            return try await apiClient.unauthenticatedPost(path: exchangeEndpoint, body: body)
        } catch {
            throw Self.mapExchangeError(error)
        }
    }

    private static func mapExchangeError(_ error: Error) -> SIWASignInError {
        if error is APIClientResponseError { return .responseUnreadable }
        if let apiError = error as? APIError {
            return .backendExchangeFailed(statusCode: apiError.code)
        }
        return .connectionFailed
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension SIWASignInService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { self.continuation = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            self.continuation?.resume(throwing: SIWASignInError.noIdentityToken)
            return
        }
        self.continuation?.resume(returning: credential)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { self.continuation = nil }
        if let err = error as? ASAuthorizationError, err.code == .canceled {
            self.continuation?.resume(throwing: SIWASignInError.userCancelled)
        } else {
            self.continuation?.resume(throwing: SIWASignInError.appleAuthFailed(error))
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension SIWASignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Best-effort: first key window. SwiftUI scenes will provide a real anchor in production.
        ASPresentationAnchor()
    }
}
