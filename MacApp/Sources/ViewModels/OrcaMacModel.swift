import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import OrcaAPI
import OrcaRuntime
import OrcaRuntimeContracts

@Observable
@MainActor
final class OrcaMacModel {
    static let defaultServerAddress = OrcaEndpointPolicy.productionOrigin

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
    var runtimeTurns: [String: Components.Schemas.ChatRuntimeTurnRead] = [:]
    var conversationMemories: [String: Components.Schemas.ConversationMemoryRead] = [:]
    var sectionSnapshots: [ConsoleSection: ConsoleSectionSnapshot] = [:]
    var lastUpdatedAt: Date?
    var presentedError: String?
    var sectionError: String?
    var serverAddress: String
    var hasStoredCredential = false
    var agents: [AgentProfile] = AgentProfile.fallbackRoster
    var isLoadingRuntimeEvidence = false
    var isApplyingMemoryProposal = false
    var runtimeEvidenceError: String?
    var providerControl: Components.Schemas.ChatRuntimeProviderControlBundleRead?
    var providerControlError: String?
    var isLoadingProviderControl = false

    @ObservationIgnored private let tokenStore: any RuntimeTokenStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var service: (any OrcaRuntimeServing)?
    @ObservationIgnored private var consoleService: OrcaConsoleService?
    @ObservationIgnored private var authService: OrcaNativeAuthService?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var providerRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var conversationScope: (origin: String, organizationID: String)?

    init(
        tokenStore: any RuntimeTokenStoring = RuntimeTokenStore(),
        defaults: UserDefaults = .standard
    ) {
        self.tokenStore = tokenStore
        self.defaults = defaults
        serverAddress = defaults.string(forKey: "orca.mac.runtime.server")
            ?? Self.defaultServerAddress
        let storedAgent = defaults.string(forKey: "orca.mac.selected-agent") ?? "coral"
        selectedAgentID = AgentProfile.fallbackRoster.contains(where: { $0.id == storedAgent })
            ? storedAgent
            : "coral"
        selectedSection = ConsoleSection(
            rawValue: defaults.string(forKey: "orca.mac.selected-section") ?? "overview"
        ) ?? .overview
    }

    var selectedAgent: AgentProfile {
        agents.first(where: { $0.id == selectedAgentID }) ?? agents[0]
    }

    var selectedConversation: ConversationState {
        conversations[selectedAgentID] ?? ConversationState(
            conversationID: storedConversationID(for: selectedAgentID)
        )
    }

    var selectedMessages: [TranscriptMessage] { selectedConversation.messages }

    var selectedRuntimeTurn: Components.Schemas.ChatRuntimeTurnRead? {
        runtimeTurns[selectedAgentID]
    }

