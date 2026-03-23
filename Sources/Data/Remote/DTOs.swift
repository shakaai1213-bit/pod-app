import Foundation

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
    let type: ChannelType
    let description: String?
    let isPinned: Bool
    let unreadCount: Int
}

enum ChannelType: String, Codable {
    case general
    case project
    case agent
    case research
    case alerts
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

// MARK: - Task DTO

struct TaskDTO: Codable, Identifiable {
    let id: String
    let boardId: String
    let title: String
    let description: String?
    let status: TaskStatus
    let stage: String?
    let assigneeId: String?
    let dueDate: Date?
    let priority: TaskPriority?
    let tags: [String]
}

enum TaskStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case done
    case blocked
}

enum TaskPriority: String, Codable {
    case low
    case medium
    case high
    case critical
}

// MARK: - Agent DTO

struct AgentDTO: Codable, Identifiable {
    let id: String
    let name: String
    let role: String
    let status: AgentStatus
    let currentTask: String?
    let lastActivity: Date?
    let skills: [String]
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
    let data: [T]
    let total: Int
    let page: Int
    let pageSize: Int
}
