import SwiftUI

// MARK: - Lab Content
//
// Hardcoded mirror of Team-Wiki/operating-system/LAB-SYSTEMS-INDEX.md per SPEC-POD-LAB-TAB-2026-05-23 §13.
// Pre-M-005 v2 first-ship path: structured constant.
// When M-005 v2 ships GET /api/v1/lab/sections, replace `LabContent.load()` with a fetch — signature stable.

enum LabStatus: String {
    case live
    case building
    case partial
    case planned
    case retired

    var emoji: String {
        switch self {
        case .live:     return "🟢"
        case .building: return "🟡"
        case .partial:  return "🟠"
        case .planned:  return "🔴"
        case .retired:  return "⚫"
        }
    }

    var label: String {
        switch self {
        case .live:     return "LIVE"
        case .building: return "BUILDING"
        case .partial:  return "PARTIAL"
        case .planned:  return "PLANNED"
        case .retired:  return "RETIRED"
        }
    }

    var color: Color {
        switch self {
        case .live:     return AppColors.accentSuccess
        case .building: return AppColors.accentWarning
        case .partial:  return AppColors.accentCaptain
        case .planned:  return AppColors.accentDanger
        case .retired:  return AppColors.textTertiary
        }
    }
}

struct LabStackLayer: Identifiable {
    let id: String
    let title: String
    let oneLine: String
    let status: LabStatus
    let owner: String       // 3-letter chip e.g. "MAU"
    let icon: String        // SF Symbol
    let tint: Color
}

struct LabFish: Identifiable {
    let id: String
    let emoji: String
    let name: String
    let role: String
    let status: LabStatus
}

struct LabSpinningItem: Identifiable {
    let id = UUID()
    let title: String
    let stage: String       // loop position
    let owner: String
}

struct LabRetiredItem: Identifiable {
    let id = UUID()
    let name: String
    let reason: String
}

struct LabBuildingItem: Identifiable {
    let id = UUID()
    let title: String
    let stage: String
    let owner: String
    let shortId: String
}

// MARK: - Static content (hand-mirror until M-005 v2)

enum LabContent {

    static let stack: [LabStackLayer] = [
        LabStackLayer(
            id: "team-wiki",
            title: "Team-Wiki",
            oneLine: "Doctrine vault · markdown · git-backed · both Macs",
            status: .live,
            owner: "ALO",
            icon: "books.vertical.fill",
            tint: AppColors.accentAgent
        ),
        LabStackLayer(
            id: "orca",
            title: "ORCA (Mission Control)",
            oneLine: "Backend control plane · ~250 endpoints · truth layer",
            status: .live,
            owner: "MAU",
            icon: "server.rack",
            tint: AppColors.accentElectric
        ),
        LabStackLayer(
            id: "pod",
            title: "Pod",
            oneLine: "Tony's iPad/iPhone cockpit · SwiftUI · 8 tabs",
            status: .building,
            owner: "MAU",
            icon: "ipad.landscape",
            tint: AppColors.accentElectric
        ),
        LabStackLayer(
            id: "compute",
            title: "Compute",
            oneLine: "Spark + Kimi + Claude · routed by tier",
            status: .live,
            owner: "MAU",
            icon: "cpu.fill",
            tint: AppColors.accentSuccess
        ),
        LabStackLayer(
            id: "memory",
            title: "Memory",
            oneLine: "Daily logs · ORCA Notes · Chroma · candidate review",
            status: .partial,
            owner: "ALO",
            icon: "brain",
            tint: AppColors.accentCaptain
        ),
        LabStackLayer(
            id: "schoolhouse",
            title: "Schoolhouse",
            oneLine: "Agent operating loop · intent → triage → ORCA → evidence",
            status: .partial,
            owner: "MAU",
            icon: "graduationcap.fill",
            tint: AppColors.accentCaptain
        )
    ]

    static let agents: [LabFish] = [
        LabFish(id: "aloha",   emoji: "🌸", name: "Aloha",   role: "Backbone · Nerve · Coordinator",    status: .live),
        LabFish(id: "maui",    emoji: "🪝", name: "Maui",    role: "Engineering · ORCA · Pod",          status: .live),
        LabFish(id: "chief",   emoji: "🦅", name: "Chief",   role: "Fund · trading · protected",        status: .live),
        LabFish(id: "rooster", emoji: "🐓", name: "Rooster", role: "Security · credentials · tools",    status: .live),
        LabFish(id: "coral",   emoji: "🪸", name: "Coral",   role: "Shaka-Mac runtime · daemons",       status: .live),
        LabFish(id: "reef",    emoji: "🐡", name: "Reef",    role: "Chief-Mac runtime · daemons",       status: .live)
    ]

