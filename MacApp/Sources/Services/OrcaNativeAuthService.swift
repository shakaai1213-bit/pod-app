import CryptoKit
import Foundation
import Security

enum OrcaNativeAuthError: Error, LocalizedError {
    case missingSession
    case invalidResponse
    case unapprovedOrigin
    case keychain(OSStatus)
    case rejected(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingSession: return "Sign in to ORCA to continue."
        case .invalidResponse: return "ORCA returned an unreadable sign-in response."
        case .unapprovedOrigin: return "This ORCA address is not an approved credential origin."
        case let .keychain(status): return "ORCA device identity could not be loaded (Keychain status \(status))."
        case let .rejected(status, detail): return "ORCA sign-in failed (HTTP \(status)): \(detail)"
        }
    }
}

enum OrcaServerOrigin {
    static let production = "http://100.104.72.62:8000"

    static func normalized(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    static func isApproved(_ url: URL) -> Bool {
        guard let origin = normalized(url) else { return false }
        if origin == production { return true }
#if DEBUG
        if url.scheme?.lowercased() == "http", ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "") { return true }
#endif
        return false
    }
}

enum OrcaDeviceIdentity {
    private static let service = "com.orcamc.mac.device-identity"
    private static let account = "ed25519-signing-key-v1"

    static func privateKey() throws -> Curve25519.Signing.PrivateKey {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var query = lookup
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let existing = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return existing
        }
        guard status == errSecItemNotFound else { throw OrcaNativeAuthError.keychain(status) }

        let value = Curve25519.Signing.PrivateKey()
        var insertion = lookup
        insertion[kSecValueData as String] = value.rawRepresentation
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw OrcaNativeAuthError.keychain(addStatus) }
        return value
    }

    static func publicKey(_ key: Curve25519.Signing.PrivateKey) -> String {
        key.publicKey.rawRepresentation.base64URLEncodedString()
    }

    static func deviceID(_ key: Curve25519.Signing.PrivateKey) -> String {
        "ed25519:\(SHA256.hash(data: key.publicKey.rawRepresentation).hex)"
    }

    static func current() -> String {
        guard let key = try? privateKey() else { return "unavailable-device-identity" }
        return deviceID(key)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private struct NativeTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let organizationId: String
}

private struct ChallengeResponse: Decodable { let nonce: String }
private struct ChallengeRequest: Encodable {
    let clientId: String
    let deviceId: String
    let devicePublicKey: String
    let operation: String
}
private struct DeviceProof: Encodable {
    let clientId: String
    let deviceId: String
    let devicePublicKey: String
    let challengeNonce: String
    let deviceSignature: String
}
private struct AppleExchangeRequest: Encodable {
    let identityToken: String
    let appleUserId: String
    let deviceId: String
    let clientId: String
    let devicePublicKey: String
    let challengeNonce: String
    let deviceSignature: String
}
private struct RefreshRequest: Encodable {
    let refreshToken: String
    let deviceId: String
    let clientId: String
    let devicePublicKey: String
    let challengeNonce: String
    let deviceSignature: String
}
private typealias LogoutRequest = RefreshRequest

