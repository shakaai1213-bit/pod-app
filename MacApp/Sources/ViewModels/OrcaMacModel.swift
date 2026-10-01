import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import OrcaAPI
import OrcaRuntime
import OrcaRuntimeContracts

enum ConsoleAutomaticBoardRefreshStrategy: Equatable {
    case none
    case hydratePortfolio
    case selectedBoard
}

@Observable
@MainActor
final class OrcaMacModel {
    static let defaultServerAddress = OrcaEndpointPolicy.productionOrigin
    static let initialConversationRefreshLimit = 200
    static let incrementalConversationRefreshLimit = 50
    static let waitingOnCaptainRefreshIntervalSeconds: TimeInterval = 30

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
    var runtimeReconciliations: [String: OrcaRuntimeReconciliationUpdate] = [:]
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
    var workControl: OrcaWorkControlProjection?
    var workMode: ConsoleWorkMode = .portfolio
    var workMetricFilter: ConsoleWorkMetricFilter?
    var boards: [OrcaBoardDirectoryItem] = []
    var boardArchitectureProfilesByID: [UUID: OrcaBoardArchitectureProfile] = [:]
    var boardPlansByID: [UUID: OrcaBoardPlan] = [:]
    var selectedBoardID: UUID?
    var boardPlan: OrcaBoardPlan?
    var boardProjects: [OrcaBoardProjectSummary] = []
    var boardTasks: [OrcaBoardTaskSummary] = []
    var boardTickets: [OrcaBoardTicketSummary] = []
    var isLoadingBoardPlan = false
    var boardPlanError: String?
    var boardDetailError: String?
    var providerControlError: String?
    var isLoadingProviderControl = false
    var selectedWorkbenchPane: WorkbenchPane = .workspace
    var workbenchTickets: [WorkbenchTicketSummary] = []
    var selectedWorkbenchTicketID: String?
    var selectedWorkbenchOperationID: String?
    var workbenchContract: OrcaEngineeringWorkbenchContract?
    var workbenchSession: OrcaEngineeringWorkbenchSession?
    var workbenchRootID = "pod-client"
    var workbenchRelativePath = "."
    var workbenchSearchQuery = ""
    var workbenchPatchDraft = ""
    var isLoadingWorkbench = false
    var isSubmittingWorkbench = false
    var workbenchError: String?
    var workbenchNotice: String?
    var isDecidingApproval = false
    var approvalNotice: String?
    var approvalError: String?
    var activeTicketChat: TicketChatContext?
    var isOpeningTicketChat = false

    struct TicketChatContext: Equatable, Sendable {
        let ticketID: String
        let ownerSlug: String
        let title: String
        let channelID: String
        let returnSection: ConsoleSection
        let returnRecordID: String?
        let returnWorkbenchTicketID: String?

        var conversationKey: String { "ticket:\(ticketID)" }
    }

    @ObservationIgnored private var workbenchFetchGeneration = 0
    @ObservationIgnored private var sectionFetchGeneration = 0

    @ObservationIgnored private let tokenStore: any RuntimeTokenStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let deviceIDProvider: () -> String
    @ObservationIgnored private let runtimeCursorStore: OrcaRuntimeCursorStore
    @ObservationIgnored private var service: (any OrcaRuntimeServing)?
    @ObservationIgnored private var consoleService: OrcaConsoleService?
    @ObservationIgnored private var authService: OrcaNativeAuthService?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var providerRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var connectInFlight: (id: UUID, task: Task<Void, Never>)?
    @ObservationIgnored private var conversationScope: (origin: String, organizationID: String)?
    @ObservationIgnored private var lastWaitingOnCaptainRefreshAt: Date?
    @ObservationIgnored private var runtimeReconciliationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var runtimeReconciliationTurnIDs: [String: String] = [:]

    init(
        tokenStore: any RuntimeTokenStoring = RuntimeTokenStore(),
        defaults: UserDefaults = .standard,
        deviceIDProvider: @escaping () -> String = { OrcaDeviceIdentity.current() }
    ) {
        self.tokenStore = tokenStore
        self.defaults = defaults
        self.deviceIDProvider = deviceIDProvider
        runtimeCursorStore = OrcaRuntimeCursorStore(defaults: defaults)
        serverAddress = defaults.string(forKey: "orca.mac.runtime.server")
            ?? Self.defaultServerAddress
        let storedAgent = defaults.string(forKey: "orca.mac.selected-agent") ?? "coral"
        selectedAgentID = AgentProfile.fallbackRoster.contains(where: { $0.id == storedAgent })
            ? storedAgent
            : "coral"
        workMode = ConsoleWorkMode(
            rawValue: defaults.string(forKey: "orca.mac.work-mode") ?? ""
        ) ?? .portfolio
        let storedSection = ConsoleSection(
            rawValue: defaults.string(forKey: "orca.mac.selected-section") ?? "overview"
        ) ?? .overview
        if storedSection == .waitingOnCaptain {
            selectedSection = .work
            workMode = .captain
            defaults.set(ConsoleSection.work.rawValue, forKey: "orca.mac.selected-section")
            defaults.set(ConsoleWorkMode.captain.rawValue, forKey: "orca.mac.work-mode")
        } else {
            selectedSection = storedSection
        }
    }

