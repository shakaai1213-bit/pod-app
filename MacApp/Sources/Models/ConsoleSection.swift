import Foundation

enum ConsoleSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case conversations
    case work
    case fund
    case crew
    case knowledge
    case lab
    case runtime
    case maker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .conversations: return "Conversations"
        case .work: return "Work"
        case .fund: return "Fund"
        case .crew: return "Crew"
        case .knowledge: return "Knowledge"
        case .lab: return "Lab"
        case .runtime: return "Runtime"
        case .maker: return "Maker"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Operating picture"
        case .conversations: return "Named-agent channels"
        case .work: return "Boards, tickets, and approvals"
        case .fund: return "Protected read model"
        case .crew: return "Focus, load, plan, dispatch"
        case .knowledge: return "Research and durable knowledge"
        case .lab: return "Products and systems"
        case .runtime: return "Services and infrastructure"
        case .maker: return "Skills and evaluations"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .conversations: return "bubble.left.and.bubble.right"
        case .work: return "square.stack.3d.up"
        case .fund: return "chart.line.uptrend.xyaxis"
        case .crew: return "person.3.sequence"
        case .knowledge: return "books.vertical"
        case .lab: return "flask"
        case .runtime: return "waveform.path.ecg"
        case .maker: return "wand.and.sparkles"
        }
    }

    var isProtected: Bool { self == .fund }
}
