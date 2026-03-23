import Foundation

// MARK: - Channel

struct Channel: Identifiable {
    let id: UUID
    let name: String
    let type: ChannelType
    let description: String
    let isPinned: Bool
    var unreadCount: Int
    var lastMessage: Message?
}

extension Channel: Codable {}
extension Channel: Hashable {}

// MARK: - Channel Type

enum ChannelType: String, Codable, CaseIterable {
    case general
    case project
    case agent
    case research
    case alerts
}

// MARK: - Message

struct Message: Identifiable {
    let id: UUID
    let channelId: UUID
    let authorId: UUID
    let content: String
    let timestamp: Date
    let isAgent: Bool
    let agentId: String?
    var reactions: [Reaction]
    var threadCount: Int
}

extension Message: Codable {}
extension Message: Hashable {}

// MARK: - Reaction

struct Reaction: Identifiable, Codable {
    let id: UUID
    let emoji: String
    let userIds: [UUID]
}

extension Reaction: Hashable {}