    var selectedAgent: AgentProfile {
        agents.first(where: { $0.id == selectedAgentID }) ?? agents[0]
    }

    var selectedConversation: ConversationState {
        if let ticketChat = activeTicketChat {
            return conversations[ticketChat.conversationKey]
                ?? ConversationState(conversationID: ticketChat.channelID)
        }
        return conversations[selectedAgentID] ?? ConversationState(
            conversationID: storedConversationID(for: selectedAgentID)
        )
    }

    var selectedMessages: [TranscriptMessage] { selectedConversation.messages }

    var selectedRuntimeTurn: Components.Schemas.ChatRuntimeTurnRead? {
        runtimeTurns[activeTicketChat?.conversationKey ?? selectedAgentID]
    }

    var selectedRuntimeReconciliation: OrcaRuntimeReconciliationUpdate? {
        runtimeReconciliations[selectedAgentID]
    }

    var selectedConversationMemory: Components.Schemas.ConversationMemoryRead? {
        conversationMemories[activeTicketChat?.conversationKey ?? selectedAgentID]
    }

    private var activeConversationKey: String {
        activeTicketChat?.conversationKey ?? selectedAgentID
    }

    func openTicketChat(ticketID: String, ownerSlug: String?, title: String) async {
        approvalError = nil
        approvalNotice = nil
        guard let consoleService, connectionState.isReady, !isOpeningTicketChat else { return }
        isOpeningTicketChat = true
        defer { isOpeningTicketChat = false }
        do {
            let thread = try await consoleService.ensureTicketChatThread(ticketID: ticketID)
            let context = TicketChatContext(
                ticketID: ticketID,
                ownerSlug: thread.ownerAgentSlug,
                title: title,
                channelID: thread.channelId,
                returnSection: selectedSection,
                returnRecordID: selectedRecordID,
                returnWorkbenchTicketID: selectedSection == .workbench ? selectedWorkbenchTicketID : nil
            )
            activeTicketChat = context
            if conversations[context.conversationKey] == nil {
                conversations[context.conversationKey] = ConversationState(conversationID: thread.channelId)
            } else {
                conversations[context.conversationKey]?.conversationID = thread.channelId
            }
            selectedSection = .conversations
            await refreshSelectedConversation(silent: true)
        } catch let error as OrcaConsoleServiceError {
            if case let .httpStatus(409, detail) = error, detail == "ticket_has_no_owner" {
                presentedError = "Assign an owner first"
            } else {
                presentedError = error.localizedDescription
            }
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func closeTicketChat() {
        guard let context = activeTicketChat else { return }
        activeTicketChat = nil
        selectedSection = context.returnSection
        selectedRecordID = context.returnRecordID
        if context.returnSection == .workbench, let ticketID = context.returnWorkbenchTicketID {
            selectedWorkbenchTicketID = ticketID
            Task { await refreshWorkbenchSession(silent: true) }
        }
        Task { await refreshCurrentSurface(silent: true) }
    }

    func injectServicesForTesting(
        runtime: (any OrcaRuntimeServing)?,
        console: OrcaConsoleService?
    ) {
        service = runtime
        consoleService = console
    }

    var selectedSnapshot: ConsoleSectionSnapshot {
        sectionSnapshots[selectedSection] ?? .empty(selectedSection)
    }

    var selectedRecord: ConsoleRecord? {
        guard let selectedRecordID else { return nil }
        return selectedSnapshot.records.first(where: { $0.id == selectedRecordID })
    }

    var displayedWorkRecords: [ConsoleRecord] {
        guard let workMetricFilter else { return selectedSnapshot.records }
        return selectedSnapshot.records(matching: workMetricFilter)
    }

    func toggleWorkMetricFilter(_ metricID: String) {
        guard selectedSection == .work || selectedSection == .waitingOnCaptain,
              workMode == .agentWork || workMode == .captain || workMode == .team else { return }
        guard let filter = ConsoleWorkMetricFilter.filter(forMetricID: metricID) else { return }
        workMetricFilter = workMetricFilter == filter ? nil : filter
        clearStaleApprovalOutcome()
        reconcileRecordSelectionWithFilter()
    }

    func activateConsoleMetric(_ metricID: String, refresh: Bool = true) {
        if selectedSection == .overview, metricID == "attention" {
            selectSection(.waitingOnCaptain, refresh: refresh)
            return
        }
        toggleWorkMetricFilter(metricID)
    }

    private func reconcileRecordSelectionWithFilter() {
        guard let workMetricFilter, let selectedRecordID else { return }
        let visible = selectedSnapshot.records(matching: workMetricFilter)
        if !visible.contains(where: { $0.id == selectedRecordID }) {
            self.selectedRecordID = nil
        }
    }

    private func clearStaleApprovalOutcome() {
        guard approvalError != nil || approvalNotice != nil else { return }
        approvalError = nil
        approvalNotice = nil
    }

    private func recordSelectionChanged(to id: String?) {
        guard id != selectedRecordID else { return }
        clearStaleApprovalOutcome()
    }

    var selectedWorkbenchTicket: WorkbenchTicketSummary? {
        guard let selectedWorkbenchTicketID else { return nil }
        return workbenchTickets.first(where: { $0.id == selectedWorkbenchTicketID })
    }

    var selectedWorkbenchOperation: OrcaEngineeringOperation? {
        guard let selectedWorkbenchOperationID else { return nil }
        return workbenchSession?.operations.first(where: { $0.id == selectedWorkbenchOperationID })
    }

    var selectedWorkbenchRoot: OrcaEngineeringRoot? {
        workbenchContract?.roots.first(where: { $0.id == workbenchRootID })
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
        if let connectInFlight {
            await connectInFlight.task.value
            return
        }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performConnect()
        }
        connectInFlight = (id, task)
        await task.value
        if connectInFlight?.id == id {
            connectInFlight = nil
        }
    }

    private func performConnect() async {
        refreshTask?.cancel()
        providerRefreshTask?.cancel()
        stopRuntimeReconciliation()
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
                workMetricFilter = nil
            }
            let channelIDs = try await nextConsoleService.directAgentChannelIDs(
                allowedAgentIDs: Set(agents.map(\.id))
            )
            hydrateCanonicalConversationIDs(channelIDs)
            contractVersion = compatibility.contractVersion
            schemaSHA256 = compatibility.schemaSHA256
            connectionState = .ready
            await refreshProviderControl(silent: true)
            await refreshCurrentSurface(silent: true)
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
        sectionFetchGeneration += 1
        isLoadingSection = false
        recordSelectionChanged(to: nil)
        selectedRecordID = nil
        workMetricFilter = nil
        if section == .waitingOnCaptain {
            selectedSection = .work
            workMode = .captain
        } else {
            selectedSection = section
            if section == .work, workMode == .captain {
                workMode = .portfolio
            }
        }
        defaults.set(selectedSection.rawValue, forKey: "orca.mac.selected-section")
        defaults.set(workMode.rawValue, forKey: "orca.mac.work-mode")
        if refreshTask != nil {
            beginRefreshLoop()
        }
        guard refresh else { return }
        Task { await refreshCurrentSurface(silent: true) }
    }

