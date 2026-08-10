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
protocol RuntimeTokenStoring: Sendable {
    func loadToken() async throws -> String?
    func storeToken(_ token: String) async throws
    func deleteToken() async throws
}

actor RuntimeTokenStore: RuntimeTokenStoring {
    private let service = "com.orcamc.mac.runtime"
    private let account = "orca-console-access-token"

    func loadToken() throws -> String? {
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
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw RuntimeTokenStoreError.invalidToken
        }
        return token
    }

    func storeToken(_ token: String) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let data = normalized.data(using: .utf8) else {
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

    func deleteToken() throws {
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
