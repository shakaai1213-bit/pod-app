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
//    3. POST identity_token to /api/v1/auth/siwa/exchange (backend verifies w/ Apple, returns JWT)
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
    case backendExchangeFailed(statusCode: Int, message: String)
    case malformedJWTResponse
    case keychainStoreFailed(Error)

    var errorDescription: String? {
        switch self {
        case .userCancelled:                          return "Sign in cancelled."
        case .appleAuthFailed(let e):                 return "Apple sign-in failed: \(e.localizedDescription)"
        case .noIdentityToken:                        return "No identity token from Apple."
        case .backendExchangeFailed(let code, let m): return "Auth exchange failed (\(code)): \(m)"
        case .malformedJWTResponse:                   return "Auth response missing JWT."
        case .keychainStoreFailed(let e):             return "Keychain store failed: \(e.localizedDescription)"
        }
    }
}

// MARK: - Backend exchange payload
//
// Conforms to backend AppleCallbackRequest / TokenResponse shapes
// (app/api/auth.py and app/services/apple_auth.py). Snake_case field
// names match backend pydantic models exactly.

// Property names use Swift camelCase; APIClient's encoder/decoder
// handles snake_case conversion automatically (.convertToSnakeCase /
// .convertFromSnakeCase). Backend pydantic models match snake_case.
private struct AppleCallbackRequest: Codable {
    let identityToken: String           // Apple JWS → identity_token
    let appleUserId: String             // Apple's stable sub → apple_user_id
    let deviceId: String?               // Session telemetry → device_id
}

private struct AppleCallbackResponse: Codable {
    let accessToken: String             // ORCA JWT, 1h TTL ← access_token
    let refreshToken: String            // 30d TTL, rotated ← refresh_token
    let tokenType: String               // "bearer" ← token_type
    let expiresIn: Int                  // Seconds ← expires_in
}

// MARK: - Service

@MainActor
final class SIWASignInService: NSObject {
    private let tokenManager: TokenManager
    private let apiClient: APIClient

    /// Backend endpoint that verifies Apple's identity_token + returns ORCA JWT pair.
    /// Verified live in `openclaw-mission-control-backend-1` 2026-05-09.
    private let exchangeEndpoint = "/api/v1/auth/apple/callback"

    /// Active continuation for the in-flight Apple sign-in.
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    init(tokenManager: TokenManager, apiClient: APIClient) {
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
        let response = try await exchangeWithBackend(
            identityToken: identityToken,
            appleUserId: credential.user,
            deviceId: await currentDeviceId()
        )

        // 4. Store JWT pair in Keychain. We don't yet have a userId from this
        //    response (backend's TokenResponse omits it); decode the access_token
        //    `sub` claim or call /auth/validate to resolve. For now use a
        //    deterministic UUID-from-apple-sub until Sprint C settles this.
        let now = Date()
        let userId = userIdFromAppleSub(credential.user)
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
            throw SIWASignInError.keychainStoreFailed(error)
        }

        return token
    }

    /// Best-effort device identifier for backend session telemetry.
    /// Falls back to a per-install UUID stored in UserDefaults.
    private func currentDeviceId() async -> String {
        let key = "pod.device_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
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
        deviceId: String?
    ) async throws -> AppleCallbackResponse {
        let body = AppleCallbackRequest(
            identityToken: identityToken,
            appleUserId: appleUserId,
            deviceId: deviceId
        )

        // Use unauthenticatedPost — the SIWA exchange itself has no bearer yet.
        do {
            return try await apiClient.unauthenticatedPost(path: exchangeEndpoint, body: body)
        } catch {
            throw SIWASignInError.backendExchangeFailed(
                statusCode: -1,
                message: "Until APIClient.unauthenticatedPost exists: \(error.localizedDescription)"
            )
        }
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