    func selectWorkControlAgent(_ id: String) {
        guard agents.contains(where: { $0.id == id }) else { return }
        sectionFetchGeneration += 1
        isLoadingSection = false
        recordSelectionChanged(to: nil)
        selectedAgentID = id
        selectedRecordID = nil
        workMetricFilter = nil
        defaults.set(id, forKey: "orca.mac.selected-agent")
        Task { await refreshSelectedSection(silent: true) }
    }

    func selectWorkMode(_ mode: ConsoleWorkMode) {
        if selectedSection != .work {
            selectSection(.work, refresh: false)
        }
        sectionFetchGeneration += 1
        isLoadingSection = false
        recordSelectionChanged(to: nil)
        workMode = mode
        selectedRecordID = nil
        defaults.set(mode.rawValue, forKey: "orca.mac.work-mode")
        workMetricFilter = nil
        workControl = nil
        sectionSnapshots[.work] = .empty(.work)
        sectionError = nil
        Task { await refreshSelectedSection(silent: true) }
    }

    func selectBoard(_ id: UUID) {
        guard let board = boards.first(where: { $0.id == id }) else { return }
        selectedBoardID = id
        boardPlan = nil
        boardProjects = []
        boardTasks = []
        boardTickets = []
        boardPlanError = nil
        boardDetailError = nil
        guard !board.isProtected else { return }
        Task { await refreshSelectedBoardPlan(silent: true) }
    }

    func selectRecord(_ id: String?) {
        recordSelectionChanged(to: id)
        selectedRecordID = id
    }

    func refreshSelectedSection(
        silent: Bool = false,
        refreshPortfolio: Bool = true
    ) async {
        guard selectedSection != .conversations,
              selectedSection != .workbench,
              let consoleService else { return }
        sectionFetchGeneration += 1
        let generation = sectionFetchGeneration
        let section = selectedSection
        let mode = workMode
        let agentID = selectedAgentID
        isLoadingSection = true
        defer {
            if generation == sectionFetchGeneration { isLoadingSection = false }
        }
        do {
            let bundle: Components.Schemas.ChatRuntimeWorkControlBundleRead?
            if section == .work, mode == .agentWork {
                guard let service else { throw OrcaConsoleServiceError.invalidResponse }
                bundle = try await service.workControl(agentKey: agentID)
            } else {
                bundle = nil
            }
            let snapshot: ConsoleSectionSnapshot
            if section == .work, mode == .team {
                snapshot = try await consoleService.teamWorkLensSnapshot()
            } else {
                snapshot = try await consoleService.snapshot(for: section, workControl: bundle)
            }
            guard generation == sectionFetchGeneration,
                  section == selectedSection,
                  mode == workMode,
                  agentID == selectedAgentID else { return }
            if section == .work {
                workControl = bundle.map(OrcaWorkControlProjection.init)
            }
            sectionSnapshots[section] = snapshot
            if section == .waitingOnCaptain
                || section == .work && mode == .captain {
                sectionSnapshots[.waitingOnCaptain] = snapshot
                lastWaitingOnCaptainRefreshAt = Date()
            }
            sectionError = nil
            lastUpdatedAt = snapshot.updatedAt
            if let selectedRecordID,
               !snapshot.records.contains(where: { $0.id == selectedRecordID }) {
                recordSelectionChanged(to: nil)
                self.selectedRecordID = nil
            }
            if section == .work, refreshPortfolio, mode == .portfolio {
                await refreshBoardPortfolio(silent: true)
            }
        } catch {
            guard generation == sectionFetchGeneration,
                  section == selectedSection,
                  mode == workMode,
                  agentID == selectedAgentID else { return }
            if section == .fund {
                sectionSnapshots[section] = .empty(section)
                selectedRecordID = nil
            }
            sectionError = error.localizedDescription
            if !silent { presentedError = error.localizedDescription }
        }
    }

