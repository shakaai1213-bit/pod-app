import Foundation

// MARK: - Chat Channel Type

/// DTO-level channel type enum (singular forms to match API response)
enum DTOChatChannelType: String, Codable {
    case general
    case project
    case agent
    case research
    case alerts

    // Handle API's "public" / "group" / "private" types by mapping to name-based type
    // The API uses channel.name (e.g. "general", "projects", "alerts") to determine type
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        // Try to match the standard enum cases first
        if let channelType = DTOChatChannelType(rawValue: rawValue) {
            self = channelType
        } else {
            // API returns "public", "group", "private" — default to general
            self = .general
        }
    }
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
    let unreadCount: Int
    // API doesn't return isPinned — default to false
    var isPinned: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, type, description, unreadCount
    }
}

// MARK: - Message DTO

struct MessageDTO: Codable, Identifiable {
    let id: String
    let channelId: String
    let authorId: String
    let content: String
    let timestamp: Date
    var isAgent: Bool
    let agentId: String?
    let reactions: [ReactionDTO]?
    let threadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, content, isAgent, agentId, reactions, threadCount
        case channelId = "channel_id"
        case authorId = "sender_user_id"
        case timestamp = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        channelId = try container.decode(String.self, forKey: .channelId)
        authorId = try container.decode(String.self, forKey: .authorId)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        reactions = try container.decodeIfPresent([ReactionDTO].self, forKey: .reactions)
        threadCount = try container.decodeIfPresent(Int.self, forKey: .threadCount) ?? 0
        // Infer isAgent from presence of sender_agent_id
        isAgent = self.agentId != nil
    }
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

    enum CodingKeys: String, CodingKey {
        case id, name, status, stage, taskCount, completedTaskCount
        case description = "objective"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum BoardStatus: String, Codable {
    case active
    case archived
    case completed
}

// MARK: - Task DTO

struct TaskDTO: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let status: String?
    let stage: String?
    let assigneeId: String?
    let dueDate: Date?
    let priority: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, stage, priority, tags
        case assigneeId = "assignee_id"
        case dueDate = "due_date"
    }
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
