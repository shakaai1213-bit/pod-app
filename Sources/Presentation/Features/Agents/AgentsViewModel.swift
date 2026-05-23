import Foundation
import SwiftUI

// MARK: - Agent Profile Enrichment
// Backend /api/v1/agents returns minimal data (name, status, last_seen_at).
// Rich display fields (role, skills, avatarColor) come from here until the API grows.
// Keyed by lowercase name — matches ORCA MC agent names.

private let agentProfiles: [String: (role: String, skills: [String], avatarColor: String)] = [
    "maui":    (role: "Head of Engineering", skills: ["SwiftUI", "iOS", "Architecture", "Swift", "Xcode"], avatarColor: "#22C55E"),
    "chief":   (role: "Protected Fund Lead",  skills: ["Trading Research", "Risk Review", "Python", "Finance", "Data Analysis"], avatarColor: "#22C55E"),
    "aloha":   (role: "Communications",      skills: ["Messaging", "Coordination", "Discord", "Notifications"], avatarColor: "#A855F7"),
    "coral":   (role: "Support Runtime",      skills: ["Watchdogs", "Daemons", "Runtime Health", "Observability"], avatarColor: "#06B6D4"),
    "reef":    (role: "Chief Mac Support",    skills: ["Mirrors", "Surfaces", "Watchdogs", "Chief Mac Support"], avatarColor: "#14B8A6"),
    "rooster": (role: "Security",             skills: ["Security", "Credentials", "Guardrails", "Chief Mac Protection"], avatarColor: "#EF4444"),
    "aurora":  (role: "Dormant Advisor",      skills: ["Jarvis Memory", "iMessage", "Coordination", "Historical Context"], avatarColor: "#F59E0B"),
    "shaka":   (role: "Dormant CEO Advisor",  skills: ["Vision", "Leadership", "Historical Context"], avatarColor: "#F97316"),
    "shaka-agent": (role: "Dormant CEO Advisor", skills: ["Vision", "Leadership", "Historical Context"], avatarColor: "#F97316"),
    "luna":    (role: "Dormant Fund Analyst", skills: ["Fund Analysis", "Research", "Historical Context"], avatarColor: "#6366F1"),
]

private struct AgentResponsibilityRegistryDTO: Decodable {
    let agents: [String: AgentResponsibilityProfileDTO]
}

private struct AgentResponsibilityProfileDTO: Decodable {
    let rosterLane: String?
    let defaultRoutingEnabled: Bool?
    let title: String?
    let summary: String?
    let owns: [String]
    let defaultWorkerLane: String?
    let protectedDomains: [String]

    enum CodingKeys: String, CodingKey {
        case title, summary, owns
        case rosterLane = "roster_lane"
        case defaultRoutingEnabled = "default_routing_enabled"
        case defaultWorkerLane = "default_worker_lane"
        case protectedDomains = "protected_domains"
    }
}

// MARK: - Agents ViewModel

@Observable
final class AgentsViewModel {

    // MARK: - State

    var agents: [Agent] = []
    var archivedAgents: [Agent] = []
    var selectedAgent: Agent?
    var isLoading: Bool = false
    var error: String?

    /// POD-5 (c797ada1): per-agent inbox tail (unread count + recent entries).
    /// Keyed by lowercased agent name to match the backend filesystem convention.
    var inboxTails: [String: InboxTailDTO] = [:]

    /// Read-only ORCA activation wake packet, keyed by normalized agent name.
    var activationContexts: [String: AgentActivationContextDTO] = [:]

    private(set) var sseClient: LocalSSEClient?

    // MARK: - Private

    private let apiClient: APIClient

    // MARK: - Init

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Load Agents