    func refreshBoardPortfolio(silent: Bool = false) async {
        guard let consoleService, !isLoadingBoardPlan else { return }
        isLoadingBoardPlan = true
        defer { isLoadingBoardPlan = false }
        do {
            let directory = try await consoleService.boardArchitectureDirectory()
            boardArchitectureProfilesByID = Dictionary(
                uniqueKeysWithValues: directory.profiles.map { ($0.id, $0) }
            )
            boards = directory.directoryItems
                .sorted { left, right in
                    if left.slug == "pod" { return true }
                    if right.slug == "pod" { return false }
                    return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
                }
            if selectedBoardID == nil || !boards.contains(where: { $0.id == selectedBoardID }) {
                selectedBoardID = boards.first(where: { $0.slug == "pod" })?.id ?? boards.first?.id
            }
            boardPlansByID = await loadProductBoardPlans(
                service: consoleService,
                boards: Array(boards.filter(\.isProduct).prefix(6))
            )
            do {
                try await loadSelectedBoardPlan()
                boardPlanError = nil
            } catch {
                boardPlanError = error.localizedDescription
            }
            await loadSelectedBoardDetail()
        } catch {
            boardPlanError = error.localizedDescription
            if !silent { presentedError = error.localizedDescription }
        }
    }

    func refreshSelectedBoardPlan(silent: Bool = false) async {
        guard !isLoadingBoardPlan else { return }
        isLoadingBoardPlan = true
        defer { isLoadingBoardPlan = false }
        do {
            try await loadSelectedBoardPlan()
            boardPlanError = nil
        } catch {
            boardPlanError = error.localizedDescription
            if !silent { presentedError = error.localizedDescription }
        }
        await loadSelectedBoardDetail()
    }

    private func loadSelectedBoardPlan() async throws {
        guard let consoleService, let selectedBoardID else {
            boardPlan = nil
            return
        }
        guard boards.first(where: { $0.id == selectedBoardID })?.isProtected != true else {
            boardPlan = nil
            return
        }
        if let cached = boardPlansByID[selectedBoardID] {
            boardPlan = cached
        } else {
            boardPlan = try await consoleService.boardPlan(boardID: selectedBoardID)
        }
    }

    private func loadSelectedBoardDetail() async {
        boardProjects = []
        boardTasks = []
        boardTickets = []
        boardDetailError = nil
        guard let consoleService,
              let selectedBoardID,
              let board = boards.first(where: { $0.id == selectedBoardID }),
              !board.isProtected else { return }
        var errors: [String] = []
        do {
            let profile = try await consoleService.boardArchitectureProfile(boardID: selectedBoardID)
            guard profile.header.boardID == selectedBoardID else {
                throw OrcaConsoleServiceError.invalidResponse
            }
            boardArchitectureProfilesByID[selectedBoardID] = profile
        } catch {
            errors.append("Architecture profile refresh unavailable; showing the directory snapshot.")
        }
        let protectedBoardIDs = Set(boards.filter(\.isProtected).map(\.id))
        guard !protectedBoardIDs.isEmpty else {
            boardDetailError = "Protected board boundary is unavailable; board detail failed closed."
            return
        }

        do {
            boardProjects = try await consoleService.boardProjects(
                boardID: selectedBoardID,
                protectedBoardIDs: protectedBoardIDs
            )
            .sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            errors.append("Projects unavailable.")
        }
        do {
            boardTasks = try await consoleService.boardTasks(boardID: selectedBoardID)
                .sorted { workStateSort($0.status, $0.title, $1.status, $1.title) }
        } catch {
            errors.append("Tasks unavailable.")
        }
        do {
            boardTickets = try await consoleService.boardTickets(boardID: selectedBoardID)
                .sorted { workStateSort($0.status, $0.title, $1.status, $1.title) }
        } catch {
            errors.append("Tickets unavailable.")
        }
        boardDetailError = errors.isEmpty ? nil : errors.joined(separator: " ")
    }

    private func workStateSort(
        _ leftState: String,
        _ leftTitle: String,
        _ rightState: String,
        _ rightTitle: String
    ) -> Bool {
        let leftRank = workStateRank(leftState)
        let rightRank = workStateRank(rightState)
        if leftRank != rightRank { return leftRank < rightRank }
        return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
    }

    private func workStateRank(_ state: String) -> Int {
        switch state.lowercased() {
        case "in_progress", "in-progress", "working": return 0
        case "review": return 1
        case "blocked", "waiting_on", "failed": return 2
        case "open", "inbox", "backlog", "planned": return 3
        case "done", "completed", "closed", "resolved": return 8
        case "archived", "cancelled": return 9
        default: return 4
        }
    }

