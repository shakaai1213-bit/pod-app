import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class DirectChatViewModel {
    // MARK: - State

    var navigationPath = NavigationPath()
    var selectedAgent: AgentInfo?
    var composedMessage: String = ""
    var isStreaming: Bool = false
    var streamingContent: String = ""
    var error: String?

    // Conversation data from SwiftData
    var conversations: [DMConversation] = []
    var currentMessages: [DMMessage] = []

    private var modelContext: ModelContext?
    private var currentService: AgentChatService?

    // MARK: - Setup

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadConversations()
    }

    // MARK: - Load Conversations

    func loadConversations() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<DMConversation>(
            sortBy: [SortDescriptor(\.lastMessageDate, order: .reverse)]
        )
        conversations = (try? ctx.fetch(descriptor)) ?? []
    }

    // MARK: - Select Agent

    func selectAgent(_ agent: AgentInfo) {
        selectedAgent = agent
        currentService = AgentChatService(agent: agent)
        loadMessages(for: agent)
    }

    func loadMessages(for agent: AgentInfo) {
        guard let ctx = modelContext else { return }
        let agentId = agent.id
        let descriptor = FetchDescriptor<DMMessage>(
            predicate: #Predicate<DMMessage> { msg in
                msg.conversation?.agentId == agentId
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        currentMessages = (try? ctx.fetch(descriptor)) ?? []
    }

    // MARK: - Get or Create Conversation

    private func getOrCreateConversation(for agent: AgentInfo) -> DMConversation {
        guard let ctx = modelContext else {
            fatalError("ModelContext not set")
        }

        // Try to find existing
        let agentId = agent.id
        let descriptor = FetchDescriptor<DMConversation>(
            predicate: #Predicate<DMConversation> { conv in
                conv.agentId == agentId
            }
        )
        if let existing = try? ctx.fetch(descriptor).first {
            return existing
        }

        // Create new
        let conv = DMConversation(agentId: agent.id)
        ctx.insert(conv)
        try? ctx.save()
        return conv
    }

    // MARK: - Send Message

    func sendMessage() {
        guard let agent = selectedAgent,
              !composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let text = composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        composedMessage = ""
        error = nil

        guard let ctx = modelContext else { return }

        // Save user message
        let conversation = getOrCreateConversation(for: agent)
        let userMsg = DMMessage(role: "user", content: text)
        userMsg.conversation = conversation
        ctx.insert(userMsg)

        conversation.lastMessageText = text
        conversation.lastMessageDate = Date()
        try? ctx.save()

        currentMessages.append(userMsg)

        // Create placeholder for assistant response
        let assistantMsg = DMMessage(role: "assistant", content: "", isStreaming: true)
        assistantMsg.conversation = conversation
        ctx.insert(assistantMsg)
        currentMessages.append(assistantMsg)

        isStreaming = true
        streamingContent = ""
        let startTime = Date()

        // Build history for context
        let history = currentMessages
            .filter { !$0.isStreaming }
            .map { (role: $0.role, content: $0.content) }

        // Stream via OpenClaw webhook injection
        let service = AgentChatService(agent: agent)

        Task {
            do {
                let stream = await service.send(message: text, history: history)
                for try await token in stream {
                    streamingContent += token
                    // Update the assistant message in-place
                    assistantMsg.content = streamingContent
                }

                // Finalize
                assistantMsg.isStreaming = false
                assistantMsg.latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                conversation.lastMessageText = assistantMsg.content
                conversation.lastMessageDate = Date()
                try? ctx.save()

                isStreaming = false
                loadConversations()
            } catch {
                assistantMsg.content = "Error: \(error.localizedDescription)"
                assistantMsg.isStreaming = false
                try? ctx.save()
                self.error = error.localizedDescription
                isStreaming = false
            }
        }
    }

    // MARK: - Agent Status

    func lastMessagePreview(for agent: AgentInfo) -> (text: String, date: Date?) {
        let conv = conversations.first { $0.agentId == agent.id }
        return (conv?.lastMessageText ?? "Tap to start chatting", conv?.lastMessageDate)
    }

    func unreadCount(for agent: AgentInfo) -> Int {
        conversations.first { $0.agentId == agent.id }?.unreadCount ?? 0
    }
}