    var selectedConversationMemory: Components.Schemas.ConversationMemoryRead? {
        conversationMemories[selectedAgentID]
    }

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
        let origin = Self.normalizedEndpoint(serverAddress).flatMap(OrcaServerOrigin.normalized) ?? ""
        do {
            hasStoredCredential = try await tokenStore.loadCredential(for: origin) != nil
        } catch {
            presentedError = error.localizedDescription
        }
        await connect()
    }

    func connect() async {
        refreshTask?.cancel()
        providerRefreshTask?.cancel()
        guard let endpoint = Self.normalizedEndpoint(serverAddress) else {
            connectionState = .unavailable("Invalid ORCA server address.")
            return
        }
        guard let origin = OrcaServerOrigin.normalized(endpoint) else {
            connectionState = .unavailable("Invalid ORCA server address.")
            return
        }
        do {
            guard try await tokenStore.loadCredential(for: origin) != nil else {
                hasStoredCredential = false
                service = nil
                consoleService = nil
                authService = nil
                deactivateConversationScope()
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
            let nextAuthService = try OrcaNativeAuthService(
                serverURL: endpoint,
                tokenStore: tokenStore
            )
            _ = try await nextAuthService.validAccessToken()
            guard let boundCredential = try await tokenStore.loadCredential(for: origin),
                  !boundCredential.organizationID.isEmpty else {
                throw OrcaNativeAuthError.missingSession
            }
            activateConversationScope(
                origin: origin,
                organizationID: boundCredential.organizationID
            )
            let nextService = OrcaRuntimeService(serverURL: endpoint, authService: nextAuthService)
            let compatibility = try await nextService.verifyCompatibility()
            authService = nextAuthService
            service = nextService
            let nextConsoleService = OrcaConsoleService(
                serverURL: endpoint,
                tokenStore: tokenStore,
                authService: nextAuthService,
                deviceID: await nextAuthService.boundDeviceID()
            )
            consoleService = nextConsoleService
            let runtimeAgents = try OrcaRuntimeProjection.profiles(
                from: await nextService.agentPacks()
            )
            guard !runtimeAgents.isEmpty else { throw OrcaConsoleServiceError.invalidResponse }
            agents = runtimeAgents
            if !agents.contains(where: { $0.id == selectedAgentID }) {
                selectedAgentID = agents[0].id
            }
            contractVersion = compatibility.contractVersion
            schemaSHA256 = compatibility.schemaSHA256
            connectionState = .ready
            await refreshProviderControl(silent: true)
            if selectedSection == .conversations {
                await refreshSelectedConversation(silent: true)
            } else {
                await refreshSelectedSection(silent: true)
            }
            beginRefreshLoop()
            beginProviderRefreshLoop()
        } catch let error as OrcaRuntimeClientError {
            service = nil
            consoleService = nil
            deactivateConversationScope()
            connectionState = .incompatible(error.localizedDescription)
        } catch {
            service = nil
            consoleService = nil
            deactivateConversationScope()
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
            let nextAuthService = try OrcaNativeAuthService(
                serverURL: endpoint,
                tokenStore: tokenStore
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
                let origin = Self.normalizedEndpoint(serverAddress).flatMap(OrcaServerOrigin.normalized) ?? ""
                try await tokenStore.deleteCredential(for: origin)
            }
            hasStoredCredential = false
            service = nil
            consoleService = nil
            authService = nil
            deactivateConversationScope()
            refreshTask?.cancel()
            providerRefreshTask?.cancel()
            await connect()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func selectAgent(_ id: String) {
        guard agents.contains(where: { $0.id == id }) else { return }
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
            let remote = try await loadAllMessages(service: service, conversationID: conversationID)
            var state = conversations[agentID] ?? ConversationState(conversationID: conversationID)
            state.conversationID = conversationID
            state.mergeCanonical(remote.map(Self.transcriptMessage))
            conversations[agentID] = state
            lastUpdatedAt = Date()
            await refreshRuntimeEvidence(
                agentID: agentID,
                conversationID: conversationID,
                turnID: state.messages.last(where: { $0.role == .user })?.id,
                silent: silent
            )
        } catch {
            if !silent { presentedError = error.localizedDescription }
        }
    }

    func sendDraft(retryIdentity: TurnRetryIdentity? = nil) async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let service, connectionState.isReady else { return }

        let agentID = selectedAgentID
        let traceID = retryIdentity?.traceID ?? "orca-mac-\(UUID().uuidString.lowercased())"
        let idempotencyKey = retryIdentity?.idempotencyKey ?? "orca-mac-turn:\(traceID)"
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
        state.appendPending(
            id: pendingID,
            content: content,
            at: startedAt,
            retryIdentity: TurnRetryIdentity(traceID: traceID, idempotencyKey: idempotencyKey)
        )
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
                    idempotencyKey: idempotencyKey,
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
                    deliveryState: .persisted,
                    retryIdentity: nil
                ),
            ]
            if !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                canonical.append(
                    TranscriptMessage(
                        id: response.assistantMessageID,
                        role: .agent,
                        content: response.content,
                        createdAt: Date(),
                        deliveryState: .persisted,
                        retryIdentity: nil
                    )
                )
            }
            resolved.resolvePending(id: pendingID, with: canonical)
            resolved.latestReceipt = RuntimeReceipt(
                turnID: response.userMessageID,
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
            await refreshConversation(
                agentID: agentID,
                conversationID: response.conversationID,
                turnID: response.userMessageID
            )
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
        await sendDraft(retryIdentity: message.retryIdentity)
    }

    static func normalizedEndpoint(_ raw: String) -> URL? {
        OrcaEndpointPolicy.normalizedEndpoint(raw)
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

    func refreshProviderControl(silent: Bool = false) async {
        guard let service else { return }
        isLoadingProviderControl = providerControl == nil
        defer { isLoadingProviderControl = false }
        do {
            providerControl = try await service.providerControl()
            providerControlError = nil
        } catch {
            providerControlError = error.localizedDescription
            if !silent { presentedError = error.localizedDescription }
        }
    }

    private func beginProviderRefreshLoop() {
        providerRefreshTask?.cancel()
        providerRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                await self.refreshProviderControl(silent: true)
            }
        }
    }

    func applyLatestMemoryProposal() async {
        guard let service,
              let memory = selectedConversationMemory,
              let proposal = memory.pendingProposals?.first else { return }
        isApplyingMemoryProposal = true
        defer { isApplyingMemoryProposal = false }
        do {
            let applied = try await service.applyConversationMemoryProposal(
                conversationID: memory.conversationId,
                proposalID: proposal.proposalId,
                reason: "Applied from ORCA Console after owner review."
            )
            conversationMemories[selectedAgentID] = applied
            runtimeEvidenceError = nil
            lastUpdatedAt = Date()
        } catch {
            runtimeEvidenceError = error.localizedDescription
            presentedError = error.localizedDescription
        }
    }

    private func refreshConversation(
        agentID: String,
        conversationID: String,
        turnID: String? = nil
    ) async {
        guard let service else { return }
        do {
            let remote = try await loadAllMessages(service: service, conversationID: conversationID)
            var state = conversations[agentID] ?? ConversationState(conversationID: conversationID)
            state.conversationID = conversationID
            state.mergeCanonical(remote.map(Self.transcriptMessage))
            conversations[agentID] = state
            lastUpdatedAt = Date()
            await refreshRuntimeEvidence(
                agentID: agentID,
                conversationID: conversationID,
                turnID: turnID ?? state.messages.last(where: { $0.role == .user })?.id,
                silent: true
            )
        } catch {
            // The immediate persisted response remains visible; polling retries.
        }
    }

    private func refreshRuntimeEvidence(
        agentID: String,
        conversationID: String,
        turnID: String?,
        silent: Bool
    ) async {
        guard let service else { return }
        isLoadingRuntimeEvidence = true
        defer { isLoadingRuntimeEvidence = false }
        var errors: [String] = []

        do {
            conversationMemories[agentID] = try await service.conversationMemory(
                conversationID: conversationID
            )
        } catch {
            errors.append("Memory: \(error.localizedDescription)")
        }

        if let turnID, !turnID.isEmpty {
            do {
                runtimeTurns[agentID] = try await service.runtimeTurn(turnID: turnID)
            } catch OrcaRuntimeClientError.httpStatus(404) {
                runtimeTurns.removeValue(forKey: agentID)
            } catch {
                if runtimeTurns[agentID]?.turnId != turnID {
                    runtimeTurns.removeValue(forKey: agentID)
                }
                errors.append("Turn: \(error.localizedDescription)")
            }
        } else {
            runtimeTurns.removeValue(forKey: agentID)
        }

        if agentID == selectedAgentID {
            runtimeEvidenceError = errors.isEmpty ? nil : errors.joined(separator: " ")
            if !silent, let runtimeEvidenceError {
                presentedError = runtimeEvidenceError
            }
        }
    }

    static func conversationDefaultsKey(
        origin: String,
        organizationID: String,
        agentID: String
    ) -> String {
        let material = "\(origin)\n\(organizationID)\n\(agentID.lowercased())"
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "orca.mac.conversation.v2.\(digest)"
    }

    func activateConversationScope(origin: String, organizationID: String) {
        let next = (origin: origin, organizationID: organizationID)
        if conversationScope?.origin != next.origin
            || conversationScope?.organizationID != next.organizationID {
            conversations.removeAll()
            runtimeTurns.removeAll()
            conversationMemories.removeAll()
        }
        conversationScope = next
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("orca.mac.conversation.")
                && !key.hasPrefix("orca.mac.conversation.v2.") {
            defaults.removeObject(forKey: key)
        }
    }

    private func deactivateConversationScope() {
        conversationScope = nil
        conversations.removeAll()
        runtimeTurns.removeAll()
        conversationMemories.removeAll()
        runtimeEvidenceError = nil
        providerControl = nil
        providerControlError = nil
        isLoadingProviderControl = false
    }

    private func storedConversationID(for agentID: String) -> String? {
        guard let conversationScope else { return nil }
        return defaults.string(forKey: Self.conversationDefaultsKey(
            origin: conversationScope.origin,
            organizationID: conversationScope.organizationID,
            agentID: agentID
        ))
    }

    private func loadAllMessages(
        service: any OrcaRuntimeServing,
        conversationID: String
    ) async throws -> [OrcaRuntimeConversationMessage] {
        let pageSize = 200
        let maximum = 5_000
        var offset = 0
        var output: [OrcaRuntimeConversationMessage] = []
        while output.count < maximum {
            let page = try await service.messages(
                conversationID: conversationID,
                offset: offset,
                limit: pageSize
            )
            output.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += page.count
        }
        return output
    }

    private func storeConversationID(_ conversationID: String, for agentID: String) {
        guard let conversationScope else { return }
        defaults.set(conversationID, forKey: Self.conversationDefaultsKey(
            origin: conversationScope.origin,
            organizationID: conversationScope.organizationID,
            agentID: agentID
        ))
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
            deliveryState: .persisted,
            retryIdentity: nil
        )
    }
}
