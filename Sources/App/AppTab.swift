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
        case .dashboard: return "house.fill"
        case .projects: return "rectangle.3.group.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .knowledge: return "books.vertical.fill"
        case .agents: return "cpu.fill"
        case .wallDisplay: return "tv.fill"
        }
    }
}
