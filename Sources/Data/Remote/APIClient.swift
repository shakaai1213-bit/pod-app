import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL = "http://192.168.4.243:8000"
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var authToken: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Auth

    func setToken(_ token: String?) {
        self.authToken = token
    }

    func login(token: String) async throws -> AuthResponse {
        let endpoint = "\(baseURL)/api/v1/auth/login"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Key")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        self.authToken = token
        return try decoder.decode(AuthResponse.self, from: data)
    }

    // MARK: - Generic Request

    private func buildRequest(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        var components = URLComponents(string: "\(baseURL)\(path)")
        if let queryItems = queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw APIError(message: "Invalid URL", code: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Api-Key")
        }

        if let body = body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 500...599:
            throw APIError.serverError
        default:
            throw APIError(message: "Request failed with status \(httpResponse.statusCode)", code: httpResponse.statusCode)
        }
    }

    // MARK: - Public API Methods

    func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "GET")
        return try await perform(request)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let request = try buildRequest(path: path, method: "POST", body: AnyEncodable(body))
        return try await perform(request)
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let request = try buildRequest(path: path, method: "PUT", body: AnyEncodable(body))
        return try await perform(request)
    }

    func delete(_ path: String) async throws {
        let request = try buildRequest(path: path, method: "DELETE")
        let _: EmptyResponse = try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError
        }
    }
}

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

// MARK: - Project Model

struct Project: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let status: ProjectStatus
    let priority: Priority
    let ownerId: String
    let teamIds: [String]
    let createdAt: Date?
    let updatedAt: Date?
    let dueDate: Date?
    let tags: [String]

    enum ProjectStatus: String, Codable, Sendable, CaseIterable {
        case active
        case paused
        case completed
        case archived

        var displayName: String {
            rawValue.capitalized
        }

        var color: String {
            switch self {
            case .active:    return "00FF9D"
            case .paused:    return "FFB800"
            case .completed: return "00D4FF"
            case .archived:  return "55556A"
            }
        }
    }

    enum Priority: String, Codable, Sendable, CaseIterable {
        case low, medium, high, critical

        var displayName: String { rawValue.capitalized }

        var color: String {
            switch self {
            case .low:      return "55556A"
            case .medium:   return "00D4FF"
            case .high:     return "FF6B35"
            case .critical: return "FF3B5C"
            }
        }
    }
}

// MARK: - Chat Models

struct ChatMessage: Codable, Identifiable, Sendable {
    let id: String
    let channelId: String
    let authorId: String
    let authorName: String
    let content: String
    let createdAt: Date
    let updatedAt: Date?
    let attachments: [Attachment]?
    let isEdited: Bool
}

struct Attachment: Codable, Sendable {
    let id: String
    let filename: String
    let url: String
    let mimeType: String
    let sizeBytes: Int?
}

struct Channel: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let channelType: ChannelType
    let unreadCount: Int
    let lastMessage: ChatMessage?

    enum ChannelType: String, Codable, Sendable {
        case general
        case project
        case research
        case alert
        case direct
    }
}

// MARK: - Knowledge Models

struct KnowledgeEntry: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let content: String
    let category: String
    let tags: [String]
    let authorId: String
    let authorName: String
    let createdAt: Date
    let updatedAt: Date
    let version: Int
    let isPinned: Bool
}

// MARK: - Agent Models

struct Agent: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let model: String
    let status: AgentStatus
    let capabilities: [String]
    let config: AgentConfig?
    let lastActive: Date?
}

enum AgentStatus: String, Codable, Sendable {
    case running
    case idle
    case error
    case stopped
}

struct AgentConfig: Codable, Sendable {
    let temperature: Double?
    let maxTokens: Int?
    let systemPrompt: String?
}

// MARK: - Dashboard Stats

struct DashboardStats: Codable, Sendable {
    let activeProjects: Int
    let openTasks: Int
    let teamOnline: Int
    let unreadMessages: Int
    let recentActivity: [ActivityItem]
}

// MARK: - Empty Response

struct EmptyResponse: Decodable {}

// MARK: - Activity Item

struct ActivityItem: Codable, Identifiable, Sendable {
    let id: String
    let type: ActivityType
    let title: String
    let description: String?
    let actorName: String
    let timestamp: Date
    let projectId: String?
    let channelId: String?

    enum ActivityType: String, Codable, Sendable {
        case projectCreated, projectUpdated, taskCompleted, messagePosted, agentRan, memberJoined
    }
}
