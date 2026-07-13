import Foundation
import Security

enum AgentTokenStoreError: Error {
    case keychain(OSStatus)
    case invalidData
}

/// Stores the one device-bound named-agent credential used by strict agent routes.
actor AgentTokenManager {
    private let serviceName = "com.podapp.agent-auth"
    private let accountName = "active-agent-token"

    func storeToken(_ token: String) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let data = normalized.data(using: .utf8) else {
            throw AgentTokenStoreError.invalidData
        }

        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AgentTokenStoreError.keychain(updateStatus)
        }

        var insert = lookup
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AgentTokenStoreError.keychain(addStatus)
        }
    }

    func getToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            if status == errSecSuccess { throw AgentTokenStoreError.invalidData }
            throw AgentTokenStoreError.keychain(status)
        }
        return token
    }

    func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AgentTokenStoreError.keychain(status)
        }
    }
}
