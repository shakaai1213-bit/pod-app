import Foundation

// Resolve name collisions: Domain entities and DTOs both define AgentStatus
typealias DomainAgentStatus = Domain.Entities.AgentStatus

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
            let dtos: [AgentDTO] = try await api.get(Endpoint.agents.path)
            let remote = dtos.map { dto -> Agent in
                Agent(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    role: dto.role,
                    status: mapStatus(dto.status),
                    currentTask: dto.currentTask,
                    lastActivity: dto.lastActivity ?? Date(),
                    skills: dto.skills,
                    avatarColor: dto.avatarColor ?? "3B82F6"
                )
            }
            agents = remote
            await cache.syncAgents(remote)
        } catch {
            lastError = error
            // Fall back to cache
            let cached = cache.fetchCachedAgents()
            agents = cached.map { $0.toAgent() }
        }
    }

    // MARK: - Refresh Single Agent

    func refreshAgent(id: UUID) async {
        let path = Endpoint.agentStatus(agentId: id.uuidString).path
        guard let dto: AgentDTO = try? await api.get(path) else { return }

        let agent = Agent(
            id: UUID(uuidString: dto.id) ?? id,
            name: dto.name,
            role: dto.role,
            status: mapStatus(dto.status),
            currentTask: dto.currentTask,
            lastActivity: dto.lastActivity ?? Date(),
            skills: dto.skills,
            avatarColor: dto.avatarColor ?? "3B82F6"
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

    func agentsByStatus(_ status: AgentStatus) -> [Agent] {
        agents.filter { $0.status == status }
    }

    // MARK: - Status Mapping

    /// Maps DTO AgentStatus (from AgentDTO) → Domain AgentStatus (from Agents.swift)
    private func mapStatus(_ dtoStatus: AgentStatus) -> AgentStatus {
        switch dtoStatus {
        case .online:  return .online
        case .busy:    return .busy
        case .idle:    return .idle
        case .offline: return .offline
        case .error:   return .error
        }
    }
}
