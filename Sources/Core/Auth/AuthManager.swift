import Foundation
import Security
import AuthenticationServices

// MARK: - Token Manager

/// Actor responsible for secure token storage, retrieval, and refresh.
/// Uses iOS Keychain Services for secure storage.
actor TokenManager {

    // MARK: - Constants

    private let serviceName = "com.podapp.auth"
    private let maxStoredUsers = 5

    // MARK: - Token Storage Keys

    private enum StorageKey {
        static func tokenKey(for userId: UUID) -> String {
            "token_\(userId.uuidString)"
        }
        static let activeUserId = "active_user_id"
        static let storedUserIds = "stored_user_ids"
        static let allTokensKey = "all_tokens"
    }

    // MARK: - Store Token

    /// Stores a token for a user in Keychain. Supports multi-user (up to 5).
    func storeToken(_ token: StoredToken, for userId: UUID) throws {
        // Get existing stored user IDs
        var userIds = loadStoredUserIds()

        // Add user if not already stored
        if !userIds.contains(userId) {
            if userIds.count >= maxStoredUsers {
                // Remove oldest user (first in array)
                let removedId = userIds.removeFirst()
                try? deleteToken(for: removedId)
                try? deleteUserProfile(for: removedId)
            }
            userIds.append(userId)
            saveStoredUserIds(userIds)
        }

        // Encode and store token
        let tokenData = try JSONEncoder().encode(token)
        try storeInKeychain(data: tokenData, forKey: StorageKey.tokenKey(for: userId))

        // Store user profile separately
        let userProfile = UserProfile(id: userId, email: token.accessToken) // email from token or separate
        let profileData = try JSONEncoder().encode(userProfile)
        try storeInKeychain(data: profileData, forKey: "profile_\(userId.uuidString)")

        print("[TokenManager] Stored token for user \(userId.uuidString.prefix(8))..., \(userIds.count) total users")
    }

    // MARK: - Retrieve Token

    /// Retrieves the stored token for a user.
    func getToken(for userId: UUID) throws -> StoredToken {
        let data = try loadFromKeychain(forKey: StorageKey.tokenKey(for: userId))
        return try JSONDecoder().decode(StoredToken.self, from: data)
    }

    /// Retrieves the active (most recently used) user's token.
    func getActiveToken() throws -> (userId: UUID, token: StoredToken)? {
        guard let activeUserIdString = UserDefaults.standard.string(forKey: StorageKey.activeUserId),
              let activeUserId = UUID(uuidString: activeUserIdString) else {
            return nil
        }
        let token = try getToken(for: activeUserId)
        return (activeUserId, token)
    }

    // MARK: - Update Token

    /// Updates an existing token (e.g., after refresh).
    func updateToken(_ token: StoredToken, for userId: UUID) throws {
        try storeToken(token, for: userId)
        print("[TokenManager] Updated token for user \(userId.uuidString.prefix(8))...")
    }

    // MARK: - Delete Token

    /// Deletes a user's token from Keychain.
    func deleteToken(for userId: UUID) throws {
        try deleteFromKeychain(forKey: StorageKey.tokenKey(for: userId))
        try deleteFromKeychain(forKey: "profile_\(userId.uuidString)")

        var userIds = loadStoredUserIds()
        userIds.removeAll { $0 == userId }
        saveStoredUserIds(userIds)

        // Clear active user if this was the active one
        if UserDefaults.standard.string(forKey: StorageKey.activeUserId) == userId.uuidString {
            UserDefaults.standard.removeObject(forKey: StorageKey.activeUserId)
        }

        print("[TokenManager] Deleted token for user \(userId.uuidString.prefix(8))...")
    }

    /// Deletes all stored tokens (sign out all users).
    func deleteAllTokens() throws {
        let userIds = loadStoredUserIds()
        for userId in userIds {
            try? deleteFromKeychain(forKey: StorageKey.tokenKey(for: userId))
            try? deleteFromKeychain(forKey: "profile_\(userId.uuidString)")
        }
        saveStoredUserIds([])
        UserDefaults.standard.removeObject(forKey: StorageKey.activeUserId)
        print("[TokenManager] Deleted all tokens")
    }

    // MARK: - Active User Management

    /// Sets the active (currently signed-in) user.
    func setActiveUser(_ userId: UUID) {
        UserDefaults.standard.set(userId.uuidString, forKey: StorageKey.activeUserId)
        print("[TokenManager] Set active user: \(userId.uuidString.prefix(8))...")
    }

    /// Returns all stored user IDs.
    func getStoredUserIds() -> [UUID] {
        loadStoredUserIds()
    }

    /// Checks if any tokens are stored (for auto-login on app launch).
    func hasStoredTokens() -> Bool {
        !loadStoredUserIds().isEmpty
    }

    /// Deletes a user's profile from Keychain.
    func deleteUserProfile(for userId: UUID) throws {
        try deleteFromKeychain(forKey: "profile_\(userId.uuidString)")
    }

    // MARK: - Keychain Operations

    private func storeInKeychain(data: Data, forKey key: String) throws {
        // First try to delete any existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func loadFromKeychain(forKey key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.invalidItemFormat
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func deleteFromKeychain(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - UserDefaults Helpers (for non-sensitive data)

    private func loadStoredUserIds() -> [UUID] {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.storedUserIds),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return []
        }
        return ids
    }

    private func saveStoredUserIds(_ ids: [UUID]) {
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: StorageKey.storedUserIds)
        }
    }
}

