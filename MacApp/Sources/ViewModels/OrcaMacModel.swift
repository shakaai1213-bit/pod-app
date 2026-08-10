import Foundation
import Observation
import OrcaRuntimeContracts

@Observable
@MainActor
final class OrcaMacModel {
    static let defaultServerAddress = "http://100.104.72.62:8000"

    var selectedAgentID: String
    var draft = ""
    var isSending = false
    var connectionState: RuntimeConnectionState = .idle
    var contractVersion: String?
    var schemaSHA256: String?
    var conversations: [String: ConversationState] = [:]
    var lastUpdatedAt: Date?
    var presentedError: String?
    var serverAddress: String
    var hasStoredCredential = false

    @ObservationIgnored private let tokenStore: any RuntimeTokenStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var service: (any OrcaRuntimeServing)?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        tokenStore: any RuntimeTokenStoring = RuntimeTokenStore(),
        defaults: UserDefaults = .standard
    ) {
        self.tokenStore = tokenStore
        self.defaults = defaults
        serverAddress = defaults.string(forKey: "orca.mac.runtime.server")
            ?? Self.defaultServerAddress
        let storedAgent = defaults.string(forKey: "orca.mac.selected-agent") ?? "coral"
        selectedAgentID = AgentProfile.roster.contains(where: { $0.id == storedAgent })
            ? storedAgent
            : "coral"
    }

    var agents: [AgentProfile] { AgentProfile.roster }

    var selectedAgent: AgentProfile {
        AgentProfile.roster.first(where: { $0.id == selectedAgentID }) ?? AgentProfile.roster[0]
    }

    var selectedConversation: ConversationState {
        conversations[selectedAgentID] ?? ConversationState(
            conversationID: storedConversationID(for: selectedAgentID)
        )
    }

    var selectedMessages: [TranscriptMessage] { selectedConversation.messages }

    var canSend: Bool {
        connectionState.isReady
            && !isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var connectionDetail: String? {
        switch connectionState {
        case let .incompatible(detail), let .unavailable(detail): return detail
        default: return nil
        }
    }

    func start() async {
        do {
            if let bootstrap = ProcessInfo.processInfo.environment["ORCA_AGENT_TOKEN"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !bootstrap.isEmpty {
                try await tokenStore.storeToken(bootstrap)
            }
            hasStoredCredential = try await tokenStore.loadToken() != nil
        } catch {
            presentedError = error.localizedDescription
        }
        await connect()
    }

    func connect() async {
        refreshTask?.cancel()
        guard let endpoint = Self.normalizedEndpoint(serverAddress) else {
            connectionState = .unavailable("Invalid ORCA server address.")
            return
        }
        do {
            guard try await tokenStore.loadToken() != nil else {
                hasStoredCredential = false
                connectionState = .credentialsRequired
                service = nil
                return
            }
            hasStoredCredential = true
            connectionState = .connecting
            let nextService = OrcaRuntimeService(serverURL: endpoint, tokenStore: tokenStore)
            let compatibility = try await nextService.verifyCompatibility()
            service = nextService
            contractVersion = compatibility.contractVersion
            schemaSHA256 = compatibility.schemaSHA256
            connectionState = .ready
            await refreshSelectedConversation(silent: true)
            beginRefreshLoop()
        } catch let error as OrcaRuntimeClientError {
            service = nil
            connectionState = .incompatible(error.localizedDescription)
        } catch {
            service = nil
            connectionState = .unavailable(error.localizedDescription)
        }
    }

    func saveConnection(serverAddress: String, token: String) async {
        guard let endpoint = Self.normalizedEndpoint(serverAddress) else {
            presentedError = "Enter a valid ORCA server address."
            return
        }
        do {
            let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedToken.isEmpty {
                try await tokenStore.storeToken(normalizedToken)
            }
            self.serverAddress = endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            defaults.set(self.serverAddress, forKey: "orca.mac.runtime.server")
            hasStoredCredential = try await tokenStore.loadToken() != nil
            await connect()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func removeCredential() async {
        do {
            try await tokenStore.deleteToken()
            hasStoredCredential = false
            service = nil
            refreshTask?.cancel()
            connectionState = .credentialsRequired
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func selectAgent(_ id: String) {
        guard AgentProfile.roster.contains(where: { $0.id == id }) else { return }
        selectedAgentID = id
        defaults.set(id, forKey: "orca.mac.selected-agent")
        if conversations[id] == nil {
            conversations[id] = ConversationState(conversationID: storedConversationID(for: id))
        }
        Task { await refreshSelectedConversation(silent: true) }
    }

    func refreshSelectedConversation(silent: Bool = false) async {
        guard let service else { return }
        let agentID = selectedAgentID
        guard let conversationID = conversations[agentID]?.conversationID
            ?? storedConversationID(for: agentID) else { return }
        do {
            let remote = try await service.messages(
                conversationID: conversationID,
                offset: 0,
                limit: 200
            )
            var state = conversations[agentID] ?? ConversationState(conversationID: conversationID)
            state.conversationID = conversationID
            state.mergeCanonical(remote.map(Self.transcriptMessage))
            conversations[agentID] = state
            lastUpdatedAt = Date()
        } catch {
            if !silent { presentedError = error.localizedDescription }
        }
    }

    func sendDraft() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let service, connectionState.isReady else { return }

        let agentID = selectedAgentID
        let traceID = "orca-mac-\(UUID().uuidString.lowercased())"
        let pendingID = "pending:\(traceID)"
        let startedAt = Date()
        var state = conversations[agentID]
            ?? ConversationState(conversationID: storedConversationID(for: agentID))
        let history = state.messages.compactMap { message -> OrcaRuntimeHistoryMessage? in
            guard message.deliveryState == .persisted, message.role != .system else { return nil }
            return OrcaRuntimeHistoryMessage(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            )
        }
        state.appendPending(id: pendingID, content: content, at: startedAt)
        conversations[agentID] = state
        draft = ""
        isSending = true
        presentedError = nil

        do {
            let response = try await service.send(
                OrcaRuntimeDirectTurnRequest(
                    agentSlug: agentID,
                    content: content,
                    history: Array(history.suffix(20)),
                    deliveryMode: "agent_inbox",
                    asyncResponse: true,
                    traceID: traceID,
                    idempotencyKey: "orca-mac-turn:\(traceID)",
                    conversationID: state.conversationID
                )
            )
            storeConversationID(response.conversationID, for: agentID)
            var resolved = conversations[agentID] ?? state
            resolved.conversationID = response.conversationID
            var canonical = [
                TranscriptMessage(
                    id: response.userMessageID,
                    role: .user,
                    content: content,
                    createdAt: startedAt,
                    deliveryState: .persisted
                ),
            ]
            if !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                canonical.append(
                    TranscriptMessage(
                        id: response.assistantMessageID,
                        role: .agent,
                        content: response.content,
                        createdAt: Date(),
                        deliveryState: .persisted
                    )
                )
            }
            resolved.resolvePending(id: pendingID, with: canonical)
            resolved.latestReceipt = RuntimeReceipt(
                traceID: response.traceID,
                source: response.source,
                lane: response.lane,
                deliveryMode: response.deliveryMode,
                responseState: response.responseState,
                provider: response.provider,
                model: response.model,
                tier: response.tier,
                computeRunID: response.computeRunID
            )
            conversations[agentID] = resolved
            lastUpdatedAt = Date()
            await refreshConversation(agentID: agentID, conversationID: response.conversationID)
        } catch {
            var failed = conversations[agentID] ?? state
            failed.failPending(id: pendingID, reason: error.localizedDescription)
            conversations[agentID] = failed
            presentedError = error.localizedDescription
        }
        isSending = false
    }

    func retryFailedMessage(_ message: TranscriptMessage) async {
        guard case .failed = message.deliveryState else { return }
        var state = conversations[selectedAgentID] ?? ConversationState()
        state.messages.removeAll { $0.id == message.id }
        conversations[selectedAgentID] = state
        draft = message.content
        await sendDraft()
    }

    static func normalizedEndpoint(_ raw: String) -> URL? {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if !normalized.contains("://") { normalized = "http://\(normalized)" }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }

    private func beginRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self else { return }
                await self.refreshSelectedConversation(silent: true)
            }
        }
    }

    private func refreshConversation(agentID: String, conversationID: String) async {
        guard let service else { return }
        do {
            let remote = try await service.messages(
                conversationID: conversationID,
                offset: 0,
                limit: 200
            )
            var state = conversations[agentID] ?? ConversationState(conversationID: conversationID)
            state.conversationID = conversationID
            state.mergeCanonical(remote.map(Self.transcriptMessage))
            conversations[agentID] = state
            lastUpdatedAt = Date()
        } catch {
            // The immediate persisted response remains visible; polling retries.
        }
    }

    private func storedConversationID(for agentID: String) -> String? {
        defaults.string(forKey: "orca.mac.conversation.\(agentID)")
    }

    private func storeConversationID(_ conversationID: String, for agentID: String) {
        defaults.set(conversationID, forKey: "orca.mac.conversation.\(agentID)")
    }

    private static func transcriptMessage(
        _ message: OrcaRuntimeConversationMessage
    ) -> TranscriptMessage {
        let role: TranscriptRole
        if message.messageType.lowercased() == "system" {
            role = .system
        } else if message.senderAgentID == nil {
            role = .user
        } else {
            role = .agent
        }
        return TranscriptMessage(
            id: message.id,
            role: role,
            content: message.content,
            createdAt: message.createdAt,
            deliveryState: .persisted
        )
    }
}
