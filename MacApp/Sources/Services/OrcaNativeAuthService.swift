import Foundation

enum OrcaNativeAuthError: Error, LocalizedError {
    case missingSession
    case invalidResponse
    case rejected(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Sign in to ORCA to continue."
        case .invalidResponse:
            return "ORCA returned an unreadable sign-in response."
        case let .rejected(status, detail):
            return "ORCA sign-in failed (HTTP \(status)): \(detail)"
        }
    }
}

enum OrcaDeviceIdentity {
    private static let key = "orca.mac.device-id"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key), existing.count >= 16 {
            return existing
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: key)
        return value
    }
}

private struct NativeTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

private struct AppleExchangeRequest: Encodable {
    let identityToken: String
    let appleUserId: String
    let deviceId: String
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
    let deviceId: String
}

private struct LogoutRequest: Encodable {
    let refreshToken: String
    let deviceId: String
}

actor OrcaNativeAuthService {
    static let clientID = "com.orcamc.mac"

    private let serverURL: URL
    private let tokenStore: any RuntimeTokenStoring
    private let session: URLSession
    private let deviceID: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        serverURL: URL,
        tokenStore: any RuntimeTokenStoring,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        self.serverURL = serverURL
        self.tokenStore = tokenStore
        self.session = session
        deviceID = OrcaDeviceIdentity.current(defaults: defaults)
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func exchange(identityToken: String, appleUserID: String) async throws {
        let response = try await post(
            "/api/v1/auth/apple/callback",
            AppleExchangeRequest(
                identityToken: identityToken,
                appleUserId: appleUserID,
                deviceId: deviceID
            )
        )
        try await store(response)
    }

    func validAccessToken() async throws -> String {
        guard let credential = try await tokenStore.loadCredential() else {
            throw OrcaNativeAuthError.missingSession
        }
        guard credential.clientID == Self.clientID,
              credential.deviceID == deviceID else {
            try await tokenStore.deleteCredential()
            throw OrcaNativeAuthError.missingSession
        }
        if credential.needsRefresh {
            let response = try await post(
                "/api/v1/auth/refresh",
                RefreshRequest(refreshToken: credential.refreshToken, deviceId: deviceID)
            )
            try await store(response)
            return response.accessToken
        }
        return credential.accessToken
    }

    func logout() async throws {
        guard let credential = try await tokenStore.loadCredential() else { return }
        _ = try await post(
            "/api/v1/auth/logout",
            LogoutRequest(refreshToken: credential.refreshToken, deviceId: deviceID),
            expectsTokenResponse: false
        )
        try await tokenStore.deleteCredential()
    }

    func boundDeviceID() -> String { deviceID }

    private func store(_ response: NativeTokenResponse) async throws {
        try await tokenStore.storeCredential(
            RuntimeCredential(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
                clientID: Self.clientID,
                deviceID: deviceID
            )
        )
    }

    private func post<Body: Encodable>(
        _ path: String,
        _ body: Body,
        expectsTokenResponse: Bool = true
    ) async throws -> NativeTokenResponse {
        guard let url = URL(string: path, relativeTo: serverURL)?.absoluteURL else {
            throw OrcaNativeAuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-ORCA-Device-ID")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrcaNativeAuthError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw OrcaNativeAuthError.rejected(http.statusCode, detail ?? "request rejected")
        }
        if !expectsTokenResponse {
            return NativeTokenResponse(accessToken: "", refreshToken: "", expiresIn: 0)
        }
        guard let value = try? decoder.decode(NativeTokenResponse.self, from: data) else {
            throw OrcaNativeAuthError.invalidResponse
        }
        return value
    }
}
