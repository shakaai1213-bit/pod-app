import Foundation

// AgentState is defined in Domain/Entities/Agents.swift (same module)


@Observable
final class AgentRepository {
    private let api = APIClient.shared
    private let cache = PersistenceController.shared

    var agents: [Agent] = []
    var isLoading: Bool = false
    var lastError: Error?

    private init() {}

    // MARK: - Load

    func loadAgents() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let response: PaginatedResponse<AgentDTO> = try await api.get(path: Endpoint.agents.path)
            let remote = response.items.map { dto -> Agent in
                Agent(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    role: dto.role ?? "Agent",
                    status: mapStatus(dto.status),
                    currentTask: dto.currentTask,
                    lastActivity: dto.lastSeenAt ?? Date(),
                    skills: dto.skills ?? [],
                    avatarColor: dto.avatarColor ?? "#3B82F6"
                )
            }
            agents = remote
            await cache.syncAgents(remote)
        } catch {
            lastError = error
            // Fall back to cache
            let cached = await MainActor.run { cache.fetchCachedAgents() }
            agents = cached.map { $0.toAgent() }
        }
    }

    // MARK: - Refresh Single Agent

    func refreshAgent(id: UUID) async {
        let path = Endpoint.agentStatus(agentId: id.uuidString).path
        guard let dto: AgentDTO = try? await api.get(path: path) else { return }

        let agent = Agent(
            id: UUID(uuidString: dto.id) ?? id,
            name: dto.name,
            role: dto.role ?? "Agent",
            status: mapStatus(dto.status),
            currentTask: dto.currentTask,
            lastActivity: dto.lastSeenAt ?? Date(),
            skills: dto.skills ?? [],
            avatarColor: dto.avatarColor ?? "#3B82F6"
        )

        if let index = agents.firstIndex(where: { $0.id == id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
        await cache.syncAgents([agent])
    }

    // MARK: - Queries

    func getAgent(id: UUID) -> Agent? {
        agents.first { $0.id == id }
    }

    func agentsByStatus(_ status: AgentState) -> [Agent] {
        agents.filter { $0.status == status }
    }

    // MARK: - Status Mapping

    /// Maps DTO AgentStatus (from AgentDTO) → Domain AgentState (from Agents.swift)
    private func mapStatus(_ dtoStatus: AgentStatus) -> AgentState {
        switch dtoStatus {
        case .online:  return .online
        case .busy:    return .busy
        case .idle:    return .idle
        case .offline: return .offline
        case .error:   return .error
        }
    }
}
