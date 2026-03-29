import Foundation
import SwiftUI

// MARK: - Agent

struct Agent: Identifiable {
    var id: UUID
    var name: String
    var role: String
    var status: AgentState
    var currentTask: String?
    var lastActivity: Date?
    var skills: [String]
    var avatarColor: String?
}

extension Agent: Codable {}
extension Agent: Hashable {}

// MARK: - Agent Status

enum AgentState: String, Codable, CaseIterable {
    case online
    case busy
    case idle
    case offline
    case error
    case provisioning

    var displayName: String {
        switch self {
        case .provisioning: return "Provisioning"
        default: return rawValue.capitalized
        }
    }

    var isAvailable: Bool {
        self == .online || self == .idle
    }
}