    @MainActor
    func loadAgents() async {
        isLoading = true
        error = nil

        do {
            let responsibilityRegistry: AgentResponsibilityRegistryDTO? = try? await apiClient.get(path: "/api/v1/agent-responsibilities")
            let response: PaginatedResponse<AgentDTO> = try await apiClient.request(.agents)
            let mappedAgents = response.items.map { dto in
                let key = dto.name.lowercased()
                let profile = agentProfiles[key]
                let responsibility = responsibilityRegistry?.agents[key]
                let responsibilitySkills = Self.skills(from: responsibility)
                let role = dto.role.isEmpty || dto.role == "Agent"
                    ? (responsibility?.title ?? profile?.role ?? "Agent")
                    : dto.role
                let skills = dto.skills.isEmpty ? (responsibilitySkills.isEmpty ? (profile?.skills ?? []) : responsibilitySkills) : dto.skills
                let rosterLane = Self.rosterLane(from: responsibility) ?? dto.domainRosterLane
                return Agent(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    role: role,
                    status: AgentState(rawValue: dto.status.rawValue) ?? .offline,
                    currentTask: dto.currentTask ?? responsibility?.summary ?? profile?.skills.first,
                    lastActivity: dto.lastSeenAt ?? Date(),
                    skills: skills,
                    avatarColor: dto.avatarColor ?? profile?.avatarColor ?? "#3B82F6",
                    rosterLane: rosterLane,
                    isDefaultRoutingEnabled: dto.isDefaultRoutingEnabled ?? responsibility?.defaultRoutingEnabled ?? !AgentRosterPolicy.isDormantOrArchived(dto.name),
                    quarantineState: dto.quarantineState,
                    rosterNote: dto.rosterNote
                )
            }
            agents = AgentRosterPolicy.filterActive(mappedAgents)
            archivedAgents = AgentRosterPolicy.filterDormant(mappedAgents)
        } catch {
            self.error = error.localizedDescription
            agents = []
            archivedAgents = []
        }

        isLoading = false
    }

    private static func skills(from responsibility: AgentResponsibilityProfileDTO?) -> [String] {
        guard let responsibility else { return [] }
        let owned = responsibility.owns
            .prefix(5)
            .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        let protected = responsibility.protectedDomains
            .prefix(2)
            .map { "Protected: " + $0.replacingOccurrences(of: "_", with: " ").capitalized }
        let worker = responsibility.defaultWorkerLane.map { ["Worker: \($0)"] } ?? []
        return Array(owned + protected + worker)
    }

    private static func rosterLane(from responsibility: AgentResponsibilityProfileDTO?) -> AgentRosterLane? {
        guard let raw = responsibility?.rosterLane else { return nil }
        return AgentRosterLane(rawValue: raw)
    }

    // MARK: - POD-5: Inbox Tail (c797ada1)

    /// Fetch the non-destructive inbox tail for a single agent. Updates
    /// `inboxTails[name.lowercased()]`. Best-effort — swallows errors so a
    /// missing/offline agent inbox doesn't break the agents view.
    @MainActor
    func loadInboxTail(for agentName: String, limit: Int = 20) async {
        let key = agentName.lowercased()
        do {
            let dto: InboxTailDTO = try await apiClient.request(
                .agentInboxTail(name: key, limit: limit)
            )
            inboxTails[key] = dto
        } catch {
            // Soft fail — support lanes may not have a local inbox yet. Do not
            // surface this to the user.
        }
    }

    /// Fetch tails for all currently-loaded agents in parallel. Call after
    /// `loadAgents()` from the AgentsView .task.
    @MainActor
    func loadAllInboxTails(limit: Int = 20) async {
        await withTaskGroup(of: Void.self) { group in
            for agent in agents {
                group.addTask { [weak self] in
                    await self?.loadInboxTail(for: agent.name, limit: limit)
                }
            }
        }
    }

    /// Convenience for views: how many unread for this agent?
    func unreadCount(for agentName: String) -> Int {
        inboxTails[agentName.lowercased()]?.unreadEntries ?? 0
    }

    // MARK: - Activation Context

