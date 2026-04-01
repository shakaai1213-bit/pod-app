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
    var replyTo: UUID?  // Parent message ID for threading

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
        replyTo: UUID? = nil
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
    var typingUsers: [TypingUser] = []
    var replyingTo: Message?
    private var lastMessageTimestamp: Date?
    private var pollingTask: Task<Void, Never>?
    private var typingSimTimer: Timer?

    // MARK: - SSE Streaming

    private var sseStreamManager: SSEStreamManager?
    private var sseListenTask: Task<Void, Never>?
    private var sseFallbackTimer: Timer?
    private var sseConnected = false

    // MARK: - Polling (SSE fallback — polls for new messages when chat is open)

    /// Start polling for new messages every 5 seconds
    func startPolling() {
        stopPolling()

        // Simulate typing: show agent "Maui" typing briefly every 15-30s when channel is general
        typingSimTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.simulateTyping()
            }
        }

        // Start SSE streaming
        startSSEStreaming()

        // Fallback: if SSE doesn't connect within 5s, fall back to polling
        sseFallbackTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.sseConnected == false {
                    self?.startPollingFallback()
                }
                self?.sseFallbackTimer = nil
            }
        }
    }

    private func startSSEStreaming() {
        guard let channelId = selectedChannel?.id else { return }
        guard let token = UserDefaults.standard.string(forKey: "orca_auth_token") else { return }

        sseStreamManager = SSEStreamManager()
        let manager = sseStreamManager!

        sseListenTask = Task { @MainActor in
            do {
                let baseURL = AppState.backendURL
                let events = await manager.connect(channelId: channelId.uuidString, token: token, baseURL: baseURL)

                for try await event in events {
                    switch event {
                    case .connected:
                        self.sseConnected = true
                        self.stopPollingFallback()
                    case .message(let payload):
                        await self.handleSSEMessage(payload)
                    case .keepalive:
                        break
                    case .error(let error):
                        print("[ChatViewModel] SSE error: \(error.localizedDescription)")
                        self.sseConnected = false
                    }
                }
            } catch {
                print("[ChatViewModel] SSE stream ended: \(error.localizedDescription)")
                self.sseConnected = false
            }
        }
    }

    private func handleSSEMessage(_ payload: MessageNewPayload) async {
        guard let channelId = selectedChannel?.id else { return }
        guard let payloadChannelId = UUID(uuidString: payload.channelId),
              payloadChannelId == channelId else { return }

        // Avoid duplicates
        let existingIds = Set(messages.map(\.id))
        guard !existingIds.contains(UUID(uuidString: payload.id) ?? UUID()) else { return }

        let newMessage = Message(
            id: UUID(uuidString: payload.id) ?? UUID(),
            channelId: channelId,
            authorId: UUID(uuidString: payload.senderId) ?? UUID(),
            authorName: payload.senderName,
            authorRole: payload.isThreadReply ? .human : .human,
            isAgent: false,
            agentId: nil,
            content: payload.content,
            timestamp: payload.timestamp ?? Date(),
            replyTo: payload.replyToId != nil ? UUID(uuidString: payload.replyToId!) : nil
        )
        messages.append(newMessage)
    }

    private func startPollingFallback() {
        pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                await TaskSafeSleep.sleep(seconds: 5)
                await pollForNewMessages()
                self.typingUsers.removeAll { Date().timeIntervalSince($0.startedAt) > 5 }
            }
        }
    }

    private func stopPollingFallback() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func simulateTyping() {
        guard selectedChannel?.type == .general else { return }
        let mauiTyping = TypingUser(id: "agent-maui", name: "Maui", isAgent: true)
        if !typingUsers.contains(where: { $0.id == mauiTyping.id }) {
            typingUsers.append(mauiTyping)
        }
        // Auto-clear after 3s
        Task { @MainActor in
            await TaskSafeSleep.sleep(seconds: 3)
            typingUsers.removeAll { $0.id == "agent-maui" }
        }
    }

    /// Stop polling
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        typingUsers = []
        typingSimTimer?.invalidate()
        typingSimTimer = nil
        sseFallbackTimer?.invalidate()
        sseFallbackTimer = nil
        sseListenTask?.cancel()
        sseListenTask = nil
        sseConnected = false
        if let mgr = sseStreamManager {
            Task { await mgr.disconnect() }
        }
        sseStreamManager = nil
    }

    /// Fetch new messages since last load and append any new ones
    @MainActor
    private func pollForNewMessages() async {
        guard let channelId = selectedChannel?.id else { return }
        guard !isLoading else { return }

        let repo = ChannelRepository()
        let latestTimestamp = messages.map(\.timestamp).max() ?? lastMessageTimestamp ?? Date.distantPast

        do {
            // Fetch with since parameter if backend supports it, otherwise fetch all and dedupe
            let dtos: [MessageDTO] = try await api.get(path: Endpoint.channelMessages(channelId: channelId.uuidString).path)
            let newMessages = await resolveMessageNames(dtos: dtos, channelId: channelId)

            // Only append truly new messages (not already in list)
            let existingIds = Set(messages.map(\.id))
            let fresh = newMessages.filter { !existingIds.contains($0.id) }
            if !fresh.isEmpty {
                messages.append(contentsOf: fresh.sorted { $0.timestamp < $1.timestamp })
                lastMessageTimestamp = fresh.map(\.timestamp).max()
            }
        } catch {
            // Silently ignore polling errors — background refresh
        }
    }

    // Re-declare api and resolveMessageNames for polling context
    private var api: APIClient { APIClient.shared }
    private func resolveMessageNames(dtos: [MessageDTO], channelId: UUID) async -> [Message] {
        await withTaskGroup(of: Message.self) { group in
            for dto in dtos {
                group.addTask {
                    let authorName = await UserNameCache.shared.displayName(userId: dto.authorId, agentId: dto.agentId)
                    return Message(
                        id: UUID(uuidString: dto.id) ?? UUID(),
                        channelId: channelId,
                        authorId: UUID(uuidString: dto.authorId) ?? UUID(),
                        authorName: authorName,
                        isAgent: dto.isAgent,
                        agentId: dto.agentId,
                        content: dto.content,
                        timestamp: dto.timestamp,
                        reactions: dto.reactions?.map { r in
                            Reaction(emoji: r.emoji, count: r.count, userIds: r.userIds, isReactedByMe: false)
                        } ?? []
                    )
                }
            }
            var results: [Message] = []
            for await msg in group { results.append(msg) }
            return results.sorted { $0.timestamp < $1.timestamp }
        }
    }

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
    func sendMessage(channelId: UUID, content: String, replyToId: UUID? = nil) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSending = true

        // Optimistically add the message with "Me" — will be corrected after API response
        let newMessage = Message(
            channelId: channelId,
            authorId: ChatViewModel.mockUserId,
            authorName: "Me",
            authorRole: .human,
            content: content,
            timestamp: Date(),
            replyTo: replyToId
        )
        messages.append(newMessage)

        // Send via API
        let repo = ChannelRepository()
        try? await repo.sendMessage(channelId: channelId, content: content, replyToId: replyToId)

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

    /// Relative timestamp for chat messages — "just now", "2m ago", "1h ago", etc.
    /// Falls back to absolute time for older messages.
    var relativeTimeString: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        // Future dates or within 30 seconds → "just now"
        if interval < 30 {
            return "just now"
        }

        // Within 1 minute → "1m ago"
        if interval < 60 {
            return "\(Int(interval))s ago"
        }

        // Within 1 hour → "5m ago"
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        }

        // Within today → "2h ago" or absolute time
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            if interval < 14400 { // < 4 hours
                let hours = Int(interval / 3600)
                return "\(hours)h ago"
            }
            // Fall through to absolute time
        }

        // Yesterday → "Yesterday at 2:30 PM"
        if calendar.isDateInYesterday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "'Yesterday at' h:mm a"
            return formatter.string(from: self)
        }

        // Older → absolute date and time
        let formatter = DateFormatter()
        formatter.dateStyle = .short
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