// MARK: - User Profile (stored alongside token)

struct UserProfile: Codable {
    let id: UUID
    let email: String
    var name: String?
    var role: UserRole?
}

// MARK: - Auth Manager

/// Authentication manager. Coordinates between UI and TokenManager.
/// Thread-safe: uses internal actor isolation for token operations.
@Observable
final class AuthManager {

    // MARK: - Published State

    private(set) var currentUser: User?
    private(set) var isAuthenticated: Bool = false
    private(set) var sessionExpiry: Date?
    private(set) var isLoading: Bool = false
    private(set) var error: AuthError?
    private(set) var storedUsers: [StoredUserInfo] = []

    // MARK: - Private State

    private let tokenManager = TokenManager()
    private let backendURL: String

    #if targetEnvironment(simulator)
    private let baseURL = "http://127.0.0.1:19002"
    #else
    private let baseURL = "http://shakas-mac-mini.tail82d30d.ts.net:8000"
    #endif

    // MARK: - Initialization

    init(backendURL: String? = nil) {
        self.backendURL = backendURL ?? Self.defaultBackendURL
        Task { await loadStoredUsers() }
    }

    private static var defaultBackendURL: String {
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:19002"
        #else
        return "http://shakas-mac-mini.tail82d30d.ts.net:8000"
        #endif
    }

    // MARK: - Load Stored Users (for user switcher)

    /// Loads list of stored users for the user switcher UI.
    func loadStoredUsers() async {
        let ids = await tokenManager.getStoredUserIds()
        var users: [StoredUserInfo] = []
        for id in ids {
            if let profile = try? await loadUserProfile(id) {
                users.append(StoredUserInfo(id: id, email: profile.email, name: profile.name))
            }
        }
        self.storedUsers = users
    }

