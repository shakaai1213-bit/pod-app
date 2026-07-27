import Foundation

struct Channel: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let type: ChatChannelType
    var lastMessage: String?
    var lastMessageTimestamp: Date?
    var unreadCount: Int
    var isPinned: Bool
    var isMuted: Bool

    var icon: String {
        switch type {
        case .general: return "#"
        case .projects: return "folder"
        case .agents: return "cpu"
        case .research: return "magnifyingglass"
        case .alerts: return "bell"
        case .direct: return "person.fill"
        }
    }

    var displayName: String { name }
}

enum ChatChannelType: String, CaseIterable, Sendable {
    case general
    case projects
    case agents
    case research
    case alerts
    case direct
}

struct Message: Identifiable, Hashable, Sendable {
    let id: UUID
    let channelId: UUID
    let authorId: UUID
    let authorName: String
    let authorRole: AuthorRole
    var isAgent: Bool
    var agentId: String?
    let content: String
    let timestamp: Date
    var reactions: [Reaction]
    var isHighlighted: Bool
    var replyTo: UUID?
    var queueState: CachedQueueMessage.QueueState?
    var fileAttachment: ChatFileAttachment?

    init(
        id: UUID = UUID(),
        channelId: UUID,
        authorId: UUID,
        authorName: String = "",
        authorRole: AuthorRole = .human,
        isAgent: Bool = false,
        agentId: String? = nil,
        content: String,
        timestamp: Date = Date(),
        reactions: [Reaction] = [],
        isHighlighted: Bool = false,
        replyTo: UUID? = nil,
        queueState: CachedQueueMessage.QueueState? = nil,
        fileAttachment: ChatFileAttachment? = nil
    ) {
        self.id = id
        self.channelId = channelId
        self.authorId = authorId
        self.authorName = authorName
        self.authorRole = authorRole
        self.isAgent = isAgent
        self.agentId = agentId
        self.content = content
        self.timestamp = timestamp
        self.reactions = reactions
        self.isHighlighted = isHighlighted
        self.replyTo = replyTo
        self.queueState = queueState
        self.fileAttachment = fileAttachment
    }
}

enum AuthorRole: String, Sendable {
    case human
    case agent
    case system
}

struct Reaction: Identifiable, Hashable, Sendable {
    let id: String
    let emoji: String
    var count: Int
    var userIds: [String]
    var isReactedByMe: Bool

    init(
        emoji: String,
        count: Int = 1,
        userIds: [String] = [],
        isReactedByMe: Bool = false
    ) {
        self.id = emoji
        self.emoji = emoji
        self.count = count
        self.userIds = userIds
        self.isReactedByMe = isReactedByMe
    }
}