    @MainActor
    func loadActivationContext(for agentName: String, limit: Int = 10) async {
        let key = AgentRosterPolicy.normalizedName(agentName)
        do {
            let dto: AgentActivationContextDTO = try await apiClient.request(
                .agentActivationContext(name: key, limit: limit)
            )
            activationContexts[key] = dto
        } catch {
            // Soft fail: detail surfaces can show their own unavailable state.
        }
    }

    // MARK: - Update Agent Status

    @MainActor
    func updateAgentState(_ agentId: UUID, _ newStatus: AgentState) async {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else { return }

        // Optimistic update
        agents[index].status = newStatus

        do {
            let body = AgentStateUpdateRequest(status: newStatus.rawValue)
            let _: AgentDTO = try await apiClient.request(
                .agentStatus(agentId: agentId.uuidString),
                body: body
            )
        } catch {
            // Revert on failure — reload from server
            await loadAgents()
        }
    }

    // MARK: - Pause Agent

    @MainActor
    func pauseAgent(_ agentId: UUID) async {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else { return }
        agents[index].status = .idle
    }

    // MARK: - Restart Agent

    @MainActor
    func restartAgent(_ agentId: UUID) async {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else { return }
        agents[index].status = .busy
        // Simulate startup delay then go online
        await TaskSafeSleep.sleep(seconds: 2)
        if let i = agents.firstIndex(where: { $0.id == agentId }) {
            agents[i].status = .online
        }
    }

    // MARK: - SSE Subscription

    func subscribeToAgentState() {
        // d87ed975: fix dead /events/agents → real /agents/stream endpoint
        let token = UserDefaults.standard.string(forKey: "orca_auth_token") ?? ""
        #if targetEnvironment(simulator)
        sseClient = LocalSSEClient(baseURL: "http://127.0.0.1:19002")
        #else
        sseClient = LocalSSEClient(baseURL: "http://100.76.196.40:8000")
        #endif
        sseClient?.connect(to: "/api/v1/agents/stream", token: token) { [weak self] event in
            Task { @MainActor in
                self?.onAgentStateUpdate(event)
            }
        }
    }

    func disconnectSSE() {
        sseClient?.disconnect()
        sseClient = nil
    }

    // MARK: - SSE Event Handler

    @MainActor
    func onAgentStateUpdate(_ event: SSEEvent) {
        // d87ed975: backend /agents/stream emits event:"agent" with data:{"agent":{id,status,...}}
        guard event.type == "agent" else { return }
        guard let agentPayload = event.data["agent"] as? [String: Any],
              let agentIdString = agentPayload["id"] as? String,
              let agentId = UUID(uuidString: agentIdString),
              let statusString = agentPayload["status"] as? String,
              let newStatus = AgentState(rawValue: statusString)
        else { return }

        if let index = agents.firstIndex(where: { $0.id == agentId }) {
            agents[index].status = newStatus
        } else if let agentName = agentPayload["name"] as? String,
                  AgentRosterPolicy.isActiveOrSupport(agentName) || AgentRosterPolicy.isDormantOrArchived(agentName) {
            Task {
                await loadAgents()
            }
        }
    }

    // MARK: - Computed Properties

    var onlineAgents: [Agent] {
        agents.filter { $0.status == .online || $0.status == .busy }
    }

    var onlineCount: Int {
        agents.filter { $0.status == .online || $0.status == .busy }.count
    }