    private func loadUserProfile(_ userId: UUID) async throws -> UserProfile {
        // Try to load from Keychain profile key
        let serviceName = "com.podapp.auth"
        let key = "profile_\(userId.uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.itemNotFound
        }
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }

    // MARK: - Sign In with Email/Password

    /// Signs in with email and password. Creates/reuses a stored token.
    func signIn(email: String, password: String) async throws -> User {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // Call backend login endpoint
        let loginRequest = LoginCredentials(email: email, password: password)
        let authResponse: AuthLoginResponse = try await postAuth(
            path: "/api/v1/auth/login",
            body: loginRequest
        )

        let user = authResponse.user
        let storedToken = StoredToken(
            userId: user.id,
            accessToken: authResponse.token.accessToken,
            refreshToken: authResponse.token.refreshToken,
            expiresAt: authResponse.token.expiresAt,
            issuedAt: Date()
        )

        // Store in Keychain
        try await tokenManager.storeToken(storedToken, for: user.id)
        await tokenManager.setActiveUser(user.id)

        // Update state
        currentUser = user
        sessionExpiry = storedToken.expiresAt
        isAuthenticated = true

        await loadStoredUsers()

        print("[AuthManager] Signed in: \(user.email)")
        return user
    }

    // MARK: - Sign In with Token (existing flow - token passthrough)

    /// Signs in using an existing API token (for ORCA MC backend compatibility).
    /// Creates a user object from the token identity.
    func signInWithToken(_ token: String) async throws -> User {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // Verify token by calling /api/v1/users/me
        guard let url = URL(string: "\(backendURL)/api/v1/users/me") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw AuthError.invalidCredentials
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError(httpResponse.statusCode)
        }

        // Decode user from response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let userDTO = try decoder.decode(UserDTO.self, from: data)

        let user = User(
            id: UUID(uuidString: userDTO.id) ?? UUID(),
            email: userDTO.email,
            name: userDTO.preferredName ?? userDTO.name,
            role: UserRole(rawValue: userDTO.role) ?? .member,
            createdAt: Date()
        )

        // Store token with a synthetic stored token (no refresh for raw token auth)
        let storedToken = StoredToken(
            userId: user.id,
            accessToken: token,
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(365 * 24 * 60 * 60), // 1 year expiry for raw tokens
            issuedAt: Date()
        )

        try await tokenManager.storeToken(storedToken, for: user.id)
        await tokenManager.setActiveUser(user.id)

        currentUser = user
        sessionExpiry = storedToken.expiresAt
        isAuthenticated = true

        await loadStoredUsers()

        print("[AuthManager] Signed in with token: \(user.email)")
        return user
    }

    // MARK: - Sign In with Apple

    /// Initiates Sign in with Apple flow.
    /// Note: Requires ASAuthorizationController setup in a UIViewController.
    /// This method handles the token exchange after Apple returns an authorization.
    func signInWithApple(authorization: ASAuthorization) async throws -> User {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidResponse
        }

        isLoading = true
        error = nil

        defer { isLoading = false }

        // Exchange Apple token for backend token
        let appleRequest = AppleAuthRequest(
            identityToken: tokenString,
            authorizationCode: appleIDCredential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
            email: appleIDCredential.email,
            fullName: appleIDCredential.fullName?.description
        )

        let authResponse: AuthLoginResponse = try await postAuth(
            path: "/api/v1/auth/apple",
            body: appleRequest
        )

        let user = authResponse.user
        let storedToken = StoredToken(
            userId: user.id,
            accessToken: authResponse.token.accessToken,
            refreshToken: authResponse.token.refreshToken,
            expiresAt: authResponse.token.expiresAt,
            issuedAt: Date()
        )

        try await tokenManager.storeToken(storedToken, for: user.id)
        await tokenManager.setActiveUser(user.id)

        currentUser = user
        sessionExpiry = storedToken.expiresAt
        isAuthenticated = true

        await loadStoredUsers()

        print("[AuthManager] Signed in with Apple: \(user.email)")
        return user
    }

    // MARK: - Switch User

    /// Switches to a different stored user (no re-auth needed).
    func switchToUser(_ userId: UUID) async throws {
        let token = try await tokenManager.getToken(for: userId)

        // Check if token is expired
        if token.isExpired {
            // Try to refresh
            if let refreshToken = token.refreshToken {
                let newToken = try await refreshAccessToken(refreshToken: refreshToken, userId: userId)
                try await tokenManager.updateToken(newToken, for: userId)
            } else {
                throw AuthError.tokenExpired
            }
        }

        await tokenManager.setActiveUser(userId)
        currentUser = User(
            id: userId,
            email: storedUsers.first { $0.id == userId }?.email ?? "",
            name: storedUsers.first { $0.id == userId }?.name ?? "User",
            role: .member
        )
        sessionExpiry = token.expiresAt
        isAuthenticated = true

        print("[AuthManager] Switched to user: \(userId.uuidString.prefix(8))...")
    }

    // MARK: - Validate Session

    /// Checks if the current session is valid. Auto-refreshes if needed.
    func validateSession() async -> Bool {
        guard let activeTokenInfo = try? await tokenManager.getActiveToken() else {
            return false
        }

        let token = activeTokenInfo.token

        if token.isExpired {
            if let refreshToken = token.refreshToken {
                do {
                    let newToken = try await refreshAccessToken(refreshToken: refreshToken, userId: activeTokenInfo.userId)
                    try await tokenManager.updateToken(newToken, for: activeTokenInfo.userId)
                    sessionExpiry = newToken.expiresAt
                    return true
                } catch {
                    print("[AuthManager] Token refresh failed: \(error)")
                    return false
                }
            }
            return false
        }

        // Token is valid
        sessionExpiry = token.expiresAt
        return true
    }

    // MARK: - Refresh Token

    private func refreshAccessToken(refreshToken: String, userId: UUID) async throws -> StoredToken {
        let request = AuthRefreshRequest(refreshToken: refreshToken)
        let response: AuthRefreshResponse = try await postAuth(
            path: "/api/v1/auth/refresh",
            body: request
        )

        return StoredToken(
            userId: userId,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt: response.expiresAt,
            issuedAt: Date()
        )
    }

    // MARK: - Rotate Token (Admin)

    /// Rotates the access token (admin function). Requests a new token from backend.
    func rotateToken() async throws {
        guard let activeTokenInfo = try await tokenManager.getActiveToken() else {
            throw AuthError.unauthorized
        }

        let response: AuthRefreshResponse = try await postAuth(
            path: "/api/v1/auth/rotate",
            body: AuthEmptyBody()
        )

        let newToken = StoredToken(
            userId: activeTokenInfo.userId,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? activeTokenInfo.token.refreshToken,
            expiresAt: response.expiresAt,
            issuedAt: Date()
        )

        try await tokenManager.updateToken(newToken, for: activeTokenInfo.userId)
        sessionExpiry = newToken.expiresAt

        print("[AuthManager] Token rotated for user \(activeTokenInfo.userId.uuidString.prefix(8))...")
    }

    // MARK: - Sign Out

    /// Signs out the current user. Optionally removes all tokens.
    func signOut(removeAllUsers: Bool = false) {
        if removeAllUsers {
            Task { try? await tokenManager.deleteAllTokens() }
        } else if let userId = currentUser?.id {
            Task { try? await tokenManager.deleteToken(for: userId) }
        }

        currentUser = nil
        isAuthenticated = false
        sessionExpiry = nil
        error = nil

        Task { await loadStoredUsers() }

        print("[AuthManager] Signed out")
    }

    // MARK: - Auto Login

    /// Attempts to auto-login using stored token on app launch.
    /// Returns true if successful, false if no stored token or token invalid.
    func attemptAutoLogin() async -> Bool {
        guard let activeTokenInfo = try? await tokenManager.getActiveToken() else {
            print("[AuthManager] No stored token found")
            return false
        }

        // Check if token is expired
        if activeTokenInfo.token.isExpired {
            if let refreshToken = activeTokenInfo.token.refreshToken {
                do {
                    let newToken = try await refreshAccessToken(
                        refreshToken: refreshToken,
                        userId: activeTokenInfo.userId
                    )
                    try await tokenManager.updateToken(newToken, for: activeTokenInfo.userId)
                    sessionExpiry = newToken.expiresAt
                    print("[AuthManager] Auto-login: token refreshed")
                } catch {
                    print("[AuthManager] Auto-login: token refresh failed, clearing")
                    try? await tokenManager.deleteToken(for: activeTokenInfo.userId)
                    return false
                }
            } else {
                print("[AuthManager] Auto-login: token expired, no refresh token")
                return false
            }
        } else {
            sessionExpiry = activeTokenInfo.token.expiresAt
        }

        // Fetch user profile
        do {
            let user: User = try await getAuth(path: "/api/v1/users/me")
            currentUser = user
            isAuthenticated = true
            print("[AuthManager] Auto-login successful: \(user.email)")
            return true
        } catch {
            print("[AuthManager] Auto-login: failed to fetch user: \(error)")
            return false
        }
    }

    // MARK: - Network Helpers

    private func postAuth<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        guard let url = URL(string: "\(backendURL)\(path)") else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(AnyEncodable(body))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        case 401:
            throw AuthError.unauthorized
        default:
            throw AuthError.serverError(httpResponse.statusCode)
        }
    }

    private func getAuth<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: "\(backendURL)\(path)") else {
            throw AuthError.invalidResponse
        }

        guard let activeTokenInfo = try await tokenManager.getActiveToken() else {
            throw AuthError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(activeTokenInfo.token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        case 401:
            throw AuthError.unauthorized
        default:
            throw AuthError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Supporting Types

struct StoredUserInfo: Identifiable {
    let id: UUID
    let email: String
    var name: String?

    var displayName: String {
        name ?? email
    }
}

struct AppleAuthRequest: Codable {
    let identityToken: String
    let authorizationCode: String?
    let email: String?
    let fullName: String?
}

struct AuthEmptyBody: Codable {}

// MARK: - AnyEncodable Helper

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ value: some Encodable) {
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