    private func loadProductBoardPlans(
        service: OrcaConsoleService,
        boards: [OrcaBoardDirectoryItem]
    ) async -> [UUID: OrcaBoardPlan] {
        await withTaskGroup(of: (UUID, OrcaBoardPlan?).self) { group in
            for board in boards {
                group.addTask {
                    (board.id, try? await service.boardPlan(boardID: board.id))
                }
            }
            var plans: [UUID: OrcaBoardPlan] = [:]
            for await (id, plan) in group {
                if let plan { plans[id] = plan }
            }
            return plans
        }
    }

    func refreshCurrentSurface(
        silent: Bool = false,
        automatic: Bool = false
    ) async {
        let hasOwnWorkProjection = selectedSection == .work
            && (workMode == .captain || workMode == .team)
        if !hasOwnWorkProjection,
           !automatic || Self.shouldRefreshWaitingOnCaptain(
               lastRefreshAt: lastWaitingOnCaptainRefreshAt,
               now: Date()
           ) {
            await refreshWaitingOnCaptainSnapshot(silent: true)
        }
        switch selectedSection {
        case .conversations:
            await refreshSelectedConversation(silent: silent)
        case .workbench:
            await refreshWorkbench(silent: silent)
        default:
            await refreshSelectedSection(
                silent: silent,
                refreshPortfolio: !automatic
            )
            if automatic {
                switch Self.automaticBoardRefreshStrategy(
                    section: selectedSection,
                    workMode: workMode,
                    hasBoards: !boards.isEmpty
                ) {
                case .hydratePortfolio:
                    await refreshBoardPortfolio(silent: true)
                case .selectedBoard:
                    await refreshSelectedBoardPlan(silent: true)
                case .none:
                    break
                }
            }
        }
    }

    private func refreshWaitingOnCaptainSnapshot(silent: Bool) async {
        guard let consoleService else { return }
        defer { lastWaitingOnCaptainRefreshAt = Date() }
        do {
            sectionSnapshots[.waitingOnCaptain] = try await consoleService.snapshot(
                for: .waitingOnCaptain,
                workControl: nil
            )
        } catch {
            if !silent { presentedError = error.localizedDescription }
        }
    }

    func selectWorkbenchAgent(_ id: String) {
        guard agents.contains(where: { $0.id == id }) else { return }
        selectedAgentID = id
        defaults.set(id, forKey: "orca.mac.selected-agent")
        workbenchFetchGeneration += 1
        workbenchTickets = []
        workbenchContract = nil
        workbenchSession = nil
        selectedWorkbenchTicketID = nil
        selectedWorkbenchOperationID = nil
        workbenchError = nil
        Task { await refreshWorkbench(silent: true) }
    }

    func selectWorkbenchTicket(_ id: String?) {
        guard id == nil || workbenchTickets.contains(where: { $0.id == id }) else { return }
        selectedWorkbenchTicketID = id
        selectedWorkbenchOperationID = nil
        workbenchSession = nil
        workbenchError = nil
        Task { await refreshWorkbenchSession(silent: true) }
    }

    func selectWorkbenchOperation(_ id: String?) {
        selectedWorkbenchOperationID = id
    }

    func refreshWorkbench(silent: Bool = false) async {
        guard let consoleService else { return }
        workbenchFetchGeneration += 1
        let generation = workbenchFetchGeneration
        let agentID = selectedAgentID
        isLoadingWorkbench = true
        defer {
            if generation == workbenchFetchGeneration { isLoadingWorkbench = false }
        }
        do {
            async let contract = consoleService.workbenchContract(agentSlug: agentID)
            async let tickets = consoleService.workbenchTickets(agentSlug: agentID)
            let (nextContract, nextTickets) = try await (contract, tickets)
            guard generation == workbenchFetchGeneration, selectedAgentID == agentID else { return }
            workbenchContract = nextContract
            workbenchTickets = nextTickets
            if selectedWorkbenchTicketID == nil
                || !nextTickets.contains(where: { $0.id == selectedWorkbenchTicketID }) {
                selectedWorkbenchTicketID = nextTickets.first(where: {
                    !["closed", "cancelled"].contains($0.status.lowercased())
                })?.id ?? nextTickets.first?.id
            }
            if !nextContract.roots.contains(where: { $0.id == workbenchRootID }) {
                workbenchRootID = nextContract.roots.first?.id ?? ""
            }
            workbenchError = nil
            await refreshWorkbenchSession(silent: true)
            lastUpdatedAt = Date()
        } catch {
            guard generation == workbenchFetchGeneration, selectedAgentID == agentID else { return }
            workbenchSession = nil
            workbenchError = error.localizedDescription
            if !silent { presentedError = error.localizedDescription }
        }
    }

