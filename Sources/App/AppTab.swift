import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case dashboard
    case runtime
    case chat
    case work          // replaces .tickets + .projects
    case captainsLog
    case lab           // product catalog
    case arms
    case agents
    case knowledge

    var title: String {
        switch self {
        case .dashboard:   return "Dashboard"
        case .runtime:     return "Runtime"
        case .chat:        return "Chat"
        case .work:        return "Work"
        case .captainsLog: return "Captain's Log"
        case .lab:         return "Lab"
        case .arms:        return "Arms"
        case .agents:      return "Agents"
        case .knowledge:   return "Knowledge"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:   return "house.fill"
        case .runtime:     return "waveform.path.ecg"
        case .chat:        return "bubble.left.and.bubble.right.fill"
        case .work:        return "square.stack.3d.up.fill"
        case .captainsLog: return "square.and.pencil"
        case .lab:         return "flask.fill"
        case .arms:        return "person.3.sequence.fill"
        case .agents:      return "cpu.fill"
        case .knowledge:   return "books.vertical.fill"
        }
    }
}
