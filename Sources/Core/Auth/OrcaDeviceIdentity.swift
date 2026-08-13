import CryptoKit
import Foundation
import Security

enum OrcaDeviceIdentity {
    private static let service = "com.orcamc.pod.device-identity"
    private static let account = "ed25519-signing-key-v1"
    private static let signingKeyResult: Result<Curve25519.Signing.PrivateKey, Error> = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return Result { try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x42, count: 32)) }
        }
        return Result { try loadOrCreateKey() }
    }()

    private static func loadOrCreateKey() throws -> Curve25519.Signing.PrivateKey {
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

        guard status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
        let value = Curve25519.Signing.PrivateKey()
        var insertion = lookup
        insertion[kSecValueData as String] = value.rawRepresentation
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        return value
    }

    private static func signingKey() throws -> Curve25519.Signing.PrivateKey {
        try signingKeyResult.get()
    }

    static func current() -> String {
        guard let publicKey = try? signingKey().publicKey.rawRepresentation else {
            return "unavailable-device-identity"
        }
        return "ed25519:\(SHA256.hash(data: publicKey).hexString)"
    }

    static func publicKey() -> String {
        (try? signingKey().publicKey.rawRepresentation.base64URLString) ?? ""
    }

    static func proof(
        operation: String,
        clientID: String,
        nonce: String,
        token: String
    ) throws -> String {
        let deviceID = current()
        let tokenHash = SHA256.hash(data: Data(token.utf8)).hexString
        let statement = "orca-native-auth-v1\n\(operation)\n\(clientID)\n\(deviceID)\n\(nonce)\n\(tokenHash)"
        return try signingKey().signature(for: Data(statement.utf8)).base64URLString
    }

    static func requestProofHeaders(
        method: String,
        target: String,
        body: Data,
        token: String,
        clientID: String = "com.orcamc.pod"
    ) throws -> [String: String] {
        guard let accessJTI = accessTokenJTI(token) else { throw AuthError.invalidResponse }
        let deviceID = current()
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString.lowercased()
        let statement = "orca-api-request-v1\n\(method.uppercased())\n\(target)\n\(SHA256.hash(data: body).hexString)\n\(clientID)\n\(deviceID)\n\(timestamp)\n\(nonce)\n\(accessJTI)\n\(SHA256.hash(data: Data(token.utf8)).hexString)"
        return [
            "X-ORCA-Client-ID": clientID,
            "X-ORCA-Device-ID": deviceID,
            "X-ORCA-Device-Public-Key": publicKey(),
            "X-ORCA-Proof-Timestamp": timestamp,
            "X-ORCA-Proof-Nonce": nonce,
            "X-ORCA-Proof-JTI": accessJTI,
            "X-ORCA-Proof-Signature": try signingKey().signature(for: Data(statement.utf8)).base64URLString,
        ]
    }

    static func authorize(_ request: inout URLRequest, token: String) throws {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(current(), forHTTPHeaderField: "X-ORCA-Device-ID")
        guard token.split(separator: ".", omittingEmptySubsequences: false).count == 3,
              let url = request.url else { return }
        let target = url.path(percentEncoded: true)
            + (url.query(percentEncoded: true).map { "?\($0)" } ?? "")
        let headers = try requestProofHeaders(
            method: request.httpMethod ?? "GET",
            target: target,
            body: request.httpBody ?? Data(),
            token: token
        )
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private static func accessTokenJTI(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jti = payload["jti"] as? String,
              !jti.isEmpty else { return nil }
        return jti
    }
}

private extension Data {
    var base64URLString: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
