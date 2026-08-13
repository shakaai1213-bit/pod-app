import CryptoKit
import Foundation
import Security

enum OrcaDeviceIdentity {
    private static let service = "com.orcamc.pod.device-identity"
    private static let account = "ed25519-signing-key-v1"
    private static let signingKey = loadOrCreateKey()

    private static func loadOrCreateKey() -> Curve25519.Signing.PrivateKey {
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

        precondition(status == errSecItemNotFound, "ORCA device identity Keychain read failed: \(status)")
        let value = Curve25519.Signing.PrivateKey()
        var insertion = lookup
        insertion[kSecValueData as String] = value.rawRepresentation
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        precondition(addStatus == errSecSuccess, "ORCA device identity Keychain write failed: \(addStatus)")
        return value
    }

    static func current() -> String {
        let publicKey = signingKey.publicKey.rawRepresentation
        return "ed25519:\(SHA256.hash(data: publicKey).hexString)"
    }

    static func publicKey() -> String {
        signingKey.publicKey.rawRepresentation.base64URLString
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
        return try signingKey.signature(for: Data(statement.utf8)).base64URLString
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
