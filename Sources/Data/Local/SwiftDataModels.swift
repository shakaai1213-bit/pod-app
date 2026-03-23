import Foundation
import SwiftData

// MARK: - CachedAgent

@Model
final class CachedAgent {
    @Attribute(.unique) var id: UUID
    var name: String
    var role: String
    var status: String
    var currentTask: String?
    var lastActivity: Date?
    var skills: [String]
    var avatarColor: String?
    var cachedAt: Date

    init(
        id: UUID,
        name: String,
        role: String,
        status: String,
        currentTask: String?,
        lastActivity: Date?,
        skills: [String],
        avatarColor: String?,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.status = status
        self.currentTask = currentTask
        self.lastActivity = lastActivity
        self.skills = skills
        self.avatarColor = avatarColor
        self.cachedAt = cachedAt
    }

    convenience init(from agent: Agent) {
        self.init(
            id: agent.id,
            name: agent.name,
            role: agent.role,
            status: agent.status.rawValue,
            currentTask: agent.currentTask,
            lastActivity: agent.lastActivity,
            skills: agent.skills,
            avatarColor: agent.avatarColor,
            cachedAt: Date()
        )
    }

    func toAgent() -> Agent {
        Agent(
            id: id,
            name: name,
            role: role,
            status: AgentState(rawValue: status) ?? .offline,
            currentTask: currentTask,
            lastActivity: lastActivity,
            skills: skills,
            avatarColor: avatarColor
        )
    }
}

// MARK: - CachedChannel

@Model
final class CachedChannel {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: String
    var unreadCount: Int
    var lastMessagePreview: String?
    var lastMessageTime: Date?
    var isPinned: Bool
    var cachedAt: Date

    init(
        id: UUID,
        name: String,
        type: String,
        unreadCount: Int,
        lastMessagePreview: String?,
        lastMessageTime: Date?,
        isPinned: Bool,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.unreadCount = unreadCount
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageTime = lastMessageTime
        self.isPinned = isPinned
        self.cachedAt = cachedAt
    }

    convenience init(from channel: Channel) {
        self.init(
            id: channel.id,
            name: channel.name,
            type: channel.type.rawValue,
            unreadCount: channel.unreadCount,
            lastMessagePreview: channel.lastMessage,
            lastMessageTime: channel.lastMessageTimestamp,
            isPinned: channel.isPinned,
            cachedAt: Date()
        )
    }

    func toChannel() -> Channel {
        return Channel(
            id: id,
            name: name,
            type: ChatChannelType(rawValue: type) ?? .general,
            lastMessage: lastMessagePreview,
            lastMessageTimestamp: lastMessageTime,
            unreadCount: unreadCount,
            isPinned: isPinned,
            isMuted: false
        )
    }
}

// MARK: - CachedMessage

@Model
final class CachedMessage {
    @Attribute(.unique) var id: UUID
    var channelId: UUID
    var authorId: UUID
    var content: String
    var timestamp: Date
    var isAgent: Bool
    var agentId: String?
    var cachedAt: Date

    init(
        id: UUID,
        channelId: UUID,
        authorId: UUID,
        content: String,
        timestamp: Date,
        isAgent: Bool,
        agentId: String?,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.channelId = channelId
        self.authorId = authorId
        self.content = content
        self.timestamp = timestamp
        self.isAgent = isAgent
        self.agentId = agentId
        self.cachedAt = cachedAt
    }

    convenience init(from message: Message) {
        self.init(
            id: message.id,
            channelId: message.channelId,
            authorId: message.authorId,
            content: message.content,
            timestamp: message.timestamp,
            isAgent: message.isAgent,
            agentId: message.agentId,
            cachedAt: Date()
        )
    }

    func toMessage() -> Message {
        Message(
            id: id,
            channelId: channelId,
            authorId: authorId,
            isAgent: isAgent,
            agentId: agentId,
            content: content,
            timestamp: timestamp
        )
    }
}

// MARK: - CachedStandard

@Model
final class CachedStandard {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: String
    var content: String
    var isFavorite: Bool
    var readingPosition: Int?
    var updatedAt: Date
    var cachedAt: Date

    init(
        id: UUID,
        title: String,
        category: String,
        content: String,
        isFavorite: Bool,
        readingPosition: Int?,
        updatedAt: Date,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.content = content
        self.isFavorite = isFavorite
        self.readingPosition = readingPosition
        self.updatedAt = updatedAt
        self.cachedAt = cachedAt
    }

    convenience init(from standard: Standard) {
        self.init(
            id: standard.id,
            title: standard.title,
            category: standard.category.rawValue,
            content: standard.content,
            isFavorite: standard.isFavorite,
            readingPosition: standard.readingPosition,
            updatedAt: standard.updatedAt,
            cachedAt: Date()
        )
    }

    func toStandard() -> Standard {
        Standard(
            id: id,
            title: title,
            category: StandardCategory(rawValue: category) ?? .standards,
            content: content,
            authorId: UUID(),
            authorName: "",
            tags: [],
            version: 1,
            createdAt: cachedAt,
            updatedAt: updatedAt,
            isFavorite: isFavorite,
            readingPosition: readingPosition,
            relatedStandardIds: [],
            versions: []
        )
    }
}

// MARK: - ReadingHistory

@Model
final class ReadingHistory {
    @Attribute(.unique) var standardId: UUID
    var lastReadAt: Date
    var readingPosition: Int

    init(standardId: UUID, lastReadAt: Date, readingPosition: Int) {
        self.standardId = standardId
        self.lastReadAt = lastReadAt
        self.readingPosition = readingPosition
    }
}