actor OrcaNativeAuthService {
    static let clientID = "com.orcamc.mac"

    private let serverURL: URL
    private let serverOrigin: String
    private let tokenStore: any RuntimeTokenStoring
    private let session: URLSession
    private let signingKey: Curve25519.Signing.PrivateKey
    private let deviceID: String
    private let devicePublicKey: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(serverURL: URL, tokenStore: any RuntimeTokenStoring, session: URLSession = .shared) throws {
        self.serverURL = serverURL
        serverOrigin = OrcaServerOrigin.normalized(serverURL) ?? ""
        self.tokenStore = tokenStore
        self.session = session
        signingKey = try OrcaDeviceIdentity.privateKey()
        deviceID = OrcaDeviceIdentity.deviceID(signingKey)
        devicePublicKey = OrcaDeviceIdentity.publicKey(signingKey)
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func exchange(identityToken: String, appleUserID: String) async throws {
        let proof = try await proof(operation: "apple_callback", token: identityToken)
        let response = try await post("/api/v1/auth/apple/callback", AppleExchangeRequest(
            identityToken: identityToken, appleUserId: appleUserID, deviceId: proof.deviceId,
            clientId: proof.clientId, devicePublicKey: proof.devicePublicKey,
            challengeNonce: proof.challengeNonce, deviceSignature: proof.deviceSignature
        ))
        try await store(response)
    }

    func validAccessToken() async throws -> String {
        try requireApprovedOrigin()
        guard let credential = try await tokenStore.loadCredential(for: serverOrigin) else { throw OrcaNativeAuthError.missingSession }
        guard credential.clientID == Self.clientID, credential.deviceID == deviceID, credential.serverOrigin == serverOrigin else {
            try await tokenStore.deleteCredential(for: serverOrigin)
            throw OrcaNativeAuthError.missingSession
        }
        if credential.needsRefresh {
            let proof = try await proof(operation: "refresh", token: credential.refreshToken)
            let response = try await post("/api/v1/auth/refresh", RefreshRequest(
                refreshToken: credential.refreshToken, deviceId: proof.deviceId,
                clientId: proof.clientId, devicePublicKey: proof.devicePublicKey,
                challengeNonce: proof.challengeNonce, deviceSignature: proof.deviceSignature
            ))
            guard response.organizationId == credential.organizationID else { throw OrcaNativeAuthError.invalidResponse }
            try await store(response)
            return response.accessToken
        }
        return credential.accessToken
    }

    func logout() async throws {
        guard let credential = try await tokenStore.loadCredential(for: serverOrigin) else { return }
        let proof = try await proof(operation: "logout", token: credential.refreshToken)
        _ = try await post("/api/v1/auth/logout", LogoutRequest(
            refreshToken: credential.refreshToken, deviceId: proof.deviceId,
            clientId: proof.clientId, devicePublicKey: proof.devicePublicKey,
            challengeNonce: proof.challengeNonce, deviceSignature: proof.deviceSignature
        ), expectsTokenResponse: false)
        try await tokenStore.deleteCredential(for: serverOrigin)
    }

    func boundDeviceID() -> String { deviceID }
    func origin() -> String { serverOrigin }

    private func proof(operation: String, token: String) async throws -> DeviceProof {
        try requireApprovedOrigin()
        let challenge: ChallengeResponse = try await postJSON("/api/v1/auth/native/challenge", ChallengeRequest(
            clientId: Self.clientID, deviceId: deviceID, devicePublicKey: devicePublicKey, operation: operation
        ))
        let tokenHash = SHA256.hash(data: Data(token.utf8)).hex
        let statement = "orca-native-auth-v1\n\(operation)\n\(Self.clientID)\n\(deviceID)\n\(challenge.nonce)\n\(tokenHash)"
        let signature = try signingKey.signature(for: Data(statement.utf8)).base64URLEncodedString()
        return DeviceProof(clientId: Self.clientID, deviceId: deviceID, devicePublicKey: devicePublicKey, challengeNonce: challenge.nonce, deviceSignature: signature)
    }

    private func requireApprovedOrigin() throws {
        guard OrcaServerOrigin.isApproved(serverURL), !serverOrigin.isEmpty else { throw OrcaNativeAuthError.unapprovedOrigin }
    }

    private func store(_ response: NativeTokenResponse) async throws {
        try await tokenStore.storeCredential(RuntimeCredential(
            accessToken: response.accessToken, refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            clientID: Self.clientID, deviceID: deviceID,
            serverOrigin: serverOrigin, organizationID: response.organizationId
        ))
    }

    private func post<Body: Encodable>(_ path: String, _ body: Body, expectsTokenResponse: Bool = true) async throws -> NativeTokenResponse {
        try requireApprovedOrigin()
        let data = try await responseData(path, body)
        if !expectsTokenResponse { return NativeTokenResponse(accessToken: "", refreshToken: "", expiresIn: 0, organizationId: "") }
        guard let value = try? decoder.decode(NativeTokenResponse.self, from: data) else { throw OrcaNativeAuthError.invalidResponse }
        return value
    }

    private func postJSON<Body: Encodable, Result: Decodable>(_ path: String, _ body: Body) async throws -> Result {
        let data = try await responseData(path, body)
        guard let value = try? decoder.decode(Result.self, from: data) else { throw OrcaNativeAuthError.invalidResponse }
        return value
    }

    private func responseData<Body: Encodable>(_ path: String, _ body: Body) async throws -> Data {
        try requireApprovedOrigin()
        guard let url = URL(string: path, relativeTo: serverURL)?.absoluteURL,
              OrcaServerOrigin.normalized(url) == serverOrigin else { throw OrcaNativeAuthError.unapprovedOrigin }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-ORCA-Device-ID")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OrcaNativeAuthError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw OrcaNativeAuthError.rejected(http.statusCode, detail ?? "request rejected")
        }
        return data
    }
}
