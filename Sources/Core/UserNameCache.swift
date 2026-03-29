import Foundation

/// Caches user and agent names for display in chat.
/// Fetches current user from /users/me and agents from /agents on first access.
actor UserNameCache {
    static let shared = UserNameCache()

    private var userNames: [String: String] = [:]  // userId → name
    private var agentNames: [String: String] = [:]  // agentId → name
    private var currentUserName: String?
    private var isLoaded = false

    private init() {}

    /// Load current user and agent names from backend
    func load() async {
        guard !isLoaded else { return }

        // Load current user
        do {
            let user: UserDTO = try await APIClient.shared.get(path: "/api/v1/users/me")
            userNames[user.id] = user.preferredName ?? user.name
            currentUserName = user.preferredName ?? user.name
        } catch {
            print("[UserNameCache] Failed to load user: \(error)")
        }

        // Load agents
        do {
            let response: PaginatedResponse<AgentDTO> = try await APIClient.shared.get(path: "/api/v1/agents")
            for agent in response.items {
                agentNames[agent.id] = agent.name
                // Also cache as user (some messages come from agents with user IDs)
                userNames[agent.id] = agent.name
            }
        } catch {
            print("[UserNameCache] Failed to load agents: \(error)")
        }

        isLoaded = true
    }

    /// Resolve a sender user ID to a display name
    func displayName(userId: String, agentId: String?) -> String {
        // Agent messages优先
        if let agentId = agentId, let name = agentNames[agentId] {
            return name
        }
        if let name = userNames[userId] {
            return name
        }
        // Fallback
        if userId == currentUserName {
            return currentUserName ?? "You"
        }
        return "Unknown"
    }

    /// Get current user's display name
    var me: String {
        currentUserName ?? "Me"
    }
}
