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

    // MARK: - Init

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Load

    @MainActor
    func loadDashboard() async {
        isLoading = true
        error = nil

        do {
            let agentDTOs: [AgentDTO] = try await apiClient.request(.agents)
            agents = agentDTOs.map { dto in
                Agent(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    role: dto.role,
                    status: AgentStatus(rawValue: dto.status.rawValue) ?? .offline,
                    currentTask: dto.currentTask,
                    lastActivity: dto.lastActivity ?? Date(),
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
                actorName: "Kai",
                isActorAgent: true
            ),
            ActivityItem(
                type: .messageSent,
                description: "Posted weekly status update in #general",
                timestamp: now.addingTimeInterval(-900),
                actorName: "Nova",
                isActorAgent: true
            ),
            ActivityItem(
                type: .agentMilestone,
                description: "Orca deployed v2.3.1 to staging",
                timestamp: now.addingTimeInterval(-1800),
                actorName: "Orca",
                isActorAgent: true
            ),
            ActivityItem(
                type: .taskCreated,
                description: "Created task: Implement auth token refresh",
                timestamp: now.addingTimeInterval(-3600),
                actorName: "Shaka",
                isActorAgent: false
            ),
            ActivityItem(
                type: .fileUploaded,
                description: "Uploaded architecture_diagram_v3.pdf",
                timestamp: now.addingTimeInterval(-7200),
                actorName: "Pulse",
                isActorAgent: true
            ),
        ]
    }

    private static var mockAttentionItems: [AttentionItem] {
        [
            AttentionItem(
                type: .blockedTask,
                title: "Auth token refresh blocked",
                subtitle: "Waiting on backend API changes",
                severity: .warning
            ),
            AttentionItem(
                type: .pendingApproval,
                title: "PR #41 pending review",
                subtitle: "From Kai · 3h ago",
                severity: .warning
            ),
            AttentionItem(
                type: .agentError,
                title: "Beacon encountered an error",
                subtitle: "Knowledge base indexing failed",
                severity: .critical
            ),
        ]
    }
}
