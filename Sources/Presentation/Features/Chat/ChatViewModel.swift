import Foundation

// MARK: - Channel

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
        case .general:   return "#"
        case .projects:  return "folder"
        case .agents:    return "cpu"
        case .research:  return "magnifyingglass"
        case .alerts:    return "bell"
        }
    }

    var displayName: String { type.rawValue }
}

enum ChatChannelType: String, CaseIterable, Sendable {
    case general  = "general"
    case projects = "projects"
    case agents   = "agents"
    case research = "research"
    case alerts   = "alerts"
}

// MARK: - Message

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
        isHighlighted: Bool = false
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
    }
}

enum AuthorRole: String, Sendable {
    case human
    case agent
    case system
}

// MARK: - Reaction

struct Reaction: Identifiable, Hashable, Sendable {
    let id: String
    let emoji: String
    var count: Int
    var userIds: [String]
    var isReactedByMe: Bool

    init(emoji: String, count: Int = 1, userIds: [String] = [], isReactedByMe: Bool = false) {
        self.id = emoji
        self.emoji = emoji
        self.count = count
        self.userIds = userIds
        self.isReactedByMe = isReactedByMe
    }
}

// MARK: - Message Group (for timestamp grouping)

struct MessageGroup: Identifiable, Sendable {
    let id: String
    let date: Date
    let messages: [Message]

    init(messages: [Message]) {
        self.id = messages.first?.id.uuidString ?? UUID().uuidString
        self.date = messages.first?.timestamp ?? Date()
        self.messages = messages
    }
}

// MARK: - ChatViewModel

import SwiftUI

@MainActor
@Observable
final class ChatViewModel {

    // MARK: - Mock IDs (replace with real auth/API data)

    static let mockUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let chGeneral = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    private static let chAgents  = UUID(uuidString: "00000000-0000-0000-0001-000000000002")!
    private static let chProjects = UUID(uuidString: "00000000-0000-0000-0001-000000000003")!
    private static let chResearch = UUID(uuidString: "00000000-0000-0000-0001-000000000004")!
    private static let chAlerts  = UUID(uuidString: "00000000-0000-0000-0001-000000000005")!
    private static let userAlexId = UUID(uuidString: "00000000-0000-0000-0002-000000000001")!
    private static let userSamId  = UUID(uuidString: "00000000-0000-0000-0002-000000000002")!
    private static let agentMauiId = UUID(uuidString: "00000000-0000-0000-0002-000000000010")!
    private static let agentClioId = UUID(uuidString: "00000000-0000-0000-0002-000000000011")!
    private static let systemId   = UUID(uuidString: "00000000-0000-0000-0002-000000000100")!

    // MARK: - State

    var channels: [Channel] = []
    var selectedChannel: Channel?
    var messages: [Message] = []
    var isLoading = false
    var isSending = false
    var highlightedAuthorId: UUID?
    var errorMessage: String?

    // MARK: - Computed

    var pinnedChannels: [Channel] {
        channels.filter(\.isPinned)
    }

    var unpinnedChannels: [Channel] {
        channels.filter { !$0.isPinned }
    }

    var currentUserIsAgent: Bool {
        false
    }

    // MARK: - Grouped Messages

    func groupedMessages(_ messages: [Message]) -> [MessageGroup] {
        guard !messages.isEmpty else { return [] }

        let calendar = Calendar.current
        var groups: [MessageGroup] = []
        var currentGroup: [Message] = []

        for message in messages.sorted(by: { $0.timestamp < $1.timestamp }) {
            let messageDate = calendar.startOfDay(for: message.timestamp)

            if let last = currentGroup.last {
                let lastDate = calendar.startOfDay(for: last.timestamp)
                if messageDate != lastDate {
                    if !currentGroup.isEmpty {
                        groups.append(MessageGroup(messages: currentGroup))
                    }
                    currentGroup = []
                }
            }

            // Check if consecutive messages from same author within 5 minutes
            if let last = currentGroup.last,
               last.authorId == message.authorId,
               message.timestamp.timeIntervalSince(last.timestamp) < 300 {
                currentGroup.append(message)
            } else {
                if !currentGroup.isEmpty {
                    groups.append(MessageGroup(messages: currentGroup))
                }
                currentGroup = [message]
            }
        }

        if !currentGroup.isEmpty {
            groups.append(MessageGroup(messages: currentGroup))
        }

        return groups
    }

    // MARK: - Actions

    @MainActor
    func loadChannels() async {
        isLoading = true
        errorMessage = nil

        let repo = ChannelRepository()
        await repo.loadChannels()
        channels = repo.channels

        if let error = repo.lastError {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    func loadMessages(channelId: UUID) async {
        isLoading = true
        errorMessage = nil

        let repo = ChannelRepository()
        let msgs = await repo.loadMessages(channelId: channelId)
        messages = msgs

        // Apply highlighting if set
        if let highlightId = highlightedAuthorId {
            messages = messages.map { msg in
                var m = msg
                m.isHighlighted = (m.authorId == highlightId)
                return m
            }
        }

        isLoading = false
    }

    @MainActor
    func sendMessage(channelId: UUID, content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSending = true

        // Optimistically add the message
        let newMessage = Message(
            channelId: channelId,
            authorId: UUID(),
            authorName: "You",
            authorRole: .human,
            content: content,
            timestamp: Date()
        )
        messages.append(newMessage)

        // Send via API
        let repo = ChannelRepository()
        try? await repo.sendMessage(channelId: channelId, content: content)

        isSending = false
    }

    func selectChannel(_ channel: Channel) {
        selectedChannel = channel
        // Clear unread count on selection
        if let idx = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[idx].unreadCount = 0
        }
    }

    func toggleMute(channelId: UUID) {
        if let idx = channels.firstIndex(where: { $0.id == channelId }) {
            channels[idx].isMuted.toggle()
        }
    }

    func highlightAgent(authorId: UUID) {
        highlightedAuthorId = authorId
        messages = messages.map { msg in
            var m = msg
            m.isHighlighted = (m.authorId == authorId)
            return m
        }
    }

    func clearHighlight() {
        highlightedAuthorId = nil
        messages = messages.map { msg in
            var m = msg
            m.isHighlighted = false
            return m
        }
    }

    func addReaction(to messageId: UUID, emoji: String) {
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            var reactions = messages[idx].reactions
            if let rIdx = reactions.firstIndex(where: { $0.emoji == emoji }) {
                if reactions[rIdx].isReactedByMe {
                    // Remove reaction
                    reactions[rIdx].count -= 1
                    reactions[rIdx].isReactedByMe = false
                } else {
                    reactions[rIdx].count += 1
                    reactions[rIdx].isReactedByMe = true
                }
            } else {
                reactions.append(Reaction(emoji: emoji, count: 1, isReactedByMe: true))
            }
            messages[idx].reactions = reactions
        }
    }
}

// MARK: - Date Formatting

extension Date {
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var groupDateString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Today"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: self)
        }
    }
}
