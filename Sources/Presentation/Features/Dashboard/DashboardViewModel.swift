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
    var isLoading: Bool = false
    var error: String?

    // MARK: - Metrics

    var activeProjectsCount: Int {
        projects.filter { $0.status.rawValue != "done" && $0.status.rawValue != "archived" }.count
    }

    var inProgressCount: Int {
        projects.filter { $0.status.rawValue == "in-progress" }.count
    }

    var agentsOnlineCount: Int {
        agents.filter { $0.status != .offline }.count
    }

    var needsReviewCount: Int {
        projects.filter { $0.status.rawValue == "review" }.count
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
    func loadDashboard() async {
        isLoading = true
        error = nil

        // Fetch agents
        do {
            let response: PaginatedResponse<AgentDTO> = try await apiClient.get(path: Endpoint.agents.path)
            agents = response.items.map { dto in
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
        } catch {
            self.error = error.localizedDescription
            agents = Self.mockAgents
        }

        // Fetch projects
        do {
            let response: PaginatedResponse<ProjectDTO> = try await apiClient.get(path: Endpoint.listProjects().path)
            projects = response.items.map { dto in
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
            // Non-fatal: keep existing projects
            if projects.isEmpty {
                projects = Self.mockProjects
            }
        }

        activities = Self.mockActivities
        attentionItems = Self.mockAttentionItems

        isLoading = false
    }

    // MARK: - Status Mappers

    private func mapProjectStatus(_ status: String) -> ProjectStatus {
        switch status.lowercased() {
        case "done", "completed", "archived": return .completed
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

    // MARK: - Mock Data

    private static var mockAgents: [Agent] {
        [
            Agent(
                id: UUID(),
                name: "Kai",
                role: "Code Architect",
                status: .online,
                currentTask: "Reviewing PR #42",
                lastActivity: Date().addingTimeInterval(-120),
                skills: ["swift", "architecture", "swiftui"],
                avatarColor: "#3B82F6"
            ),
            Agent(
                id: UUID(),
                name: "Nova",
                role: "Research Analyst",
                status: .busy,
                currentTask: "Gathering market data",
                lastActivity: Date().addingTimeInterval(-300),
                skills: ["research", "analysis"],
                avatarColor: "#A855F7"
            ),
            Agent(
                id: UUID(),
                name: "Orca",
                role: "DevOps Engineer",
                status: .online,
                currentTask: nil,
                lastActivity: Date().addingTimeInterval(-60),
                skills: ["kubernetes", "docker", "ci-cd"],
                avatarColor: "#22C55E"
            ),
            Agent(
                id: UUID(),
                name: "Pulse",
                role: "QA Specialist",
                status: .idle,
                currentTask: nil,
                lastActivity: Date().addingTimeInterval(-3600),
                skills: ["testing", "automation"],
                avatarColor: "#F59E0B"
            ),
            Agent(
                id: UUID(),
                name: "Beacon",
                role: "Documentation",
                status: .error,
                currentTask: "Indexing knowledge base",
                lastActivity: Date().addingTimeInterval(-7200),
                skills: ["docs", "markdown"],
                avatarColor: "#EF4444"
            ),
        ]
    }

    private static var mockProjects: [Project] {
        [
            Project(
                id: UUID(),
                name: "Auth System",
                description: "Implement token refresh and SSO",
                boardGroupId: UUID(),
                status: .active,
                stage: .dev,
                createdAt: Date().addingTimeInterval(-86400 * 7),
                updatedAt: Date().addingTimeInterval(-3600),
                taskCount: 8,
                completedTaskCount: 3
            ),
            Project(
                id: UUID(),
                name: "Dashboard UI",
                description: "Mission control dashboard",
                boardGroupId: UUID(),
                status: .active,
                stage: .verify,
                createdAt: Date().addingTimeInterval(-86400 * 3),
                updatedAt: Date().addingTimeInterval(-7200),
                taskCount: 12,
                completedTaskCount: 8
            ),
            Project(
                id: UUID(),
                name: "API Integration",
                description: "Connect to ORCA MC backend",
                boardGroupId: UUID(),
                status: .completed,
                stage: .done,
                createdAt: Date().addingTimeInterval(-86400 * 14),
                updatedAt: Date().addingTimeInterval(-86400),
                taskCount: 5,
                completedTaskCount: 5
            ),
        ]
    }

    private static var mockActivities: [ActivityItem] {
        let now = Date()
        return [
            ActivityItem(
                type: .taskCompleted,
                description: "Completed sprint planning board setup",
                timestamp: now.addingTimeInterval(-300),
                actor: "Kai",
                isAgent: true
            ),
            ActivityItem(
                type: .messageSent,
                description: "Posted weekly status update in #general",
                timestamp: now.addingTimeInterval(-900),
                actor: "Nova",
                isAgent: true
            ),
            ActivityItem(
                type: .agentMilestone,
                description: "Orca deployed v2.3.1 to staging",
                timestamp: now.addingTimeInterval(-1800),
                actor: "Orca",
                isAgent: true
            ),
            ActivityItem(
                type: .taskCreated,
                description: "Created task: Implement auth token refresh",
                timestamp: now.addingTimeInterval(-3600),
                actor: "Shaka",
                isAgent: false
            ),
            ActivityItem(
                type: .fileUploaded,
                description: "Uploaded architecture_diagram_v3.pdf",
                timestamp: now.addingTimeInterval(-7200),
                actor: "Pulse",
                isAgent: true
            ),
        ]
    }

    private static var mockAttentionItems: [AttentionItem] {
        [
            AttentionItem(
                type: .blockedTask,
                title: "Auth token refresh blocked",
                severity: .warning,
                actor: "Waiting on backend API changes"
            ),
            AttentionItem(
                type: .pendingApproval,
                title: "PR #41 pending review",
                severity: .warning,
                actor: "From Kai · 3h ago"
            ),
            AttentionItem(
                type: .agentError,
                title: "Beacon encountered an error",
                severity: .critical,
                actor: "Knowledge base indexing failed"
            ),
        ]
    }
}
