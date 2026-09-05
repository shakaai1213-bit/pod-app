import Foundation
import OrcaDomain

// MARK: - App Tab

// L1 Layout Revamp 2026-W22 (SPEC-POD-LAYOUT-REVAMP-2026-W22):
// Visible tab bar: dashboard, workbench, fund, crew, library, lab, runtime, maker
// Legacy cases (.captainsLog, .arms, .agents, .system) kept for deep-link and nav-state compat.
// They are not shown in the tab bar but remain routable.

enum AppTab: String, CaseIterable, Hashable {
    // MARK: Visible (8 tabs — ordered as shown in tab bar)
    case dashboard
    case chat           // legacy Pod Chat alias; normalized to Work and never shown
    case work
    case fund           // protected read-only Fund cockpit, sourced through ORCA
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
        case .dashboard:   return OrcaSurfaceSection.overview.title
        case .chat:        return "Pod Chat"
        case .work:        return OrcaSurfaceSection.work.title
        case .fund:        return OrcaSurfaceSection.fund.title
        case .crew:        return OrcaSurfaceSection.crew.title
        case .knowledge:   return OrcaSurfaceSection.knowledge.title
        case .lab:         return OrcaSurfaceSection.lab.title
        case .runtime:     return OrcaSurfaceSection.runtime.title
        case .maker:       return OrcaSurfaceSection.maker.title
        case .system:      return OrcaSurfaceSection.runtime.title
        // Legacy
        case .captainsLog: return "Captain's Log"
        case .arms:        return "Arms + Team"
        case .agents:      return "Agents"
        }
    }

    var tabBarTitle: String {
        switch self {
        case .dashboard: return "Home"
        case .chat:      return "Chat"
        case .work:      return "Work"
        default:         return title
        }
    }

    var icon: String {
        switch self {
        case .dashboard:   return OrcaSurfaceSection.overview.symbol
        case .chat:        return "bubble.left.and.bubble.right.fill"
        case .work:        return OrcaSurfaceSection.work.symbol
        case .fund:        return OrcaSurfaceSection.fund.symbol
        case .crew:        return OrcaSurfaceSection.crew.symbol
        case .knowledge:   return OrcaSurfaceSection.knowledge.symbol
        case .lab:         return OrcaSurfaceSection.lab.symbol
        case .runtime:     return OrcaSurfaceSection.runtime.symbol
        case .maker:       return OrcaSurfaceSection.maker.symbol
        case .system:      return OrcaSurfaceSection.runtime.symbol
        // Legacy (not shown in tab bar)
        case .captainsLog: return "square.and.pencil"
        case .arms:        return "person.3.sequence.fill"
        case .agents:      return "cpu.fill"
        }
    }
}
