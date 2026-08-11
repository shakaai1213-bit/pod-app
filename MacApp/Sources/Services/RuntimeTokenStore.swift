import Foundation
import Security

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

    var needsRefresh: Bool {
        Date() >= expiresAt.addingTimeInterval(-300)
    }
}

protocol RuntimeTokenStoring: Sendable {
    func loadCredential() async throws -> RuntimeCredential?
    func storeCredential(_ credential: RuntimeCredential) async throws
    func deleteCredential() async throws
}

extension RuntimeTokenStoring {
    func loadToken() async throws -> String? {
        try await loadCredential()?.accessToken
    }
}

actor RuntimeTokenStore: RuntimeTokenStoring {
    private let service = "com.orcamc.mac.runtime"
    private let account = "orca-console-native-session-v1"
    private let legacyAccount = "orca-console-access-token"

    func loadCredential() throws -> RuntimeCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
              !credential.refreshToken.isEmpty else {
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
            kSecAttrAccount as String: account,
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

    func deleteCredential() throws {
        try delete(account: account)
        try delete(account: legacyAccount)
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