    static let workers: [LabFish] = [
        LabFish(id: "merman",  emoji: "🧜‍♂️", name: "Merman",  role: "Triage classifier",                status: .live),
        LabFish(id: "mermaid", emoji: "🧜‍♀️", name: "Mermaid", role: "Bounded worker (V2 dry-run)",      status: .partial),
        LabFish(id: "turtle",  emoji: "🐢",   name: "Turtle",  role: "Research · slow + thorough",       status: .live),
        LabFish(id: "miner",   emoji: "⛏️",   name: "Miner",   role: "Data extract · structured pulls",  status: .live),
        LabFish(id: "pearl",   emoji: "🦪",   name: "Pearl",   role: "Audit · Maui-only doctrine check", status: .live)
    ]

    static let compute: [LabFish] = [
        LabFish(id: "spark",  emoji: "✨", name: "Spark",  role: "Local LLM · short-route default", status: .live),
        LabFish(id: "kimi",   emoji: "🌊", name: "Kimi",   role: "Frontier premium · no-fallback",  status: .live),
        LabFish(id: "claude", emoji: "🧠", name: "Claude", role: "Per-agent reasoning runtime",     status: .live)
    ]

    /// Flywheel loop nodes, in order. Static rendering for v1 (no animation).
    static let flywheelNodes: [String] = [
        "Captured", "Assessment", "Experiment", "Evidence", "Decision", "Doctrine"
    ]

    static let currentlySpinning: [LabSpinningItem] = [
        LabSpinningItem(title: "Mermaid V2 bounded executor",         stage: "Experiment", owner: "MAU"),
        LabSpinningItem(title: "Pod tab redesign",                    stage: "Experiment", owner: "MAU"),
        LabSpinningItem(title: "Knowledge Center auto-surface (M-005 v2)", stage: "Experiment", owner: "MAU"),
        LabSpinningItem(title: "Duplicate-detection watchdog",        stage: "Evidence",   owner: "ALO")
    ]

    static let currentlyBuilding: [LabBuildingItem] = [
        LabBuildingItem(title: "Schoolhouse Transition Closeout",         stage: "Active",   owner: "ALO", shortId: "bbc62861"),
        LabBuildingItem(title: "Pod Tab Redesign (Work + Captain's Log)", stage: "Active",   owner: "MAU", shortId: "spec-tabs"),
        LabBuildingItem(title: "Board-folds-into-Project ADR",            stage: "Scoping",  owner: "MAU", shortId: "adr-bf"),
        LabBuildingItem(title: "Project Lifecycle Standard",              stage: "Handoff",  owner: "ALO", shortId: "std-life"),
        LabBuildingItem(title: "Knowledge Center Index",                  stage: "Active",   owner: "ALO", shortId: "kc-idx"),
        LabBuildingItem(title: "Pod Agents Tab",                          stage: "Building", owner: "MAU", shortId: "spec-agt"),
        LabBuildingItem(title: "Pod Lab Tab",                             stage: "Building", owner: "MAU", shortId: "spec-lab"),
        LabBuildingItem(title: "APPROVAL-TIERS doctrine",                 stage: "Active",   owner: "ALO", shortId: "std-tier"),
        LabBuildingItem(title: "Weekly Ticket Hygiene Petal",             stage: "Building", owner: "COR", shortId: "petal-h"),
        LabBuildingItem(title: "M-005 Wiki-ORCA mirror",                  stage: "Active",   owner: "MAU", shortId: "m-005"),
        LabBuildingItem(title: "Memory Spine",                            stage: "Captured", owner: "ALO", shortId: "mem-spn"),
        LabBuildingItem(title: "iMessage outbound contract",              stage: "Active",   owner: "ALO", shortId: "cfde783b"),
        LabBuildingItem(title: "Roster Archive cleanup",                  stage: "Active",   owner: "MAU", shortId: "85103d0c")
    ]

    static let retiredItems: [LabRetiredItem] = [
        LabRetiredItem(name: "MQTT bus",            reason: "Replaced by NATS (2026-04)"),
        LabRetiredItem(name: "Aurora / Shaka / Luna agents", reason: "Roster restructure 2026-05-22 (decision-note b6af3ef3)"),
        LabRetiredItem(name: "Old Project Tracker", reason: "Superseded by ORCA projects 2026-05-09"),
        LabRetiredItem(name: "Legacy SOPs (SOP-ALOHA-001/002/003, CHROMA_MAINTENANCE_SOP)", reason: "Pre-Backbone era; superseded by current canon")
    ]
}