    func refreshWorkbenchSession(silent: Bool = false) async {
        workbenchFetchGeneration += 1
        guard let consoleService,
              let ticketID = selectedWorkbenchTicketID,
              workbenchTickets.contains(where: { $0.id == ticketID }) else {
            workbenchSession = nil
            return
        }
        let generation = workbenchFetchGeneration
        let agentID = selectedAgentID
        workbenchError = nil
        do {
            let next = try await consoleService.workbenchSession(
                ticketID: ticketID,
                agentSlug: agentID
            )
            guard generation == workbenchFetchGeneration,
                  selectedAgentID == agentID,
                  selectedWorkbenchTicketID == ticketID else { return }
            workbenchSession = next
            workbenchContract = next.contract
            workbenchError = nil
            if let selectedWorkbenchOperationID,
               !next.operations.contains(where: { $0.id == selectedWorkbenchOperationID }) {
                self.selectedWorkbenchOperationID = nil
            }
            lastUpdatedAt = Date()
        } catch {
            guard generation == workbenchFetchGeneration,
                  selectedAgentID == agentID,
                  selectedWorkbenchTicketID == ticketID else { return }
            workbenchError = error.localizedDescription
            if !silent { presentedError = error.localizedDescription }
        }
    }

    func submitWorkbenchAction(_ actionID: String) async {
        guard let consoleService,
              let ticketID = selectedWorkbenchTicketID,
              let contract = workbenchContract,
              let action = contract.actions.first(where: { $0.id == actionID }),
              action.available,
              action.allowedRootIDs.contains(workbenchRootID),
              !isSubmittingWorkbench else { return }
        let query = actionID == "search.rg"
            ? workbenchSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let patch = actionID == "patch.draft"
            ? workbenchPatchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        if actionID == "search.rg" && (query?.isEmpty ?? true) {
            workbenchError = "Enter a search query before starting Search Workspace."
            return
        }
        if actionID == "patch.draft" && (patch?.isEmpty ?? true) {
            workbenchError = "Enter a unified diff before staging a patch draft."
            return
        }
        if actionID != "patch.draft", !contract.host.ready {
            workbenchError = contract.host.reason
            return
        }
        let enteredPath = workbenchRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)

