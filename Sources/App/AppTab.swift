import Foundation

// MARK: - App Tab

// L1 Layout Revamp 2026-W22 (SPEC-POD-LAYOUT-REVAMP-2026-W22):
// Visible tab bar: dashboard, chat, work, crew, library, lab, runtime
// Legacy cases (.captainsLog, .arms, .agents, .system) kept for deep-link and nav-state compat.
// They are not shown in the tab bar but remain routable.

enum AppTab: String, CaseIterable, Hashable {
    // MARK: Visible (7 tabs — ordered as shown in tab bar)
    case dashboard
    case chat
    case work
    case crew           // NEW — merges Agents + Arms+Team + Focus
    case knowledge
    case lab
    case runtime
    case maker
    case system         // folded into Runtime → Overview; kept routable during dwell

    // MARK: Legacy aliases (not in tab bar; kept for deep-link compat — 30-day dwell per spec)
    case captainsLog    // folded into Library → Notes
    case arms           // folded into Crew → Arms Dispatch
    case agents         // folded into Crew → Agents

    var title: String {
        switch self {
        case .dashboard:   return "Dashboard"
        case .chat:        return "Playground"
        case .work:        return "Work"
        case .crew:        return "Crew"
        case .knowledge:   return "Library"
        case .lab:         return "Lab"
        case .runtime:     return "Runtime"
        case .maker:       return "Maker"
        case .system:      return "System"
        // Legacy
        case .captainsLog: return "Captain's Log"
        case .arms:        return "Arms + Team"
        case .agents:      return "Agents"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:   return "house.fill"
        case .chat:        return "dot.radiowaves.left.and.right"
        case .work:        return "square.stack.3d.up.fill"
        case .crew:        return "person.3.sequence.fill"
        case .knowledge:   return "books.vertical.fill"
        case .lab:         return "flask.fill"
        case .runtime:     return "waveform.path.ecg"
        case .maker:       return "wand.and.sparkles"
        case .system:      return "server.rack"
        // Legacy (not shown in tab bar)
        case .captainsLog: return "square.and.pencil"
        case .arms:        return "person.3.sequence.fill"
        case .agents:      return "cpu.fill"
        }
    }
}