    func agents(matching query: String) -> [Agent] {
        guard !query.isEmpty else { return agents }
        let lowercased = query.lowercased()
        return agents.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.role.lowercased().contains(lowercased) ||
            $0.skills.contains { $0.lowercased().contains(lowercased) }
        }
    }

    func archivedAgents(matching query: String) -> [Agent] {
        guard !query.isEmpty else { return archivedAgents }
        let lowercased = query.lowercased()
        return archivedAgents.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.role.lowercased().contains(lowercased) ||
            ($0.rosterNote ?? "").lowercased().contains(lowercased) ||
            $0.skills.contains { $0.lowercased().contains(lowercased) }
        }
    }

    // MARK: - Mock Data

    private static var mockAgents: [Agent] {
        [
            Agent(
                id: UUID(),
                name: "Maui",
                role: "Engineering Lead",
                status: .online,
                currentTask: "TICKET-001: Voice Companion Tab",
                lastActivity: Date().addingTimeInterval(-120),
                skills: ["swift", "swiftui", "ios", "architecture"],
                avatarColor: "#3B82F6"
            ),
            Agent(
                id: UUID(),
                name: "Chief",
                role: "Protected Fund Lead",
                status: .idle,
                currentTask: "Chief/Fund work is read-only until reviewed",
                lastActivity: Date().addingTimeInterval(-60),
                skills: ["trading research", "risk review", "python", "finance"],
                avatarColor: "#22C55E"
            ),
            Agent(
                id: UUID(),
                name: "Aloha",
                role: "Communications Lead",
                status: .online,
                currentTask: nil,
                lastActivity: Date().addingTimeInterval(-300),
                skills: ["comms", "documentation", "standards", "nats"],
                avatarColor: "#22C55E"
            ),
            Agent(
                id: UUID(),
                name: "Coral",
                role: "Support Runtime",
                status: .idle,
                currentTask: "Watching Shaka Mac runtime health",
                lastActivity: Date().addingTimeInterval(-30),
                skills: ["watchdogs", "daemons", "observability"],
                avatarColor: "#06B6D4"
            ),
            Agent(
                id: UUID(),
                name: "Reef",
                role: "Chief Mac Support",
                status: .idle,
                currentTask: "Chief Mac support lane only",
                lastActivity: Date().addingTimeInterval(-3600),
                skills: ["mirrors", "watchdogs", "surfaces"],
                avatarColor: "#14B8A6"
            ),
        ]
    }
}

// MARK: - SSE Event

struct SSEEvent {
    let type: String
    let data: [String: Any]

    init?(from raw: String) {
        // Simple SSE parser — handles "event: type" and "data: {json}" lines
        var eventType: String?
        var eventData: [String: Any]?

        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("event:") {
                eventType = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if let jsonData = jsonString.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    eventData = parsed
                }
            }
        }

        guard let type = eventType else { return nil }
        self.type = type
        self.data = eventData ?? [:]
    }
}

// MARK: - SSE Client

final class LocalSSEClient: NSObject, URLSessionDataDelegate {
    private let baseURL: String
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var onEvent: ((SSEEvent) -> Void)?

    init(baseURL: String) {
        self.baseURL = baseURL
        super.init()
    }

    func connect(to path: String, token: String = "", onEvent: @escaping (SSEEvent) -> Void) {
        self.onEvent = onEvent
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        guard let url = URL(string: "\(baseURL)\(path)") else { return }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        task = session.dataTask(with: request)
        task?.resume()
    }

    func disconnect() {
        task?.cancel()
        session?.invalidateAndCancel()
        session = nil
        task = nil
        onEvent = nil
    }

    private var buffer = ""

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk

        // Process complete events (double newline delimited)
        let events = buffer.components(separatedBy: "\n\n")
        for event in events.dropLast() {
            if let parsed = SSEEvent(from: event) {
                onEvent?(parsed)
            }
        }
        buffer = events.last ?? ""
    }
}

// MARK: - Agent Status Update Request

private struct AgentStateUpdateRequest: Encodable {
    let status: String
}

// MARK: - APIClient Extended Request

extension APIClient {
    /// Request with a body (POST/PUT)
    func request<T: Decodable>(
        _ endpoint: Endpoint,
        body: some Encodable
    ) async throws -> T {
        let request = try buildRequest(path: endpoint.path, method: endpoint.method.rawValue, body: body)
        return try await perform(request)
    }

    /// Request without a body (GET/DELETE)
    func request<T: Decodable>(
        _ endpoint: Endpoint
    ) async throws -> T {
        let request = try buildRequest(path: endpoint.path, method: endpoint.method.rawValue)
        return try await perform(request)
    }
}