        isSubmittingWorkbench = true
        defer { isSubmittingWorkbench = false }
        do {
            let result = try await consoleService.createWorkbenchOperation(
                ticketID: ticketID,
                payload: OrcaEngineeringOperationCreate(
                    agentSlug: selectedAgentID,
                    actionID: actionID,
                    rootID: workbenchRootID,
                    relativePath: enteredPath.isEmpty ? "." : enteredPath,
                    searchQuery: query,
                    patch: patch,
                    idempotencyKey: "orca-console-workbench:\(UUID().uuidString.lowercased())"
                )
            )
            workbenchNotice = result.message
            workbenchError = nil
            selectedWorkbenchOperationID = result.operation.id
            await refreshWorkbenchSession(silent: true)
        } catch {
            workbenchError = error.localizedDescription
            presentedError = error.localizedDescription
        }
    }

    func decideWorkbenchApproval(
        operation: OrcaEngineeringOperation,
        decision: String,
        note: String? = nil
    ) async {
        guard let consoleService, !isSubmittingWorkbench else { return }
        workbenchNotice = nil
        guard operation.approvalStatus == "pending",
              operation.status == "waiting_for_human",
              operation.approvalID != nil else {
            workbenchError = "This exact operation has no pending approval or is no longer waiting for Captain review. Refresh Workbench."
            return
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if decision == "rejected" && !(3...1000).contains(trimmedNote.count) {
            workbenchError = "A rejection reason must be 3 to 1000 characters."
            return
        }
        isSubmittingWorkbench = true
        defer { isSubmittingWorkbench = false }
        do {
            let updated = try await consoleService.decideWorkbenchApproval(
                runID: operation.id,
                decision: OrcaEngineeringApprovalDecision(
                    decision: decision,
                    note: trimmedNote.isEmpty
                        ? "Approved from ORCA Console for this exact AgentRun."
                        : trimmedNote
                )
            )
            selectedWorkbenchOperationID = updated.id
            workbenchNotice = "Operation \(updated.id.prefix(8)) is \(decision)."
            workbenchError = nil
            await refreshWorkbenchSession(silent: true)
        } catch {
            let message = error.localizedDescription
            await refreshWorkbenchSession(silent: true)
            workbenchError = message
            presentedError = message
        }
    }

    func decideTicketApproval(
        recordID: String,
        decision: ConsoleTicketApprovalDecision,
        reason: String
    ) async {
        approvalNotice = nil
        approvalError = nil
        guard let consoleService, !isDecidingApproval else { return }
        guard let record = sectionSnapshots[selectedSection]?.records.first(where: { $0.id == recordID }),
              let approval = record.approval else {
            approvalError = "That approval is no longer in view. Refresh and try again."
            presentedError = nil
            return
        }
        guard approval.isCaptainAuthority else {
            approvalError = ConsoleApprovalBlockReason.authorityMismatch(approval.authority).message
            presentedError = nil
            return
        }
        guard approval.canResolve else {
            approvalError = approval.blockReason?.message
            presentedError = nil
            return
        }
        guard let decisionEndpoint = approval.captainDecisionEndpoint else {
            approvalError = ConsoleApprovalBlockReason.ticketUnresolved.message
            presentedError = nil
            return
        }
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if decision == .rejected && trimmedReason.isEmpty {
            approvalError = ConsoleTicketApprovalError.emptyRejectionReason.errorDescription
            presentedError = nil
            return
        }
        isDecidingApproval = true
        defer { isDecidingApproval = false }
        do {
            let result = try await consoleService.decideTicketApproval(
                approvalID: approval.id,
                decisionEndpoint: decisionEndpoint,
                decision: decision,
                reason: trimmedReason
            )
            approvalNotice = "Approval \(approval.id) is \(result.status ?? decision.rawValue)."
            approvalError = nil
            await refreshSelectedSection(silent: true)
        } catch {
            approvalError = error.localizedDescription
            presentedError = error.localizedDescription
        }
    }

    func refreshSelectedConversation(silent: Bool = false) async {
        guard let service else { return }
        let conversationKey = activeConversationKey
        guard let conversationID = conversations[conversationKey]?.conversationID
            ?? (activeTicketChat == nil ? storedConversationID(for: conversationKey) : nil) else { return }
        do {
            var state = conversations[conversationKey] ?? ConversationState(conversationID: conversationID)
            let remote = try await loadRecentMessages(
                service: service,
                conversationID: conversationID,
                hasCanonicalMessages: state.messages.contains { $0.deliveryState == .persisted }
            )
            state.conversationID = conversationID
            state.mergeCanonical(remote.map(Self.transcriptMessage))
            conversations[conversationKey] = state
            lastUpdatedAt = Date()
            await refreshRuntimeEvidence(
                agentID: conversationKey,
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

        let agentID = activeTicketChat?.ownerSlug ?? selectedAgentID
        let conversationKey = activeConversationKey
        let ticketChat = activeTicketChat
        let traceID = retryIdentity?.traceID ?? "orca-mac-\(UUID().uuidString.lowercased())"
        let idempotencyKey = retryIdentity?.idempotencyKey ?? "orca-mac-turn:\(traceID)"
        let pendingID = "pending:\(traceID)"
        let startedAt = Date()
        var state = conversations[conversationKey]
            ?? ConversationState(conversationID: ticketChat?.channelID ?? storedConversationID(for: agentID))
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
        conversations[conversationKey] = state
        draft = ""
        isSending = true
        presentedError = nil

        do {
            let deviceID = deviceIDProvider()
            let response = try await service.send(
                OrcaRuntimeDirectTurnRequest(
                    agentSlug: agentID,
                    content: content,
                    history: Array(history.suffix(20)),
                    sourceSurface: "console",
                    deliveryMode: "agent_inbox",
                    asyncResponse: true,
                    traceID: traceID,
                    idempotencyKey: idempotencyKey,
                    activeTicketID: ticketChat?.ticketID,
                    conversationID: state.conversationID,
                    threadScope: ticketChat == nil ? "direct" : "ticket",
                    clientVersion: Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String,
                    clientBuild: Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleVersion"
                    ) as? String,
                    clientInstanceID: deviceID,
                    deviceRegistrationRef: deviceID.hasPrefix("ed25519:")
                        ? "orca://devices/\(deviceID)"
                        : nil
                )
            )
            if ticketChat == nil {
                storeConversationID(response.conversationID, for: agentID)
            }
            var resolved = conversations[conversationKey] ?? state
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
                        role: response.terminalKind == nil ? .agent : .system,
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
            conversations[conversationKey] = resolved
            lastUpdatedAt = Date()
            await refreshConversation(
                agentID: conversationKey,
                conversationID: response.conversationID,
                turnID: response.userMessageID
            )
        } catch {
            var failed = conversations[conversationKey] ?? state
            failed.failPending(id: pendingID, reason: error.localizedDescription)
            conversations[conversationKey] = failed
            presentedError = error.localizedDescription
        }
        isSending = false
    }

    func retryFailedMessage(_ message: TranscriptMessage) async {
        guard case .failed = message.deliveryState else { return }
        let conversationKey = activeConversationKey
        var state = conversations[conversationKey] ?? ConversationState()
        state.messages.removeAll { $0.id == message.id }
        conversations[conversationKey] = state
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
                guard let self else { return }
                let delay = Self.automaticRefreshIntervalSeconds(for: self.selectedSection)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self.refreshCurrentSurface(silent: true, automatic: true)
            }
        }
    }

    static func automaticRefreshIntervalSeconds(for section: ConsoleSection) -> TimeInterval {
        switch section {
        case .conversations:
            return 4
        case .waitingOnCaptain:
            return 15
        default:
            return 30
        }
    }

    static func shouldRefreshWaitingOnCaptain(lastRefreshAt: Date?, now: Date) -> Bool {
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) >= waitingOnCaptainRefreshIntervalSeconds
    }

    static func automaticBoardRefreshStrategy(
        section: ConsoleSection,
        workMode: ConsoleWorkMode,
        hasBoards: Bool
    ) -> ConsoleAutomaticBoardRefreshStrategy {
        guard section == .work, workMode == .portfolio else { return .none }
        return hasBoards ? .selectedBoard : .hydratePortfolio
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
            var state = conversations[agentID] ?? ConversationState(conversationID: conversationID)
            let remote = try await loadRecentMessages(
                service: service,
                conversationID: conversationID,
                hasCanonicalMessages: state.messages.contains { $0.deliveryState == .persisted }
            )
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
            await startRuntimeReconciliation(
                agentID: agentID,
                turnID: turnID,
                service: service
            )
        } else {
            stopRuntimeReconciliation(for: agentID)
            runtimeTurns.removeValue(forKey: agentID)
            runtimeReconciliations.removeValue(forKey: agentID)
        }

        if agentID == activeConversationKey {
            runtimeEvidenceError = errors.isEmpty ? nil : errors.joined(separator: " ")
            if !silent, let runtimeEvidenceError {
                presentedError = runtimeEvidenceError
            }
        }
    }

    private func startRuntimeReconciliation(
        agentID: String,
        turnID: String,
        service: any OrcaRuntimeServing
    ) async {
        if runtimeReconciliationTurnIDs[agentID] == turnID,
           runtimeReconciliationTasks[agentID] != nil {
            return
        }
        stopRuntimeReconciliation(for: agentID)
        runtimeReconciliationTurnIDs[agentID] = turnID

        let scope = conversationScope.flatMap {
            OrcaRuntimeCursorScope(
                origin: $0.origin,
                organizationID: $0.organizationID,
                agentKey: agentID,
                turnID: turnID
            )
        }
        let cursorStore = runtimeCursorStore
        let persistedCursor = scope.flatMap(cursorStore.cursor)
        let updates = await service.runtimeUpdates(
            turnID: turnID,
            persistedCursor: persistedCursor,
            persistCursor: { cursor in
                guard let scope else { return }
                cursorStore.store(cursor, for: scope)
            }
        )
        runtimeReconciliationTasks[agentID] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await update in updates {
                    guard !Task.isCancelled,
                          self.runtimeReconciliationTurnIDs[agentID] == turnID else {
                        return
                    }
                    self.runtimeTurns[agentID] = update.turn
                    self.runtimeReconciliations[agentID] = update
                    if agentID == self.selectedAgentID {
                        self.runtimeEvidenceError = nil
                    }
                    self.lastUpdatedAt = Date()
                }
            } catch OrcaRuntimeClientError.httpStatus(404) {
                self.runtimeTurns.removeValue(forKey: agentID)
                self.runtimeReconciliations.removeValue(forKey: agentID)
            } catch {
                if self.runtimeTurns[agentID]?.turnId != turnID {
                    self.runtimeTurns.removeValue(forKey: agentID)
                    self.runtimeReconciliations.removeValue(forKey: agentID)
                }
                if agentID == self.selectedAgentID {
                    self.runtimeEvidenceError = "Turn: \(error.localizedDescription)"
                }
            }
            if self.runtimeReconciliationTurnIDs[agentID] == turnID {
                self.runtimeReconciliationTasks.removeValue(forKey: agentID)
                self.runtimeReconciliationTurnIDs.removeValue(forKey: agentID)
            }
        }
    }

    private func stopRuntimeReconciliation(for agentID: String) {
        runtimeReconciliationTasks[agentID]?.cancel()
        runtimeReconciliationTasks.removeValue(forKey: agentID)
        runtimeReconciliationTurnIDs.removeValue(forKey: agentID)
    }

    private func stopRuntimeReconciliation() {
        runtimeReconciliationTasks.values.forEach { $0.cancel() }
        runtimeReconciliationTasks.removeAll()
        runtimeReconciliationTurnIDs.removeAll()
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
            stopRuntimeReconciliation()
            conversations.removeAll()
            runtimeTurns.removeAll()
            runtimeReconciliations.removeAll()
            conversationMemories.removeAll()
            activeTicketChat = nil
        }
        conversationScope = next
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("orca.mac.conversation.")
                && !key.hasPrefix("orca.mac.conversation.v2.") {
            defaults.removeObject(forKey: key)
        }
    }

    func hydrateCanonicalConversationIDs(_ channelIDs: [String: String]) {
        guard conversationScope != nil else { return }
        for agent in agents {
            guard let canonicalID = channelIDs[agent.id], !canonicalID.isEmpty else { continue }
            let current = conversations[agent.id]
            if current?.conversationID == canonicalID {
                storeConversationID(canonicalID, for: agent.id)
                continue
            }
            conversations[agent.id] = ConversationState(conversationID: canonicalID)
            stopRuntimeReconciliation(for: agent.id)
            runtimeTurns.removeValue(forKey: agent.id)
            runtimeReconciliations.removeValue(forKey: agent.id)
            conversationMemories.removeValue(forKey: agent.id)
            storeConversationID(canonicalID, for: agent.id)
        }
    }

    private func deactivateConversationScope() {
        stopRuntimeReconciliation()
        conversationScope = nil
        activeTicketChat = nil
        conversations.removeAll()
        runtimeTurns.removeAll()
        runtimeReconciliations.removeAll()
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

    static func conversationRefreshLimit(hasCanonicalMessages: Bool) -> Int {
        hasCanonicalMessages
            ? incrementalConversationRefreshLimit
            : initialConversationRefreshLimit
    }

    private func loadRecentMessages(
        service: any OrcaRuntimeServing,
        conversationID: String,
        hasCanonicalMessages: Bool
    ) async throws -> [OrcaRuntimeConversationMessage] {
        try await service.messages(
            conversationID: conversationID,
            offset: 0,
            limit: Self.conversationRefreshLimit(
                hasCanonicalMessages: hasCanonicalMessages
            )
        )
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
        if message.messageType.lowercased() == "system" || message.terminalKind != nil {
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
