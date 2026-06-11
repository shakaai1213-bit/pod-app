import Foundation
import UIKit

// MARK: - Wall Display ViewModel

@Observable
final class WallDisplayViewModel {

    // MARK: - State

    var agents: [Agent] = []
    var activities: [ActivityItem] = []
    var attentionCount: Int = 0
    var isDimmed: Bool = false
    var brightness: Double = 1.0
    var currentTime: Date = Date()
    var dataSourceLabel: String = "ORCA"
    var dataSourceMessage: String = "Wall Display is backed by ORCA agents and tickets."

    // MARK: - Private

    private var timeTimer: Timer?
    private var refreshTimer: Timer?
    private var dimTimer: Timer?
    private var lastActivityTime: Date = Date()
    private var originalBrightness: CGFloat = 1.0

    private let dimDelaySeconds: TimeInterval = 300 // 5 minutes
    private let refreshIntervalSeconds: TimeInterval = 60

    // MARK: - Init

    init() {
        startClock()
    }

    deinit {
        timeTimer?.invalidate()
        refreshTimer?.invalidate()
        dimTimer?.invalidate()
        restoreBrightness()
    }

    // MARK: - Load

    @MainActor
    func loadAll() async {
        await fetchAgents()
        await fetchActivities()
        await fetchAttentionCount()
        resetDimTimer()
    }

    // MARK: - Refresh

    @MainActor
    func refresh() async {
        await fetchActivities()
        await fetchAttentionCount()
        await fetchAgents()
    }

    // MARK: - Dim / Wake

    func dim() {
        guard !isDimmed else { return }
        originalBrightness = UIScreen.main.brightness
        isDimmed = true
        brightness = 0.3
        UIScreen.main.brightness = CGFloat(brightness)
    }

    func wake() {
        guard isDimmed else { return }
        isDimmed = false
        brightness = 1.0
        UIScreen.main.brightness = CGFloat(brightness)
        resetDimTimer()
    }

    func recordActivity() {
        resetDimTimer()
        if isDimmed {
            wake()
        }
    }

    // MARK: - Private: Fetch

    @MainActor
    private func fetchAgents() async {
        do {
            let response: WallListResponse<AgentDTO> = try await APIClient.shared.get(path: "/api/v1/agents?status=active,support&limit=50")
            agents = response.items.map(Self.agent(from:))
            dataSourceLabel = "ORCA"
            dataSourceMessage = "Wall Display is backed by ORCA agents and tickets."
        } catch {
            agents = []
            dataSourceLabel = "ORCA ERROR"
            dataSourceMessage = "ORCA agents are unavailable. Wall Display is not showing snapshot agents."
        }
    }

    @MainActor
    private func fetchActivities() async {
        do {
            let response: WallListResponse<WallTicketDTO> = try await APIClient.shared.get(path: "/api/v1/tickets?status=open&limit=12")
            activities = response.items
                .sorted { Self.priorityRank($0.priority) < Self.priorityRank($1.priority) }
                .map(Self.activity(from:))
            dataSourceLabel = "ORCA"
            dataSourceMessage = "Wall Display is backed by ORCA agents and tickets."
        } catch {
            activities = []
            dataSourceLabel = "ORCA ERROR"
            dataSourceMessage = "ORCA tickets are unavailable. Wall Display is not showing snapshot activity."
        }
    }

    @MainActor
    private func fetchAttentionCount() async {
        do {
            let response: WallListResponse<WallTicketDTO> = try await APIClient.shared.get(path: "/api/v1/tickets?status=open&limit=200")
            attentionCount = response.items.filter { ticket in
                let priority = ticket.priority.lowercased()
                let status = ticket.status.lowercased()
                return priority == "urgent" || priority == "high" || status == "blocked" || status == "waiting_human"
            }.count
        } catch {
            attentionCount = 0
        }
    }

    // MARK: - Private: Clock

    private func startClock() {
        timeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = Date()
            }
        }
    }

    // MARK: - Private: Dim Timer

    private func resetDimTimer() {
        lastActivityTime = Date()
        dimTimer?.invalidate()
        guard !isDimmed else { return }
        dimTimer = Timer.scheduledTimer(withTimeInterval: dimDelaySeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dim()
            }
        }
    }

    // MARK: - Private: Restore Brightness

    private func restoreBrightness() {
        UIScreen.main.brightness = originalBrightness
    }

    // MARK: - ORCA Mapping

    private static func agent(from dto: AgentDTO) -> Agent {
        Agent(
            id: UUID(uuidString: dto.id) ?? UUID(),
            name: dto.name,
            role: dto.role,
            status: agentState(from: dto.status),
            currentTask: dto.currentTask,
            lastActivity: dto.lastSeenAt,
            skills: dto.skills,
            avatarColor: dto.avatarColor ?? "#3B82F6",
            rosterLane: dto.domainRosterLane,
            isDefaultRoutingEnabled: dto.isDefaultRoutingEnabled,
            quarantineState: dto.quarantineState,
            rosterNote: dto.rosterNote
        )
    }

    private static func agentState(from status: AgentStatus) -> AgentState {
        switch status {
        case .online: return .online
        case .active: return .online
        case .busy: return .busy
        case .idle: return .idle
        case .offline: return .offline
        case .error: return .error
        case .provisioning: return .provisioning
        }
    }

    private static func activity(from ticket: WallTicketDTO) -> ActivityItem {
        let owner = ticket.assigneeAgentId?.isEmpty == false ? "agent \(ticket.assigneeAgentId!.prefix(6))" : "ORCA"
        let type: ActivityType = ticket.status.lowercased() == "done" ? .taskCompleted : .taskCreated
        return ActivityItem(
            type: type,
            description: "\(ticket.priority.uppercased()) ticket: \(ticket.title)",
            timestamp: ticket.updatedAt ?? ticket.createdAt ?? Date(),
            actor: owner,
            isAgent: ticket.assigneeAgentId != nil
        )
    }

    private static func priorityRank(_ priority: String) -> Int {
        switch priority.lowercased() {
        case "urgent": return 0
        case "high": return 1
        case "medium": return 2
        case "low": return 3
        default: return 9
        }
    }
}

private struct WallListResponse<Item: Decodable>: Decodable {
    let items: [Item]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let values = try? container.decode([Item].self) {
            items = values
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? container.decode([Item].self, forKey: .items))
            ?? (try? container.decode([Item].self, forKey: .results))
            ?? (try? container.decode([Item].self, forKey: .data))
            ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case results
        case data
    }
}

private struct WallTicketDTO: Decodable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let assigneeAgentId: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case priority
        case assigneeAgentId = "assignee_agent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
