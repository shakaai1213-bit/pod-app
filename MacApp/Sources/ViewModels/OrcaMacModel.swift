import AuthenticationServices
import Foundation
import Observation
import OrcaRuntimeContracts

@Observable
@MainActor
final class OrcaMacModel {
    static let defaultServerAddress = "http://100.104.72.62:8000"

    var selectedAgentID: String
    var selectedSection: ConsoleSection
    var selectedRecordID: String?
    var draft = ""
    var isSending = false
    var isLoadingSection = false
    var connectionState: RuntimeConnectionState = .idle
    var contractVersion: String?
    var schemaSHA256: String?
    var conversations: [String: ConversationState] = [:]
    var sectionSnapshots: [ConsoleSection: ConsoleSectionSnapshot] = [:]
    var lastUpdatedAt: Date?
    var presentedError: String?
    var sectionError: String?
    var serverAddress: String
    var hasStoredCredential = false

    @ObservationIgnored private let tokenStore: any RuntimeTokenStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var service: (any OrcaRuntimeServing)?
    @ObservationIgnored private var consoleService: OrcaConsoleService?
    @ObservationIgnored private var authService: OrcaNativeAuthService?
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
        selectedSection = ConsoleSection(
            rawValue: defaults.string(forKey: "orca.mac.selected-section") ?? "overview"
        ) ?? .overview
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

    var selectedSnapshot: ConsoleSectionSnapshot {
        sectionSnapshots[selectedSection] ?? .empty(selectedSection)
    }

    var selectedRecord: ConsoleRecord? {
        guard let selectedRecordID else { return nil }
        return selectedSnapshot.records.first(where: { $0.id == selectedRecordID })
    }

    var canSend: Bool {
        connectionState.isReady
            && !isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var connectionDetail: String? {
        switch connectionState {
        case let .runtimeUpgradeRequired(detail),
             let .incompatible(detail),
             let .unavailable(detail): return detail
        default: return nil
        }
    }

    func start() async {
        do {
            hasStoredCredential = try await tokenStore.loadCredential() != nil
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
            guard try await tokenStore.loadCredential() != nil else {
                hasStoredCredential = false
                service = nil
                consoleService = nil
                authService = nil
                switch await OrcaRuntimeService.probeContract(at: endpoint) {
                case .available:
                    connectionState = .credentialsRequired
                case .upgradeRequired:
                    connectionState = .runtimeUpgradeRequired(
                        "The connected ORCA backend does not expose Runtime API v1."
                    )
                case let .unavailable(detail):
                    connectionState = .unavailable(detail)
                }
                return
            }
            hasStoredCredential = true
            connectionState = .connecting
            let nextAuthService = OrcaNativeAuthService(
                serverURL: endpoint,
                tokenStore: tokenStore,
                defaults: defaults
            )
            _ = try await nextAuthService.validAccessToken()
            let nextService = OrcaRuntimeService(serverURL: endpoint, authService: nextAuthService)
            let compatibility = try await nextService.verifyCompatibility()
            authService = nextAuthService
            service = nextService
            consoleService = OrcaConsoleService(
                serverURL: endpoint,
                tokenStore: tokenStore,
                authService: nextAuthService,
                deviceID: await nextAuthService.boundDeviceID()
            )
            contractVersion = compatibility.contractVersion
            schemaSHA256 = compatibility.schemaSHA256
            connectionState = .ready
            if selectedSection == .conversations {
                await refreshSelectedConversation(silent: true)
            } else {
                await refreshSelectedSection(silent: true)
            }
            beginRefreshLoop()
        } catch let error as OrcaRuntimeClientError {
            service = nil
            consoleService = nil
            connectionState = .incompatible(error.localizedDescription)
        } catch {
            service = nil
            consoleService = nil
            connectionState = .unavailable(error.localizedDescription)
        }
    }

    func saveConnection(serverAddress: String) async {
        guard let endpoint = Self.normalizedEndpoint(serverAddress) else {
            presentedError = "Enter a valid ORCA server address."
            return
        }
        self.serverAddress = endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        defaults.set(self.serverAddress, forKey: "orca.mac.runtime.server")
        await connect()
    }

    func completeAppleSignIn(_ authorization: ASAuthorization) async {
        guard let endpoint = Self.normalizedEndpoint(serverAddress),
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            presentedError = "Apple did not return a usable ORCA identity token."
            return
        }
        do {
            let nextAuthService = OrcaNativeAuthService(
                serverURL: endpoint,
                tokenStore: tokenStore,
                defaults: defaults
            )
            try await nextAuthService.exchange(
                identityToken: identityToken,
                appleUserID: credential.user
            )
            authService = nextAuthService
            hasStoredCredential = true
            await connect()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func removeCredential() async {
        do {
            if let authService {
                try await authService.logout()
            } else {
                try await tokenStore.deleteCredential()
            }
            hasStoredCredential = false
            service = nil
            consoleService = nil
            authService = nil
            refreshTask?.cancel()
            await connect()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func selectAgent(_ id: String) {
        guard AgentProfile.roster.contains(where: { $0.id == id }) else { return }
        selectSection(.conversations, refresh: false)
        selectedAgentID = id
        defaults.set(id, forKey: "orca.mac.selected-agent")
        if conversations[id] == nil {
            conversations[id] = ConversationState(conversationID: storedConversationID(for: id))
        }
        Task { await refreshSelectedConversation(silent: true) }
    }

    func selectSection(_ section: ConsoleSection, refresh: Bool = true) {
        selectedSection = section
        selectedRecordID = nil
        defaults.set(section.rawValue, forKey: "orca.mac.selected-section")
        guard refresh else { return }
        Task {
            if section == .conversations {
                await refreshSelectedConversation(silent: true)
            } else {
                await refreshSelectedSection(silent: true)
            }
        }
    }

    func selectRecord(_ id: String?) {
        selectedRecordID = id
    }

    func refreshSelectedSection(silent: Bool = false) async {
        guard selectedSection != .conversations, let consoleService else { return }
        let section = selectedSection
        isLoadingSection = true
        do {
            let snapshot = try await consoleService.snapshot(for: section)
            sectionSnapshots[section] = snapshot
            sectionError = nil
            lastUpdatedAt = snapshot.updatedAt
            if let selectedRecordID,
               !snapshot.records.contains(where: { $0.id == selectedRecordID }) {
                self.selectedRecordID = nil
            }
        } catch {
            sectionError = error.localizedDescription
            if !silent { presentedError = error.localizedDescription }
        }
        isLoadingSection = false
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
                if self.selectedSection == .conversations {
                    await self.refreshSelectedConversation(silent: true)
                } else {
                    await self.refreshSelectedSection(silent: true)
                }
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
