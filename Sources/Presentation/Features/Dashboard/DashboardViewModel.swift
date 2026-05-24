import Foundation
import SwiftUI

// MARK: - Dashboard ViewModel

@Observable
final class DashboardViewModel {

    // MARK: - Published State

    var agents: [Agent] = []
    var projects: [Project] = []
    var activities: [ActivityItem] = []
    var attentionItems: [AttentionItem] = []
    var tickets: [TicketDTO] = []
    var stateTags: [StateTagDTO] = []
    var chiefProtectionTags: [StateTagDTO] = []
    var startupStatus: DashboardStartupStatusResponse?
    var ticketFlowReview: TicketFlowReview?
    var ticketFlowLastUpdated: Date?
    var ticketFlowErrorMessage: String?
    var staleStateTagCount: Int = 0
    var stateRegistryReviewExport: StateRegistryReviewExportResult?
    var stateRegistryReviewExportMessage: String?
    var isExportingStateRegistryReview = false
    var isLoading: Bool = false
    var error: String?

    // MARK: - Metrics

    var activeProjectsCount: Int {
        projects.filter { $0.status == .active || $0.status == .inProgress || $0.status == .review }.count
    }

    var inProgressCount: Int {
        projects.filter { $0.status == .inProgress }.count
    }

    var agentsOnlineCount: Int {
        agents.filter { $0.status != .offline }.count
    }

    var openTicketsCount: Int {
        tickets.filter { !["closed", "cancelled"].contains($0.status.lowercased()) }.count
    }

    var startupDebtCount: Int {
        startupStatus?.components.filter(\.isDebt).count ?? 0
    }

    // MARK: - Private

    private let apiClient: APIClient
    private weak var appState: AppState?

    // MARK: - Init

    init(apiClient: APIClient = .shared, appState: AppState? = nil) {
        self.apiClient = apiClient
        self.appState = appState
    }

    @MainActor var displayName: String {
        appState?.currentUser?.name ?? UserDefaults.standard.string(forKey: "orca_display_name") ?? "Captain"
    }

    // MARK: - Load

    @MainActor
    func exportStateRegistryReview() async {
        guard !isExportingStateRegistryReview else { return }
        isExportingStateRegistryReview = true
        stateRegistryReviewExport = nil
        stateRegistryReviewExportMessage = nil
        defer { isExportingStateRegistryReview = false }

        do {
            let result: StateRegistryReviewExportResult = try await apiClient.post(
                path: "/api/v1/state-registry/review/export",
                body: DashboardEmptyRequestBody()
            )
            stateRegistryReviewExport = result
            stateRegistryReviewExportMessage = result.message
        } catch {
            stateRegistryReviewExportMessage = "Couldn't export State Registry review packet."
        }
    }

    @MainActor
    func loadDashboard() async {
        isLoading = true
        error = nil
        var loadErrors: [String] = []

        // Fetch agents
        do {
            let response: PaginatedResponse<AgentDTO> = try await apiClient.get(path: Endpoint.agents.path)
            let mappedAgents = response.items.map { dto in
                Agent(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    role: dto.role,
                    status: mapAgentStatus(dto.status),
                    currentTask: dto.currentTask,
                    lastActivity: dto.lastSeenAt ?? Date(),
                    skills: dto.skills,
                    avatarColor: dto.avatarColor ?? "#3B82F6"
                )
            }
            agents = AgentRosterPolicy.filterActive(mappedAgents)
        } catch {
            loadErrors.append("Agents: \(error.localizedDescription)")
            // No fallback — show empty or error state
        }

        // Fetch projects
        do {
            let response = try await ProjectRepository().listProjects()
            projects = response.map { dto in
                Project(
                    id: dto.id,
                    name: dto.name,
                    description: dto.description ?? dto.goal ?? "",
                    boardGroupId: dto.assignedTo ?? UUID(),
                    status: mapProjectStatus(dto.status),
                    stage: .dev,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt,
                    taskCount: 0,
                    completedTaskCount: 0
                )
            }
        } catch {
            loadErrors.append("Projects: \(error.localizedDescription)")
            // Non-fatal: keep existing projects
        }

        do {
            let response: [TicketDTO] = try await apiClient.get(path: "/api/v1/tickets")
            tickets = response
            attentionItems = response
                .filter { ticket in
                    let status = ticket.status.lowercased()
                    let priority = ticket.priority.lowercased()
                    return !["closed", "cancelled"].contains(status)
                        && ["high", "urgent"].contains(priority)
                }
                .prefix(5)
                .map { ticket in
                    AttentionItem(
                        type: ticket.priority.lowercased() == "urgent" ? .agentError : .blockedTask,
                        title: ticket.title,
                        severity: ticket.priority.lowercased() == "urgent" ? .critical : .warning,
                        actor: "\(ticket.priority.uppercased()) · \(ticket.status.replacingOccurrences(of: "_", with: " "))"
                    )
                }
        } catch {
            loadErrors.append("Tickets: \(error.localizedDescription)")
            tickets = []
            attentionItems = []
        }

        await loadTicketFlowReview()

        do {
            startupStatus = try await apiClient.get(path: "/api/v1/startup/status")
        } catch {
            loadErrors.append("Startup: \(error.localizedDescription)")
            startupStatus = nil
        }

        do {
            let response: StateRegistryResponse = try await apiClient.get(
                path: "/api/v1/state-registry?prefix=agent.&limit=8"
            )
            let workerResponse: StateRegistryResponse = try await apiClient.get(
                path: "/api/v1/state-registry?prefix=worker.&limit=4"
            )
            let ticketResponse: StateRegistryResponse = try await apiClient.get(
                path: "/api/v1/state-registry?prefix=ticket.&limit=6"
            )
            let memoryResponse: StateRegistryResponse = try await apiClient.get(
                path: "/api/v1/state-registry?prefix=memory.&limit=4"
            )
            stateTags = response.items + workerResponse.items + ticketResponse.items + memoryResponse.items
            staleStateTagCount = response.summary.stale + workerResponse.summary.stale + ticketResponse.summary.stale + memoryResponse.summary.stale
        } catch {
            loadErrors.append("State: \(error.localizedDescription)")
            stateTags = []
            staleStateTagCount = 0
        }

        do {
            let verifiedCards: StateRegistryResponse = try await apiClient.get(
                path: "/api/v1/state-registry?prefix=surface.pod.chief&limit=10"
            )
            let botMap: StateRegistryResponse = try await apiClient.get(
                path: "/api/v1/state-registry?prefix=agent.chief.fund&limit=10"
            )
            chiefProtectionTags = verifiedCards.items + botMap.items
        } catch {
            loadErrors.append("Chief/Fund: \(error.localizedDescription)")
            chiefProtectionTags = []
        }

        if !loadErrors.isEmpty {
            error = loadErrors.joined(separator: " · ")
        }
        isLoading = false
    }

