import Foundation
import SwiftUI

// MARK: - Dashboard ViewModel

@Observable
final class DashboardViewModel {

    // MARK: - Published State

    var agents: [Agent] = []
    var activities: [ActivityItem] = []
    var attentionItems: [AttentionItem] = []
    var isLoading: Bool = false
    var error: String?

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

        activities = Self.mockActivities
        attentionItems = Self.mockAttentionItems

        isLoading = false
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

    // MARK: - Helpers

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
