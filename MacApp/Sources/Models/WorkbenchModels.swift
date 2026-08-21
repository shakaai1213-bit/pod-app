import Foundation

enum WorkbenchPane: String, CaseIterable, Identifiable {
    case workspace
    case files
    case diff
    case tests
    case terminal
    case workers
    case evidence
    case approvals

    static let minimumBarWidth: CGFloat = 520
    static let minimumControlWidth: CGFloat = 60

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .files: return "Files"
        case .diff: return "Diff"
        case .tests: return "Tests"
        case .terminal: return "Terminal"
        case .workers: return "Workers"
        case .evidence: return "Evidence"
        case .approvals: return "Approvals"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: return "folder"
        case .files: return "doc.text"
        case .diff: return "arrow.left.arrow.right"
        case .tests: return "checkmark.circle"
        case .terminal: return "terminal"
        case .workers: return "person.2"
        case .evidence: return "checkmark.seal"
        case .approvals: return "signature"
        }
    }
}

struct WorkbenchTicketSummary: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let status: String
    let flowState: String?
    let priority: String?
    let nextAction: String?
}
