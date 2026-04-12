import Foundation
import SwiftUI

// MARK: - Agent Profile Enrichment
// Backend /api/v1/agents returns minimal data (name, status, last_seen_at).
// Rich display fields (role, skills, avatarColor) come from here until the API grows.
// Keyed by lowercase name — matches ORCA MC agent names.

private let agentProfiles: [String: (role: String, skills: [String], avatarColor: String)] = [
    "maui":    (role: "Head of Engineering", skills: ["SwiftUI", "iOS", "Architecture", "Swift", "Xcode"], avatarColor: "#22C55E"),
    "chief":   (role: "Trading Lead",         skills: ["Trading", "Python", "Finance", "NATS", "Data Analysis"], avatarColor: "#F97316"),
    "aloha":   (role: "Communications",      skills: ["Messaging", "Coordination", "Discord", "Notifications"], avatarColor: "#A855F7"),
    "turtle":  (role: "Research",             skills: ["Analysis", "Research", "Experimentation", "Statistics"], avatarColor: "#3B82F6"),
    "aurora":  (role: "Architecture",        skills: ["Design", "Systems", "DDS", "Protocol Buffers"], avatarColor: "#F59E0B"),
]

// MARK: - Agents ViewModel

@Observable
final class AgentsViewModel {

    // MARK: - State

    var agents: [Agent] = []
    var selectedAgent: Agent?
    var isLoading: Bool = false
    var error: String?

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
            let response: PaginatedResponse<AgentDTO> = try await apiClient.request(.agents)
            agents = response.items.map { dto in
                let profile = agentProfiles[dto.name.lowercased()]
                return Agent(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    role: dto.role ?? profile?.role ?? "Agent",
                    status: AgentState(rawValue: dto.status.rawValue) ?? .offline,
                    currentTask: dto.currentTask ?? profile?.skills.first,
                    lastActivity: dto.lastSeenAt ?? Date(),
                    skills: dto.skills ?? profile?.skills ?? [],
                    avatarColor: dto.avatarColor ?? profile?.avatarColor ?? "#3B82F6"
                )
            }
        } catch {
            self.error = error.localizedDescription
            agents = Self.mockAgents
        }

        isLoading = false
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
        #if targetEnvironment(simulator)
        sseClient = LocalSSEClient(baseURL: "http://127.0.0.1:19002")
        #else
        sseClient = LocalSSEClient(baseURL: "http://100.76.196.40:8000")
        #endif
        sseClient?.connect(to: "/api/v1/events/agents") { [weak self] event in
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
        guard event.type == "agent.status" else { return }
        guard let agentIdString = event.data["agent_id"] as? String,
              let agentId = UUID(uuidString: agentIdString),
              let statusString = event.data["status"] as? String,
              let newStatus = AgentState(rawValue: statusString)
        else { return }

        if let index = agents.firstIndex(where: { $0.id == agentId }) {
            agents[index].status = newStatus
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
                role: "Head of Trading & Research",
                status: .busy,
                currentTask: "Running Octopus trading strategy",
                lastActivity: Date().addingTimeInterval(-60),
                skills: ["trading", "research", "python", "ml"],
                avatarColor: "#F59E0B"
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
                name: "Aurora",
                role: "Mission Control",
                status: .online,
                currentTask: "TICKET-003: Mock data sync",
                lastActivity: Date().addingTimeInterval(-30),
                skills: ["coordination", "architecture", "pm", "strategy"],
                avatarColor: "#A855F7"
            ),
            Agent(
                id: UUID(),
                name: "Luna",
                role: "Trading Intelligence (Chief's Mac)",
                status: .idle,
                currentTask: nil,
                lastActivity: Date().addingTimeInterval(-3600),
                skills: ["trading", "research", "analysis", "coordination"],
                avatarColor: "#06B6D4"
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

    func connect(to path: String, onEvent: @escaping (SSEEvent) -> Void) {
        self.onEvent = onEvent
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        guard let url = URL(string: "\(baseURL)\(path)") else { return }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity

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