    @MainActor
    func startFlowReviewPolling() async {
        await loadTicketFlowReview()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if Task.isCancelled { break }
            await loadTicketFlowReview()
        }
    }

    @MainActor
    func loadTicketFlowReview(limit: Int = 200) async {
        do {
            let dto: DashboardTicketFlowReviewDTO = try await apiClient.get(
                path: "/api/v1/tickets/flow-review?limit=\(limit)&include_closed=false"
            )
            ticketFlowReview = dto.toDomain()
            ticketFlowLastUpdated = Date()
            ticketFlowErrorMessage = nil
        } catch {
            ticketFlowReview = nil
            ticketFlowErrorMessage = "Flow review unavailable."
        }
    }

    // MARK: - Status Mappers

    private func mapProjectStatus(_ status: String) -> ProjectStatus {
        switch status.lowercased() {
        case "in-progress", "in_progress": return .inProgress
        case "review", "needs_review", "needs-review": return .review
        case "archived": return .archived
        case "done", "completed", "closed": return .completed
        case "paused", "blocked": return .paused
        default: return .active
        }
    }

    /// Maps DTO AgentStatus → Domain AgentState
    private func mapAgentStatus(_ status: AgentStatus) -> AgentState {
        switch status {
        case .online:  return .online
        case .busy:    return .busy
        case .idle:    return .idle
        case .offline: return .offline
        case .error:   return .error
        case .provisioning: return .provisioning
        }
    }

}

private struct DashboardTicketFlowReviewDTO: Decodable {
    let counts: DashboardTicketFlowCountsDTO
    let items: [DashboardTicketFlowItemDTO]

    func toDomain() -> TicketFlowReview {
        TicketFlowReview(
            counts: counts.toDomain(),
            items: items.map { $0.toDomain() }
        )
    }
}

private struct DashboardTicketFlowCountsDTO: Decodable {
    let total: Int?
    let dispatchable: Int?
    let noiseReview: Int?
    let protected: Int?
    let byFlowState: [String: Int]?
    let byOwnerAgent: [String: Int]?
    let bySupportLane: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case total, dispatchable, protected
        case noiseReview = "noise_review"
        case byFlowState = "by_flow_state"
        case byOwnerAgent = "by_owner_agent"
        case bySupportLane = "by_support_lane"
    }

    func toDomain() -> TicketFlowCounts {
        TicketFlowCounts(
            total: total ?? 0,
            dispatchable: dispatchable ?? 0,
            noiseReview: noiseReview ?? 0,
            protected: protected ?? 0,
            byFlowState: byFlowState ?? [:],
            byOwnerAgent: byOwnerAgent ?? [:],
            bySupportLane: bySupportLane ?? [:]
        )
    }
}

private struct DashboardTicketFlowItemDTO: Decodable {
    let ticketId: String
    let title: String?
    let status: String?
    let priority: String?
    let flowState: String?
    let nextAction: String?
    let ownerAgent: String?
    let supportLane: String?
    let workerLane: String?
    let approvalState: String?
    let approvalGate: String?
    let autonomyLevel: String?
    let dispatchable: Bool?
    let noiseReview: Bool?
    let protected: Bool?
    let blockers: [String]?
    let reasons: [String]?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case title, status, priority, dispatchable, protected, blockers, reasons
        case ticketId = "ticket_id"
        case flowState = "flow_state"
        case nextAction = "next_action"
        case ownerAgent = "owner_agent"
        case supportLane = "support_lane"
        case workerLane = "worker_lane"
        case approvalState = "approval_state"
        case approvalGate = "approval_gate"
        case autonomyLevel = "autonomy_level"
        case noiseReview = "noise_review"
        case updatedAt = "updated_at"
    }

    func toDomain() -> TicketFlowItem {
        TicketFlowItem(
            ticketId: ticketId,
            title: title ?? "Untitled ticket",
            status: status ?? "unknown",
            priority: priority ?? "normal",
            flowState: flowState ?? "unknown",
            nextAction: nextAction ?? "Review",
            ownerAgent: ownerAgent ?? "unassigned",
            supportLane: supportLane,
            workerLane: workerLane,
            approvalState: approvalState ?? "not_required",
            approvalGate: approvalGate,
            autonomyLevel: autonomyLevel ?? "owner-review",
            dispatchable: dispatchable ?? false,
            noiseReview: noiseReview ?? false,
            protected: protected ?? false,
            blockers: blockers ?? [],
            reasons: reasons ?? [],
            updatedAt: updatedAt ?? .distantPast
        )
    }
}
