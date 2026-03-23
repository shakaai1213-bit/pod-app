import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case dashboard
    case projects
    case chat
    case knowledge
    case agents
    case wallDisplay

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .projects: return "Projects"
        case .chat: return "Chat"
        case .knowledge: return "Knowledge"
        case .agents: return "Agents"
        case .wallDisplay: return "Wall Display"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .projects: return "checklist"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .knowledge: return "book.fill"
        case .agents: return "person.3.fill"
        case .wallDisplay: return "tv.fill"
        }
    }
}
