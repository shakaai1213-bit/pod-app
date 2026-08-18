import Foundation

public enum OrcaSurfaceSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case overview
    case conversations
    case work
    case workbench
    case fund
    case crew
    case knowledge
    case lab
    case runtime
    case maker

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .conversations: return "Conversations"
        case .work: return "Work"
        case .workbench: return "Workbench"
        case .fund: return "Fund"
        case .crew: return "Crew"
        case .knowledge: return "Knowledge"
        case .lab: return "Lab"
        case .runtime: return "Runtime"
        case .maker: return "Maker"
        }
    }

    public var subtitle: String {
        switch self {
        case .overview: return "Operating picture"
        case .conversations: return "Named-agent channels"
        case .work: return "Boards, projects, tickets, tasks, and approvals"
        case .workbench: return "Files, diffs, tests, workers, and evidence"
        case .fund: return "Protected read model"
        case .crew: return "Focus, load, plan, and dispatch"
        case .knowledge: return "Research and durable knowledge"
        case .lab: return "Products and systems"
        case .runtime: return "Services and infrastructure"
        case .maker: return "Skills and evaluations"
        }
    }

    public var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .conversations: return "bubble.left.and.bubble.right"
        case .work: return "square.stack.3d.up"
        case .workbench: return "hammer"
        case .fund: return "chart.line.uptrend.xyaxis"
        case .crew: return "person.3.sequence"
        case .knowledge: return "books.vertical"
        case .lab: return "flask"
        case .runtime: return "waveform.path.ecg"
        case .maker: return "wand.and.sparkles"
        }
    }

    public var isProtected: Bool { self == .fund }
}
