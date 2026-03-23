import Foundation

// MARK: - Navigation State

enum NavigationState: Equatable {
    case dashboard
    case chat(channelId: UUID?)
    case projects(taskId: UUID?)
    case knowledge(standardId: UUID?)
    case agents(agentId: UUID?)
    case settings

    static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        switch (lhs, rhs) {
        case (.dashboard, .dashboard): return true
        case let (.chat(a), .chat(b)): return a == b
        case let (.projects(a), .projects(b)): return a == b
        case let (.knowledge(a), .knowledge(b)): return a == b
        case let (.agents(a), .agents(b)): return a == b
        case (.settings, .settings): return true
        default: return false
        }
    }
}
