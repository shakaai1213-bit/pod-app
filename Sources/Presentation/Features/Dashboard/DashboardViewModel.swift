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
            let response: [ProjectDTO] = try await apiClient.get(path: Endpoint.listProjects().path)
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
