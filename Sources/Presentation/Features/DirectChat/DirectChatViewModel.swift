import Foundation
import SwiftData
import SwiftUI

extension Notification.Name {
    static let orcaAuthTokenInvalidated = Notification.Name("orcaAuthTokenInvalidated")
}

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
    var errorIsDestructive: Bool = false
    var ticketActionMessage: String?
    var isCreatingTicket: Bool = false
    var pendingTicketDraft: DirectChatTicketDraft?
    var attachableTickets: [DirectChatAttachableTicket] = []
    var isLoadingAttachableTickets: Bool = false
    var attachTicketError: String?
    var activeTicketId: String?
    var activeTicketTitle: String?
    var liveChatStatus: String?
    var agentRegistry: [String: Agent] = [:]
    var isLoadingAgentRegistry: Bool = false
    var selectedDeliveryMode: DMDeliveryMode = .compute
    var orcaChannelStatusByAgent: [String: String] = [:]
    var orcaChannelIdByAgent: [String: String] = [:]
    var routeProgressSteps: [DirectChatProgressStep] = []
    var latestTriagePreview: DirectChatTriagePreview?
    var isPreviewingTriage: Bool = false
    var triagePreviewError: String?
    var ticketLiveStatus: String?
    var ticketLiveEventCount: Int = 0
    var ticketLiveLastEventAt: Date?
    var ticketLiveLastAction: String?
    var activeTicketContinuity: DirectChatTicketContinuity?
    var isLoadingTicketContinuity: Bool = false
    var ticketContinuityError: String?
    var agentRunTrace: AgentRunTrace?
    var isLoadingAgentRunTrace: Bool = false
    var agentRunTraceError: String?
    var artifactSummariesByRunId: [String: [AgentRunArtifactSummary]] = [:]
    var artifactSummaryErrorsByRunId: [String: String] = [:]
    var ticketApprovals: [DirectChatApprovalRecord] = []
    var isLoadingTicketApprovals: Bool = false
    var isRequestingTicketApproval: Bool = false
    var resolvingApprovalIds: Set<String> = []
    var approvalActionMessage: String?
    var isSavingMemoryCandidate: Bool = false
    var memoryCandidateMessage: String?
    var isRefreshingWorkClassroom: Bool = false
    var workClassroomLastRefreshAt: Date?
    var workspaceContext: DirectChatWorkspaceContext?
    var isLoadingWorkspaceContext: Bool = false
    var workspaceContextError: String?
    var isSavingWorkspaceArtifact: Bool = false
    var workspaceArtifactMessage: String?
    var isRequestingWorkspaceTool: Bool = false
    var workspaceToolMessage: String?
    var executingWorkspaceToolRunIds: Set<String> = []
    var sonarRooms: [SonarRoom] = []
    var selectedRoom: SonarRoom?
    var roomMessages: [SonarRoomMessage] = []
    var composedRoomMessage: String = ""
    var selectedRoomMessageType: SonarRoomMessageType = .text
    var replyingToRoomMessage: SonarRoomMessage?
    var isLoadingRooms: Bool = false
    var isLoadingRoomMessages: Bool = false
    var isSendingRoomMessage: Bool = false
    var roomError: String?
    var roomActionMessage: String?
    var sonarSearchText: String = ""
    var selectedSonarRoomFilter: SonarRoomFilter = .all
    var sonarHealth: SonarHealth?
    var isLoadingSonarHealth: Bool = false
    var sonarContactsGeneratedAt: Date?
    var agentPresenceById: [String: AgentPresence] = [:]
    var agentLockerSummaryByAgent: [String: AgentChatService.LockerSummary] = [:]
    var isLoadingAgentLocker: Bool = false
    var agentLockerError: String?

    // Conversation data from SwiftData
    var conversations: [DMConversation] = []
    var currentMessages: [DMMessage] = []

    private var modelContext: ModelContext?
    private var currentService: AgentChatService?
    private let api = APIClient.shared
    private var liveRefreshTask: Task<Void, Never>?
    private var liveSSEManager: SSEStreamManager?
    private var liveSSEConnectedChannels: Set<String> = []
    private var ticketSSEManager: SSEStreamManager?
    private var ticketLiveTask: Task<Void, Never>?
    private var ticketLiveRefreshTask: Task<Void, Never>?
    private var ticketLiveTicketId: String?
    private var agentRunRefreshTask: Task<Void, Never>?
    private var roomAutoRefreshTask: Task<Void, Never>?
    private var presenceRefreshTask: Task<Void, Never>?
    private var pendingTicketContinuation: (ticketId: String, ticketTitle: String, agentId: String, channelId: String?)?

    // MARK: - Setup

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadConversations()
        if let agent = selectedAgent {
            applyPendingTicketContinuationIfNeeded(for: agent)
        }
    }

    // MARK: - Agent Registry

    func loadAgentRegistry() async {
        isLoadingAgentRegistry = true
        defer { isLoadingAgentRegistry = false }

        do {
            let response: PaginatedResponse<AgentDTO> = try await api.get(path: "/api/v1/agents")
            var mapped: [String: Agent] = [:]
            for dto in response.items {
                let agent = Agent(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    role: dto.role,
                    status: AgentState(rawValue: dto.status.rawValue) ?? .offline,
                    currentTask: dto.currentTask,
                    lastActivity: dto.lastSeenAt,
                    skills: dto.skills,
                    avatarColor: dto.avatarColor,
                    rosterLane: dto.domainRosterLane,
                    isDefaultRoutingEnabled: dto.isDefaultRoutingEnabled ?? !AgentRosterPolicy.isDormantOrArchived(dto.name),
                    quarantineState: dto.quarantineState,
                    rosterNote: dto.rosterNote,
                    supportRuntime: dto.supportRuntime,
                    allowedRuntimes: dto.allowedRuntimes,
                    runtimeHost: dto.runtimeHost,
                    lastAwakeProofAt: dto.lastAwakeProofAt,
                    lastSleepProofAt: dto.lastSleepProofAt,
                    driftState: dto.driftState,
                    tokenProfile: dto.tokenProfile
                )
                mapped[AgentRosterPolicy.normalizedName(dto.name)] = agent
            }
            agentRegistry = mapped
        } catch {
            // Keep the static chat roster visible, but label it as static in the UI.
        }
    }

    func startPresenceMonitoring() {
        presenceRefreshTask?.cancel()
        presenceRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadAgentPresence()
            while !Task.isCancelled {
                await TaskSafeSleep.sleep(seconds: 60)
                if Task.isCancelled { return }
                await self.loadAgentPresence()
            }
        }
    }

    func stopPresenceMonitoring() {
        presenceRefreshTask?.cancel()
        presenceRefreshTask = nil
    }

    func loadAgentPresence() async {
        do {
            let response: SonarPresenceResponseDTO = try await api.get(path: "/api/v1/sonar/presence")
            var mapped = agentPresenceById
            for presence in response.presences {
                mapped[AgentRosterPolicy.normalizedName(presence.agentId)] = presence
            }
            agentPresenceById = mapped
        } catch {
            // Presence is advisory; static roster, registry, and room state remain usable.
        }
    }

    func presence(for agent: AgentInfo) -> AgentPresence {
        let key = AgentRosterPolicy.normalizedName(agent.id)
        if var presence = agentPresenceById[key] {
            if let channelId = currentChannelId(for: agent),
               liveSSEConnectedChannels.contains(channelId) {
                presence.isWorking = true
            }
            return presence
        }
        if let registryAgent = registryAgent(for: agent) {
            return AgentPresence(
                agentId: agent.id,
                state: AgentPresence.State(agentState: registryAgent.status),
                isWorking: currentChannelId(for: agent).map { liveSSEConnectedChannels.contains($0) } ?? false,
                lastSeen: registryAgent.lastActivity
            )
        }
        return AgentPresence(
            agentId: agent.id,
            state: .offline,
            isWorking: currentChannelId(for: agent).map { liveSSEConnectedChannels.contains($0) } ?? false,
            lastSeen: nil
        )
    }

    private func applyPresencePayload(_ payload: PresencePayload) {
        let agentId = payload.agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agentId.isEmpty else { return }
        let presence = AgentPresence(
            agentId: agentId,
            state: AgentPresence.State(rawValue: payload.state.lowercased()) ?? .offline,
            isWorking: payload.working,
            lastSeen: payload.lastSeen
        )
        agentPresenceById[AgentRosterPolicy.normalizedName(agentId)] = presence
    }

    var directChatAgents: [AgentInfo] {
        AgentInfo.team.filter { info in
            guard let registryAgent = registryAgent(for: info) else {
                return info.lane != .dormantAdvisor
            }
            return !AgentRosterPolicy.isDormantOrArchived(registryAgent)
        }
    }

    func registryAgent(for info: AgentInfo) -> Agent? {
        agentRegistry[AgentRosterPolicy.normalizedName(info.id)]
            ?? agentRegistry[AgentRosterPolicy.normalizedName(info.name)]
    }

    func canStartChat(with info: AgentInfo) -> Bool {
        guard info.isReachable else { return false }
        guard let registryAgent = registryAgent(for: info) else { return true }
        if AgentRosterPolicy.isDormantOrArchived(registryAgent) { return false }
        if !registryAgent.isDefaultRoutingEnabled { return false }
        if let quarantine = registryAgent.quarantineState?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quarantine.isEmpty,
           quarantine.lowercased() != "none" {
            return false
        }
        return true
    }

    func rosterBadgeText(for info: AgentInfo) -> String {
        guard let registryAgent = registryAgent(for: info) else {
            return "Static roster · \(info.defaultDeliveryMode.displayLabel)"
        }
        if !canStartChat(with: info) {
            return "Registry disabled"
        }
        return "\(registryAgent.rosterLane.label) · \(info.defaultDeliveryMode.displayLabel)"
    }

    func rosterDetailText(for info: AgentInfo) -> String {
        guard let registryAgent = registryAgent(for: info) else {
            return "ORCA registry unavailable; using Pod guardrails."
        }
        if let quarantine = registryAgent.quarantineState?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quarantine.isEmpty,
           quarantine.lowercased() != "none" {
            return "ORCA \(registryAgent.status.displayName.lowercased()) · quarantine: \(quarantine)"
        }
        if !registryAgent.isDefaultRoutingEnabled {
            return "ORCA \(registryAgent.status.displayName.lowercased()) · default routing off"
        }
        return "ORCA \(registryAgent.status.displayName.lowercased()) · default routing on"
    }

    func serverChannelStatusText(for agent: AgentInfo) -> String? {
        orcaChannelStatusByAgent[agent.id]
    }

    func currentChannelId(for agent: AgentInfo) -> String? {
        guard let ctx = modelContext else { return nil }
        let agentId = agent.id
        let descriptor = FetchDescriptor<DMConversation>(
            predicate: #Predicate<DMConversation> { conv in
                conv.agentId == agentId
            }
        )
        let local = try? ctx.fetch(descriptor).first?.orcaChannelId
        if let local, !local.isEmpty { return local }
        return orcaChannelIdByAgent[agent.id]
    }

    func shortChannelId(for agent: AgentInfo) -> String? {
        guard let channelId = currentChannelId(for: agent), !channelId.isEmpty else { return nil }
        return String(channelId.prefix(8))
    }

    // MARK: - Load Conversations

    func loadConversations() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<DMConversation>(
            sortBy: [SortDescriptor(\.lastMessageDate, order: .reverse)]
        )
        conversations = (try? ctx.fetch(descriptor)) ?? []
    }

    func loadORCAChannelSummaries() async {
        isLoadingRooms = true
        defer { isLoadingRooms = false }

        do {
            let response: SonarContactsResponseDTO = try await api.get(path: "/api/v1/sonar/contacts")
            sonarContactsGeneratedAt = response.generatedAt
            let directContacts = response.contacts.filter { $0.kind == "agent" || $0.name.hasPrefix("direct:") }
            var idMap: [String: String] = [:]
            var statusMap: [String: String] = [:]

            for contact in directContacts {
                let agentId = contact.name.replacingOccurrences(of: "direct:", with: "")
                idMap[agentId] = contact.channelId
                statusMap[agentId] = contact.statusLine
            }

            orcaChannelIdByAgent = idMap
            orcaChannelStatusByAgent = statusMap
            sonarRooms = response.contacts
                .filter { !($0.kind == "agent" || $0.name.hasPrefix("direct:")) }
                .map { SonarRoom(contact: $0) }
                .sorted { lhs, rhs in
                    if lhs.lastActivity != rhs.lastActivity {
                        return lhs.lastActivity > rhs.lastActivity
                    }
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            await syncSonarNotificationBadge()
            roomError = nil
            return
        } catch {
            // Older ORCA builds only expose /chat/channels. Keep Sonar usable
            // during backend rollouts, but prefer the /sonar facade when present.
        }

        do {
            let channels: [DirectChatChannelDTO] = try await api.get(path: "/api/v1/chat/channels")
            let directChannels = channels.filter { $0.type == "direct" }
            var roomItems: [SonarRoom] = []
            var idMap: [String: String] = [:]
            var statusMap: [String: String] = [:]

            for agent in AgentInfo.team where agent.isReachable {
                guard let channel = directChannels.first(where: { $0.name == "direct:\(agent.id)" }) else { continue }
                idMap[agent.id] = channel.id
                if let summary: DirectChatChannelSummaryDTO = try? await api.get(path: "/api/v1/chat/channels/\(channel.id)/summary") {
                    statusMap[agent.id] = Self.channelSummaryStatus(summary, agent: agent)
                } else {
                    statusMap[agent.id] = "ORCA channel \(String(channel.id.prefix(8)))"
                }
            }

            for channel in channels where channel.type != "direct" {
                let summary: DirectChatChannelSummaryDTO? = try? await api.get(path: "/api/v1/chat/channels/\(channel.id)/summary")
                roomItems.append(SonarRoom(channel: channel, summary: summary))
            }

            orcaChannelIdByAgent = idMap
            orcaChannelStatusByAgent = statusMap
            sonarRooms = roomItems.sorted { lhs, rhs in
                if lhs.lastActivity != rhs.lastActivity {
                    return lhs.lastActivity > rhs.lastActivity
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            await syncSonarNotificationBadge()
        } catch {
            roomError = "ORCA room discovery unavailable."
            // Static local chat remains usable when ORCA channel discovery is unavailable.
        }
    }

    func refreshSonarSurface() {
        Task {
            await loadSonarHealth()
            await loadORCAChannelSummaries()
            if let selectedRoom {
                await loadRoomMessages(selectedRoom)
            }
            if let selectedAgent,
               let channelId = currentChannelId(for: selectedAgent),
               !channelId.isEmpty {
                await importORCAChannelHistory(agent: selectedAgent, channelId: channelId)
                await refreshChannelSummary(agent: selectedAgent, channelId: channelId)
            }
        }
    }

    func loadSonarHealth() async {
        isLoadingSonarHealth = true
        defer { isLoadingSonarHealth = false }

        do {
            let dto: SonarHealthDTO = try await api.get(path: "/api/v1/sonar/health")
            sonarHealth = dto.toDomain()
        } catch {
            sonarHealth = SonarHealth(
                status: "degraded",
                generatedAt: Date(),
                checks: [
                    SonarHealthCheck(
                        key: "sonar_health",
                        label: "Sonar health",
                        status: "degraded",
                        detail: "Health endpoint unavailable.",
                        count: nil
                    )
                ]
            )
        }
    }

    var filteredSonarRooms: [SonarRoom] {
        let query = sonarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sonarRooms.filter { room in
            selectedSonarRoomFilter.includes(room)
        }
        .filter { room in
            guard !query.isEmpty else { return true }
            return [
                room.displayName,
                room.name,
                room.description ?? "",
                room.roomKindLabel,
                room.channelPurpose,
                room.linkedTicketId ?? "",
                room.linkedBoardId ?? "",
                room.presence,
                room.notificationLevel,
                room.allowedActions.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    func selectRoom(_ room: SonarRoom) {
        selectedRoom = room
        roomError = nil
        roomActionMessage = nil
        composedRoomMessage = ""
        replyingToRoomMessage = nil
        Task { await loadRoomMessages(room) }
        startRoomAutoRefresh(room: room)
    }

    func refreshSelectedRoom() {
        guard let selectedRoom else { return }
        Task {
            await loadRoomMessages(selectedRoom)
            await loadORCAChannelSummaries()
        }
    }

    func startRoomAutoRefresh(room: SonarRoom) {
        roomAutoRefreshTask?.cancel()
        roomAutoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await MainActor.run {
                    guard let self,
                          self.selectedRoom?.id == room.id,
                          !self.isSendingRoomMessage else { return }
                    Task {
                        await self.loadRoomMessages(room)
                        await self.loadORCAChannelSummaries()
                    }
                }
            }
        }
    }

    func stopRoomAutoRefresh() {
        roomAutoRefreshTask?.cancel()
        roomAutoRefreshTask = nil
    }

    func loadRoomMessages(_ room: SonarRoom) async {
        isLoadingRoomMessages = true
        roomError = nil
        defer { isLoadingRoomMessages = false }

        do {
            let messages: [DirectChatORCAMessageDTO] = try await api.get(path: "/api/v1/chat/channels/\(room.id)/messages?limit=150")
            roomMessages = messages.map { SonarRoomMessage(dto: $0) }
            await markRoomRead(room, readThroughMessageId: messages.last?.id)
        } catch let apiError as APIError {
            roomError = apiError.message
        } catch {
            roomError = "Room messages are unavailable."
        }
    }

    private func markRoomRead(_ room: SonarRoom, readThroughMessageId: String?) async {
        do {
            let body = SonarReadStateBody(readThroughMessageId: readThroughMessageId)
            let _: SonarReadStateDTO = try await api.post(
                path: "/api/v1/sonar/channels/\(room.id)/read-state",
                body: body
            )
            await loadORCAChannelSummaries()
        } catch {
            // Read state is a convenience signal; message loading should remain usable.
        }
    }

    private func syncSonarNotificationBadge() async {
        let unreadRooms = sonarRooms.filter { $0.unreadCount > 0 }.count
        let mentionRooms = sonarRooms.filter { $0.mentionCount > 0 }.count
        let attentionRooms = sonarRooms.filter { $0.notificationLevel == "urgent" || $0.notificationLevel == "attention" }.count
        await PushNotificationService.shared.syncSonarBadge(
            unreadRooms: unreadRooms,
            mentionRooms: mentionRooms,
            attentionRooms: attentionRooms
        )
    }

    func sendRoomMessage() {
        guard let room = selectedRoom,
              !isSendingRoomMessage,
              !composedRoomMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard room.canPost else {
            roomError = room.protectionReason ?? "ORCA has this room in read-only mode."
            return
        }
        guard selectedRoomMessageType == .text || room.canRequestWorkflow else {
            roomError = room.protectionReason ?? "\(selectedRoomMessageType.title) is not allowed by this room policy."
            return
        }
        let content = composedRoomMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyToId = replyingToRoomMessage?.id
        composedRoomMessage = ""
        replyingToRoomMessage = nil
        isSendingRoomMessage = true
        roomError = nil
        roomActionMessage = nil

        Task {
            defer { isSendingRoomMessage = false }
            do {
                let traceId = Self.makeTraceId(prefix: "pod-sonar-room")
                let body = SonarRoomMessageCreateBody(
                    content: content,
                    messageType: selectedRoomMessageType.rawValue,
                    traceId: traceId,
                    source: "pod.sonar.room",
                    lane: selectedRoomMessageType.lane,
                    deliveryMode: "auto",
                    provenance: "system",
                    responseState: "recorded",
                    replyToId: replyToId
                )
                let dto: DirectChatORCAMessageDTO = try await api.post(path: "/api/v1/chat/channels/\(room.id)/messages", body: body)
                roomMessages.append(SonarRoomMessage(dto: dto))
                await materializeSonarRoomCardIfNeeded(
                    room: room,
                    content: content,
                    messageType: selectedRoomMessageType,
                    traceId: traceId,
                    messageId: dto.id
                )
                await loadORCAChannelSummaries()
            } catch let apiError as APIError {
                roomError = apiError.message
                composedRoomMessage = content
                replyingToRoomMessage = roomMessages.first { $0.id == replyToId }
            } catch {
                roomError = "Could not send the room message."
                composedRoomMessage = content
                replyingToRoomMessage = roomMessages.first { $0.id == replyToId }
            }
        }
    }

    func replyToRoomMessage(_ message: SonarRoomMessage) {
        replyingToRoomMessage = message
        selectedRoomMessageType = .text
        roomActionMessage = "Replying in thread to \(message.displayName)."
    }

    func cancelRoomReply() {
        replyingToRoomMessage = nil
        if roomActionMessage?.hasPrefix("Replying in thread") == true {
            roomActionMessage = nil
        }
    }

    func prepareRoomWorkRequest(from message: SonarRoomMessage, type: SonarRoomMessageType) {
        selectedRoomMessageType = type
        replyingToRoomMessage = message
        let quote = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        composedRoomMessage = quote.isEmpty
            ? "\(type.title) from \(message.displayName): "
            : "\(type.title) from \(message.displayName):\n\(quote)"
        roomActionMessage = "\(type.title) drafted from \(message.displayName)."
    }

    private func materializeSonarRoomCardIfNeeded(
        room: SonarRoom,
        content: String,
        messageType: SonarRoomMessageType,
        traceId: String,
        messageId: String
    ) async {
        guard messageType != .text else { return }
        guard room.canRequestWorkflow else {
            roomActionMessage = room.protectionReason
                ?? "\(messageType.title) recorded in chat only. Protected lanes require an approved ORCA ticket before workflow creation."
            return
        }
        guard let ticketId = room.linkedTicketId, !ticketId.isEmpty else {
            roomActionMessage = "\(messageType.title) recorded in chat only. Link this room to a ticket before ORCA can create a workflow object."
            return
        }

        switch messageType {
        case .approvalRequest:
            await createSonarApprovalRequest(ticketId: ticketId, content: content, traceId: traceId, messageId: messageId)
        case .toolRequest:
            await createSonarToolRequest(ticketId: ticketId, content: content)
        case .fileRequest:
            await createSonarWorkspaceArtifact(ticketId: ticketId, content: content, traceId: traceId, room: room)
        case .memoryCandidate:
            await createSonarMemoryCandidate(ticketId: ticketId, content: content, traceId: traceId, messageId: messageId, room: room)
        case .agentRunRequest:
            await createSonarAgentRunComment(ticketId: ticketId, content: content, traceId: traceId, messageId: messageId)
        case .text:
            break
        }
    }

    private func createSonarApprovalRequest(ticketId: String, content: String, traceId: String, messageId: String) async {
        let body = DirectChatApprovalRequestBody(
            reason: content,
            traceId: traceId,
            source: "pod.sonar.approval_request",
            lane: "human_approval_request"
        )
        do {
            let dto: DirectChatApprovalDTO = try await api.post(path: "/api/v1/tickets/\(ticketId)/approval-requests", body: body)
            roomActionMessage = "Approval \(dto.approvalId) created for ticket \(String(ticketId.prefix(8)))."
        } catch let apiError as APIError {
            roomActionMessage = "Approval card recorded, but approval object was not created: \(apiError.message)"
            await createSonarAgentRunComment(ticketId: ticketId, content: "Approval request from Sonar message \(messageId):\n\n\(content)", traceId: traceId, messageId: messageId)
        } catch {
            roomActionMessage = "Approval card recorded, but approval object was not created."
        }
    }

    private func createSonarToolRequest(ticketId: String, content: String) async {
        let body = DirectChatWorkspaceToolRequestBody(
            toolName: "agent_workspace_task",
            instruction: content,
            reason: "Requested from Sonar room for ticket \(ticketId).",
            source: "pod.sonar.tool_request"
        )
        do {
            let dto: DirectChatWorkspaceToolRequestCreateDTO = try await api.post(path: "/api/v1/workspaces/tickets/\(ticketId)/tool-requests", body: body)
            roomActionMessage = "Tool request \(String(dto.runId.prefix(8))) created for owner review."
        } catch let apiError as APIError {
            roomActionMessage = "Tool card recorded, but tool request was not created: \(apiError.message)"
        } catch {
            roomActionMessage = "Tool card recorded, but tool request was not created."
        }
    }

    private func createSonarWorkspaceArtifact(ticketId: String, content: String, traceId: String, room: SonarRoom) async {
        let body = DirectChatWorkspaceFileWriteRequest(
            filename: "sonar-file-request-\(Self.timestampForFilename()).md",
            content: """
            # Sonar File Context Request

            Room: \(room.displayName)
            Ticket: \(ticketId)
            Trace: \(traceId)

            ## Request
            \(content)
            """,
            description: "Sonar file/context request for ticket \(ticketId)",
            runId: nil,
            source: "pod.sonar.file_request"
        )
        do {
            let dto: DirectChatWorkspaceFileWriteDTO = try await api.post(path: "/api/v1/workspaces/tickets/\(ticketId)/files", body: body)
            roomActionMessage = "Workspace artifact saved: \(dto.file.path.split(separator: "/").last.map(String.init) ?? dto.file.path)."
        } catch let apiError as APIError {
            roomActionMessage = "File card recorded, but workspace artifact was not saved: \(apiError.message)"
        } catch {
            roomActionMessage = "File card recorded, but workspace artifact was not saved."
        }
    }

    private func createSonarMemoryCandidate(ticketId: String, content: String, traceId: String, messageId: String, room: SonarRoom) async {
        let body = SonarMemoryCandidateCreateBody(
            candidateId: "sonar-\(UUID().uuidString.lowercased())",
            sourceType: "pod_sonar",
            sourceRef: "orca://chat/messages/\(messageId)",
            sourceAgent: nil,
            textOriginal: content,
            textProposed: content,
            sensitivityClass: "normal",
            reviewersRequired: ["aloha", "maui"],
            target: [
                "type": "ticket",
                "ticket_id": ticketId,
                "room_id": room.id
            ],
            provenance: [
                "trace_id": traceId,
                "source": "pod.sonar.memory_candidate",
                "room": room.name
            ],
            createdBy: "pod-sonar"
        )
        do {
            let dto: SonarMemoryCandidateDTO = try await api.post(path: "/api/v1/memory/candidate-records", body: body)
            roomActionMessage = "Memory candidate \(String(dto.candidateId.prefix(12))) queued for review."
        } catch let apiError as APIError {
            roomActionMessage = "Memory card recorded, but candidate was not created: \(apiError.message)"
        } catch {
            roomActionMessage = "Memory card recorded, but candidate was not created."
        }
    }

    private func createSonarAgentRunComment(ticketId: String, content: String, traceId: String, messageId: String) async {
        let body = DirectChatTicketCommentBody(
            message: """
            ## Sonar Agent Run Request

            \(content)

            Trace: \(traceId)
            Source message: \(messageId)

            Recorded only. Dispatch must still go through ORCA owner/preview controls.
            """,
            traceId: traceId,
            source: "pod.sonar.agent_run_request",
            lane: "agent_run_request"
        )
        do {
            let _: DirectChatTicketCommentDTO = try await api.post(path: "/api/v1/tickets/\(ticketId)/comments", body: body)
            roomActionMessage = "Agent Run request added to ticket \(String(ticketId.prefix(8))) for owner dispatch."
        } catch let apiError as APIError {
            roomActionMessage = "Agent Run card recorded, but ticket comment was not saved: \(apiError.message)"
        } catch {
            roomActionMessage = "Agent Run card recorded, but ticket comment was not saved."
        }
    }

    // MARK: - Select Agent

    func selectAgent(_ agent: AgentInfo) {
        selectedAgent = agent
        selectedRoom = nil
        stopRoomAutoRefresh()
        currentService = AgentChatService(agent: agent)
        liveRefreshTask?.cancel()
        stopLiveResponseStream()
        isStreaming = false
        streamingContent = ""
        composedMessage = ""
        error = nil
        errorIsDestructive = false
        ticketActionMessage = nil
        liveChatStatus = nil
        routeProgressSteps = []
        latestTriagePreview = nil
        triagePreviewError = nil
        selectedDeliveryMode = agent.defaultDeliveryMode
        loadMessages(for: agent)
        loadTicketContext(for: agent)
        Task { await loadAgentLocker(for: agent) }
        applyPendingTicketContinuationIfNeeded(for: agent)
        let conversation = getOrCreateConversation(for: agent)
        if conversation.orcaChannelId == nil, let serverChannelId = orcaChannelIdByAgent[agent.id] {
            conversation.orcaChannelId = serverChannelId
            try? modelContext?.save()
        }
        if let channelId = conversation.orcaChannelId {
            Task { await importORCAChannelHistory(agent: agent, channelId: channelId) }
            Task { await refreshChannelSummary(agent: agent, channelId: channelId) }
            startLiveResponseRefresh(agent: agent, channelId: channelId, excluding: nil)
        }
        if let ticketId = activeTicketId {
            Task { await loadAttachedTicketContinuity(ticketId: ticketId) }
            startAttachedTicketLifecycleStream(agent: agent, ticketId: ticketId)
        } else {
            stopAttachedTicketLifecycleStream()
            activeTicketContinuity = nil
            ticketContinuityError = nil
        }
    }

    func clearSelection() {
        selectedAgent = nil
        currentService = nil
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        stopLiveResponseStream()
        stopAttachedTicketLifecycleStream()
        stopAgentRunFollowupRefresh()
        isStreaming = false
        streamingContent = ""
        currentMessages = []
        composedMessage = ""
        error = nil
        ticketActionMessage = nil
        liveChatStatus = nil
        ticketLiveStatus = nil
        routeProgressSteps = []
        latestTriagePreview = nil
        triagePreviewError = nil
        activeTicketId = nil
        activeTicketTitle = nil
        selectedDeliveryMode = .compute
        selectedRoom = nil
        roomMessages = []
        composedRoomMessage = ""
        roomActionMessage = nil
        isLoadingAgentLocker = false
        agentLockerError = nil
        stopRoomAutoRefresh()
    }

    func loadAgentLocker(for agent: AgentInfo) async {
        isLoadingAgentLocker = true
        agentLockerError = nil
        defer { isLoadingAgentLocker = false }

        do {
            let service = AgentChatService(agent: agent)
            let summary = try await service.loadLockerSummary()
            agentLockerSummaryByAgent[agent.id] = summary
            if selectedAgent?.id == agent.id, liveChatStatus == nil {
                liveChatStatus = "Locker loaded · \(summary.readinessText)"
            }
        } catch let apiError as APIError {
            if selectedAgent?.id == agent.id {
                agentLockerError = apiError.message
            }
        } catch {
            if selectedAgent?.id == agent.id {
                agentLockerError = "Agent locker unavailable"
            }
        }
    }

    func refreshCurrentChannel() {
        guard let agent = selectedAgent,
              let channelId = currentChannelId(for: agent),
              !channelId.isEmpty else {
            liveChatStatus = "No ORCA channel has been recorded for this chat yet."
            return
        }

        liveChatStatus = "Refreshing ORCA channel \(String(channelId.prefix(8)))..."
        Task {
            await importORCAChannelHistory(agent: agent, channelId: channelId)
            await refreshChannelSummary(agent: agent, channelId: channelId)
            if selectedAgent?.id == agent.id {
                startLiveResponseRefresh(agent: agent, channelId: channelId, excluding: nil)
                if liveChatStatus?.hasPrefix("Refreshing ORCA channel") == true {
                    liveChatStatus = "ORCA channel \(String(channelId.prefix(8))) refreshed."
                }
            }
        }
    }

    // Agents with confirmed NATS wake listeners — liveInbox button is exposed only for these.
    // shaka-mac: aloha (pilot), maui, coral — LaunchAgents verified 2026-05-23.
    // chief-mac: chief, rooster, reef — PIDs 83636/83642/42758 confirmed active by Reef 2026-05-23.
    private static let liveInboxAgents: Set<String> = ["aloha", "maui", "coral", "chief", "rooster", "reef"]

    func availableDeliveryModes(for agent: AgentInfo) -> [DMDeliveryMode] {
        let workModes: [DMDeliveryMode] = activeTicketId == nil ? [] : [.agentRun]
        if Self.liveInboxAgents.contains(agent.id) {
            return [.compute, .liveInbox, .auto] + workModes
        }
        return [.compute, .auto] + workModes
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

    private func loadTicketContext(for agent: AgentInfo) {
        guard let ctx = modelContext else {
            activeTicketId = nil
            activeTicketTitle = nil
            return
        }

        let agentId = agent.id
        let descriptor = FetchDescriptor<DMConversation>(
            predicate: #Predicate<DMConversation> { conv in
                conv.agentId == agentId
            }
        )
        let conversation = try? ctx.fetch(descriptor).first
        activeTicketId = conversation?.activeTicketId
        activeTicketTitle = conversation?.activeTicketTitle
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

    func continueWithTicket(ticketId: String, ticketTitle: String, agent: AgentInfo, channelId: String? = nil) {
        pendingTicketContinuation = (ticketId, ticketTitle, agent.id, channelId)
        navigationPath = NavigationPath()
        navigationPath.append(agent)
        if selectedAgent?.id == agent.id {
            applyPendingTicketContinuationIfNeeded(for: agent)
        }
    }

    private func applyPendingTicketContinuationIfNeeded(for agent: AgentInfo) {
        guard let pending = pendingTicketContinuation,
              pending.agentId == agent.id,
              modelContext != nil else { return }
        saveTicketContext(ticketId: pending.ticketId, ticketTitle: pending.ticketTitle, channelId: pending.channelId, for: agent)
        activeTicketId = pending.ticketId
        activeTicketTitle = pending.ticketTitle
        ticketActionMessage = "Continuing ORCA ticket \(pending.ticketId) with \(agent.name)."
        Task { await loadAttachedTicketContinuity(ticketId: pending.ticketId) }
        appendLocalAssistantMessage(
            "Continuing ORCA ticket \(pending.ticketId): \(pending.ticketTitle). Messages in this \(agent.name) chat can add ticket evidence or help clarify next action.",
            for: agent
        )
        pendingTicketContinuation = nil
        loadMessages(for: agent)
        if let channelId = pending.channelId {
            Task {
                await importORCAChannelHistory(agent: agent, channelId: channelId)
                startLiveResponseRefresh(agent: agent, channelId: channelId, excluding: nil)
            }
        }
        startAttachedTicketLifecycleStream(agent: agent, ticketId: pending.ticketId)
    }

    // MARK: - Send Message

    func sendMessage() {
        guard let agent = selectedAgent,
              !isStreaming,
              !composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        guard canStartChat(with: agent) else {
            error = "ORCA registry has disabled direct chat routing for \(agent.name). Create or attach a ticket instead."
            return
        }

        let text = composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        var deliveryMode = selectedDeliveryMode
        composedMessage = ""
        error = nil
        ticketActionMessage = nil

        guard let ctx = modelContext else { return }

        // Build history before inserting the outbound message. The service
        // appends `text` separately; including it here duplicates the user turn.
        let history = currentMessages
            .filter { !$0.isStreaming }
            .map { (role: $0.role, content: $0.content) }
        let outgoingTraceId = Self.makeTraceId(prefix: "pod-chat")

        // Save user message
        let conversation = getOrCreateConversation(for: agent)
        let userMsg = DMMessage(role: "user", content: text)
        userMsg.traceId = outgoingTraceId
        userMsg.userDeliveryState = DMUserMessageDeliveryState.sending.rawValue
        userMsg.conversation = conversation
        ctx.insert(userMsg)

        conversation.lastMessageText = text
        conversation.lastMessageDate = Date()
        try? ctx.save()

        currentMessages.append(userMsg)

        // Create placeholder for assistant response
        let assistantMsg = DMMessage(role: "assistant", content: "", isStreaming: true)
        assistantMsg.content = Self.initialRouteStatus(for: agent, deliveryMode: deliveryMode)
        assistantMsg.source = "pod.chat"
        assistantMsg.lane = "route_pending"
        assistantMsg.deliveryMode = DMDeliveryMode.system.rawValue
        assistantMsg.provenance = DMResponseProvenance.system.rawValue
        assistantMsg.deliveryState = DMDeliveryState.routing.rawValue
        assistantMsg.traceId = outgoingTraceId
        assistantMsg.conversation = conversation
        ctx.insert(assistantMsg)
        currentMessages.append(assistantMsg)

        isStreaming = true
        streamingContent = ""
        liveChatStatus = Self.routeStatusBarText(for: agent, deliveryMode: deliveryMode)
        routeProgressSteps = Self.routeProgressSteps(for: deliveryMode, stage: .routing)
        let startTime = Date()

        // Send through Schoolhouse compute. If compute is slow/down, Pod keeps
        // the conversation useful with an honest local fallback.
        let service = AgentChatService(agent: agent)

        Task {
            do {
                let triagePreview = await resolvedTriagePreview(for: text, agent: agent, requestedMode: deliveryMode)
                if deliveryMode == .auto,
                   let previewMode = DMDeliveryMode.parse(triagePreview?.deliveryMode) {
                    deliveryMode = previewMode
                    selectedDeliveryMode = previewMode
                }
                userMsg.triageId = triagePreview?.id
                userMsg.triageTraceId = triagePreview?.traceId
                assistantMsg.triageId = triagePreview?.id
                assistantMsg.triageTraceId = triagePreview?.traceId

                if deliveryMode == .agentRun {
                    guard let ticketId = activeTicketId else {
                        throw APIError(code: 0, message: "Attach an ORCA ticket before starting an Agent Run from chat.")
                    }
                    let dispatch = try await dispatchAttachedTicketToAgentRun(
                        ticketId: ticketId,
                        intake: text,
                        agent: agent,
                        traceId: outgoingTraceId,
                        triagePreview: triagePreview
                    )
                    assistantMsg.content = Self.agentRunAcceptedText(for: agent, dispatch: dispatch)
                    assistantMsg.isStreaming = false
                    assistantMsg.source = "pod.chat.agent_run"
                    assistantMsg.lane = "agent_run"
                    assistantMsg.deliveryMode = DMDeliveryMode.agentRun.rawValue
                    assistantMsg.provenance = DMResponseProvenance.agentRun.rawValue
                    assistantMsg.deliveryState = Self.deliveryState(forAgentRun: dispatch.run.status).rawValue
                    assistantMsg.modelUsed = dispatch.run.operationalSourceLabel
                    assistantMsg.traceId = dispatch.run.traceId ?? outgoingTraceId
                    assistantMsg.remoteMessageId = dispatch.commentId
                    assistantMsg.latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                    userMsg.userDeliveryState = Self.userDeliveryState(
                        remoteUserMessageId: dispatch.commentId,
                        responseState: assistantMsg.deliveryState
                    ).rawValue
                    conversation.lastMessageText = assistantMsg.content
                    conversation.lastMessageDate = Date()
                    try? ctx.save()
                    isStreaming = false
                    liveChatStatus = Self.agentRunStatusBarText(for: agent, dispatch: dispatch)
                    routeProgressSteps = Self.routeProgressSteps(
                        for: .agentRun,
                        stage: dispatch.run.status == .succeeded ? .responseReceived : .computeRunning
                    )
                    await loadAttachedTicketContinuity(ticketId: ticketId)
                    startAgentRunFollowupRefresh(ticketId: ticketId)
                    loadConversations()
                    return
                }

                let stream = await service.send(
                    message: text,
                    history: history,
                    deliveryMode: deliveryMode,
                    triagePreview: triagePreview,
                    activeTicketId: activeTicketId,
                    chatThreadId: conversation.orcaChannelId,
                    traceId: assistantMsg.traceId
                )
                for try await chunk in stream {
                    let responseMode = DMDeliveryMode.parse(chunk.metadata?.deliveryMode)
                    let responseProvenance = DMResponseProvenance.parse(chunk.metadata?.provenance)
                    let responseState = DMDeliveryState.parse(chunk.metadata?.responseState)
                    let isLiveInboxAck = deliveryMode == .liveInbox
                        || responseMode == .liveInbox
                        || responseProvenance == .liveInbox
                        || responseProvenance == .coordinationReview
                    let isAsyncComputeAck = responseState == .computeRunning

                    if isLiveInboxAck {
                        assistantMsg.content = Self.liveInboxAckText(for: agent)
                        assistantMsg.source = "orca.chat.ack"
                        assistantMsg.lane = "direct_agent_inbox"
                        assistantMsg.deliveryMode = DMDeliveryMode.liveInbox.rawValue
                        assistantMsg.provenance = responseProvenance?.rawValue ?? DMResponseProvenance.liveInbox.rawValue
                        assistantMsg.deliveryState = DMDeliveryState.waitingForLiveAgent.rawValue
                        routeProgressSteps = Self.routeProgressSteps(for: deliveryMode, stage: .waitingLive)
                    } else if isAsyncComputeAck {
                        assistantMsg.content = Self.computeAcceptedText(for: agent, ack: chunk.content)
                        assistantMsg.source = chunk.metadata?.source
                        assistantMsg.lane = chunk.metadata?.lane
                        assistantMsg.deliveryMode = chunk.metadata?.deliveryMode
                        assistantMsg.provenance = responseProvenance?.rawValue ?? chunk.metadata?.provenance
                        assistantMsg.deliveryState = DMDeliveryState.computeRunning.rawValue
                        routeProgressSteps = Self.routeProgressSteps(for: deliveryMode, stage: .computeRunning)
                    } else {
                        streamingContent += chunk.content
                        assistantMsg.content = streamingContent
                        assistantMsg.source = chunk.metadata?.source
                        assistantMsg.lane = chunk.metadata?.lane
                        assistantMsg.deliveryMode = chunk.metadata?.deliveryMode
                        assistantMsg.provenance = responseProvenance?.rawValue ?? chunk.metadata?.provenance
                        assistantMsg.deliveryState = responseState?.rawValue ?? DMDeliveryState.responseReceived.rawValue
                        routeProgressSteps = Self.routeProgressSteps(for: deliveryMode, stage: .responseReceived)
                    }

                    assistantMsg.deliveryError = chunk.metadata?.deliveryError
                    assistantMsg.deliveryFailedHop = chunk.metadata?.deliveryFailedHop
                    assistantMsg.deliveryEvidence = chunk.metadata?.deliveryEvidence
                    userMsg.deliveryError = chunk.metadata?.deliveryError
                    userMsg.deliveryFailedHop = chunk.metadata?.deliveryFailedHop
                    userMsg.deliveryEvidence = chunk.metadata?.deliveryEvidence
                    assistantMsg.modelUsed = chunk.metadata?.displayName
                    assistantMsg.tokenCount = chunk.metadata?.tokenCount
                    assistantMsg.traceId = chunk.metadata?.traceId
                    assistantMsg.computeRunId = chunk.metadata?.computeRunId
                    assistantMsg.triageId = chunk.metadata?.triageId ?? assistantMsg.triageId
                    assistantMsg.triageTraceId = chunk.metadata?.traceId ?? assistantMsg.triageTraceId
                    if let userMessageId = chunk.metadata?.userMessageId, !userMessageId.isEmpty {
                        userMsg.remoteMessageId = userMessageId
                    }
                    userMsg.traceId = userMsg.traceId ?? chunk.metadata?.traceId
                    userMsg.triageId = chunk.metadata?.triageId ?? userMsg.triageId
                    userMsg.triageTraceId = chunk.metadata?.traceId ?? userMsg.triageTraceId
                    userMsg.userDeliveryState = Self.userDeliveryState(
                        remoteUserMessageId: chunk.metadata?.userMessageId,
                        responseState: assistantMsg.deliveryState
                    ).rawValue
                    assistantMsg.remoteMessageId = chunk.metadata?.assistantMessageId
                    if let channelId = chunk.metadata?.channelId {
                        conversation.orcaChannelId = channelId
                    }
                }

                // Finalize
                assistantMsg.isStreaming = false
                assistantMsg.latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                userMsg.userDeliveryState = Self.userDeliveryState(
                    remoteUserMessageId: userMsg.remoteMessageId,
                    responseState: assistantMsg.deliveryState
                ).rawValue
                conversation.lastMessageText = assistantMsg.content
                conversation.lastMessageDate = Date()
                try? ctx.save()

                isStreaming = false
                loadConversations()
                if assistantMsg.deliveryState == DMDeliveryState.waitingForLiveAgent.rawValue,
                   let channelId = conversation.orcaChannelId {
                    liveChatStatus = "Sent to \(agent.name)'s inbox. Waiting for a reply."
                    routeProgressSteps = Self.routeProgressSteps(for: deliveryMode, stage: .waitingLive)
                    startLiveResponseRefresh(
                        agent: agent,
                        channelId: channelId,
                        excluding: assistantMsg.remoteMessageId,
                        since: assistantMsg.timestamp
                    )
                } else if assistantMsg.deliveryState == DMDeliveryState.computeRunning.rawValue,
                          let channelId = conversation.orcaChannelId {
                    liveChatStatus = "Helper draft for \(agent.name) accepted. Waiting for the answer."
                    routeProgressSteps = Self.routeProgressSteps(for: deliveryMode, stage: .computeRunning)
                    startLiveResponseRefresh(
                        agent: agent,
                        channelId: channelId,
                        excluding: assistantMsg.remoteMessageId,
                        since: assistantMsg.timestamp
                    )
                }
            } catch {
                userMsg.userDeliveryState = DMUserMessageDeliveryState.failed.rawValue
                assistantMsg.isStreaming = false
                assistantMsg.latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                routeProgressSteps = Self.routeProgressSteps(for: deliveryMode, stage: .failed)

                if Self.isUnauthorized(error) {
                    UserDefaults.standard.removeObject(forKey: "orca_auth_token")
                    await APIClient.shared.setToken(nil)
                    NotificationCenter.default.post(name: .orcaAuthTokenInvalidated, object: nil)
                }

                if Self.isNetworkOrHTTPFailure(error) {
                    let reason = Self.sendFailureReason(error)
                    assistantMsg.content = ""
                    assistantMsg.source = "pod.chat"
                    assistantMsg.lane = "send_failed"
                    assistantMsg.deliveryMode = DMDeliveryMode.system.rawValue
                    assistantMsg.provenance = DMResponseProvenance.system.rawValue
                    assistantMsg.deliveryState = DMDeliveryState.failed.rawValue
                    conversation.lastMessageText = "Message NOT sent to \(agent.name)"
                    conversation.lastMessageDate = Date()
                    self.error = "Message NOT sent to \(agent.name) - \(reason). Tap to retry."
                    errorIsDestructive = true
                } else {
                    assistantMsg.content = Self.localFallback(for: agent, userMessage: text, error: error)
                    assistantMsg.source = "pod.chat"
                    assistantMsg.lane = "local_guardrail"
                    assistantMsg.deliveryMode = DMDeliveryMode.fallback.rawValue
                    assistantMsg.provenance = DMResponseProvenance.fallback.rawValue
                    assistantMsg.deliveryState = DMDeliveryState.fallbackPresented.rawValue
                    conversation.lastMessageText = assistantMsg.content
                    conversation.lastMessageDate = Date()
                    self.error = "Using local guardrail mode while Schoolhouse compute is slow."
                    errorIsDestructive = false
                }

                try? ctx.save()
                isStreaming = false
                loadConversations()
            }
        }
    }

    func retryMessage(_ message: DMMessage) {
        guard message.role == "user",
              Self.isRetryableUserDelivery(message.userDeliveryState),
              !isStreaming else { return }
        composedMessage = message.content
        sendMessage()
    }

    func retryLastFailedMessage() {
        guard let message = currentMessages.last(where: {
            $0.role == "user" && Self.isRetryableUserDelivery($0.userDeliveryState)
        }) else { return }
        retryMessage(message)
    }

    private func dispatchAttachedTicketToAgentRun(
        ticketId: String,
        intake: String,
        agent: AgentInfo,
        traceId: String,
        triagePreview: DirectChatTriagePreview?
    ) async throws -> DirectChatAgentRunDispatch {
        let comment = DirectChatTicketCommentBody(
            message: Self.agentRunInstructionComment(
                intake: intake,
                agent: agent,
                traceId: traceId,
                triagePreview: triagePreview
            ),
            traceId: traceId,
            source: "pod.chat.agent_run",
            lane: "agent_run_instruction"
        )
        let _: DirectChatTicketCommentDTO = try await api.post(
            path: "/api/v1/tickets/\(ticketId)/comments",
            body: comment
        )

        let dispatchDTO: DirectChatAgentRunDispatchDTO = try await api.post(
            path: "/api/v1/agent-runs/tickets/\(ticketId)/dispatch",
            body: DirectChatEmptyRequestBody()
        )
        let dispatch = dispatchDTO.toDomain()
        if dispatch.run.status == .failed {
            throw APIError(code: 0, message: dispatch.run.error ?? dispatch.message)
        }

        if let executionDTO: DirectChatAgentRunDispatchDTO = try? await api.post(
            path: "/api/v1/agent-runs/\(dispatch.run.id)/queue-execution",
            body: DirectChatEmptyRequestBody()
        ) {
            return executionDTO.toDomain()
        }

        return dispatch
    }

    private func startAgentRunFollowupRefresh(ticketId: String) {
        agentRunRefreshTask?.cancel()
        agentRunRefreshTask = Task { [weak self] in
            for _ in 0..<8 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.loadAttachedTicketContinuity(ticketId: ticketId)
                await self?.loadAgentRunContext(ticketId: ticketId)
            }
        }
    }

    private func stopAgentRunFollowupRefresh() {
        agentRunRefreshTask?.cancel()
        agentRunRefreshTask = nil
    }

    private func clearAgentRunContext() {
        agentRunTrace = nil
        isLoadingAgentRunTrace = false
        agentRunTraceError = nil
        artifactSummariesByRunId = [:]
        artifactSummaryErrorsByRunId = [:]
        ticketApprovals = []
        isLoadingTicketApprovals = false
        isRequestingTicketApproval = false
        resolvingApprovalIds = []
        approvalActionMessage = nil
        isSavingMemoryCandidate = false
        memoryCandidateMessage = nil
        isRefreshingWorkClassroom = false
        workClassroomLastRefreshAt = nil
        workspaceContext = nil
        isLoadingWorkspaceContext = false
        workspaceContextError = nil
        isSavingWorkspaceArtifact = false
        workspaceArtifactMessage = nil
        isRequestingWorkspaceTool = false
        workspaceToolMessage = nil
        executingWorkspaceToolRunIds = []
    }

    func previewMermanTriage() {
        guard let agent = selectedAgent, !isPreviewingTriage else { return }
        let intake = triagePreviewText()
        guard !intake.isEmpty else {
            triagePreviewError = "Write a message first, then ask Merman."
            return
        }

        isPreviewingTriage = true
        triagePreviewError = nil
        Task {
            defer { isPreviewingTriage = false }
            if let triage = await requestMermanTriage(intake: intake, target: agent) {
                latestTriagePreview = triage.toPreview(sourceText: intake, targetAgentId: agent.id)
                selectedDeliveryMode = DMDeliveryMode.parse(triage.deliveryMode) ?? selectedDeliveryMode
                liveChatStatus = "Merman preview: \(triage.intentType.replacingOccurrences(of: "_", with: " ")) -> \(triage.suggestedOwner)."
            } else {
                triagePreviewError = "Merman triage is unavailable."
            }
        }
    }

    private func triagePreviewText() -> String {
        let draft = composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty { return draft }
        return currentMessages
            .last { $0.role == "user" && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func resolvedTriagePreview(for text: String, agent: AgentInfo, requestedMode: DMDeliveryMode) async -> DirectChatTriagePreview? {
        let normalizedText = Self.normalizedTriageText(text)
        let matchingPreview = latestTriagePreview.flatMap { preview in
            Self.normalizedTriageText(preview.sourceText) == normalizedText && preview.targetAgentId == agent.id ? preview : nil
        }

        if requestedMode != .auto {
            if latestTriagePreview != nil, matchingPreview == nil {
                triagePreviewError = "Draft changed since Merman preview; sending without stale triage."
            }
            return matchingPreview
        }

        liveChatStatus = "Merman is choosing the route..."
        if let triage = await requestMermanTriage(intake: text, target: agent) {
            let preview = triage.toPreview(sourceText: text, targetAgentId: agent.id)
            latestTriagePreview = preview
            triagePreviewError = nil
            liveChatStatus = "Merman selected \(preview.deliveryLabel) for \(preview.suggestedOwner)."
            return preview
        }

        triagePreviewError = "Merman triage unavailable; Schoolhouse auto route will decide without preview."
        return matchingPreview
    }

    private static func normalizedTriageText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum RouteProgressStage {
        case routing
        case computeRunning
        case waitingLive
        case responseReceived
        case failed
    }

    private static func routeProgressSteps(for mode: DMDeliveryMode, stage: RouteProgressStage) -> [DirectChatProgressStep] {
        let thirdTitle: String
        let thirdIcon: String
        switch mode {
        case .liveInbox:
            thirdTitle = "Live inbox"
            thirdIcon = "tray.full"
        case .auto:
            thirdTitle = "Route"
            thirdIcon = "arrow.triangle.branch"
        case .compute:
            thirdTitle = "Compute helper"
            thirdIcon = "cpu"
        case .agentRun:
            thirdTitle = "Agent Run"
            thirdIcon = "bolt.badge.clock"
        case .fallback:
            thirdTitle = "Fallback"
            thirdIcon = "exclamationmark.triangle"
        case .system:
            thirdTitle = "System"
            thirdIcon = "gearshape"
        case .ticket:
            thirdTitle = "Ticket"
            thirdIcon = "text.badge.checkmark"
        }

        let finalTitle: String
        switch mode {
        case .liveInbox:
            finalTitle = "Live reply"
        case .compute:
            finalTitle = "Compute answer"
        case .agentRun:
            finalTitle = "Run evidence"
        case .fallback:
            finalTitle = "Fallback note"
        case .ticket:
            finalTitle = "Ticket update"
        case .auto, .system:
            finalTitle = "Answer"
        }
        let failed = stage == .failed
        let secondCurrent = stage == .routing
        let thirdCurrent = stage == .computeRunning || stage == .waitingLive
        let finalDone = stage == .responseReceived

        return [
            DirectChatProgressStep(
                id: "recorded",
                title: "Recorded",
                icon: "checkmark.circle",
                state: failed ? .done : .done
            ),
            DirectChatProgressStep(
                id: "routed",
                title: "Routed",
                icon: "arrow.triangle.branch",
                state: failed ? .failed : (secondCurrent ? .current : .done)
            ),
            DirectChatProgressStep(
                id: "handler",
                title: thirdTitle,
                icon: thirdIcon,
                state: failed ? .failed : (thirdCurrent ? .current : (finalDone ? .done : .pending))
            ),
            DirectChatProgressStep(
                id: "response",
                title: finalTitle,
                icon: finalDone ? "checkmark.seal" : "hourglass",
                state: failed ? .failed : (finalDone ? .done : .pending)
            ),
        ]
    }

    private func startLiveResponseRefresh(agent: AgentInfo, channelId: String, excluding acknowledgedMessageId: String?, since minimumCreatedAt: Date? = nil) {
        liveRefreshTask?.cancel()
        stopLiveResponseStream()
        liveRefreshTask = Task { [weak self] in
            guard let self else { return }
            async let polling: Void = self.startLiveResponsePolling(agent: agent, channelId: channelId, excluding: acknowledgedMessageId, since: minimumCreatedAt)
            for attempt in 0..<3 {
                if Task.isCancelled || self.selectedAgent?.id != agent.id { break }
                let completedCleanly = await self.startLiveResponseStream(
                    agent: agent,
                    channelId: channelId,
                    excluding: acknowledgedMessageId,
                    since: minimumCreatedAt
                )
                if completedCleanly || Task.isCancelled || self.selectedAgent?.id != agent.id { break }
                await TaskSafeSleep.sleep(seconds: Double(attempt + 1) * 2)
            }
            await polling
        }
    }

    private func stopLiveResponseStream() {
        liveSSEConnectedChannels.removeAll()
        let manager = liveSSEManager
        liveSSEManager = nil
        Task {
            await manager?.disconnect()
        }
    }

    private func startLiveResponseStream(agent: AgentInfo, channelId: String, excluding acknowledgedMessageId: String?, since minimumCreatedAt: Date?) async -> Bool {
        guard selectedAgent?.id == agent.id,
              let token = await api.currentToken(),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let manager = SSEStreamManager()
        liveSSEManager = manager
        liveChatStatus = "Opening live \(agent.name) stream..."
        do {
            let stream = await manager.connect(
                channelId: channelId,
                token: token,
                baseURL: AppState.backendURL
            )
            for try await event in stream {
                if Task.isCancelled {
                    await manager.disconnect()
                    return true
                }
                guard selectedAgent?.id == agent.id else {
                    await manager.disconnect()
                    return true
                }
                switch event {
                case .connected:
                    liveSSEConnectedChannels.insert(channelId)
                    liveChatStatus = "Live \(agent.name) stream connected."
                case .message(let payload):
                    importLiveAgentResponsePayload(
                        payload,
                        agent: agent,
                        channelId: channelId,
                        excluding: acknowledgedMessageId,
                        since: minimumCreatedAt
                    )
                case .presence(let payload):
                    applyPresencePayload(payload)
                case .keepalive:
                    break
                case .error:
                    liveChatStatus = "Live stream paused; using refresh."
                    await manager.disconnect()
                    return false
                case .ticketLifecycle:
                    break
                }
            }
            if selectedAgent?.id == agent.id {
                liveChatStatus = "Live stream closed; using refresh."
            }
            liveSSEConnectedChannels.remove(channelId)
            await manager.disconnect()
            return false
        } catch {
            if selectedAgent?.id == agent.id {
                liveChatStatus = "Live stream unavailable; using refresh."
            }
            liveSSEConnectedChannels.remove(channelId)
            await manager.disconnect()
            return false
        }
    }

    private func startLiveResponsePolling(agent: AgentInfo, channelId: String, excluding acknowledgedMessageId: String?, since minimumCreatedAt: Date?) async {
        for _ in 0..<20 {
            if Task.isCancelled { return }
            await TaskSafeSleep.sleep(seconds: 3)
            if Task.isCancelled { return }
            await importLiveAgentResponses(
                agent: agent,
                channelId: channelId,
                excluding: acknowledgedMessageId,
                since: minimumCreatedAt
            )
        }
            if !Task.isCancelled, selectedAgent?.id == agent.id {
                guard hasPendingAsyncReply(for: agent) else {
                    return
                }
                if liveSSEConnectedChannels.contains(channelId) {
                    liveChatStatus = "Live \(agent.name) stream is still connected. I’ll append the reply when ORCA returns it."
                    return
                }
            if hasPendingLiveInboxReply(for: agent) {
                liveChatStatus = "Live reply window expired for \(agent.name). Requesting an honest compute fallback draft."
                markLiveInboxWaitTimedOut(for: agent, since: minimumCreatedAt)
                await requestLiveInboxFallback(for: agent, channelId: channelId, since: minimumCreatedAt)
            } else {
                liveChatStatus = "Still waiting for \(agent.name). New replies will appear here when ORCA returns them."
            }
        }
    }

    private func importLiveAgentResponsePayload(_ payload: MessageNewPayload, agent: AgentInfo, channelId: String, excluding acknowledgedMessageId: String?, since minimumCreatedAt: Date?) {
        let timestamp = payload.timestamp ?? Date()
        let role = Self.localRole(
            senderAgentId: payload.senderAgentId,
            messageType: payload.messageType,
            source: payload.source,
            responseState: payload.responseState
        )
        guard selectedAgent?.id == agent.id,
              let ctx = modelContext,
              payload.id != acknowledgedMessageId,
              Self.isImportableRemoteMessage(
                  senderAgentId: payload.senderAgentId,
                messageType: payload.messageType,
                source: payload.source,
                responseState: payload.responseState
              ),
              minimumCreatedAt.map({ timestamp >= $0 }) ?? true,
              !payload.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !hasImportedRemoteMessage(id: payload.id, content: payload.content, timestamp: timestamp, role: role) else {
            return
        }

        let conversation = getOrCreateConversation(for: agent)
        conversation.orcaChannelId = channelId
        let message = DMMessage(
            role: role,
            content: payload.content,
            timestamp: timestamp,
            isStreaming: false
        )
        message.source = payload.source ?? "orca.chat.sse"
        message.lane = payload.lane ?? Self.defaultLane(senderAgentId: payload.senderAgentId, messageType: payload.messageType, source: payload.source, responseState: payload.responseState)
        message.deliveryMode = payload.deliveryMode ?? Self.defaultDeliveryMode(senderAgentId: payload.senderAgentId, messageType: payload.messageType, source: payload.source, responseState: payload.responseState)
        message.provenance = payload.provenance ?? DMResponseProvenance(deliveryMode: payload.deliveryMode, source: payload.source, lane: payload.lane).rawValue
        message.deliveryState = Self.effectiveDeliveryState(
            content: payload.content,
            deliveryMode: payload.deliveryMode,
            provenance: payload.provenance,
            source: payload.source,
            lane: payload.lane,
            responseState: payload.responseState
        ) ?? DMDeliveryState.responseReceived.rawValue
        message.deliveryError = payload.deliveryError
        message.deliveryFailedHop = payload.deliveryFailedHop
        message.deliveryEvidence = payload.deliveryEvidence
        message.traceId = payload.traceId
        message.remoteMessageId = payload.id
        message.triageId = payload.triageId
        message.triageTraceId = payload.triageTraceId
        message.fileAttachmentPath = payload.fileAttachment?.path
        message.conversation = conversation
        ctx.insert(message)
        currentMessages.append(message)
        conversation.lastMessageText = payload.content
        conversation.lastMessageDate = timestamp
        liveChatStatus = nil
        if Self.shouldResolvePendingAsync(
            senderAgentId: payload.senderAgentId,
            messageType: payload.messageType,
            source: payload.source,
            responseState: payload.responseState,
            content: payload.content
        ) {
            markAsyncReplyResolved(for: agent, traceId: payload.traceId)
        }
        try? ctx.save()
        loadConversations()
    }

    private func importLiveAgentResponses(agent: AgentInfo, channelId: String, excluding acknowledgedMessageId: String?, since minimumCreatedAt: Date?) async {
        guard selectedAgent?.id == agent.id, let ctx = modelContext else { return }
        do {
            let messages: [DirectChatORCAMessageDTO] = try await api.get(path: "/api/v1/chat/channels/\(channelId)/messages")
            let liveReplies = messages
                .filter {
                    $0.id != acknowledgedMessageId
                    && Self.isImportableRemoteMessage(
                        senderAgentId: $0.senderAgentId,
                        messageType: $0.messageType,
                        source: $0.source,
                        responseState: $0.responseState
                    )
                    && (minimumCreatedAt == nil || $0.createdAt >= minimumCreatedAt!)
                    && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !hasImportedRemoteMessage(
                        id: $0.id,
                        content: $0.content,
                        timestamp: $0.createdAt,
                        role: Self.localRole(
                            senderAgentId: $0.senderAgentId,
                            messageType: $0.messageType,
                            source: $0.source,
                            responseState: $0.responseState
                        )
                    )
                }
                .sorted(by: { $0.createdAt < $1.createdAt })

            guard !liveReplies.isEmpty else { return }
            let conversation = getOrCreateConversation(for: agent)
            conversation.orcaChannelId = channelId
            for reply in liveReplies {
                let message = DMMessage(
                    role: Self.localRole(
                        senderAgentId: reply.senderAgentId,
                        messageType: reply.messageType,
                        source: reply.source,
                        responseState: reply.responseState
                    ),
                    content: reply.content,
                    timestamp: reply.createdAt,
                    isStreaming: false
                )
                message.source = reply.source ?? "orca.chat.direct"
                message.lane = reply.lane ?? Self.defaultLane(senderAgentId: reply.senderAgentId, messageType: reply.messageType, source: reply.source, responseState: reply.responseState)
                message.deliveryMode = reply.deliveryMode ?? Self.defaultDeliveryMode(senderAgentId: reply.senderAgentId, messageType: reply.messageType, source: reply.source, responseState: reply.responseState)
                message.provenance = reply.provenance ?? DMResponseProvenance(deliveryMode: reply.deliveryMode, source: reply.source, lane: reply.lane).rawValue
                message.deliveryState = Self.effectiveDeliveryState(
                    content: reply.content,
                    deliveryMode: reply.deliveryMode,
                    provenance: reply.provenance,
                    source: reply.source,
                    lane: reply.lane,
                    responseState: reply.responseState
                ) ?? DMDeliveryState.responseReceived.rawValue
                message.deliveryError = reply.deliveryError
                message.deliveryFailedHop = reply.deliveryFailedHop
                message.deliveryEvidence = reply.deliveryEvidence
                message.traceId = reply.traceId
                message.remoteMessageId = reply.id
                message.triageId = reply.triageId
                message.triageTraceId = reply.triageTraceId
                message.fileAttachmentPath = reply.fileAttachment?.path
                message.conversation = conversation
                ctx.insert(message)
                currentMessages.append(message)
                conversation.lastMessageText = reply.content
                conversation.lastMessageDate = reply.createdAt
            }
            liveChatStatus = nil
            for reply in liveReplies where Self.shouldResolvePendingAsync(
                senderAgentId: reply.senderAgentId,
                messageType: reply.messageType,
                source: reply.source,
                responseState: reply.responseState,
                content: reply.content
            ) {
                markAsyncReplyResolved(for: agent, traceId: reply.traceId)
            }
            try? ctx.save()
            loadConversations()
        } catch {
            if selectedAgent?.id == agent.id {
                liveChatStatus = "Live response refresh is unavailable."
            }
        }
    }

    private func hasImportedRemoteMessage(id: String, content: String, timestamp: Date, role: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return currentMessages.contains { message in
            if message.remoteMessageId == id { return true }
            return message.role == role
                && message.content.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
                && abs(message.timestamp.timeIntervalSince(timestamp)) < 5
        }
    }

    private func importORCAChannelHistory(agent: AgentInfo, channelId: String) async {
        guard selectedAgent?.id == agent.id, let ctx = modelContext else { return }
        do {
            let remoteMessages: [DirectChatORCAMessageDTO] = try await api.get(path: "/api/v1/chat/channels/\(channelId)/messages")
            let conversation = getOrCreateConversation(for: agent)
            conversation.orcaChannelId = channelId
            var existingRemoteIds = Set(currentMessages.compactMap(\.remoteMessageId))
            var didChange = false

            for remote in remoteMessages
                .filter({
                    Self.isImportableRemoteMessage(
                        senderAgentId: $0.senderAgentId,
                        messageType: $0.messageType,
                        source: $0.source,
                        responseState: $0.responseState,
                        includeUserMessages: true
                    )
                    && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })
                .sorted(by: { $0.createdAt < $1.createdAt }) {
                if let existing = currentMessages.first(where: { $0.remoteMessageId == remote.id }) {
                    existing.content = remote.content
                    existing.timestamp = remote.createdAt
                    existing.source = remote.source ?? existing.source
                    existing.lane = remote.lane ?? existing.lane
                    existing.deliveryMode = remote.deliveryMode ?? existing.deliveryMode
                    existing.provenance = remote.normalizedProvenance ?? existing.provenance
                    existing.deliveryState = Self.effectiveDeliveryState(
                        content: remote.content,
                        deliveryMode: remote.deliveryMode,
                        provenance: remote.normalizedProvenance,
                        source: remote.source,
                        lane: remote.lane,
                        responseState: remote.responseState
                    ) ?? existing.deliveryState
                    existing.deliveryError = remote.deliveryError ?? existing.deliveryError
                    existing.deliveryFailedHop = remote.deliveryFailedHop ?? existing.deliveryFailedHop
                    existing.deliveryEvidence = remote.deliveryEvidence ?? existing.deliveryEvidence
                    if existing.role == "user" {
                        existing.userDeliveryState = Self.userDeliveryState(
                            remoteUserMessageId: remote.id,
                            responseState: existing.deliveryState ?? remote.deliveryState ?? remote.responseState
                        ).rawValue
                    }
                    existing.modelUsed = remote.computeAttributionLabel ?? existing.modelUsed
                    existing.traceId = remote.traceId ?? existing.traceId
                    existing.triageId = remote.triageId ?? existing.triageId
                    existing.triageTraceId = remote.triageTraceId ?? existing.triageTraceId
                    existing.fileAttachmentPath = remote.fileAttachment?.path ?? existing.fileAttachmentPath
                    conversation.lastMessageText = remote.content
                    conversation.lastMessageDate = remote.createdAt
                    didChange = true
                    if Self.shouldResolvePendingAsync(
                        senderAgentId: remote.senderAgentId,
                        messageType: remote.messageType,
                        source: remote.source,
                        responseState: remote.responseState,
                        content: remote.content
                    ) {
                        markAsyncReplyResolved(for: agent, traceId: remote.traceId)
                    }
                    continue
                }

                let role = Self.localRole(
                    senderAgentId: remote.senderAgentId,
                    messageType: remote.messageType,
                    source: remote.source,
                    responseState: remote.responseState
                )
                if let localMatch = currentMessages.first(where: { message in
                    message.remoteMessageId == nil
                        && message.role == role
                        && message.content.trimmingCharacters(in: .whitespacesAndNewlines) == remote.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        && abs(message.timestamp.timeIntervalSince(remote.createdAt)) < 45
                }) {
                    localMatch.remoteMessageId = remote.id
                    localMatch.source = localMatch.source ?? remote.source
                    localMatch.lane = localMatch.lane ?? remote.lane
                    localMatch.deliveryMode = localMatch.deliveryMode ?? remote.deliveryMode
                    localMatch.provenance = localMatch.provenance ?? remote.normalizedProvenance
                    localMatch.deliveryState = localMatch.deliveryState ?? Self.effectiveDeliveryState(
                        content: remote.content,
                        deliveryMode: remote.deliveryMode,
                        provenance: remote.normalizedProvenance,
                        source: remote.source,
                        lane: remote.lane,
                        responseState: remote.responseState
                    )
                    localMatch.deliveryError = localMatch.deliveryError ?? remote.deliveryError
                    localMatch.deliveryFailedHop = localMatch.deliveryFailedHop ?? remote.deliveryFailedHop
                    localMatch.deliveryEvidence = localMatch.deliveryEvidence ?? remote.deliveryEvidence
                    if localMatch.role == "user" {
                        localMatch.userDeliveryState = Self.userDeliveryState(
                            remoteUserMessageId: remote.id,
                            responseState: localMatch.deliveryState ?? remote.deliveryState ?? remote.responseState
                        ).rawValue
                    }
                    localMatch.modelUsed = localMatch.modelUsed ?? remote.computeAttributionLabel
                    localMatch.traceId = localMatch.traceId ?? remote.traceId
                    localMatch.triageId = localMatch.triageId ?? remote.triageId
                    localMatch.triageTraceId = localMatch.triageTraceId ?? remote.triageTraceId
                    localMatch.fileAttachmentPath = localMatch.fileAttachmentPath ?? remote.fileAttachment?.path
                    existingRemoteIds.insert(remote.id)
                    didChange = true
                    continue
                }

                let message = DMMessage(
                    role: role,
                    content: remote.content,
                    timestamp: remote.createdAt,
                    isStreaming: false
                )
                message.source = remote.source ?? "orca.chat.history"
                message.lane = remote.lane ?? Self.defaultLane(senderAgentId: remote.senderAgentId, messageType: remote.messageType, source: remote.source, responseState: remote.responseState)
                message.deliveryMode = remote.deliveryMode ?? Self.defaultDeliveryMode(senderAgentId: remote.senderAgentId, messageType: remote.messageType, source: remote.source, responseState: remote.responseState)
                message.provenance = remote.normalizedProvenance ?? DMResponseProvenance(deliveryMode: remote.deliveryMode, source: remote.source, lane: remote.lane).rawValue
                message.deliveryState = Self.effectiveDeliveryState(
                    content: remote.content,
                    deliveryMode: remote.deliveryMode,
                    provenance: remote.normalizedProvenance,
                    source: remote.source,
                    lane: remote.lane,
                    responseState: remote.responseState
                ) ?? DMDeliveryState.responseReceived.rawValue
                message.deliveryError = remote.deliveryError
                message.deliveryFailedHop = remote.deliveryFailedHop
                message.deliveryEvidence = remote.deliveryEvidence
                if role == "user" {
                    message.userDeliveryState = Self.userDeliveryState(
                        remoteUserMessageId: remote.id,
                        responseState: message.deliveryState
                    ).rawValue
                }
                message.modelUsed = remote.computeAttributionLabel
                message.traceId = remote.traceId
                message.remoteMessageId = remote.id
                message.triageId = remote.triageId
                message.triageTraceId = remote.triageTraceId
                message.fileAttachmentPath = remote.fileAttachment?.path
                message.conversation = conversation
                ctx.insert(message)
                currentMessages.append(message)
                conversation.lastMessageText = remote.content
                conversation.lastMessageDate = remote.createdAt
                existingRemoteIds.insert(remote.id)
                didChange = true
            }

            if didChange {
                currentMessages.sort { $0.timestamp < $1.timestamp }
                try? ctx.save()
                loadConversations()
            }
        } catch {
            if selectedAgent?.id == agent.id {
                liveChatStatus = "ORCA chat history refresh unavailable."
            }
        }
    }

    private static func isImportableRemoteMessage(
        senderAgentId: String?,
        messageType: String?,
        source: String?,
        responseState: String?,
        includeUserMessages: Bool = false
    ) -> Bool {
        let normalizedType = messageType?.lowercased() ?? "text"
        let normalizedSource = source?.lowercased() ?? ""
        let parsedState = DMDeliveryState.parse(responseState)

        if senderAgentId != nil, normalizedType == "text" {
            return true
        }
        if includeUserMessages, senderAgentId == nil, normalizedType == "text" {
            return true
        }
        if normalizedType == "system" {
            return true
        }
        if normalizedSource.contains("orca.chat.ack")
            || normalizedSource.contains("schoolhouse")
            || parsedState == .computeRunning
            || parsedState == .waitingForLiveAgent
            || parsedState == .claimedByAgent
            || parsedState == .deliveryNatsFailed
            || parsedState == .agentUnresponsive {
            return true
        }
        return false
    }

    private static func localRole(senderAgentId: String?, messageType: String?, source: String?, responseState: String?) -> String {
        if isSystemRemoteMessage(messageType: messageType, source: source, responseState: responseState) {
            return "assistant"
        }
        return senderAgentId == nil ? "user" : "assistant"
    }

    private static func defaultLane(senderAgentId: String?, messageType: String?, source: String?, responseState: String?) -> String? {
        if isSystemRemoteMessage(messageType: messageType, source: source, responseState: responseState) {
            return "schoolhouse_status"
        }
        return senderAgentId == nil ? nil : "direct_agent_inbox"
    }

    private static func defaultDeliveryMode(senderAgentId: String?, messageType: String?, source: String?, responseState: String?) -> String? {
        if isSystemRemoteMessage(messageType: messageType, source: source, responseState: responseState) {
            return DMDeliveryMode.system.rawValue
        }
        return senderAgentId == nil ? nil : DMDeliveryMode.liveInbox.rawValue
    }

    private static func isSystemRemoteMessage(messageType: String?, source: String?, responseState: String?) -> Bool {
        let normalizedType = messageType?.lowercased()
        let normalizedSource = source?.lowercased() ?? ""
        let parsedState = DMDeliveryState.parse(responseState)
        return normalizedType == "system"
            || normalizedSource.contains("orca.chat.ack")
            || normalizedSource.contains("schoolhouse")
            || parsedState == .computeRunning
            || parsedState == .waitingForLiveAgent
            || parsedState == .claimedByAgent
            || parsedState == .deliveryNatsFailed
            || parsedState == .agentUnresponsive
    }

    private static func normalizedDeliveryState(_ raw: String?) -> String? {
        DMDeliveryState.parse(raw)?.rawValue
    }

    private static func userDeliveryState(remoteUserMessageId: String?, responseState: String?) -> DMUserMessageDeliveryState {
        let parsedState = DMDeliveryState.parse(responseState)
        switch parsedState {
        case .deliveryNatsFailed:
            return .transportFailed
        case .agentUnresponsive:
            return .agentUnresponsive
        case .failed, .fallbackPresented:
            return .failed
        case .responseReceived:
            return .sent
        case .computeRunning, .waitingForLiveAgent, .claimedByAgent, .agentRunQueued, .agentRunRunning, .timedOut:
            return .accepted
        case .sending, .routing:
            return .sending
        case nil:
            let remoteId = remoteUserMessageId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return remoteId.isEmpty ? .sending : .accepted
        }
    }

    private static func isRetryableUserDelivery(_ raw: String?) -> Bool {
        switch DMUserMessageDeliveryState.parse(raw) {
        case .failed, .transportFailed, .agentUnresponsive:
            return true
        default:
            return false
        }
    }

    private static func effectiveDeliveryState(
        content: String,
        deliveryMode: String?,
        provenance: String?,
        source: String?,
        lane: String?,
        responseState: String?
    ) -> String? {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parsedMode = DMDeliveryMode.parse(deliveryMode)
        let parsedProvenance = DMResponseProvenance.parse(provenance)
        let parsedState = DMDeliveryState.parse(responseState)
        let normalizedSource = source?.lowercased() ?? ""
        let normalizedLane = lane?.lowercased() ?? ""

        if normalized == "recorded in orca and queued for compute response. the result will appear here shortly." {
            if parsedMode == .liveInbox
                || parsedProvenance == .liveInbox
                || normalizedLane.contains("direct_agent_inbox")
                || normalizedSource.contains("pod-bridge") {
                return DMDeliveryState.waitingForLiveAgent.rawValue
            }
            return DMDeliveryState.computeRunning.rawValue
        }

        if normalized.hasPrefix("sent to ") && normalized.contains(" live nerve inbox") {
            return DMDeliveryState.waitingForLiveAgent.rawValue
        }

        if normalized.contains(" claimed this live inbox request") {
            return DMDeliveryState.claimedByAgent.rawValue
        }

        return parsedState?.rawValue
    }

    private static func isPendingAsyncDeliveryState(_ raw: String?) -> Bool {
        switch DMDeliveryState.parse(raw) {
        case .waitingForLiveAgent, .computeRunning, .claimedByAgent, .agentRunQueued, .agentRunRunning:
            return true
        default:
            return false
        }
    }

    private static func shouldResolvePendingAsync(
        senderAgentId: String?,
        messageType: String?,
        source: String?,
        responseState: String?,
        content: String
    ) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalizedType = messageType?.lowercased() ?? "text"
        let normalizedSource = source?.lowercased() ?? ""
        let parsedState = DMDeliveryState.parse(responseState)

        if normalizedSource.contains("orca.chat.ack") {
            return false
        }
        if parsedState == .waitingForLiveAgent
            || parsedState == .computeRunning
            || parsedState == .claimedByAgent {
            return false
        }
        if senderAgentId == nil {
            return false
        }
        if parsedState == .responseReceived || parsedState == .failed {
            return true
        }
        return normalizedType == "text"
    }

    private func refreshChannelSummary(agent: AgentInfo, channelId: String) async {
        guard selectedAgent?.id == agent.id else { return }
        do {
            let summary: DirectChatChannelSummaryDTO = try await api.get(path: "/api/v1/chat/channels/\(channelId)/summary")
            guard selectedAgent?.id == agent.id else { return }
            liveChatStatus = Self.channelSummaryStatus(summary, agent: agent)
        } catch {
            if selectedAgent?.id == agent.id {
                liveChatStatus = "ORCA channel summary unavailable."
            }
        }
    }

    private static func channelSummaryStatus(_ summary: DirectChatChannelSummaryDTO, agent: AgentInfo) -> String {
        let short = String(summary.channelId.prefix(8))
        var parts = ["ORCA channel \(short): \(summary.messageCount) messages"]
        if summary.pendingCount > 0 {
            parts.append("\(summary.pendingCount) pending markers")
        }
        if let state = summary.latestResponseState, !state.isEmpty {
            parts.append(DMDeliveryState.parse(state)?.displayLabel ?? state.replacingOccurrences(of: "_", with: " "))
        }
        if summary.activeSSEClients > 0 {
            parts.append("\(summary.activeSSEClients) live stream")
        }
        if let provenance = summary.latestProvenance, !provenance.isEmpty {
            parts.append(provenance.replacingOccurrences(of: "_", with: " "))
        } else {
            parts.append(agent.name)
        }
        return parts.joined(separator: " · ")
    }

    private func markLiveInboxWaitTimedOut(for agent: AgentInfo, since minimumCreatedAt: Date?) {
        guard let ctx = modelContext else { return }
        var changed = false
        for message in currentMessages where DMDeliveryState.parse(message.deliveryState) == .waitingForLiveAgent {
            if let minimumCreatedAt, message.timestamp < minimumCreatedAt {
                continue
            }
            message.deliveryState = DMDeliveryState.timedOut.rawValue
            changed = true
        }
        if changed {
            try? ctx.save()
            loadMessages(for: agent)
        }
    }

    private func requestLiveInboxFallback(for agent: AgentInfo, channelId: String, since minimumCreatedAt: Date?) async {
        guard selectedAgent?.id == agent.id,
              let pending = latestTimedOutLiveInboxMessage(since: minimumCreatedAt),
              let userMessage = sourceUserMessage(for: pending),
              let userRemoteId = userMessage.remoteMessageId,
              !userRemoteId.isEmpty else {
            liveChatStatus = "Still waiting for \(agent.name). Fallback draft is unavailable until ORCA records the source message."
            return
        }

        let traceId = pending.traceId ?? userMessage.traceId ?? Self.makeTraceId(prefix: "pod-chat-fallback")
        pending.deliveryState = DMDeliveryState.computeRunning.rawValue
        pending.provenance = DMResponseProvenance.compute.rawValue
        pending.deliveryMode = DMDeliveryMode.compute.rawValue
        pending.content = """
        \(agent.name) did not reply inside the live window.
        Requesting a compute draft in \(agent.name)'s lane. This will be labeled as fallback, not a live reply.
        """
        try? modelContext?.save()

        do {
            let body = DirectChatFallbackRequestBody(
                channelId: channelId,
                userMessageId: userRemoteId,
                content: userMessage.content,
                history: fallbackHistory(before: userMessage),
                traceId: traceId,
                triageId: userMessage.triageId ?? pending.triageId,
                triageTraceId: userMessage.triageTraceId ?? pending.triageTraceId,
                activeTicketId: activeTicketId,
                fallbackReason: "agent_timeout",
                fallbackAfterSeconds: 120
            )
            let response: DirectChatFallbackResponseDTO = try await api.post(
                path: "/api/v1/chat/direct/\(agent.id)/fallback",
                body: body
            )
            appendFallbackResponse(response, for: agent, channelId: channelId)
            await importORCAChannelHistory(agent: agent, channelId: channelId)
            await refreshChannelSummary(agent: agent, channelId: channelId)
            liveChatStatus = "Added compute fallback draft for \(agent.name)."
        } catch let apiError as APIError {
            pending.deliveryState = DMDeliveryState.timedOut.rawValue
            liveChatStatus = "Still waiting for \(agent.name). Fallback draft failed: \(apiError.message)"
            try? modelContext?.save()
        } catch {
            pending.deliveryState = DMDeliveryState.timedOut.rawValue
            liveChatStatus = "Still waiting for \(agent.name). Fallback draft failed."
            try? modelContext?.save()
        }
    }

    private func latestTimedOutLiveInboxMessage(since minimumCreatedAt: Date?) -> DMMessage? {
        currentMessages
            .filter { message in
                DMDeliveryState.parse(message.deliveryState) == .timedOut
                    && (minimumCreatedAt.map { message.timestamp >= $0 } ?? true)
                    && message.role == "assistant"
            }
            .max(by: { $0.timestamp < $1.timestamp })
    }

    private func sourceUserMessage(for pending: DMMessage) -> DMMessage? {
        let traceMatch = currentMessages.last { message in
            message.role == "user"
                && message.timestamp <= pending.timestamp
                && message.traceId == pending.traceId
        }
        if let traceMatch { return traceMatch }
        return currentMessages.last { message in
            message.role == "user" && message.timestamp <= pending.timestamp
        }
    }

    private func fallbackHistory(before userMessage: DMMessage) -> [DirectChatHistoryMessageBody] {
        currentMessages
            .filter { message in
                message.timestamp < userMessage.timestamp
                    && !message.isStreaming
                    && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .suffix(20)
            .map { DirectChatHistoryMessageBody(role: $0.role, content: $0.content) }
    }

    private func appendFallbackResponse(_ response: DirectChatFallbackResponseDTO, for agent: AgentInfo, channelId: String) {
        guard selectedAgent?.id == agent.id,
              let ctx = modelContext,
              !hasImportedRemoteMessage(
                id: response.assistantMessageId,
                content: response.content,
                timestamp: Date(),
                role: "assistant"
              ) else { return }

        let conversation = getOrCreateConversation(for: agent)
        conversation.orcaChannelId = channelId
        let message = DMMessage(role: "assistant", content: response.content, isStreaming: false)
        message.source = response.metadata.source
        message.lane = response.metadata.lane
        message.deliveryMode = response.metadata.deliveryMode
        message.provenance = response.metadata.normalizedProvenance
        message.deliveryState = response.metadata.responseState ?? DMDeliveryState.responseReceived.rawValue
        message.modelUsed = response.metadata.displayName
        message.tokenCount = response.metadata.tokenCount
        message.traceId = response.metadata.traceId
        message.remoteMessageId = response.assistantMessageId
        message.computeRunId = response.metadata.computeRunId
        message.triageId = response.metadata.triageId
        message.triageTraceId = response.metadata.triageTraceId
        message.conversation = conversation
        ctx.insert(message)
        currentMessages.append(message)
        conversation.lastMessageText = response.content
        conversation.lastMessageDate = message.timestamp
        markAsyncReplyResolved(for: agent, traceId: response.metadata.traceId)
        try? ctx.save()
        loadConversations()
    }

    private func markAsyncReplyResolved(for agent: AgentInfo, traceId: String?) {
        let pending = currentMessages.filter { message in
            Self.isPendingAsyncDeliveryState(message.deliveryState)
                || DMDeliveryState.parse(message.deliveryState) == .timedOut
        }

        let targets: [DMMessage]
        if let traceId, !traceId.isEmpty {
            targets = pending.filter { $0.traceId == traceId }
        } else if let newest = pending.max(by: { $0.timestamp < $1.timestamp }) {
            targets = [newest]
        } else {
            targets = []
        }

        guard !targets.isEmpty else { return }
        for message in targets {
            if message.deliveryState != DMDeliveryState.responseReceived.rawValue {
                message.deliveryState = DMDeliveryState.responseReceived.rawValue
            }
        }
        try? modelContext?.save()
        loadMessages(for: agent)
    }

    private func hasPendingAsyncReply(for agent: AgentInfo) -> Bool {
        currentMessages.contains { message in
            Self.isPendingAsyncDeliveryState(message.deliveryState)
        }
    }

    private func hasPendingLiveInboxReply(for agent: AgentInfo) -> Bool {
        currentMessages.contains { message in
            DMDeliveryState.parse(message.deliveryState) == .waitingForLiveAgent
        }
    }

    func createTicketFromChat() {
        guard let agent = selectedAgent, !isCreatingTicket else { return }

        let intake = ticketIntakeText()
        guard !intake.isEmpty else {
            ticketActionMessage = nil
            error = "Write a message first, then create a ticket."
            return
        }

        error = nil
        ticketActionMessage = nil
        isCreatingTicket = true
        let shouldAppendSubmittedDraft = !composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        Task {
            defer { isCreatingTicket = false }
            do {
                if let ticketId = activeTicketId {
                    let traceId = Self.makeTraceId(prefix: "pod-chat-comment")
                    let comment = DirectChatTicketCommentBody(
                        message: Self.ticketComment(from: intake, agent: agent, traceId: traceId),
                        traceId: traceId,
                        source: "pod.chat",
                        lane: "ticket_comment"
                    )
                    let _: DirectChatTicketCommentDTO = try await api.post(
                        path: "/api/v1/tickets/\(ticketId)/comments",
                        body: comment
                    )
                    if shouldAppendSubmittedDraft {
                        appendLocalUserMessage(intake, for: agent)
                        composedMessage = ""
                    }
                    ticketActionMessage = "Added comment to ORCA ticket \(ticketId)."
                    appendLocalAssistantMessage(
                        "Added this follow-up to ORCA ticket \(ticketId).",
                        for: agent
                    )
                    return
                }

                let triagePreview = await resolvedTriagePreview(for: intake, agent: agent, requestedMode: selectedDeliveryMode)
                let triage = triagePreview.map(DirectChatMermanTriageDTO.previewBacked)
                let metadata = Self.ticketCreationMetadata(for: intake, agent: agent, triage: triage)
                let assigneeAgentId = await resolveORCAAgentId(for: metadata.ownerSlug)
                pendingTicketDraft = DirectChatTicketDraft(
                    title: Self.ticketTitle(from: intake, agent: agent),
                    description: Self.ticketDescription(from: intake, agent: agent, triage: triage, metadata: metadata),
                    priority: Self.ticketPriority(for: intake),
                    ownerSlug: metadata.ownerSlug,
                    assigneeAgentId: assigneeAgentId,
                    ticketType: metadata.ticketType,
                    tags: metadata.visibleTags,
                    computeTag: metadata.computeTag,
                    approvalState: metadata.approvalState,
                    approvalGate: triage?.approvalGate,
                    autonomyLevel: metadata.autonomyLevel,
                    workerLane: metadata.workerLane,
                    toolPolicy: metadata.toolPolicy,
                    acceptanceCriteria: metadata.acceptanceCriteria,
                    desiredOutcome: Self.desiredOutcome(for: intake, agent: agent),
                    intake: intake,
                    agentId: agent.id,
                    agentName: agent.name,
                    triageId: triage?.triageId,
                    triageTraceId: triage?.traceId,
                    recommendedRuntime: triage?.recommendedRuntime,
                    recommendedSurface: triage?.recommendedSurface,
                    runtimeReason: triage?.runtimeReason,
                    handoffSubject: triage?.handoffSubject,
                    handoffPacket: Self.handoffPacket(for: triage, agent: agent),
                    triageSummary: Self.triageSummaryMarkdown(triage),
                    shouldAppendSubmittedDraft: shouldAppendSubmittedDraft
                )
                ticketActionMessage = "Review the ORCA ticket draft before creating it."
            } catch {
                self.error = "Couldn't prepare ORCA ticket. Try again."
            }
        }
    }

    func submitPendingTicketDraft(_ editedDraft: DirectChatTicketDraft? = nil) {
        guard let agent = selectedAgent, let pendingDraft = pendingTicketDraft, !isCreatingTicket else { return }
        let draft = editedDraft ?? pendingDraft
        isCreatingTicket = true
        ticketActionMessage = nil
        error = nil

        Task {
            defer { isCreatingTicket = false }
            do {
                let body = DirectChatCreateTicketBody(
                    title: draft.title,
                    description: draft.description,
                    priority: draft.priority,
                    assigneeAgentId: draft.assigneeAgentId,
                    chatThreadId: getOrCreateConversation(for: agent).orcaChannelId,
                    ticketType: draft.ticketType,
                    tags: draft.tags,
                    computeTag: draft.computeTag,
                    approvalState: draft.approvalState,
                    approvalGate: draft.approvalGate,
                    autonomyLevel: draft.autonomyLevel,
                    workerLane: draft.workerLane,
                    toolPolicy: draft.toolPolicy,
                    acceptanceCriteria: draft.acceptanceCriteria,
                    desiredOutcome: draft.desiredOutcome,
                    triageId: draft.triageId,
                    triageTraceId: draft.triageTraceId,
                    recommendedRuntime: draft.recommendedRuntime,
                    recommendedSurface: draft.recommendedSurface,
                    runtimeReason: draft.runtimeReason,
                    handoffSubject: draft.handoffSubject,
                    handoffPacket: draft.handoffPacket
                )
                let ticket: DirectChatTicketDTO = try await api.post(path: "/api/v1/tickets", body: body)
                let traceId = draft.triageTraceId ?? Self.makeTraceId(prefix: "pod-chat-ticket")
                activeTicketId = ticket.id
                activeTicketTitle = ticket.title
                saveTicketContext(ticketId: ticket.id, ticketTitle: ticket.title, channelId: getOrCreateConversation(for: agent).orcaChannelId, for: agent)
                await loadAttachedTicketContinuity(ticketId: ticket.id)
                startAttachedTicketLifecycleStream(agent: agent, ticketId: ticket.id)
                if draft.shouldAppendSubmittedDraft {
                    appendLocalUserMessage(draft.intake, for: agent)
                    composedMessage = ""
                }
                try? await postInitialTicketEvidence(ticketId: ticket.id, draft: draft, traceId: traceId)
                ticketActionMessage = "Created ORCA ticket \(ticket.id)."
                appendLocalAssistantMessage(
                    Self.createdTicketMessage(ticket: ticket, draft: draft),
                    for: agent
                )
                pendingTicketDraft = nil
            } catch let apiError as APIError {
                error = "Couldn't create ORCA ticket: \(apiError.message)"
            } catch {
                self.error = "Couldn't create ORCA ticket. Try again."
            }
        }
    }

    func cancelPendingTicketDraft() {
        pendingTicketDraft = nil
        ticketActionMessage = nil
    }

    func loadAttachableTickets() async {
        isLoadingAttachableTickets = true
        attachTicketError = nil
        do {
            let tickets: [DirectChatAttachableTicketDTO] = try await api.get(path: "/api/v1/tickets")
            let activeStatuses = Set(["open", "triaged", "planned", "approved", "assigned", "claimed", "in_progress", "blocked", "ready_for_review"])
            attachableTickets = tickets
                .filter { activeStatuses.contains($0.status.lowercased()) }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(120)
                .map { $0.toAttachableTicket() }
        } catch let apiError as APIError {
            attachableTickets = []
            attachTicketError = apiError.message
        } catch {
            attachableTickets = []
            attachTicketError = "ORCA tickets are unavailable."
        }
        isLoadingAttachableTickets = false
    }

    func attachTicket(_ ticket: DirectChatAttachableTicket) {
        guard let agent = selectedAgent else { return }
        saveTicketContext(ticketId: ticket.id, ticketTitle: ticket.title, channelId: getOrCreateConversation(for: agent).orcaChannelId, for: agent)
        activeTicketId = ticket.id
        activeTicketTitle = ticket.title
        Task { await loadAttachedTicketContinuity(ticketId: ticket.id) }
        ticketActionMessage = "Attached this chat to ORCA ticket \(ticket.id)."
        appendLocalAssistantMessage(
            "Attached this \(agent.name) chat to ORCA ticket \(ticket.id): \(ticket.title). New ticket actions from this chat will append evidence there.",
            for: agent
        )
        if let channelId = getOrCreateConversation(for: agent).orcaChannelId {
            Task { await linkORCAChatThread(ticketId: ticket.id, channelId: channelId) }
        }
        startAttachedTicketLifecycleStream(agent: agent, ticketId: ticket.id)
    }

    private func linkORCAChatThread(ticketId: String, channelId: String) async {
        do {
            let body = DirectChatPatchTicketBody(chatThreadId: channelId)
            let _: DirectChatTicketDTO = try await api.patch(path: "/api/v1/tickets/\(ticketId)", body: body)
        } catch {
            if activeTicketId == ticketId {
                ticketActionMessage = "Attached locally. ORCA thread link will retry when ticket sync is available."
            }
        }
    }

    private func requestMermanTriage(intake: String, target agent: AgentInfo) async -> DirectChatMermanTriageDTO? {
        do {
            let body = DirectChatMermanTriageBody(
                surface: "pod_chat",
                target: agent.id,
                text: intake,
                context: [
                    "selected_agent": agent.id,
                    "active_ticket_id": activeTicketId ?? "",
                    "source": "pod.direct_chat"
                ]
            )
            return try await api.post(path: "/api/v1/schoolhouse/triage", body: body)
        } catch let apiError as APIError {
            triagePreviewError = "Merman triage HTTP \(apiError.code): \(apiError.message)"
            return nil
        } catch DecodingError.keyNotFound(let key, _) {
            triagePreviewError = "Merman triage response missing \(key.stringValue)."
            return nil
        } catch DecodingError.typeMismatch(_, let context) {
            triagePreviewError = "Merman triage response type mismatch: \(context.codingPath.map(\.stringValue).joined(separator: "."))."
            return nil
        } catch DecodingError.dataCorrupted(let context) {
            triagePreviewError = "Merman triage response was malformed: \(context.debugDescription)"
            return nil
        } catch {
            triagePreviewError = "Merman triage unavailable: \(error.localizedDescription)"
            return nil
        }
    }

    private func postInitialTicketEvidence(ticketId: String, intake: String, agent: AgentInfo, triage: DirectChatMermanTriageDTO?, metadata: TicketCreationMetadata, traceId: String) async throws {
        let comment = DirectChatTicketCommentBody(
            message: """
            Created from Pod direct chat with \(agent.name).

            Trace: \(traceId)

            \(Self.triageSummaryMarkdown(triage))

            Merman linkage:
            - Triage id: \(triage?.triageId ?? "none")
            - Triage trace: \(triage?.traceId ?? traceId)

            Ticket automation:
            - Owner: \(metadata.ownerSlug)
            - Approval state: \(metadata.approvalState)
            - Autonomy: \(metadata.autonomyLevel)
            - Worker lane: \(metadata.workerLane)
            - Tool policy: \(metadata.toolPolicy)
            - Visible tags: \(metadata.visibleTags.joined(separator: ", "))

            Initial intake:
            \(intake)
            """,
            traceId: traceId,
            source: "pod.chat",
            lane: "ticket_intake"
        )
        let _: DirectChatTicketCommentDTO = try await api.post(
            path: "/api/v1/tickets/\(ticketId)/comments",
            body: comment
        )
    }

    private func postInitialTicketEvidence(ticketId: String, draft: DirectChatTicketDraft, traceId: String) async throws {
        let comment = DirectChatTicketCommentBody(
            message: """
            Created from Pod direct chat with \(draft.agentName).

            Trace: \(traceId)

            \(draft.triageSummary)

            Merman linkage:
            - Triage id: \(draft.triageId ?? "none")
            - Triage trace: \(draft.triageTraceId ?? traceId)

            Ticket automation:
            - Owner: \(draft.ownerSlug)
            - Approval state: \(draft.approvalState)
            - Autonomy: \(draft.autonomyLevel)
            - Worker lane: \(draft.workerLane)
            - Tool policy: \(draft.toolPolicy)
            - Visible tags: \(draft.tags.joined(separator: ", "))

            Initial intake:
            \(draft.intake)
            """,
            traceId: traceId,
            source: "pod.chat",
            lane: "ticket_intake"
        )
        let _: DirectChatTicketCommentDTO = try await api.post(
            path: "/api/v1/tickets/\(ticketId)/comments",
            body: comment
        )
    }

    private func saveTicketContext(ticketId: String, ticketTitle: String, channelId: String? = nil, for agent: AgentInfo) {
        guard let ctx = modelContext else { return }
        let conversation = getOrCreateConversation(for: agent)
        conversation.activeTicketId = ticketId
        conversation.activeTicketTitle = ticketTitle
        if let channelId, !channelId.isEmpty {
            conversation.orcaChannelId = channelId
        }
        try? ctx.save()
    }

    func clearTicketContext() {
        guard let agent = selectedAgent, let ctx = modelContext else { return }
        let conversation = getOrCreateConversation(for: agent)
        conversation.activeTicketId = nil
        conversation.activeTicketTitle = nil
        activeTicketId = nil
        activeTicketTitle = nil
        stopAttachedTicketLifecycleStream()
        stopAgentRunFollowupRefresh()
        activeTicketContinuity = nil
        ticketContinuityError = nil
        clearAgentRunContext()
        ticketActionMessage = "Detached this chat from ORCA. New messages stay local until you create a ticket."
        try? ctx.save()
    }

    func refreshAttachedTicketContinuity() async {
        guard let ticketId = activeTicketId else { return }
        await loadAttachedTicketContinuity(ticketId: ticketId)
        await loadAgentRunContext(ticketId: ticketId)
    }

    private func loadAttachedTicketContinuity(ticketId: String) async {
        guard activeTicketId == ticketId else { return }
        isLoadingTicketContinuity = true
        ticketContinuityError = nil
        defer { isLoadingTicketContinuity = false }

        do {
            async let ticketDTO: TicketDTO = api.get(path: "/api/v1/tickets/\(ticketId)")
            async let summaryDTO: TicketListSummaryDTO? = optionalGet(path: "/api/v1/tickets/\(ticketId)/summary")
            async let commentDTOs: [TicketCommentDTO] = api.get(path: "/api/v1/tickets/\(ticketId)/comments")
            async let runDTOs: [AgentRunDTO]? = optionalGet(path: "/api/v1/tickets/\(ticketId)/agent-runs")

            let ticketDTOValue = try await ticketDTO
            let summaryDTOValue = try await summaryDTO
            let commentDTOValues = try await commentDTOs
            let runDTOValues = try await runDTOs
            let ticket = ticketDTOValue.toDomain()
            let summary = summaryDTOValue?.toDomain()
            let comments = commentDTOValues.map { $0.toDomain() }
            let runs = (runDTOValues ?? []).map { $0.toDomain() }

            guard activeTicketId == ticketId else { return }
            activeTicketTitle = ticket.title
            activeTicketContinuity = DirectChatTicketContinuity(
                ticket: ticket,
                summary: summary,
                comments: comments,
                runs: runs
            )
            await loadAgentRunContext(ticketId: ticketId)
        } catch let apiError as APIError {
            if activeTicketId == ticketId {
                ticketContinuityError = apiError.message
            }
        } catch {
            if activeTicketId == ticketId {
                ticketContinuityError = "Attached ticket continuity is unavailable."
            }
        }
    }

    private func optionalGet<T: Decodable>(path: String) async throws -> T? {
        do {
            return try await api.get(path: path)
        } catch {
            return nil
        }
    }

    func loadAgentRunContext(ticketId: String) async {
        guard activeTicketId == ticketId else { return }
        await loadApprovals(ticketId: ticketId)
        await loadWorkspaceContext(ticketId: ticketId)
        guard let continuity = activeTicketContinuity else { return }

        let runs = continuity.sortedRuns
        if let traceId = runs.first(where: { ($0.traceId ?? "").isEmpty == false })?.traceId {
            await loadAgentRunTrace(traceId: traceId)
        }
        for run in runs.prefix(3) {
            await loadArtifactSummaries(runId: run.id)
        }
        workClassroomLastRefreshAt = Date()
    }

    func refreshWorkClassroomFromChat() {
        guard let ticketId = activeTicketId, !isRefreshingWorkClassroom else { return }
        isRefreshingWorkClassroom = true
        Task {
            defer { isRefreshingWorkClassroom = false }
            artifactSummariesByRunId = [:]
            artifactSummaryErrorsByRunId = [:]
            await loadAttachedTicketContinuity(ticketId: ticketId)
            workClassroomLastRefreshAt = Date()
        }
    }

    var workClassroomReadinessPercent: Int {
        guard activeTicketId != nil else { return 0 }
        var score = 20
        if activeTicketContinuity != nil { score += 20 }
        if activeTicketContinuity?.latestRun != nil { score += 15 }
        if agentRunTrace != nil { score += 15 }
        if !ticketApprovals.isEmpty || !isLoadingTicketApprovals { score += 10 }
        if !artifactSummariesByRunId.values.flatMap({ $0 }).isEmpty { score += 10 }
        if workspaceContext != nil { score += 10 }
        if workClassroomLastRefreshAt != nil { score += 10 }
        return min(score, 100)
    }

    var workClassroomRefreshLabel: String {
        guard let workClassroomLastRefreshAt else { return "Not refreshed yet" }
        let age = max(0, Int(Date().timeIntervalSince(workClassroomLastRefreshAt)))
        if age < 10 { return "Just refreshed" }
        if age < 60 { return "Refreshed \(age)s ago" }
        if age < 3600 { return "Refreshed \(age / 60)m ago" }
        return "Refreshed \(age / 3600)h ago"
    }

    var ticketLiveSummaryLabel: String {
        guard ticketLiveEventCount > 0 else { return "No ticket stream events yet" }
        let action = ticketLiveLastAction ?? "updated"
        let ageText: String
        if let ticketLiveLastEventAt {
            let age = max(0, Int(Date().timeIntervalSince(ticketLiveLastEventAt)))
            if age < 10 {
                ageText = "just now"
            } else if age < 60 {
                ageText = "\(age)s ago"
            } else if age < 3600 {
                ageText = "\(age / 60)m ago"
            } else {
                ageText = "\(age / 3600)h ago"
            }
        } else {
            ageText = "recently"
        }
        return "\(ticketLiveEventCount) stream event\(ticketLiveEventCount == 1 ? "" : "s") · last \(action) \(ageText)"
    }

    var workClassroomGapLabels: [String] {
        guard activeTicketId != nil else { return [] }
        var gaps: [String] = []
        if activeTicketContinuity == nil {
            gaps.append("Ticket continuity not loaded")
        }
        if activeTicketContinuity?.latestRun == nil {
            gaps.append("No Agent Run attached")
        }
        if agentRunTrace == nil {
            gaps.append(agentRunTraceError ?? "Trace evidence unavailable")
        }
        if artifactSummariesByRunId.values.flatMap({ $0 }).isEmpty {
            let artifactErrors = artifactSummaryErrorsByRunId.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            gaps.append(artifactErrors.first ?? "No artifact summaries loaded")
        }
        if ticketApprovals.isEmpty {
            gaps.append("No approval records visible")
        }
        if ticketLiveEventCount == 0 {
            gaps.append("No live ticket events seen")
        }
        if let workspaceContext {
            if workspaceContext.files.isEmpty {
                gaps.append(workspaceContext.gaps.first ?? "No ORCA-known workspace files")
            }
            if workspaceContext.capabilities["write_file"] != true {
                gaps.append("Workspace write still disabled")
            }
            if workspaceContext.capabilities["upload_file"] != true {
                gaps.append("Binary upload still disabled")
            }
        } else if isLoadingWorkspaceContext {
            gaps.append("Workspace context loading")
        } else {
            gaps.append(workspaceContextError ?? "Workspace context unavailable")
        }
        return Array(gaps.prefix(5))
    }

    private func loadWorkspaceContext(ticketId: String) async {
        isLoadingWorkspaceContext = true
        workspaceContextError = nil
        defer { isLoadingWorkspaceContext = false }

        do {
            let dto: DirectChatWorkspaceContextDTO = try await api.get(path: "/api/v1/workspaces/tickets/\(ticketId)")
            guard activeTicketId == ticketId else { return }
            workspaceContext = dto.toDomain()
        } catch let apiError as APIError {
            guard activeTicketId == ticketId else { return }
            workspaceContext = nil
            workspaceContextError = apiError.message
        } catch {
            guard activeTicketId == ticketId else { return }
            workspaceContext = nil
            workspaceContextError = "Workspace context unavailable."
        }
    }

    private func loadAgentRunTrace(traceId: String) async {
        guard !traceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoadingAgentRunTrace = true
        agentRunTraceError = nil
        defer { isLoadingAgentRunTrace = false }

        do {
            let dto: AgentRunTraceDTO = try await api.get(path: "/api/v1/agent-runs/traces/\(traceId)")
            agentRunTrace = dto.toDomain()
        } catch let apiError as APIError {
            agentRunTraceError = apiError.message
        } catch {
            agentRunTraceError = "Agent Run trace unavailable."
        }
    }

    private func loadArtifactSummaries(runId: String) async {
        guard artifactSummariesByRunId[runId] == nil else { return }
        do {
            let dtos: [AgentRunArtifactSummaryDTO] = try await api.get(path: "/api/v1/agent-runs/\(runId)/artifacts")
            artifactSummariesByRunId[runId] = dtos.map { $0.toDomain() }
            artifactSummaryErrorsByRunId[runId] = nil
        } catch let apiError as APIError {
            artifactSummaryErrorsByRunId[runId] = apiError.message
        } catch {
            artifactSummaryErrorsByRunId[runId] = "Artifacts unavailable."
        }
    }

    private func loadApprovals(ticketId: String) async {
        isLoadingTicketApprovals = true
        defer { isLoadingTicketApprovals = false }
        do {
            let dtos: [DirectChatApprovalDTO] = try await api.get(path: "/api/v1/tickets/\(ticketId)/approvals")
            ticketApprovals = dtos.map { $0.toDomain() }
        } catch {
            ticketApprovals = []
        }
    }

    func requestApprovalFromChat() {
        guard let ticketId = activeTicketId, !isRequestingTicketApproval else { return }
        isRequestingTicketApproval = true
        Task {
            defer { isRequestingTicketApproval = false }
            let body = DirectChatApprovalRequestBody(
                reason: "Approval review requested from Pod chat for attached ticket \(ticketId).",
                traceId: Self.makeTraceId(prefix: "pod-chat-approval-request"),
                source: "pod.chat.approval_request",
                lane: "human_approval_request"
            )
            do {
                let dto: DirectChatApprovalDTO = try await api.post(path: "/api/v1/tickets/\(ticketId)/approval-requests", body: body)
                approvalActionMessage = "Approval \(dto.approvalId) requested."
                await loadApprovals(ticketId: ticketId)
                await loadAttachedTicketContinuity(ticketId: ticketId)
            } catch let apiError as APIError {
                approvalActionMessage = "Couldn't request approval: \(apiError.message)"
            } catch {
                approvalActionMessage = "Couldn't request approval."
            }
        }
    }

    func resolveApprovalFromChat(_ approval: DirectChatApprovalRecord, approved: Bool) {
        guard let ticketId = activeTicketId else { return }
        guard !resolvingApprovalIds.contains(approval.id) else { return }
        resolvingApprovalIds.insert(approval.id)
        Task {
            defer { resolvingApprovalIds.remove(approval.id) }
            let body = DirectChatApprovalResolutionBody(
                status: approved ? "approved" : "rejected",
                reason: approved ? "Approved from Pod chat classroom." : "Rejected from Pod chat classroom.",
                traceId: Self.makeTraceId(prefix: approved ? "pod-chat-approval-approved" : "pod-chat-approval-rejected"),
                source: "pod.chat.approval_resolution",
                lane: "human_approval_resolution"
            )
            do {
                let _: DirectChatApprovalDTO = try await api.patch(path: "/api/v1/tickets/\(ticketId)/approvals/\(approval.id)", body: body)
                approvalActionMessage = approved ? "Approval \(approval.id) approved." : "Approval \(approval.id) rejected."
                await loadApprovals(ticketId: ticketId)
                await loadAttachedTicketContinuity(ticketId: ticketId)
            } catch let apiError as APIError {
                approvalActionMessage = "Couldn't resolve approval: \(apiError.message)"
            } catch {
                approvalActionMessage = "Couldn't resolve approval."
            }
        }
    }

    func saveMemoryCandidateFromChat() {
        guard !isSavingMemoryCandidate else { return }
        guard let ticketId = activeTicketId,
              let continuity = activeTicketContinuity else {
            memoryCandidateMessage = "Attach a ticket before saving memory."
            return
        }
        isSavingMemoryCandidate = true
        memoryCandidateMessage = nil
        Task {
            defer { isSavingMemoryCandidate = false }
            let traceId = continuity.latestRun?.traceId ?? Self.makeTraceId(prefix: "pod-chat-memory")
            let body = DirectChatNoteCreateRequest(
                targetType: "ticket",
                targetId: ticketId,
                noteType: "memory_candidate",
                title: "Memory candidate from Pod chat: \(continuity.ticket.title)",
                body: Self.memoryCandidateBody(continuity: continuity, traceId: traceId),
                tags: ["pod", "chat", "memory-candidate", "agent-run"],
                source: "pod.chat.memory_candidate",
                traceId: traceId,
                signState: "needs_review"
            )
            do {
                let _: OrcaNote = try await api.post(path: "/api/v1/notes/system/global", body: body)
                memoryCandidateMessage = "Memory candidate saved for Knowledge review."
            } catch let apiError as APIError {
                memoryCandidateMessage = "Couldn't save memory candidate: \(apiError.message)"
            } catch {
                memoryCandidateMessage = "Couldn't save memory candidate."
            }
        }
    }

    func saveWorkspaceArtifactFromChat() {
        guard !isSavingWorkspaceArtifact else { return }
        guard let ticketId = activeTicketId,
              let continuity = activeTicketContinuity else {
            workspaceArtifactMessage = "Attach a ticket before saving a workspace artifact."
            return
        }
        isSavingWorkspaceArtifact = true
        workspaceArtifactMessage = nil
        Task {
            defer { isSavingWorkspaceArtifact = false }
            let traceId = continuity.latestRun?.traceId ?? Self.makeTraceId(prefix: "pod-chat-workspace")
            let body = DirectChatWorkspaceFileWriteRequest(
                filename: "pod-chat-\(Self.slugForFilename(continuity.ticket.title))-\(Self.timestampForFilename()).md",
                content: Self.workspaceArtifactBody(
                    continuity: continuity,
                    messages: currentMessages,
                    composedMessage: composedMessage,
                    traceId: traceId
                ),
                description: "Pod chat workspace artifact for ticket \(ticketId)",
                runId: continuity.latestRun?.id,
                source: "pod.chat.workspace_artifact"
            )
            do {
                let dto: DirectChatWorkspaceFileWriteDTO = try await api.post(path: "/api/v1/workspaces/tickets/\(ticketId)/files", body: body)
                workspaceArtifactMessage = dto.message
                await loadWorkspaceContext(ticketId: ticketId)
                await loadAttachedTicketContinuity(ticketId: ticketId)
            } catch let apiError as APIError {
                workspaceArtifactMessage = "Couldn't save workspace artifact: \(apiError.message)"
            } catch {
                workspaceArtifactMessage = "Couldn't save workspace artifact."
            }
        }
    }

    func requestWorkspaceToolFromChat() {
        guard !isRequestingWorkspaceTool else { return }
        guard let ticketId = activeTicketId,
              let continuity = activeTicketContinuity else {
            workspaceToolMessage = "Attach a ticket before requesting a tool."
            return
        }
        let instruction = composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        isRequestingWorkspaceTool = true
        workspaceToolMessage = nil
        Task {
            defer { isRequestingWorkspaceTool = false }
            let body = DirectChatWorkspaceToolRequestBody(
                toolName: "agent_workspace_task",
                instruction: instruction.isEmpty ? continuity.nextActionLabel : instruction,
                reason: "Requested from Pod chat for attached ticket \(ticketId).",
                source: "pod.chat.tool_request"
            )
            do {
                let dto: DirectChatWorkspaceToolRequestCreateDTO = try await api.post(path: "/api/v1/workspaces/tickets/\(ticketId)/tool-requests", body: body)
                workspaceToolMessage = dto.message
                await loadWorkspaceContext(ticketId: ticketId)
                await loadAttachedTicketContinuity(ticketId: ticketId)
            } catch let apiError as APIError {
                workspaceToolMessage = "Couldn't request tool: \(apiError.message)"
            } catch {
                workspaceToolMessage = "Couldn't request tool."
            }
        }
    }

    func executeWorkspaceToolRequestFromChat(_ request: DirectChatWorkspaceToolRequest) {
        guard let ticketId = activeTicketId else {
            workspaceToolMessage = "Attach a ticket before executing a tool request."
            return
        }
        guard request.status == "waiting_for_human" || request.status == "queued" else {
            workspaceToolMessage = "Tool request is not waiting for execution."
            return
        }
        guard !executingWorkspaceToolRunIds.contains(request.runId) else { return }
        executingWorkspaceToolRunIds.insert(request.runId)
        workspaceToolMessage = nil
        Task {
            defer { executingWorkspaceToolRunIds.remove(request.runId) }
            let body = DirectChatWorkspaceToolExecuteBody(
                approvalNote: "Approved from Pod chat classroom.",
                source: "pod.chat.tool_execute"
            )
            do {
                let dto: DirectChatWorkspaceToolExecuteDTO = try await api.post(
                    path: "/api/v1/workspaces/tool-requests/\(request.runId)/execute-approved",
                    body: body
                )
                workspaceToolMessage = dto.message
                await loadWorkspaceContext(ticketId: ticketId)
                await loadAttachedTicketContinuity(ticketId: ticketId)
            } catch let apiError as APIError {
                workspaceToolMessage = "Couldn't execute tool request: \(apiError.message)"
            } catch {
                workspaceToolMessage = "Couldn't execute tool request."
            }
        }
    }

    private func startAttachedTicketLifecycleStream(agent: AgentInfo, ticketId: String) {
        if ticketLiveTicketId == ticketId, ticketLiveTask != nil { return }
        stopAttachedTicketLifecycleStream()
        ticketLiveTicketId = ticketId
        ticketLiveEventCount = 0
        ticketLiveLastEventAt = nil
        ticketLiveLastAction = nil
        ticketLiveStatus = "Watching ORCA ticket \(String(ticketId.prefix(8))) for live updates."

        ticketLiveTask = Task { [weak self] in
            guard let self else { return }
            guard let token = await self.api.currentToken(),
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.ticketLiveStatus = "Ticket live updates need an ORCA auth token."
                return
            }

            let manager = SSEStreamManager()
            self.ticketSSEManager = manager
            let events = await manager.connectTickets(token: token, baseURL: AppState.backendURL)
            do {
                for try await event in events {
                    if Task.isCancelled { break }
                    guard self.selectedAgent?.id == agent.id,
                          self.activeTicketId == ticketId else {
                        break
                    }
                    switch event {
                    case .connected:
                        self.ticketLiveStatus = "Live ticket stream connected for \(String(ticketId.prefix(8)))."
                    case .ticketLifecycle(let envelope):
                        guard envelope.metadata?.ticketId == ticketId else { continue }
                        self.importTicketLifecycleEnvelope(envelope, agent: agent, ticketId: ticketId)
                        self.scheduleTicketLiveContinuityRefresh(ticketId: ticketId)
                    case .keepalive:
                        break
                    case .error:
                        self.ticketLiveStatus = "Ticket stream paused; use refresh if status looks stale."
                    case .presence:
                        break
                    case .message:
                        break
                    }
                }
            } catch {
                if self.selectedAgent?.id == agent.id, self.activeTicketId == ticketId {
                    self.ticketLiveStatus = "Ticket stream unavailable; ORCA remains the source of truth."
                }
            }
            await manager.disconnect()
        }
    }

    private func stopAttachedTicketLifecycleStream() {
        ticketLiveTask?.cancel()
        ticketLiveTask = nil
        ticketLiveRefreshTask?.cancel()
        ticketLiveRefreshTask = nil
        ticketLiveTicketId = nil
        ticketLiveStatus = nil
        ticketLiveEventCount = 0
        ticketLiveLastEventAt = nil
        ticketLiveLastAction = nil
        Task { [manager = ticketSSEManager] in
            await manager?.disconnect()
        }
        ticketSSEManager = nil
    }

    private func scheduleTicketLiveContinuityRefresh(ticketId: String) {
        ticketLiveRefreshTask?.cancel()
        ticketLiveRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadAttachedTicketContinuity(ticketId: ticketId)
        }
    }

    private func importTicketLifecycleEnvelope(_ envelope: TicketLifecycleEnvelope, agent: AgentInfo, ticketId: String) {
        let action = envelope.metadata?.action?.replacingOccurrences(of: "_", with: " ") ?? envelope.type ?? "updated"
        let text = envelope.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageText = "ORCA ticket \(String(ticketId.prefix(8))) \(action)." + (text.map { "\n\($0)" } ?? "")
        let remoteId = envelope.id ?? Self.ticketLifecycleFallbackId(ticketId: ticketId, action: action, text: messageText)
        ticketLiveEventCount += 1
        ticketLiveLastEventAt = Date()
        ticketLiveLastAction = action
        ticketLiveStatus = "ORCA ticket \(String(ticketId.prefix(8))) \(action)."

        guard let ctx = modelContext,
              !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !hasImportedRemoteMessage(
                id: remoteId,
                content: messageText,
                timestamp: Date(),
                role: "assistant"
              ) else {
            return
        }

        let conversation = getOrCreateConversation(for: agent)
        let message = DMMessage(role: "assistant", content: messageText)
        message.source = "orca.tickets.sse"
        message.lane = "ticket_lifecycle"
        message.deliveryMode = DMDeliveryMode.ticket.rawValue
        message.provenance = DMResponseProvenance.ticket.rawValue
        message.deliveryState = DMDeliveryState.responseReceived.rawValue
        message.remoteMessageId = remoteId
        message.conversation = conversation
        ctx.insert(message)
        currentMessages.append(message)
        conversation.lastMessageText = messageText
        conversation.lastMessageDate = Date()
        try? ctx.save()
        loadConversations()
    }

    private static func ticketLifecycleFallbackId(ticketId: String, action: String, text: String) -> String {
        let raw = "\(ticketId)|\(action)|\(text)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "ticket-\(ticketId)-\(action.lowercased().replacingOccurrences(of: " ", with: "-"))-\(String(hash, radix: 16))"
    }

    private func ticketIntakeText() -> String {
        let draft = composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty { return draft }
        return currentMessages
            .last { $0.role == "user" && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func appendLocalAssistantMessage(_ text: String, for agent: AgentInfo) {
        appendLocalMessage(
            role: "assistant",
            content: text,
            for: agent,
            deliveryMode: .ticket,
            provenance: .ticket,
            lane: activeTicketId == nil ? "ticket_intake" : "ticket_comment"
        )
    }

    private func appendLocalUserMessage(_ text: String, for agent: AgentInfo) {
        appendLocalMessage(role: "user", content: text, for: agent)
    }

    private func appendLocalMessage(
        role: String,
        content: String,
        for agent: AgentInfo,
        deliveryMode: DMDeliveryMode? = nil,
        provenance: DMResponseProvenance? = nil,
        lane: String? = nil
    ) {
        guard let ctx = modelContext else { return }
        let conversation = getOrCreateConversation(for: agent)
        let message = DMMessage(role: role, content: content)
        message.source = deliveryMode == nil ? nil : "pod.chat"
        message.lane = lane
        message.deliveryMode = deliveryMode?.rawValue
        message.provenance = provenance?.rawValue
        message.conversation = conversation
        ctx.insert(message)
        conversation.lastMessageText = content
        conversation.lastMessageDate = Date()
        try? ctx.save()
        if selectedAgent?.id == agent.id {
            currentMessages.append(message)
        }
        loadConversations()
    }

    private func resolveORCAAgentId(for agent: AgentInfo) async -> String? {
        await resolveORCAAgentId(for: agent.id)
    }

    private func resolveORCAAgentId(for agentSlug: String) async -> String? {
        do {
            let response: PaginatedResponse<AgentDTO> = try await api.get(path: "/api/v1/agents")
            return response.items.first { $0.name.lowercased() == agentSlug.lowercased() }?.id
        } catch {
            return nil
        }
    }

    private static func isUnauthorized(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        return apiError.code == 401
    }

    private static func isNetworkOrHTTPFailure(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let apiError = error as? APIError else { return false }
        return apiError.code == 0 || apiError.code == 401 || apiError.code >= 500
    }

    private static func sendFailureReason(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError.code {
            case 401:
                return "authorization failed; sign in again"
            case 500...599:
                return "ORCA server returned \(apiError.code)"
            case 0:
                return apiError.message
            default:
                return "ORCA returned \(apiError.code): \(apiError.message)"
            }
        }
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        return error.localizedDescription
    }

    private static func localFallback(for agent: AgentInfo, userMessage: String, error: Error) -> String {
        let prefix = "Pod local guardrail fallback. This is not a live \(agent.name) reply and not a helper draft. Schoolhouse compute did not return a usable reply."
        switch agent.id {
        case "aloha":
            return "\(prefix)\n\nAloha path: this fallback is not Aloha and is not the live inbox. Switch the route to Live inbox handoff for the real Aloha lane, or use the ticket button to create an ORCA control record. Standards, memory promotion, archive decisions, and team routing still need ORCA evidence. Last compute error: \(error.localizedDescription)"
        case "maui":
            return "\(prefix)\n\nMaui path: create or update the ORCA ticket, keep the change small, verify it, then log meaningful system changes in the chronogram. Last compute error: \(error.localizedDescription)"
        case "chief":
            return "\(prefix)\n\nChief path: I cannot see live P&L, positions, orders, wallets, Chief memory, Chief Chroma, or trading runtime from Pod chat. I will not invent those numbers. Create an ORCA ticket for a Chief/Tony/Rooster-reviewed read-only inspection. Last compute error: \(error.localizedDescription)"
        case "rooster":
            return "\(prefix)\n\nRooster path: treat this as a security review item. Do not expose, rotate, or mutate secrets from chat; create a reviewed ORCA item instead. Last compute error: \(error.localizedDescription)"
        default:
            if agent.lane == .supportRuntime {
                return "\(prefix)\n\n\(agent.name) support-runtime path: Pod chat cannot inspect logs, restart daemons, read mirrors, or mutate runtime services from this fallback. Create or attach an ORCA ticket, keep it read-only until the owner gate is clear, and route execution through Agent Runs. Last compute error: \(error.localizedDescription)"
            }
            return "\(prefix)\n\nThis lane should be routed through an ORCA ticket before action. Last compute error: \(error.localizedDescription)"
        }
    }

    private static func initialRouteStatus(for agent: AgentInfo, deliveryMode: DMDeliveryMode) -> String {
        switch deliveryMode {
        case .liveInbox:
            return """
            Recorded in Pod and ORCA.
            Waiting for \(agent.name)'s live inbox reply. This is a delivery ack, not the agent's answer.
            """
        case .compute:
            return """
            Recorded in Pod.
            Requesting a helper draft for \(agent.name). This is not the live \(agent.name) runtime.
            """
        case .agentRun:
            return """
            Recorded in Pod and ORCA.
            Starting an ORCA Agent Run from the attached ticket. This is real work routing, not a chat persona reply.
            """
        case .auto:
            return """
            Recorded in Pod.
            Asking ORCA to choose live inbox, helper draft, ticket, or protected review for \(agent.name).
            """
        case .fallback:
            return "Using Pod local guardrail fallback only. This is not a live agent response."
        case .system:
            return "Recording system event."
        case .ticket:
            return "Preparing ORCA ticket evidence."
        }
    }

    private static func routeStatusBarText(for agent: AgentInfo, deliveryMode: DMDeliveryMode) -> String {
        switch deliveryMode {
        case .liveInbox:
            return "Recorded in ORCA. Waiting for \(agent.name)'s live inbox reply."
        case .compute:
            return "Recorded. Requesting a helper draft for \(agent.name)."
        case .agentRun:
            return "Recorded. Dispatching the attached ticket to Schoolhouse Agent Runs."
        case .auto:
            return "Recorded. ORCA is choosing compute, live inbox, ticket, or review."
        case .fallback:
            return "Using Pod local guardrail fallback only."
        case .system:
            return "Recording system event."
        case .ticket:
            return "Preparing ORCA ticket evidence."
        }
    }

    private static func deliveryState(forAgentRun status: AgentRunStatus) -> DMDeliveryState {
        switch status {
        case .queued, .waitingForHuman:
            return .agentRunQueued
        case .running, .retrying:
            return .agentRunRunning
        case .succeeded:
            return .responseReceived
        case .failed, .blocked, .cancelled:
            return .failed
        }
    }

    private static func agentRunStatusBarText(for agent: AgentInfo, dispatch: DirectChatAgentRunDispatch) -> String {
        let worker = dispatch.run.workerLane ?? agent.id
        switch dispatch.run.status {
        case .waitingForHuman:
            return "ORCA recorded the Agent Run for \(worker); execution is waiting for human approval."
        case .queued, .running, .retrying:
            return "ORCA recorded the Agent Run for \(worker). Watch the attached ticket for run events and evidence."
        case .succeeded:
            return "ORCA recorded Agent Run evidence for \(worker)."
        case .failed, .blocked, .cancelled:
            return "ORCA recorded the Agent Run, but it needs review: \(dispatch.run.status.label)."
        }
    }

    private static func agentRunAcceptedText(for agent: AgentInfo, dispatch: DirectChatAgentRunDispatch) -> String {
        let run = dispatch.run
        let worker = run.workerLane ?? agent.id
        let status = run.status.label
        let runId = String(run.id.prefix(8))
        let detail = run.outcome ?? run.evidence ?? dispatch.message
        return """
        ORCA Agent Run \(runId) recorded for \(worker).
        Status: \(status).

        \(detail)
        """
    }

    private static func liveInboxAckText(for agent: AgentInfo) -> String {
        """
        Sent to \(agent.name)'s inbox.
        Waiting for a live reply. This is the real-reply window, not a helper draft.
        """
    }

    private static func computeAcceptedText(for agent: AgentInfo, ack: String) -> String {
        let trimmedAck = ack.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = trimmedAck.isEmpty ? "" : "\n\nORCA ack: \(trimmedAck)"
        return """
        ORCA accepted the helper draft route for \(agent.name).
        This is a helper acknowledgement, not the final answer. I’ll append the result when it lands.\(suffix)
        """
    }

    private static func agentRunInstructionComment(
        intake: String,
        agent: AgentInfo,
        traceId: String,
        triagePreview: DirectChatTriagePreview?
    ) -> String {
        let triageBlock: String
        if let triagePreview {
            triageBlock = """

            ## Merman Route
            - Triage ID: \(triagePreview.id)
            - Intent: \(triagePreview.intentType)
            - Owner: \(triagePreview.suggestedOwner)
            - Worker: \(triagePreview.suggestedWorker ?? "none")
            - Delivery: \(triagePreview.deliveryMode)
            - Risk: \(triagePreview.riskLevel)
            - Approval required: \(triagePreview.needsApproval ? "yes" : "no")
            """
        } else {
            triageBlock = "\n\n## Merman Route\n- Preview unavailable; ORCA dispatch must enforce route policy."
        }
        return """
        ## Pod Chat Agent Run Request
        Tony requested an Agent Run from \(agent.name) chat.

        ## Instruction
        \(intake)

        ## Trace
        - Trace ID: \(traceId)\(triageBlock)
        """
    }

    private static func makeTraceId(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    private static func ticketTitle(from intake: String, agent: AgentInfo) -> String {
        let firstLine = intake
            .split(separator: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Pod chat follow-up"
        let trimmed = firstLine.count > 68 ? String(firstLine.prefix(65)) + "..." : firstLine
        return "\(agent.name): \(trimmed)"
    }

    private static func ticketDescription(from intake: String, agent: AgentInfo, triage: DirectChatMermanTriageDTO?, metadata: TicketCreationMetadata) -> String {
        """
        ## Request

        \(intake)

        ## Desired Outcome

        \(desiredOutcome(for: intake, agent: agent))

        ## Proposed Owner / Lane

        - Conversation target: \(agent.name) (`\(agent.id)`)
        - Owner: \(metadata.ownerSlug)
        - Merman triage id: \(triage?.triageId ?? "none")
        - Merman trace: \(triage?.traceId ?? "none")
        - Merman suggested worker: \(triage?.suggestedWorker ?? "none")
        - Merman recommended lane: \(metadata.recommendedLane)
        - Merman recommended runtime: \(triage?.recommendedRuntime ?? "unknown")
        - Merman recommended surface: \(triage?.recommendedSurface ?? "unknown")
        - Merman handoff subject: \(triage?.handoffSubject ?? "none")
        - Worker lane: \(metadata.workerLane)
        - Tool policy: \(metadata.toolPolicy)
        - Autonomy level: \(metadata.autonomyLevel)
        - Lane: \(agent.laneLabel)
        - Role: \(agent.role)
        - Routing note: \(metadata.routingNote)

        ## Merman Triage

        \(triageSummaryMarkdown(triage))

        ## Approval / Guardrail Check

        - Approval state: \(metadata.approvalState)
        \(metadata.guardrailNotes.map { "- \($0)" }.joined(separator: "\n"))

        ## Acceptance Criteria

        \(metadata.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n"))

        ## Done Means

        \(metadata.doneMeans)

        ## Ticket Metadata

        - ticket_type: \(metadata.ticketType)
        - compute_tag: \(metadata.computeTag)
        - owner: \(metadata.ownerSlug)
        - worker_lane: \(metadata.workerLane)
        - autonomy_level: \(metadata.autonomyLevel)
        - approval_state: \(metadata.approvalState)
        - tags: \(metadata.visibleTags.joined(separator: ", "))

        ## Source

        - Created from Pod direct chat with \(agent.name).
        - Source surface: Pod > Chat > Agents
        - Requestor: Tony / Captain

        ## Original Intake

        \(intake)
        """
    }

    private static func ticketComment(from intake: String, agent: AgentInfo, traceId: String) -> String {
        """
        Follow-up from Pod direct chat with \(agent.name).

        Trace: \(traceId)

        \(intake)
        """
    }

    private static func ticketPriority(for intake: String) -> String {
        let lowered = intake.lowercased()
        if lowered.contains("urgent") || lowered.contains("blocked") || lowered.contains("broken") || lowered.contains("security") {
            return "high"
        }
        return "medium"
    }

    private static func ticketType(for intake: String) -> String {
        let lowered = intake.lowercased()
        if lowered.contains("bug") || lowered.contains("broken") || lowered.contains("does not work") || lowered.contains("doesn't work") {
            return "bug"
        }
        return "support"
    }

    private static func ticketType(for intentType: String?, intake: String) -> String {
        switch intentType?.lowercased() {
        case "bug", "bugfix", "defect":
            return "bug"
        case "feature", "feature_request", "enhancement":
            return "feature"
        case "incident", "outage":
            return "incident"
        case "support", "question", "triage", "task", "routing":
            return "support"
        default:
            return ticketType(for: intake)
        }
    }

    private static func computeTag(for agent: AgentInfo, triage: DirectChatMermanTriageDTO? = nil) -> String {
        if let route = triage?.suggestedComputeRoute {
            switch route {
            case "financial": return "financial"
            case "security": return "security"
            case "spark": return "code"
            case "kimi": return agent.id == "aloha" ? "tony-facing" : "reasoning"
            default: break
            }
        }
        switch agent.id {
        case "maui": return "code"
        case "rooster": return "security"
        case "chief": return "financial"
        case "aloha": return "tony-facing"
        case "coral", "reef": return "reasoning"
        default: return "general"
        }
    }

    private static func ticketTags(for agent: AgentInfo, triage: DirectChatMermanTriageDTO?, metadata: TicketCreationMetadata) -> [String] {
        var values = ["pod", "chat", "triage", agent.id, "merman"]
        if let triage {
            values.append(contentsOf: triage.visibleTags ?? triage.tags)
        }
        values.append("owner:\(metadata.ownerSlug)")
        values.append("approval:\(metadata.approvalState)")
        values.append("autonomy:\(metadata.autonomyLevel)")
        values.append("worker:\(metadata.workerLane)")
        values.append("compute:\(metadata.computeTag)")
        if let triage {
            values.append("intent:\(triage.intentType)")
            values.append("risk:\(triage.riskLevel)")
            if let runtime = triage.recommendedRuntime {
                values.append("runtime:\(runtime)")
            }
            if let surface = triage.recommendedSurface {
                values.append("surface:\(surface)")
            }
        }
        var seen = Set<String>()
        return values
            .map(normalizeTag)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(12)
            .map { $0 }
    }

    private static func triageSummaryMarkdown(_ triage: DirectChatMermanTriageDTO?) -> String {
        guard let triage else {
            return "- Handler: Merman unavailable; Pod used local ticket defaults.\n- Next action: owner review required before dispatch."
        }
        return """
        - Handler: Merman
        - Triage id: \(triage.triageId ?? "none")
        - Trace: \(triage.traceId ?? "none")
        - Intent: \(triage.intentType)
        - Recommended lane: \(triage.recommendedLane)
        - Suggested owner: \(triage.suggestedOwner)
        - Suggested worker: \(triage.suggestedWorker ?? "none")
        - Risk: \(triage.riskLevel)
        - Needs ticket: \(triage.needsTicket ? "yes" : "no")
        - Needs approval: \(triage.needsApproval ? "yes" : "no")
        - Autonomy: \(triage.autonomyLevel)
        - Approval state: \(triage.approvalState ?? (triage.needsApproval ? "approval-required" : "owner-review"))
        - Worker lane: \(triage.workerLane ?? triage.suggestedWorker ?? "unspecified")
        - Recommended runtime: \(triage.recommendedRuntime ?? "unknown")
        - Recommended surface: \(triage.recommendedSurface ?? "unknown")
        - Runtime reason: \(triage.runtimeReason ?? "not provided")
        - Handoff subject: \(triage.handoffSubject ?? "none")
        - Delivery mode: \(triage.deliveryMode)
        - Compute route: \(triage.suggestedComputeRoute)
        - Next action: \(triage.nextAction)
        - Reason: \(triage.reason)
        """
    }

    private static func handoffPacket(for triage: DirectChatMermanTriageDTO?, agent: AgentInfo) -> [String: String] {
        [
            "surface": "pod_chat",
            "owner_agent": triage?.suggestedOwner ?? agent.id,
            "target_agent": agent.id,
            "triage_id": triage?.triageId ?? "",
            "triage_trace_id": triage?.traceId ?? "",
            "intent_type": triage?.intentType ?? "unknown",
            "recommended_lane": triage?.recommendedLane ?? agent.id,
            "worker_lane": triage?.workerLane ?? triage?.suggestedWorker ?? "",
            "recommended_runtime": triage?.recommendedRuntime ?? "unknown",
            "recommended_surface": triage?.recommendedSurface ?? "pod_chat",
            "runtime_reason": triage?.runtimeReason ?? "",
            "handoff_subject": triage?.handoffSubject ?? "",
            "delivery_mode": triage?.deliveryMode ?? "auto",
            "compute_route": triage?.suggestedComputeRoute ?? "auto",
            "next_action": triage?.nextAction ?? "answer_or_clarify",
        ].filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func createdTicketMessage(ticket: DirectChatTicketDTO, triage: DirectChatMermanTriageDTO?) -> String {
        if let triage {
            return """
            Created ORCA ticket \(ticket.id): \(ticket.title)

            Merman routed this as \(triage.intentType) to \(triage.suggestedOwner), worker \(triage.suggestedWorker ?? "none"), autonomy \(triage.autonomyLevel).
            Runtime path: \(triage.recommendedRuntime ?? "unknown") via \(triage.recommendedSurface ?? "unknown").
            ORCA is the control record from here.
            """
        }
        return "Created ORCA ticket \(ticket.id): \(ticket.title)\n\nMerman was unavailable, so Pod used local routing defaults. ORCA is the control record from here."
    }

    private static func createdTicketMessage(ticket: DirectChatTicketDTO, draft: DirectChatTicketDraft) -> String {
        """
        Created ORCA ticket \(ticket.id): \(ticket.title)

        Owner: \(draft.ownerSlug)
        Worker: \(draft.workerLane)
        Autonomy: \(draft.autonomyLevel)
        ORCA is the control record from here.
        """
    }

    private static func desiredOutcome(for intake: String, agent: AgentInfo) -> String {
        let lowered = intake.lowercased()
        if lowered.contains("pod") || lowered.contains("chat") || lowered.contains("app") {
            return "Pod reflects real ORCA/Schoolhouse state and Tony can verify the behavior directly."
        }
        if lowered.contains("memory") || lowered.contains("daily") || lowered.contains("guardrail") {
            return "The memory/guardrail rule is documented, reviewable, and linked back to ORCA."
        }
        if agent.id == "chief" || lowered.contains("fund") || lowered.contains("trading") {
            return "The Fund/Chief question is captured for review without mutating protected trading systems."
        }
        if agent.id == "rooster" || lowered.contains("security") || lowered.contains("token") || lowered.contains("auth") {
            return "The security concern is reviewed with no secrets exposed or changed from chat."
        }
        return "The request is triaged into a clear next action with owner, priority, approvals, and evidence path."
    }

    private static func routingNote(for intake: String, agent: AgentInfo) -> String {
        let lowered = intake.lowercased()
        if lowered.contains("watchdog") || lowered.contains("daemon") || lowered.contains("launchagent") || lowered.contains("compute observability") {
            return "Support-runtime candidate. Route to Coral/Reef only if the work is explicitly watchdog, daemon, runtime, mirror, observability, or surfaces plumbing."
        }
        switch agent.id {
        case "aloha":
            return "Aloha should triage, clarify standards/memory/process, and route execution through ORCA."
        case "maui":
            return "Maui should own implementation if this is Pod, ORCA backend, compute integration, or engineering execution."
        case "chief":
            return "Chief lane only. Keep read-only until Chief/Tony/Rooster approve any Fund runtime change."
        case "rooster":
            return "Rooster should review security, auth, credentials, or protected Chief Mac guardrails."
        default:
            return "Default main-lane routing applies unless Aloha reassigns."
        }
    }

    private static func approvalCheck(for intake: String, agent: AgentInfo) -> String {
        let lowered = intake.lowercased()
        var gates: [String] = []
        if agent.id == "chief" || lowered.contains("fund") || lowered.contains("trading") || lowered.contains("position") || lowered.contains("wallet") {
            gates.append("Chief/Fund gate: Chief plus Tony/Rooster review before mutation.")
        }
        if agent.id == "rooster" || lowered.contains("security") || lowered.contains("token") || lowered.contains("credential") || lowered.contains("auth") || lowered.contains("key") {
            gates.append("Security gate: Rooster/Tony review before exposing, rotating, or changing credentials/access.")
        }
        if lowered.contains("archive") || lowered.contains("delete") || lowered.contains("remove agent") || lowered.contains("identity") || lowered.contains("soul") {
            gates.append("Agent identity/memory gate: Tony/Aloha review before identity, Soul, durable memory, or archive changes.")
        }
        if gates.isEmpty {
            return "- No protected-domain approval detected from intake.\n- Owner should still confirm scope before execution."
        }
        return gates.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func ticketCreationMetadata(for intake: String, agent: AgentInfo, triage: DirectChatMermanTriageDTO?) -> TicketCreationMetadata {
        let computeTag = computeTag(for: agent, triage: triage)
        let ownerSlug = normalizeAgentSlug(triage?.suggestedOwner) ?? agent.id
        let approvalState = normalizedMetadataValue(triage?.approvalState)
            ?? (triage?.needsApproval == true ? "approval-required" : "owner-review")
        let workerLane = normalizedMetadataValue(triage?.workerLane)
            ?? inferredWorkerLane(computeTag: computeTag, intake: intake, agent: agent)
        let toolPolicy = toolPolicy(for: workerLane)
        let guardrailNotes = guardrailNotes(for: intake, agent: agent, triage: triage, approvalState: approvalState)
        let acceptanceCriteria = acceptanceCriteria(for: intake, agent: agent, triage: triage, metadataOwner: ownerSlug)
        let doneMeans = doneMeans(for: triage, approvalState: approvalState)
        let autonomyLevel = normalizedMetadataValue(triage?.autonomyLevel) ?? "inspect_only"
        let ticketType = ticketType(for: triage?.intentType, intake: intake)
        let recommendedLane = triage?.recommendedLane ?? agent.id
        let routingNote = triage?.reason ?? routingNote(for: intake, agent: agent)

        var metadata = TicketCreationMetadata(
            ownerSlug: ownerSlug,
            recommendedLane: recommendedLane,
            workerLane: workerLane,
            toolPolicy: toolPolicy,
            approvalState: approvalState,
            autonomyLevel: autonomyLevel,
            computeTag: computeTag,
            ticketType: ticketType,
            routingNote: routingNote,
            guardrailNotes: guardrailNotes,
            acceptanceCriteria: acceptanceCriteria,
            doneMeans: doneMeans,
            visibleTags: []
        )
        metadata.visibleTags = ticketTags(for: agent, triage: triage, metadata: metadata)
        return metadata
    }

    private static func guardrailNotes(for intake: String, agent: AgentInfo, triage: DirectChatMermanTriageDTO?, approvalState: String) -> [String] {
        var notes: [String] = []
        if let triageNotes = triage?.guardrailNotes, !triageNotes.isEmpty {
            notes.append(contentsOf: triageNotes)
        } else if let approvalGate = triage?.approvalGate, !approvalGate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.append(approvalGate)
        } else {
            notes.append(contentsOf: approvalCheck(for: intake, agent: agent)
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "- ")) }
                .filter { !$0.isEmpty })
        }
        if approvalState == "approval-required" {
            notes.append("Execution stays read-only until the approval is recorded in ORCA.")
        }
        return deduplicated(notes)
    }

    private static func acceptanceCriteria(for intake: String, agent: AgentInfo, triage: DirectChatMermanTriageDTO?, metadataOwner: String) -> [String] {
        if let criteria = triage?.acceptanceCriteria, !criteria.isEmpty {
            return deduplicated(criteria)
        }
        return [
            "ORCA captures the intake, owner, worker lane, autonomy level, and approval state.",
            "\(metadataOwner) confirms or adjusts priority, scope, and lane before execution.",
            "Protected-domain work records approval before mutation.",
            "Evidence, verification notes, or follow-up comments are attached before closure."
        ]
    }

    private static func doneMeans(for triage: DirectChatMermanTriageDTO?, approvalState: String) -> String {
        if let doneMeans = triage?.doneMeans?.trimmingCharacters(in: .whitespacesAndNewlines), !doneMeans.isEmpty {
            return doneMeans
        }
        if approvalState == "approval-required" {
            return "Done means the requester can verify the outcome, ORCA has evidence or resolution notes, and any protected mutation has an explicit approval record."
        }
        return "Done means the requester can verify the outcome and ORCA has evidence or resolution notes."
    }

    private static func inferredWorkerLane(computeTag: String, intake: String, agent: AgentInfo) -> String {
        let haystack = "\(agent.id) \(intake)".lowercased()
        if computeTag == "financial" || haystack.contains("chief") || haystack.contains("fund") || haystack.contains("trading") {
            return "protected-chief-review"
        }
        if computeTag == "security" || haystack.contains("credential") || haystack.contains("token") || haystack.contains("secret") {
            return "protected-rooster-review"
        }
        return "mermaid"
    }

    private static func toolPolicy(for workerLane: String) -> String {
        switch workerLane {
        case "protected-chief-review":
            return "read_only_until_chief_tony_rooster_approval"
        case "protected-rooster-review":
            return "read_only_until_rooster_tony_approval"
        default:
            return "bounded_workspace_edits_owner_review"
        }
    }

    private static func normalizeAgentSlug(_ value: String?) -> String? {
        guard let normalized = normalizedMetadataValue(value) else { return nil }
        let allowed = Set(AgentInfo.team.map(\.id))
        return allowed.contains(normalized) ? normalized : nil
    }

    private static func normalizeTag(_ value: String) -> String {
        (normalizedMetadataValue(value) ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#,.;:"))
    }

    private static func normalizedMetadataValue(_ value: String?) -> String? {
        let normalized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
        return normalized.isEmpty ? nil : normalized
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static func memoryCandidateBody(continuity: DirectChatTicketContinuity, traceId: String) -> String {
        let latestRun = continuity.latestRun
        return """
        ## Source
        Pod chat attached ticket \(continuity.ticket.id): \(continuity.ticket.title)

        ## Candidate Memory
        \(continuity.nextActionLabel)

        ## Evidence
        - Status: \(continuity.statusLabel)
        - Priority: \(continuity.priorityLabel)
        - Evidence: \(continuity.evidenceLabel)
        - Latest run: \(continuity.latestRunLabel)
        - Trace: \(traceId)

        ## Latest Run Detail
        - Run: \(latestRun?.id ?? "none")
        - Worker: \(latestRun?.workerLane ?? "none")
        - Tool policy: \(latestRun?.toolPolicy ?? "none")
        - Outcome: \(latestRun?.outcome ?? "none")
        - Error: \(latestRun?.error ?? "none")

        ## Review
        Keep as candidate until Aloha/Maui reviews source, scope, and duplication.
        """
    }

    private static func workspaceArtifactBody(
        continuity: DirectChatTicketContinuity,
        messages: [DMMessage],
        composedMessage: String,
        traceId: String
    ) -> String {
        let recentMessages = messages.suffix(12).map { message in
            "- \(message.role): \(message.content)"
        }.joined(separator: "\n")
        let draft = composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        # Pod Chat Workspace Artifact

        - Ticket: \(continuity.ticket.title)
        - Ticket ID: \(continuity.ticket.id)
        - Trace: \(traceId)
        - Latest run: \(continuity.latestRun?.id ?? "none")
        - Route: \(continuity.routePacketLabel ?? "none")
        - Approval: \(continuity.approvalLabel ?? "none")

        ## Current Draft

        \(draft.isEmpty ? "No unsent draft in compose." : draft)

        ## Recent Chat

        \(recentMessages.isEmpty ? "No recent chat messages." : recentMessages)

        ## Ticket Summary

        \(continuity.summary?.latestActivity ?? continuity.nextActionLabel)
        """
    }

    private static func slugForFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = value.lowercased().map { character -> Character in
            let scalarText = String(character)
            return scalarText.unicodeScalars.allSatisfy { allowed.contains($0) } ? character : "-"
        }
        let slug = String(mapped)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return slug.isEmpty ? "ticket" : String(slug.prefix(60))
    }

    private static func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
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

struct DirectChatTicketDraft: Identifiable, Sendable, Hashable {
    let id = UUID()
    let title: String
    let description: String
    let priority: String
    let ownerSlug: String
    let assigneeAgentId: String?
    let ticketType: String
    let tags: [String]
    let computeTag: String
    let approvalState: String
    let approvalGate: String?
    let autonomyLevel: String
    let workerLane: String
    let toolPolicy: String
    let acceptanceCriteria: [String]
    let desiredOutcome: String
    let intake: String
    let agentId: String
    let agentName: String
    let triageId: String?
    let triageTraceId: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let handoffPacket: [String: String]
    let triageSummary: String
    let shouldAppendSubmittedDraft: Bool

    func withEdits(
        title: String,
        description: String,
        priority: String,
        ticketType: String,
        tags: [String],
        computeTag: String,
        approvalState: String,
        autonomyLevel: String,
        workerLane: String,
        toolPolicy: String,
        desiredOutcome: String,
        acceptanceCriteria: [String]
    ) -> DirectChatTicketDraft {
        DirectChatTicketDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            ownerSlug: ownerSlug,
            assigneeAgentId: assigneeAgentId,
            ticketType: ticketType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            tags: tags.isEmpty ? self.tags : tags,
            computeTag: computeTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            approvalState: approvalState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            approvalGate: approvalGate,
            autonomyLevel: autonomyLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            workerLane: workerLane.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            toolPolicy: toolPolicy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            acceptanceCriteria: acceptanceCriteria.isEmpty ? self.acceptanceCriteria : acceptanceCriteria,
            desiredOutcome: desiredOutcome.trimmingCharacters(in: .whitespacesAndNewlines),
            intake: intake,
            agentId: agentId,
            agentName: agentName,
            triageId: triageId,
            triageTraceId: triageTraceId,
            recommendedRuntime: recommendedRuntime,
            recommendedSurface: recommendedSurface,
            runtimeReason: runtimeReason,
            handoffSubject: handoffSubject,
            handoffPacket: handoffPacket,
            triageSummary: triageSummary,
            shouldAppendSubmittedDraft: shouldAppendSubmittedDraft
        )
    }
}

private struct TicketCreationMetadata {
    let ownerSlug: String
    let recommendedLane: String
    let workerLane: String
    let toolPolicy: String
    let approvalState: String
    let autonomyLevel: String
    let computeTag: String
    let ticketType: String
    let routingNote: String
    let guardrailNotes: [String]
    let acceptanceCriteria: [String]
    let doneMeans: String
    var visibleTags: [String]
}

private struct DirectChatCreateTicketBody: Encodable {
    let title: String
    let description: String
    let priority: String
    let assigneeAgentId: String?
    let chatThreadId: String?
    let status = "open"
    let source = "pod_chat"
    let ticketType: String
    let tags: [String]
    let computeTag: String
    let approvalState: String
    let approvalGate: String?
    let autonomyLevel: String
    let workerLane: String
    let toolPolicy: String
    let acceptanceCriteria: [String]
    let desiredOutcome: String
    let triageId: String?
    let triageTraceId: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let handoffPacket: [String: String]

    enum CodingKeys: String, CodingKey {
        case title, description, priority, status, source, tags
        case assigneeAgentId = "assignee_agent_id"
        case chatThreadId = "chat_thread_id"
        case ticketType = "ticket_type"
        case computeTag = "compute_tag"
        case approvalState = "approval_state"
        case approvalGate = "approval_gate"
        case autonomyLevel = "autonomy_level"
        case workerLane = "worker_lane"
        case toolPolicy = "tool_policy"
        case acceptanceCriteria = "acceptance_criteria"
        case desiredOutcome = "desired_outcome"
        case triageId = "triage_id"
        case triageTraceId = "triage_trace_id"
        case recommendedRuntime = "recommended_runtime"
        case recommendedSurface = "recommended_surface"
        case runtimeReason = "runtime_reason"
        case handoffSubject = "handoff_subject"
        case handoffPacket = "handoff_packet"
    }
}

private struct DirectChatPatchTicketBody: Encodable {
    let chatThreadId: String

    enum CodingKeys: String, CodingKey {
        case chatThreadId = "chat_thread_id"
    }
}

private struct DirectChatEmptyRequestBody: Encodable {}

private struct DirectChatAgentRunDispatch: Sendable, Hashable {
    let run: AgentRun
    let commentId: String?
    let message: String
}

private struct DirectChatAgentRunDispatchDTO: Decodable {
    let run: AgentRunDTO
    let commentId: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case run, message
        case commentId = "comment_id"
    }

    func toDomain() -> DirectChatAgentRunDispatch {
        DirectChatAgentRunDispatch(
            run: run.toDomain(),
            commentId: commentId,
            message: message
        )
    }
}

struct DirectChatApprovalRecord: Identifiable, Sendable, Hashable {
    let id: String
    let ticketId: String
    let actionType: String
    let status: String
    let reason: String?
    let source: String?
    let lane: String?
    let traceId: String?
    let createdAt: Date
    let resolvedAt: Date?

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct DirectChatWorkspaceContext: Sendable, Hashable {
    let workspaceId: String
    let ticketId: String
    let ticketTitle: String
    let mode: String
    let storagePolicy: String
    let allowedRoots: [String]
    let files: [DirectChatWorkspaceFile]
    let toolRequests: [DirectChatWorkspaceToolRequest]
    let gaps: [String]
    let capabilities: [String: Bool]
}

struct DirectChatWorkspaceFile: Identifiable, Sendable, Hashable {
    let key: String
    let path: String
    let kind: String
    let exists: Bool?
    let sizeBytes: Int?
    let safeToPreview: Bool
    let preview: String?
    let reason: String?

    var id: String { "\(path)#\(key)" }

    var displayName: String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }
}

struct DirectChatWorkspaceToolRequest: Identifiable, Sendable, Hashable {
    let runId: String
    let status: String
    let toolName: String
    let instructionPreview: String
    let reason: String?
    let createdAt: Date

    var id: String { runId }
}

private struct DirectChatWorkspaceContextDTO: Decodable {
    let workspaceId: String
    let ticketId: String
    let ticketTitle: String
    let mode: String
    let storagePolicy: String
    let allowedRoots: [String]
    let files: [DirectChatWorkspaceFileDTO]
    let toolRequests: [DirectChatWorkspaceToolRequestSummaryDTO]
    let gaps: [String]
    let capabilities: [String: Bool]

    enum CodingKeys: String, CodingKey {
        case mode, files, gaps, capabilities
        case workspaceId = "workspace_id"
        case ticketId = "ticket_id"
        case ticketTitle = "ticket_title"
        case storagePolicy = "storage_policy"
        case allowedRoots = "allowed_roots"
        case toolRequests = "tool_requests"
    }

    func toDomain() -> DirectChatWorkspaceContext {
        DirectChatWorkspaceContext(
            workspaceId: workspaceId,
            ticketId: ticketId,
            ticketTitle: ticketTitle,
            mode: mode,
            storagePolicy: storagePolicy,
            allowedRoots: allowedRoots,
            files: files.map { $0.toDomain() },
            toolRequests: toolRequests.map { $0.toDomain() },
            gaps: gaps,
            capabilities: capabilities
        )
    }
}

private struct DirectChatWorkspaceToolRequestSummaryDTO: Decodable {
    let runId: String
    let status: String
    let toolName: String
    let instructionPreview: String
    let reason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case status, reason
        case runId = "run_id"
        case toolName = "tool_name"
        case instructionPreview = "instruction_preview"
        case createdAt = "created_at"
    }

    func toDomain() -> DirectChatWorkspaceToolRequest {
        DirectChatWorkspaceToolRequest(
            runId: runId,
            status: status,
            toolName: toolName,
            instructionPreview: instructionPreview,
            reason: reason,
            createdAt: createdAt
        )
    }
}

private struct DirectChatWorkspaceFileDTO: Decodable {
    let key: String
    let path: String
    let kind: String
    let exists: Bool?
    let sizeBytes: Int?
    let safeToPreview: Bool
    let preview: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case key, path, kind, exists, preview, reason
        case sizeBytes = "size_bytes"
        case safeToPreview = "safe_to_preview"
    }

    func toDomain() -> DirectChatWorkspaceFile {
        DirectChatWorkspaceFile(
            key: key,
            path: path,
            kind: kind,
            exists: exists,
            sizeBytes: sizeBytes,
            safeToPreview: safeToPreview,
            preview: preview,
            reason: reason
        )
    }
}

private struct DirectChatWorkspaceFileWriteRequest: Encodable {
    let filename: String
    let content: String
    let description: String?
    let runId: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case filename, content, description, source
        case runId = "run_id"
    }
}

private struct DirectChatWorkspaceFileWriteDTO: Decodable {
    let ok: Bool
    let file: DirectChatWorkspaceFileDTO
    let runId: String
    let checksum: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok, file, checksum, message
        case runId = "run_id"
    }
}

private struct DirectChatWorkspaceToolRequestBody: Encodable {
    let toolName: String
    let instruction: String
    let reason: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case instruction, reason, source
        case toolName = "tool_name"
    }
}

private struct DirectChatWorkspaceToolRequestCreateDTO: Decodable {
    let ok: Bool
    let runId: String
    let status: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok, status, message
        case runId = "run_id"
    }
}

private struct DirectChatWorkspaceToolExecuteBody: Encodable {
    let approvalNote: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case source
        case approvalNote = "approval_note"
    }
}

private struct DirectChatWorkspaceToolExecuteDTO: Decodable {
    let ok: Bool
    let runId: String
    let status: String
    let file: DirectChatWorkspaceFileDTO
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok, status, file, message
        case runId = "run_id"
    }
}

private struct SonarMemoryCandidateCreateBody: Encodable {
    let candidateId: String
    let sourceType: String
    let sourceRef: String
    let sourceAgent: String?
    let textOriginal: String
    let textProposed: String?
    let sensitivityClass: String
    let reviewersRequired: [String]
    let target: [String: String]
    let provenance: [String: String]
    let createdBy: String

    enum CodingKeys: String, CodingKey {
        case candidateId = "candidate_id"
        case sourceType = "source_type"
        case sourceRef = "source_ref"
        case sourceAgent = "source_agent"
        case textOriginal = "text_original"
        case textProposed = "text_proposed"
        case sensitivityClass = "sensitivity_class"
        case reviewersRequired = "reviewers_required"
        case target
        case provenance
        case createdBy = "created_by"
    }
}

private struct SonarMemoryCandidateDTO: Decodable {
    let id: String
    let candidateId: String
    let lifecycle: String

    enum CodingKeys: String, CodingKey {
        case id, lifecycle
        case candidateId = "candidate_id"
    }
}

private struct DirectChatApprovalRequestBody: Encodable {
    let reason: String
    let traceId: String?
    let source: String
    let lane: String

    enum CodingKeys: String, CodingKey {
        case reason, source, lane
        case traceId = "trace_id"
    }
}

private struct DirectChatApprovalResolutionBody: Encodable {
    let status: String
    let reason: String?
    let traceId: String?
    let source: String
    let lane: String

    enum CodingKeys: String, CodingKey {
        case status, reason, source, lane
        case traceId = "trace_id"
    }
}

private struct DirectChatApprovalDTO: Decodable {
    let approvalId: String
    let ticketId: String
    let actionType: String
    let status: String
    let payload: [String: AgentRunJSONValue]?
    let createdAt: Date
    let resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status, payload
        case approvalId = "approval_id"
        case ticketId = "ticket_id"
        case actionType = "action_type"
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }

    func toDomain() -> DirectChatApprovalRecord {
        DirectChatApprovalRecord(
            id: approvalId,
            ticketId: ticketId,
            actionType: actionType,
            status: status,
            reason: payload?["reason"]?.displayValue,
            source: payload?["source"]?.displayValue,
            lane: payload?["lane"]?.displayValue,
            traceId: payload?["trace_id"]?.displayValue,
            createdAt: createdAt,
            resolvedAt: resolvedAt
        )
    }
}

private struct DirectChatNoteCreateRequest: Encodable {
    let targetType: String
    let targetId: String?
    let noteType: String
    let title: String
    let body: String
    let tags: [String]
    let source: String
    let traceId: String
    let signState: String

    enum CodingKeys: String, CodingKey {
        case title, body, tags, source
        case targetType = "target_type"
        case targetId = "target_id"
        case noteType = "note_type"
        case traceId = "trace_id"
        case signState = "sign_state"
    }
}

private struct DirectChatTicketDTO: Decodable {
    let id: String
    let title: String
}

struct DirectChatAttachableTicket: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let workerLane: String?
    let approvalState: String?
    let updatedAt: Date
}

private struct DirectChatAttachableTicketDTO: Decodable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let workerLane: String?
    let approvalState: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, status, priority
        case workerLane = "worker_lane"
        case approvalState = "approval_state"
        case updatedAt = "updated_at"
    }

    func toAttachableTicket() -> DirectChatAttachableTicket {
        DirectChatAttachableTicket(
            id: id,
            title: title,
            status: status,
            priority: priority,
            workerLane: workerLane,
            approvalState: approvalState,
            updatedAt: updatedAt
        )
    }
}

private struct DirectChatTicketCommentBody: Encodable {
    let message: String
    let traceId: String?
    let source: String?
    let lane: String?

    enum CodingKeys: String, CodingKey {
        case message, source, lane
        case traceId = "trace_id"
    }
}

private struct DirectChatTicketCommentDTO: Decodable {
    let id: String
}

private struct DirectChatHistoryMessageBody: Encodable {
    let role: String
    let content: String
}

private struct DirectChatFallbackRequestBody: Encodable {
    let channelId: String
    let userMessageId: String
    let content: String
    let history: [DirectChatHistoryMessageBody]
    let traceId: String
    let triageId: String?
    let triageTraceId: String?
    let activeTicketId: String?
    let fallbackReason: String
    let fallbackAfterSeconds: Int

    enum CodingKeys: String, CodingKey {
        case content, history
        case channelId = "channel_id"
        case userMessageId = "user_message_id"
        case traceId = "trace_id"
        case triageId = "triage_id"
        case triageTraceId = "triage_trace_id"
        case activeTicketId = "active_ticket_id"
        case fallbackReason = "fallback_reason"
        case fallbackAfterSeconds = "fallback_after_seconds"
    }
}

private struct DirectChatFallbackResponseDTO: Decodable {
    let channelId: String
    let userMessageId: String
    let assistantMessageId: String
    let content: String
    let metadata: DirectChatFallbackMetadataDTO

    enum CodingKeys: String, CodingKey {
        case content, metadata
        case channelId = "channel_id"
        case userMessageId = "user_message_id"
        case assistantMessageId = "assistant_message_id"
    }
}

private struct DirectChatFallbackMetadataDTO: Decodable {
    let model: String?
    let backend: String?
    let tier: String?
    let tokenCount: Int?
    let traceId: String
    let source: String
    let lane: String
    let deliveryMode: String?
    let provenance: String?
    let responseState: String?
    let triageId: String?
    let triageTraceId: String?
    let computeRunId: String?

    enum CodingKeys: String, CodingKey {
        case model, backend, tier, source, lane, provenance
        case tokenCount = "token_count"
        case traceId = "trace_id"
        case deliveryMode = "delivery_mode"
        case responseState = "response_state"
        case triageId = "triage_id"
        case triageTraceId = "triage_trace_id"
        case computeRunId = "compute_run_id"
    }

    var displayName: String? {
        let route = tier ?? backend
        switch (route?.isEmpty == false ? route : nil, model?.isEmpty == false ? model : nil) {
        case let (route?, model?):
            return "\(route) · \(model)"
        case let (route?, nil):
            return route
        case let (nil, model?):
            return model
        default:
            return nil
        }
    }

    var normalizedProvenance: String {
        if let backend,
           ["spark", "kimi", "openclaw"].contains(backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return DMResponseProvenance.compute.rawValue
        }
        return provenance ?? DMResponseProvenance.compute.rawValue
    }
}

struct DirectChatORCAMessageDTO: Decodable {
    let id: String
    let senderUserId: String?
    let senderAgentId: String?
    let senderName: String?
    let senderType: String?
    let senderEmoji: String?
    let content: String
    let messageType: String
    let traceId: String?
    let source: String?
    let lane: String?
    let deliveryMode: String?
    let provenance: String?
    let responseState: String?
    let deliveryState: String?
    let deliveryError: String?
    let deliveryFailedHop: String?
    let deliveryEvidence: String?
    let triageId: String?
    let triageTraceId: String?
    let provider: String?
    let model: String?
    let surfaceEventProvenance: String?
    let replyToId: String?
    let isThreadReply: Bool
    let fileAttachment: ChatFileAttachment?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content, source, lane, provenance, provider, model, metadata
        case senderUserId = "sender_user_id"
        case senderAgentId = "sender_agent_id"
        case senderName = "sender_name"
        case senderType = "sender_type"
        case senderEmoji = "sender_emoji"
        case messageType = "message_type"
        case traceId = "trace_id"
        case deliveryMode = "delivery_mode"
        case responseState = "response_state"
        case deliveryState = "delivery_state"
        case deliveryError = "delivery_error"
        case deliveryFailedHop = "delivery_failed_hop"
        case failedHop = "failed_hop"
        case deliveryEvidence = "delivery_evidence"
        case evidence
        case triageId = "triage_id"
        case triageTraceId = "triage_trace_id"
        case surfaceEventProvenance = "surface_event_provenance"
        case replyToId = "reply_to_id"
        case isThreadReply = "is_thread_reply"
        case createdAt = "created_at"
    }

    private struct Metadata: Decodable {
        let file: String?
        let deliveryError: String?
        let deliveryFailedHop: String?
        let failedHop: String?
        let deliveryEvidence: String?
        let evidence: String?

        enum CodingKeys: String, CodingKey {
            case file
            case deliveryError = "delivery_error"
            case deliveryFailedHop = "delivery_failed_hop"
            case failedHop = "failed_hop"
            case deliveryEvidence = "delivery_evidence"
            case evidence
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        senderUserId = try container.decodeIfPresent(String.self, forKey: .senderUserId)
        senderAgentId = try container.decodeIfPresent(String.self, forKey: .senderAgentId)
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
        senderType = try container.decodeIfPresent(String.self, forKey: .senderType)
        senderEmoji = try container.decodeIfPresent(String.self, forKey: .senderEmoji)
        content = try container.decode(String.self, forKey: .content)
        messageType = try container.decodeIfPresent(String.self, forKey: .messageType) ?? "text"
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        lane = try container.decodeIfPresent(String.self, forKey: .lane)
        deliveryMode = try container.decodeIfPresent(String.self, forKey: .deliveryMode)
        provenance = try container.decodeIfPresent(String.self, forKey: .provenance)
        responseState = try container.decodeIfPresent(String.self, forKey: .responseState)
        deliveryState = try container.decodeIfPresent(String.self, forKey: .deliveryState)
        triageId = try container.decodeIfPresent(String.self, forKey: .triageId)
        triageTraceId = try container.decodeIfPresent(String.self, forKey: .triageTraceId)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        surfaceEventProvenance = try container.decodeIfPresent(String.self, forKey: .surfaceEventProvenance)
        replyToId = try container.decodeIfPresent(String.self, forKey: .replyToId)
        isThreadReply = try container.decodeIfPresent(Bool.self, forKey: .isThreadReply) ?? false
        let metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata)
        deliveryError = (try? container.decodeIfPresent(String.self, forKey: .deliveryError))
            ?? metadata?.deliveryError
        deliveryFailedHop = (try? container.decodeIfPresent(String.self, forKey: .deliveryFailedHop))
            ?? (try? container.decodeIfPresent(String.self, forKey: .failedHop))
            ?? metadata?.deliveryFailedHop
            ?? metadata?.failedHop
        deliveryEvidence = (try? container.decodeIfPresent(String.self, forKey: .deliveryEvidence))
            ?? (try? container.decodeIfPresent(String.self, forKey: .evidence))
            ?? metadata?.deliveryEvidence
            ?? metadata?.evidence
        fileAttachment = ChatFileAttachment(path: metadata?.file)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var computeProvider: String? {
        let normalized = provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard ["spark", "kimi", "openclaw"].contains(normalized) else { return nil }
        return normalized
    }

    var normalizedProvenance: String? {
        if computeProvider != nil { return DMResponseProvenance.compute.rawValue }
        if let surfaceEventProvenance, !surfaceEventProvenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return surfaceEventProvenance
        }
        return provenance
    }

    var computeAttributionLabel: String? {
        guard let computeProvider else { return nil }
        let providerLabel = computeProvider.capitalized
        let cleanModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanModel, !cleanModel.isEmpty {
            return "\(providerLabel) · \(cleanModel)"
        }
        return providerLabel
    }
}

struct AgentPresence: Hashable, Sendable {
    enum State: String, Hashable, Sendable {
        case active
        case idle
        case offline

        init(agentState: AgentState) {
            switch agentState {
            case .online, .busy:
                self = .active
            case .idle:
                self = .idle
            case .offline, .error, .provisioning:
                self = .offline
            }
        }

        var label: String {
            switch self {
            case .active: return "Active"
            case .idle: return "Idle"
            case .offline: return "Offline"
            }
        }

        var color: Color {
            switch self {
            case .active: return AppColors.accentSuccess
            case .idle: return AppColors.accentWarning
            case .offline: return AppColors.textTertiary
            }
        }
    }

    let agentId: String
    var state: State
    var isWorking: Bool
    let lastSeen: Date?
}

private struct SonarPresenceResponseDTO: Decodable {
    let presences: [AgentPresence]

    struct PresenceDTO: Decodable {
        let agentId: String
        let state: String
        let working: Bool
        let lastSeen: Date?

        enum CodingKeys: String, CodingKey {
            case agentId = "agent_id"
            case agent
            case name
            case state
            case working
            case isWorking = "is_working"
            case lastSeen = "last_seen"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
                ?? container.decodeIfPresent(String.self, forKey: .agent)
                ?? container.decodeIfPresent(String.self, forKey: .name)
                ?? ""
            state = try container.decodeIfPresent(String.self, forKey: .state) ?? "offline"
            working = try container.decodeIfPresent(Bool.self, forKey: .working)
                ?? container.decodeIfPresent(Bool.self, forKey: .isWorking)
                ?? false
            lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen)
        }

        func domain(agentIdOverride: String? = nil) -> AgentPresence? {
            let id = (agentIdOverride ?? agentId).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            return AgentPresence(
                agentId: id,
                state: AgentPresence.State(rawValue: state.lowercased()) ?? .offline,
                isWorking: working,
                lastSeen: lastSeen
            )
        }
    }

    struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        if let array = try? [PresenceDTO](from: decoder) {
            presences = array.compactMap { $0.domain() }
            return
        }

        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if let key = DynamicCodingKey(stringValue: "agents"),
           let array = try? container.decode([PresenceDTO].self, forKey: key) {
            presences = array.compactMap { $0.domain() }
            return
        }
        if let key = DynamicCodingKey(stringValue: "presence"),
           let array = try? container.decode([PresenceDTO].self, forKey: key) {
            presences = array.compactMap { $0.domain() }
            return
        }

        var values: [AgentPresence] = []
        for key in container.allKeys {
            if let dto = try? container.decode(PresenceDTO.self, forKey: key),
               let domain = dto.domain(agentIdOverride: key.stringValue) {
                values.append(domain)
            }
        }
        presences = values
    }
}

struct SonarRoom: Identifiable, Hashable {
    enum RoomGroup: Hashable {
        case ticket
        case boardOrProject
        case system
        case general
    }

    let id: String
    let name: String
    let type: String
    let description: String?
    let linkedTicketId: String?
    let linkedBoardId: String?
    let channelPurpose: String
    let isSystemChannel: Bool
    let messageCount: Int
    let pendingCount: Int
    let unreadCount: Int
    let mentionCount: Int
    let activeSSEClients: Int
    let needsAttention: Bool
    let latestResponseState: String?
    let latestProvenance: String?
    let presence: String
    let presenceDetail: String?
    let protectedLane: Bool
    let policyLaneType: String
    let policyProtectedLevel: String
    let policyOwner: String?
    let allowedActions: [String]
    let canPost: Bool
    let canRequestWorkflow: Bool
    let protectionReason: String?
    let notificationLevel: String
    let lastUserMessageAt: Date?
    let lastAgentMessageAt: Date?
    let lastReadAt: Date?
    let updatedAt: Date

    init(channel: DirectChatChannelDTO, summary: DirectChatChannelSummaryDTO?) {
        self.id = channel.id
        self.name = channel.name
        self.type = channel.type
        self.description = channel.description
        self.linkedTicketId = channel.linkedTicketId ?? summary?.linkedTicketId
        self.linkedBoardId = channel.linkedBoardId ?? summary?.linkedBoardId
        self.channelPurpose = channel.channelPurpose ?? summary?.channelPurpose ?? "general"
        self.isSystemChannel = channel.isSystemChannel ?? summary?.isSystemChannel ?? false
        self.messageCount = summary?.messageCount ?? 0
        self.pendingCount = summary?.pendingCount ?? 0
        self.unreadCount = 0
        self.mentionCount = 0
        self.activeSSEClients = summary?.activeSSEClients ?? 0
        self.needsAttention = summary?.pendingCount ?? 0 > 0
        self.latestResponseState = summary?.latestResponseState
        self.latestProvenance = summary?.latestProvenance
        self.presence = summary?.activeSSEClients ?? 0 > 0 ? "live" : "quiet"
        self.presenceDetail = summary?.activeSSEClients ?? 0 > 0 ? "\(summary?.activeSSEClients ?? 0) live stream" : nil
        self.protectedLane = false
        self.policyLaneType = summary?.policyLaneType ?? "standard"
        self.policyProtectedLevel = summary?.policyProtectedLevel ?? "none"
        self.policyOwner = summary?.policyOwner
        self.allowedActions = (summary?.policyAllowedActions ?? "post,workflow,ticket,approval,agent_run,file,memory")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.canPost = true
        self.canRequestWorkflow = true
        self.protectionReason = nil
        self.notificationLevel = summary?.pendingCount ?? 0 > 0 ? "attention" : "normal"
        self.lastUserMessageAt = summary?.lastUserMessageAt
        self.lastAgentMessageAt = summary?.lastAgentMessageAt
        self.lastReadAt = nil
        self.updatedAt = summary?.updatedAt ?? channel.updatedAt
    }

    fileprivate init(contact: SonarContactDTO) {
        self.id = contact.channelId
        self.name = contact.name
        self.type = contact.kind == "agent" ? "direct" : "group"
        self.description = contact.subtitle
        self.linkedTicketId = contact.linkedTicketId
        self.linkedBoardId = contact.linkedBoardId
        self.channelPurpose = contact.channelPurpose
        self.isSystemChannel = contact.isSystemChannel
        self.messageCount = contact.messageCount
        self.pendingCount = contact.pendingCount
        self.unreadCount = contact.unreadCount ?? 0
        self.mentionCount = contact.mentionCount ?? 0
        self.activeSSEClients = contact.activeSSEClients
        self.needsAttention = contact.needsAttention ?? (contact.pendingCount > 0 || (contact.mentionCount ?? 0) > 0)
        self.latestResponseState = contact.latestResponseState
        self.latestProvenance = contact.latestProvenance
        self.presence = contact.presence ?? (contact.activeSSEClients > 0 ? "live" : "quiet")
        self.presenceDetail = contact.presenceDetail
        self.protectedLane = contact.protectedLane ?? false
        self.policyLaneType = contact.policyLaneType ?? "standard"
        self.policyProtectedLevel = contact.policyProtectedLevel ?? "none"
        self.policyOwner = contact.policyOwner
        self.allowedActions = contact.allowedActions ?? []
        self.canPost = contact.canPost ?? true
        self.canRequestWorkflow = contact.canRequestWorkflow ?? true
        self.protectionReason = contact.protectionReason
        self.notificationLevel = contact.notificationLevel ?? "normal"
        self.lastUserMessageAt = contact.lastUserMessageAt
        self.lastAgentMessageAt = contact.lastAgentMessageAt
        self.lastReadAt = contact.lastReadAt
        self.updatedAt = contact.lastActivityAt
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ticket:") {
            return "Ticket \(trimmed.dropFirst(7))"
        }
        if trimmed.hasPrefix("board:") {
            return "Board \(trimmed.dropFirst(6))"
        }
        return trimmed
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var roomKindLabel: String {
        if channelPurpose == "service_request" { return "Ticket room" }
        if channelPurpose == "board" { return "Board room" }
        if linkedTicketId != nil { return "Ticket room" }
        if linkedBoardId != nil { return "Board room" }
        let lower = name.lowercased()
        if lower.hasPrefix("ticket:") { return "Ticket room" }
        if lower.hasPrefix("board:") { return "Board room" }
        if lower.contains("project") { return "Project room" }
        return "ORCA room"
    }

    var lastActivity: Date {
        [lastAgentMessageAt, lastUserMessageAt, updatedAt].compactMap { $0 }.max() ?? updatedAt
    }

    var roomGroup: RoomGroup {
        if channelPurpose == "service_request" || linkedTicketId != nil || name.lowercased().hasPrefix("ticket:") {
            return .ticket
        }
        if channelPurpose == "board" || linkedBoardId != nil || name.lowercased().hasPrefix("board:") {
            return .boardOrProject
        }
        if name.lowercased().contains("project") {
            return .boardOrProject
        }
        if isSystemChannel || ["alert", "system"].contains(channelPurpose.lowercased()) {
            return .system
        }
        if name.lowercased().contains("alert") {
            return .system
        }
        return .general
    }
}

struct SonarHealth: Hashable {
    let status: String
    let generatedAt: Date
    let checks: [SonarHealthCheck]

    var displayStatus: String {
        switch status.lowercased() {
        case "good": return "Healthy"
        case "down": return "Down"
        default: return "Degraded"
        }
    }
}

struct SonarHealthCheck: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let label: String
    let status: String
    let detail: String?
    let count: Int?

    var displayStatus: String {
        switch status.lowercased() {
        case "good": return "Good"
        case "down": return "Down"
        default: return "Degraded"
        }
    }
}

enum SonarRoomMessageType: String, CaseIterable, Identifiable, Hashable {
    case text
    case toolRequest = "tool_request"
    case fileRequest = "file_request"
    case approvalRequest = "approval_request"
    case agentRunRequest = "agent_run_request"
    case memoryCandidate = "memory_candidate"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Message"
        case .toolRequest: return "Tool"
        case .fileRequest: return "File"
        case .approvalRequest: return "Approval"
        case .agentRunRequest: return "Agent Run"
        case .memoryCandidate: return "Memory"
        }
    }

    var detail: String {
        switch self {
        case .text: return "Plain room note"
        case .toolRequest: return "Request scoped work"
        case .fileRequest: return "Request file context"
        case .approvalRequest: return "Ask for sign/pass"
        case .agentRunRequest: return "Queue agent work"
        case .memoryCandidate: return "Propose memory"
        }
    }

    var icon: String {
        switch self {
        case .text: return "text.bubble"
        case .toolRequest: return "wrench.and.screwdriver"
        case .fileRequest: return "doc.badge.gearshape"
        case .approvalRequest: return "person.badge.key"
        case .agentRunRequest: return "bolt.badge.clock"
        case .memoryCandidate: return "brain.head.profile"
        }
    }

    var lane: String {
        switch self {
        case .text: return "room_note"
        case .toolRequest: return "tool_request"
        case .fileRequest: return "file_request"
        case .approvalRequest: return "approval_request"
        case .agentRunRequest: return "agent_run_request"
        case .memoryCandidate: return "memory_candidate"
        }
    }
}

enum SonarRoomFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case attention
    case unread
    case mentions
    case waiting
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .attention: return "Attention"
        case .unread: return "Unread"
        case .mentions: return "Mentions"
        case .waiting: return "Waiting"
        case .live: return "Live"
        }
    }

    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .attention: return "bell.badge"
        case .unread: return "circle.fill"
        case .mentions: return "at"
        case .waiting: return "person.badge.clock"
        case .live: return "bolt.horizontal.circle"
        }
    }

    func includes(_ room: SonarRoom) -> Bool {
        switch self {
        case .all:
            return true
        case .attention:
            return room.needsAttention || room.notificationLevel == "urgent" || room.notificationLevel == "attention"
        case .unread:
            return room.unreadCount > 0
        case .mentions:
            return room.mentionCount > 0
        case .waiting:
            return room.pendingCount > 0
                || room.latestResponseState == DMDeliveryState.waitingForLiveAgent.rawValue
                || room.latestResponseState == DMDeliveryState.deliveryNatsFailed.rawValue
                || room.latestResponseState == DMDeliveryState.agentUnresponsive.rawValue
        case .live:
            return room.activeSSEClients > 0 || room.presence == "live"
        }
    }
}

private struct SonarHealthDTO: Decodable {
    let status: String
    let generatedAt: Date
    let checks: [SonarHealthCheckDTO]

    enum CodingKeys: String, CodingKey {
        case status
        case generatedAt = "generated_at"
        case checks
    }

    func toDomain() -> SonarHealth {
        SonarHealth(
            status: status,
            generatedAt: generatedAt,
            checks: checks.map { $0.toDomain() }
        )
    }
}

private struct SonarHealthCheckDTO: Decodable {
    let key: String
    let label: String
    let status: String
    let detail: String?
    let count: Int?

    func toDomain() -> SonarHealthCheck {
        SonarHealthCheck(
            key: key,
            label: label,
            status: status,
            detail: detail,
            count: count
        )
    }
}

private struct SonarContactsResponseDTO: Decodable {
    let generatedAt: Date
    let contacts: [SonarContactDTO]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case contacts
    }
}

private struct SonarContactDTO: Decodable {
    let id: String
    let kind: String
    let channelId: String
    let name: String
    let displayName: String
    let subtitle: String?
    let status: String
    let statusDetail: String?
    let linkedTicketId: String?
    let linkedBoardId: String?
    let channelPurpose: String
    let isSystemChannel: Bool
    let messageCount: Int
    let pendingCount: Int
    let unreadCount: Int?
    let mentionCount: Int?
    let activeSSEClients: Int
    let needsAttention: Bool?
    let latestMessageId: String?
    let latestTraceId: String?
    let latestResponseState: String?
    let latestProvenance: String?
    let presence: String?
    let presenceDetail: String?
    let protectedLane: Bool?
    let canPost: Bool?
    let canRequestWorkflow: Bool?
    let protectionReason: String?
    let notificationLevel: String?
    let policyLaneType: String?
    let policyProtectedLevel: String?
    let policyOwner: String?
    let allowedActions: [String]?
    let latestPreview: String?
    let lastUserMessageAt: Date?
    let lastAgentMessageAt: Date?
    let lastReadAt: Date?
    let lastActivityAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, name, subtitle, status
        case channelId = "channel_id"
        case displayName = "display_name"
        case statusDetail = "status_detail"
        case presence
        case presenceDetail = "presence_detail"
        case linkedTicketId = "linked_ticket_id"
        case linkedBoardId = "linked_board_id"
        case channelPurpose = "channel_purpose"
        case isSystemChannel = "is_system_channel"
        case messageCount = "message_count"
        case pendingCount = "pending_count"
        case unreadCount = "unread_count"
        case mentionCount = "mention_count"
        case activeSSEClients = "active_sse_clients"
        case needsAttention = "needs_attention"
        case protectedLane = "protected_lane"
        case canPost = "can_post"
        case canRequestWorkflow = "can_request_workflow"
        case protectionReason = "protection_reason"
        case notificationLevel = "notification_level"
        case policyLaneType = "policy_lane_type"
        case policyProtectedLevel = "policy_protected_level"
        case policyOwner = "policy_owner"
        case allowedActions = "allowed_actions"
        case latestMessageId = "latest_message_id"
        case latestTraceId = "latest_trace_id"
        case latestResponseState = "latest_response_state"
        case latestProvenance = "latest_provenance"
        case latestPreview = "latest_preview"
        case lastUserMessageAt = "last_user_message_at"
        case lastAgentMessageAt = "last_agent_message_at"
        case lastReadAt = "last_read_at"
        case lastActivityAt = "last_activity_at"
    }

    var statusLine: String {
        var parts: [String] = []
        if let statusDetail, !statusDetail.isEmpty {
            parts.append(statusDetail)
        } else {
            parts.append(status.capitalized)
        }
        if messageCount > 0 {
            parts.append("\(messageCount) messages")
        }
        if let latestResponseState, !latestResponseState.isEmpty {
            parts.append(latestResponseState.replacingOccurrences(of: "_", with: " "))
        }
        return parts.joined(separator: " · ")
    }
}

struct SonarRoomMessage: Identifiable, Hashable {
    let id: String
    let senderName: String
    let senderType: String
    let senderEmoji: String?
    let content: String
    let messageType: String
    let traceId: String?
    let source: String?
    let lane: String?
    let deliveryMode: String?
    let provenance: String?
    let provider: String?
    let model: String?
    let surfaceEventProvenance: String?
    let responseState: String?
    let deliveryState: String
    let replyToId: String?
    let isThreadReply: Bool
    let fileAttachment: ChatFileAttachment?
    let createdAt: Date

    init(dto: DirectChatORCAMessageDTO) {
        self.id = dto.id
        self.senderName = dto.senderName ?? (dto.senderAgentId == nil ? "Tony" : "Agent")
        self.senderType = dto.senderType ?? (dto.senderAgentId == nil ? "user" : "agent")
        self.senderEmoji = dto.senderEmoji
        self.content = dto.content
        self.messageType = dto.messageType
        self.traceId = dto.traceId
        self.source = dto.source
        self.lane = dto.lane
        self.deliveryMode = dto.deliveryMode
        self.provenance = dto.normalizedProvenance ?? dto.provenance
        self.provider = dto.provider
        self.model = dto.model
        self.surfaceEventProvenance = dto.surfaceEventProvenance
        self.responseState = dto.responseState
        self.deliveryState = dto.deliveryState ?? "delivered"
        self.replyToId = dto.replyToId
        self.isThreadReply = dto.isThreadReply
        self.fileAttachment = dto.fileAttachment
        self.createdAt = dto.createdAt
    }

    var isUser: Bool {
        senderType == "user" || senderName.lowercased() == "tony"
    }

    var displayName: String {
        if let senderEmoji, !senderEmoji.isEmpty {
            return "\(senderEmoji) \(senderName)"
        }
        return senderName
    }

    var statusLabel: String? {
        if let computeDraftLabel {
            return computeDraftLabel
        }
        if DMDeliveryState.parse(responseState) == .waitingForLiveAgent || DMDeliveryState.parse(deliveryState) == .waitingForLiveAgent {
            return "Waiting for \(agentDisplayName)"
        }
        if DMDeliveryState.parse(responseState) == .deliveryNatsFailed || DMDeliveryState.parse(deliveryState) == .deliveryNatsFailed {
            return DMDeliveryState.deliveryNatsFailed.displayLabel
        }
        if DMDeliveryState.parse(responseState) == .agentUnresponsive || DMDeliveryState.parse(deliveryState) == .agentUnresponsive {
            return DMDeliveryState.agentUnresponsive.displayLabel
        }
        if DMResponseProvenance.parse(provenance) == .liveInbox, !isUser {
            return "\(agentDisplayName) replied"
        }
        if let state = DMDeliveryState.parse(responseState) {
            return state.displayLabel
        }
        if deliveryState != "delivered" {
            return deliveryState.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if let provenance = DMResponseProvenance.parse(provenance) {
            return provenance.displayLabel
        }
        return nil
    }

    var computeDraftLabel: String? {
        guard let computeProvider else { return nil }
        let providerLabel = computeProvider.capitalized
        return "\(providerLabel) draft in \(agentDisplayName)'s voice — live agent offline"
    }

    private var computeProvider: String? {
        let normalized = provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard ["spark", "kimi", "openclaw"].contains(normalized) else { return nil }
        return normalized
    }

    private var agentDisplayName: String {
        senderName
            .replacingOccurrences(of: "direct:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    var isRequestCard: Bool {
        Self.requestCardTypes.contains(messageType)
    }

    var cardTitle: String {
        switch messageType {
        case "tool_request": return "Tool Request"
        case "file_request": return "File Request"
        case "memory_candidate": return "Memory Candidate"
        case "approval_request": return "Approval Request"
        case "agent_run_request": return "Agent Run Request"
        case "ticket_action": return "Ticket Action"
        case "task_action": return "Task Action"
        case "system": return "System"
        default: return "Message"
        }
    }

    var cardIcon: String {
        switch messageType {
        case "tool_request": return "wrench.and.screwdriver"
        case "file_request": return "doc.badge.gearshape"
        case "memory_candidate": return "brain.head.profile"
        case "approval_request": return "person.badge.key"
        case "agent_run_request": return "bolt.badge.clock"
        case "ticket_action": return "text.badge.checkmark"
        case "task_action": return "checklist"
        case "system": return "gearshape"
        default: return "bubble.left"
        }
    }

    private static let requestCardTypes: Set<String> = [
        "tool_request",
        "file_request",
        "memory_candidate",
        "approval_request",
        "agent_run_request",
        "ticket_action",
        "task_action",
        "system"
    ]
}

private struct SonarRoomMessageCreateBody: Encodable {
    let content: String
    let messageType: String
    let traceId: String
    let source: String
    let lane: String
    let deliveryMode: String
    let provenance: String
    let responseState: String
    let replyToId: String?

    enum CodingKeys: String, CodingKey {
        case content
        case messageType = "message_type"
        case traceId = "trace_id"
        case source
        case lane
        case deliveryMode = "delivery_mode"
        case provenance
        case responseState = "response_state"
        case replyToId = "reply_to_id"
    }
}

private struct SonarReadStateBody: Encodable {
    let readThroughMessageId: String?

    enum CodingKeys: String, CodingKey {
        case readThroughMessageId = "read_through_message_id"
    }
}

private struct SonarReadStateDTO: Decodable {
    let channelId: String
    let userId: String?
    let lastReadAt: Date
    let unreadCount: Int
    let mentionCount: Int

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case userId = "user_id"
        case lastReadAt = "last_read_at"
        case unreadCount = "unread_count"
        case mentionCount = "mention_count"
    }
}

struct DirectChatChannelDTO: Decodable {
    let id: String
    let name: String
    let type: String
    let description: String?
    let linkedTicketId: String?
    let linkedBoardId: String?
    let channelPurpose: String?
    let isSystemChannel: Bool?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, type, description
        case linkedTicketId = "linked_ticket_id"
        case linkedBoardId = "linked_board_id"
        case channelPurpose = "channel_purpose"
        case isSystemChannel = "is_system_channel"
        case updatedAt = "updated_at"
    }
}

struct DirectChatChannelSummaryDTO: Decodable {
    let channelId: String
    let messageCount: Int
    let linkedTicketId: String?
    let linkedBoardId: String?
    let channelPurpose: String?
    let isSystemChannel: Bool?
    let latestProvenance: String?
    let latestResponseState: String?
    let pendingCount: Int
    let activeSSEClients: Int
    let policyLaneType: String?
    let policyProtectedLevel: String?
    let policyOwner: String?
    let policyAllowedActions: String?
    let policyReason: String?
    let lastUserMessageAt: Date?
    let lastAgentMessageAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case messageCount = "message_count"
        case linkedTicketId = "linked_ticket_id"
        case linkedBoardId = "linked_board_id"
        case channelPurpose = "channel_purpose"
        case isSystemChannel = "is_system_channel"
        case latestProvenance = "latest_provenance"
        case latestResponseState = "latest_response_state"
        case pendingCount = "pending_count"
        case activeSSEClients = "active_sse_clients"
        case policyLaneType = "policy_lane_type"
        case policyProtectedLevel = "policy_protected_level"
        case policyOwner = "policy_owner"
        case policyAllowedActions = "policy_allowed_actions"
        case policyReason = "policy_reason"
        case lastUserMessageAt = "last_user_message_at"
        case lastAgentMessageAt = "last_agent_message_at"
        case updatedAt = "updated_at"
    }
}

private struct DirectChatMermanTriageBody: Encodable {
    let surface: String
    let target: String
    let text: String
    let context: [String: String]
}

private struct DirectChatMermanTriageDTO: Decodable {
    let triageId: String?
    let traceId: String?
    let intentType: String
    let recommendedLane: String
    let riskLevel: String
    let needsTicket: Bool
    let needsApproval: Bool
    let suggestedOwner: String
    let suggestedWorker: String?
    let suggestedComputeRoute: String
    let deliveryMode: String
    let autonomyLevel: String
    let nextAction: String
    let reason: String
    let approvalGate: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let approvalState: String?
    let guardrailNotes: [String]?
    let acceptanceCriteria: [String]?
    let doneMeans: String?
    let workerLane: String?
    let visibleTags: [String]?
    let confidence: Double?
    let quality: String?
    let cannotDo: Bool
    let needsHuman: Bool
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case triageId = "triage_id"
        case traceId = "trace_id"
        case intentType = "intent_type"
        case recommendedLane = "recommended_lane"
        case riskLevel = "risk_level"
        case needsTicket = "needs_ticket"
        case needsApproval = "needs_approval"
        case suggestedOwner = "suggested_owner"
        case suggestedWorker = "suggested_worker"
        case suggestedComputeRoute = "suggested_compute_route"
        case deliveryMode = "delivery_mode"
        case autonomyLevel = "autonomy_level"
        case nextAction = "next_action"
        case reason
        case approvalGate = "approval_gate"
        case recommendedRuntime = "recommended_runtime"
        case recommendedSurface = "recommended_surface"
        case runtimeReason = "runtime_reason"
        case handoffSubject = "handoff_subject"
        case approvalState = "approval_state"
        case guardrailNotes = "guardrail_notes"
        case acceptanceCriteria = "acceptance_criteria"
        case doneMeans = "done_means"
        case workerLane = "worker_lane"
        case visibleTags = "visible_tags"
        case confidence
        case quality
        case cannotDo = "cannot_do"
        case needsHuman = "needs_human"
        case tags
    }

    init(
        triageId: String?,
        traceId: String?,
        intentType: String,
        recommendedLane: String,
        riskLevel: String,
        needsTicket: Bool,
        needsApproval: Bool,
        suggestedOwner: String,
        suggestedWorker: String?,
        suggestedComputeRoute: String,
        deliveryMode: String,
        autonomyLevel: String,
        nextAction: String,
        reason: String,
        approvalGate: String?,
        recommendedRuntime: String?,
        recommendedSurface: String?,
        runtimeReason: String?,
        handoffSubject: String?,
        approvalState: String?,
        guardrailNotes: [String]?,
        acceptanceCriteria: [String]?,
        doneMeans: String?,
        workerLane: String?,
        visibleTags: [String]?,
        confidence: Double?,
        quality: String?,
        cannotDo: Bool,
        needsHuman: Bool,
        tags: [String]
    ) {
        self.triageId = triageId
        self.traceId = traceId
        self.intentType = intentType
        self.recommendedLane = recommendedLane
        self.riskLevel = riskLevel
        self.needsTicket = needsTicket
        self.needsApproval = needsApproval
        self.suggestedOwner = suggestedOwner
        self.suggestedWorker = suggestedWorker
        self.suggestedComputeRoute = suggestedComputeRoute
        self.deliveryMode = deliveryMode
        self.autonomyLevel = autonomyLevel
        self.nextAction = nextAction
        self.reason = reason
        self.approvalGate = approvalGate
        self.recommendedRuntime = recommendedRuntime
        self.recommendedSurface = recommendedSurface
        self.runtimeReason = runtimeReason
        self.handoffSubject = handoffSubject
        self.approvalState = approvalState
        self.guardrailNotes = guardrailNotes
        self.acceptanceCriteria = acceptanceCriteria
        self.doneMeans = doneMeans
        self.workerLane = workerLane
        self.visibleTags = visibleTags
        self.confidence = confidence
        self.quality = quality
        self.cannotDo = cannotDo
        self.needsHuman = needsHuman
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        triageId = try c.decodeIfPresent(String.self, forKey: .triageId)
        traceId = try c.decodeIfPresent(String.self, forKey: .traceId)
        intentType = try c.decodeIfPresent(String.self, forKey: .intentType) ?? "general_triage"
        recommendedLane = try c.decodeIfPresent(String.self, forKey: .recommendedLane) ?? "aloha"
        riskLevel = try c.decodeIfPresent(String.self, forKey: .riskLevel) ?? "normal"
        needsTicket = try c.decodeIfPresent(Bool.self, forKey: .needsTicket) ?? false
        needsApproval = try c.decodeIfPresent(Bool.self, forKey: .needsApproval) ?? false
        suggestedOwner = try c.decodeIfPresent(String.self, forKey: .suggestedOwner) ?? recommendedLane
        suggestedWorker = try c.decodeIfPresent(String.self, forKey: .suggestedWorker)
        suggestedComputeRoute = try c.decodeIfPresent(String.self, forKey: .suggestedComputeRoute) ?? "auto"
        deliveryMode = try c.decodeIfPresent(String.self, forKey: .deliveryMode) ?? "auto"
        autonomyLevel = try c.decodeIfPresent(String.self, forKey: .autonomyLevel) ?? "draft only"
        nextAction = try c.decodeIfPresent(String.self, forKey: .nextAction) ?? "answer_or_clarify"
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? "Merman returned a partial triage response."
        approvalGate = try c.decodeIfPresent(String.self, forKey: .approvalGate)
        recommendedRuntime = try c.decodeIfPresent(String.self, forKey: .recommendedRuntime)
        recommendedSurface = try c.decodeIfPresent(String.self, forKey: .recommendedSurface)
        runtimeReason = try c.decodeIfPresent(String.self, forKey: .runtimeReason)
        handoffSubject = try c.decodeIfPresent(String.self, forKey: .handoffSubject)
        approvalState = try c.decodeIfPresent(String.self, forKey: .approvalState)
        guardrailNotes = try c.decodeIfPresent([String].self, forKey: .guardrailNotes)
        acceptanceCriteria = try c.decodeIfPresent([String].self, forKey: .acceptanceCriteria)
        doneMeans = try c.decodeIfPresent(String.self, forKey: .doneMeans)
        workerLane = try c.decodeIfPresent(String.self, forKey: .workerLane)
        visibleTags = try c.decodeIfPresent([String].self, forKey: .visibleTags)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        quality = try c.decodeIfPresent(String.self, forKey: .quality)
        cannotDo = try c.decodeIfPresent(Bool.self, forKey: .cannotDo) ?? false
        needsHuman = try c.decodeIfPresent(Bool.self, forKey: .needsHuman) ?? false
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func toPreview(sourceText: String, targetAgentId: String) -> DirectChatTriagePreview {
        DirectChatTriagePreview(
            id: triageId ?? traceId ?? UUID().uuidString,
            traceId: traceId,
            targetAgentId: targetAgentId,
            sourceText: sourceText,
            intentType: intentType,
            recommendedLane: recommendedLane,
            riskLevel: riskLevel,
            needsTicket: needsTicket,
            needsApproval: needsApproval,
            suggestedOwner: suggestedOwner,
            suggestedWorker: suggestedWorker,
            suggestedComputeRoute: suggestedComputeRoute,
            deliveryMode: deliveryMode,
            autonomyLevel: autonomyLevel,
            nextAction: nextAction,
            reason: reason,
            approvalGate: approvalGate,
            approvalState: approvalState,
            workerLane: workerLane,
            recommendedRuntime: recommendedRuntime,
            recommendedSurface: recommendedSurface,
            runtimeReason: runtimeReason,
            handoffSubject: handoffSubject,
            confidence: confidence,
            tags: tags
        )
    }

    static func previewBacked(_ preview: DirectChatTriagePreview) -> DirectChatMermanTriageDTO {
        DirectChatMermanTriageDTO(
            triageId: preview.id,
            traceId: preview.traceId,
            intentType: preview.intentType,
            recommendedLane: preview.recommendedLane,
            riskLevel: preview.riskLevel,
            needsTicket: preview.needsTicket,
            needsApproval: preview.needsApproval,
            suggestedOwner: preview.suggestedOwner,
            suggestedWorker: preview.suggestedWorker,
            suggestedComputeRoute: preview.suggestedComputeRoute,
            deliveryMode: preview.deliveryMode,
            autonomyLevel: preview.autonomyLevel,
            nextAction: preview.nextAction,
            reason: preview.reason,
            approvalGate: preview.approvalGate,
            recommendedRuntime: preview.recommendedRuntime,
            recommendedSurface: preview.recommendedSurface,
            runtimeReason: preview.runtimeReason,
            handoffSubject: preview.handoffSubject,
            approvalState: preview.approvalState,
            guardrailNotes: nil,
            acceptanceCriteria: nil,
            doneMeans: nil,
            workerLane: preview.workerLane,
            visibleTags: nil,
            confidence: preview.confidence,
            quality: "pod_preview_reuse",
            cannotDo: false,
            needsHuman: preview.needsApproval,
            tags: preview.tags
        )
    }
}
