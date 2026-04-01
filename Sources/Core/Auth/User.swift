import Foundation

// MARK: - User Model

/// Represents an authenticated user in the pod app.
struct User: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let email: String
    let name: String
    let role: UserRole
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, name, role, createdAt
    }

    init(id: UUID, email: String, name: String, role: UserRole, createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.name = name
        self.role = role
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Support both UUID string and plain string id
        if let uuidString = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuidString
        } else {
            let stringId = try container.decode(String.self, forKey: .id)
            if let uuid = UUID(uuidString: stringId) {
                self.id = uuid
            } else {
                // Fallback: hash the string to a UUID
                self.id = UUID(uuidString: "00000000-0000-0000-0000-\(String(stringId.hashValue, radix: 16).padding(toLength: 12, withPad: "0", startingAt: 0).prefix(12))") ?? UUID()
            }
        }
        self.email = try container.decode(String.self, forKey: .email)
        self.name = try container.decode(String.self, forKey: .name)
        self.role = try container.decode(UserRole.self, forKey: .role)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - User Role

enum UserRole: String, Codable, Sendable {
    case admin
    case member
    case viewer

    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .member: return "Member"
        case .viewer: return "Viewer"
        }
    }

    var canManageUsers: Bool {
        self == .admin
    }

    var canRotateTokens: Bool {
        self == .admin
    }
}

// MARK: - Auth Token

/// Represents a stored auth token for a user session.
struct StoredToken: Codable, Sendable {
    let userId: UUID
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let issuedAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var isNearExpiry: Bool {
        // Consider "near expiry" if within 5 minutes
        Date() >= expiresAt.addingTimeInterval(-300)
    }
}

// MARK: - Auth State

/// Represents the current authentication state.
enum AuthState: Sendable {
    case unauthenticated
    case authenticating
    case authenticated(User)
    case sessionExpired(User)
    case error(AuthError)
}

// MARK: - Auth Errors

enum AuthError: Error, LocalizedError, Sendable {
    case invalidCredentials
    case tokenExpired
    case tokenRefreshFailed
    case networkError(Error)
    case keychainError(KeychainError)
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password."
        case .tokenExpired:
            return "Your session has expired. Please sign in again."
        case .tokenRefreshFailed:
            return "Failed to refresh your session. Please sign in again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .keychainError(let error):
            return "Secure storage error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server."
        case .unauthorized:
            return "Unauthorized. Please sign in."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError, Sendable {
    case itemNotFound
    case duplicateItem
    case invalidItemFormat
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Item not found in secure storage."
        case .duplicateItem:
            return "Item already exists in secure storage."
        case .invalidItemFormat:
            return "Invalid item format in secure storage."
        case .unexpectedStatus(let status):
            return "Secure storage error: \(status)"
        case .encodingFailed:
            return "Failed to encode data for secure storage."
        case .decodingFailed:
            return "Failed to decode data from secure storage."
        }
    }
}

// MARK: - Login Credentials

struct LoginCredentials: Codable, Sendable {
    let email: String
    let password: String
}

// MARK: - Auth Response DTOs

struct AuthTokenResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int  // seconds
    let tokenType: String?

    var expiresAt: Date {
        Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

struct AuthLoginResponse: Codable, Sendable {
    let user: User
    let token: AuthTokenResponse
}

struct AuthRefreshRequest: Codable, Sendable {
    let refreshToken: String
}

struct AuthRefreshResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    var expiresAt: Date {
        Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}
