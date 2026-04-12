import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case dashboard
    case projects
    case chat
    case tickets
    case agents
    case knowledge
    case voice
    case trading

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .projects:  return "Projects"
        case .chat:      return "Chat"
        case .tickets:   return "Tickets"
        case .agents:    return "Agents"
        case .knowledge: return "Knowledge"
        case .voice:     return "Voice"
        case .trading:   return "Trading"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .projects:  return "rectangle.3.group.fill"
        case .chat:      return "bubble.left.and.bubble.right.fill"
        case .tickets:   return "ticket.fill"
        case .agents:    return "cpu.fill"
        case .knowledge: return "books.vertical.fill"
        case .voice:     return "waveform"
        case .trading:   return "chart.line.uptrend.xyaxis"
        }
    }
}
