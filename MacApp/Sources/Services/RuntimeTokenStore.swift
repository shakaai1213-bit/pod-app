import Foundation
import Security
import CryptoKit

enum RuntimeTokenStoreError: Error, LocalizedError {
    case invalidToken
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "The ORCA credential is empty or unreadable."
        case let .keychain(status):
            return "Keychain returned status \(status)."
        }
    }
}

struct RuntimeCredential: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let clientID: String
    let deviceID: String
    let serverOrigin: String
    let organizationID: String

    var needsRefresh: Bool {
        Date() >= expiresAt.addingTimeInterval(-300)
    }
}

protocol RuntimeTokenStoring: Sendable {
    func loadCredential(for serverOrigin: String) async throws -> RuntimeCredential?
    func storeCredential(_ credential: RuntimeCredential) async throws
    func deleteCredential(for serverOrigin: String) async throws
}

extension RuntimeTokenStoring {
    func loadToken(for serverOrigin: String) async throws -> String? {
        try await loadCredential(for: serverOrigin)?.accessToken
    }
}

actor RuntimeTokenStore: RuntimeTokenStoring {
    private let service = "com.orcamc.mac.runtime"
    private let accountPrefix = "orca-console-native-session-v2"
    private let legacyAccount = "orca-console-access-token"

    func loadCredential(for serverOrigin: String) throws -> RuntimeCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: serverOrigin),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw RuntimeTokenStoreError.keychain(status) }
        guard let data = result as? Data,
              let credential = try? JSONDecoder().decode(RuntimeCredential.self, from: data),
              !credential.accessToken.isEmpty,
              !credential.refreshToken.isEmpty,
              credential.serverOrigin == serverOrigin else {
            throw RuntimeTokenStoreError.invalidToken
        }
        return credential
    }

    func storeCredential(_ credential: RuntimeCredential) throws {
        guard !credential.accessToken.isEmpty,
              !credential.refreshToken.isEmpty,
              let data = try? JSONEncoder().encode(credential) else {
            throw RuntimeTokenStoreError.invalidToken
        }
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: credential.serverOrigin),
        ]
        let update = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw RuntimeTokenStoreError.keychain(update) }
        var insertion = lookup
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insertion as CFDictionary, nil)
        guard status == errSecSuccess else { throw RuntimeTokenStoreError.keychain(status) }
    }

    func deleteCredential(for serverOrigin: String) throws {
        try delete(account: account(for: serverOrigin))
        try delete(account: legacyAccount)
    }

    private func account(for serverOrigin: String) -> String {
        let digest = SHA256.hash(data: Data(serverOrigin.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(accountPrefix):\(digest)"
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RuntimeTokenStoreError.keychain(status)
        }
    }
}
