import Foundation

// MARK: - Agent

struct Agent: Identifiable {
    let id: UUID
    let name: String
    let role: String
    let status: AgentStatus
    let currentTask: String?
    let lastActivity: Date
    let skills: [String]
    let avatarColor: String
}

extension Agent: Codable {}
extension Agent: Hashable {}

// MARK: - Agent Status

enum AgentStatus: String, Codable, CaseIterable {
    case online
    case busy
    case idle
    case offline
    case error

    var displayName: String {
        rawValue.capitalized
    }

    var isAvailable: Bool {
        self == .online || self == .idle
    }
}
