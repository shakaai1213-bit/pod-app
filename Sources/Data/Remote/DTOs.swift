import Foundation

// MARK: - Chat Channel Type

/// DTO-level channel type enum (singular forms to match API response)
enum DTOChatChannelType: String, Codable {
    case general
    case project
    case agent
    case research
    case alerts
}

// MARK: - User DTO

struct UserDTO: Codable, Identifiable {
    let id: String
    let name: String
    let email: String
    let preferredName: String?
    let role: String
    let isAgent: Bool
    let agentId: String?
    let avatarColor: String?
    let timezone: String?
}

// MARK: - Channel DTO

struct ChannelDTO: Codable, Identifiable {
    let id: String
    let name: String
    let type: DTOChatChannelType
    let description: String?
    let isPinned: Bool
    let unreadCount: Int
}

// MARK: - Message DTO

struct MessageDTO: Codable, Identifiable {
    let id: String
    let channelId: String
    let authorId: String
    let content: String
    let timestamp: Date
    let isAgent: Bool
    let agentId: String?
    let reactions: [ReactionDTO]?
    let threadCount: Int
}

struct ReactionDTO: Codable {
    let emoji: String
    let count: Int
    let userIds: [String]
}

// MARK: - Board DTO

struct BoardDTO: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let status: BoardStatus?
    let stage: String?
    let createdAt: Date
    let updatedAt: Date
    let taskCount: Int
    let completedTaskCount: Int
}

enum BoardStatus: String, Codable {
    case active
    case archived
    case completed
}

// MARK: - Agent DTO

struct AgentDTO: Codable, Identifiable {
    let id: String
    let name: String
    let status: AgentStatus
    let lastSeenAt: Date?
    let isBoardLead: Bool?

    // Optional fields the app uses but backend doesn't expose yet
    let role: String?
    let currentTask: String?
    let skills: [String]?
    let avatarColor: String?
}

enum AgentStatus: String, Codable {
    case online
    case busy
    case idle
    case offline
    case error
}

// MARK: - Send Message Request

struct SendMessageRequest: Encodable {
    let content: String
}

// MARK: - Paginated Response Wrapper

struct PaginatedResponse<T: Codable>: Codable {
    let items: [T]
    let total: Int
    let limit: Int?
    let offset: Int?
}
