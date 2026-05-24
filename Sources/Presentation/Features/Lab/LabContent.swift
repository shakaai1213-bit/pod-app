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

struct LabWorkflowItem: Identifiable {
    let id = UUID()
    let title: String
    let status: String      // "🟢 LIVE" / "DRAFT" / etc — short label
    let statusColor: Color
}

struct LabWorkflowGroup: Identifiable {
    let id = UUID()
    let title: String       // "Tier governance", "Project + ticket lifecycle", etc
    let items: [LabWorkflowItem]
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
            id: "nats",
            title: "NATS",
            oneLine: "Nerve bus · Track B envelopes · agent inbox/events wire",
            status: .live,
            owner: "MAU",
            icon: "point.3.connected.trianglepath.dotted",
            tint: AppColors.accentSuccess
        ),
        LabStackLayer(
            id: "pod",
            title: "Pod",
            oneLine: "Tony's iPad/iPhone cockpit · SwiftUI · 7 tabs",
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

    // The Fish 🐠 — research substrate fleet (per LAB-SYSTEMS-INDEX §11).
    // NOT operators/workers — those live on the Agents tab.
    // Each Fish has a partner-operator who owns its directive queue.
    static let fishFleet: [LabFish] = [
        LabFish(id: "starfish",    emoji: "🭐",  name: "Starfish",    role: "General autonomous research · partner: Maui 🪝",                status: .live),
        LabFish(id: "chieffish",   emoji: "🐟",  name: "Chieffish",   role: "Fund/quant lit research · partner: Chief 🦅",                   status: .live),
        LabFish(id: "roosterfish", emoji: "🐓🐟", name: "Roosterfish", role: "Security research: CVEs + threat intel · partner: Rooster 🐓", status: .live)
    ]

    // Adjacent (not Fish but research-substrate-shaped) — Octopus is chief-local, not Pod-surfaced.
    static let fishAdjacent: [LabFish] = [
        LabFish(id: "octopus", emoji: "🐙", name: "Octopus", role: "Chief's chief-mac research substrate (octopus_arms)", status: .live)
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

    // Workflows + Protocols — the procedural backbone (per LAB-SYSTEMS-INDEX §13).
    // STANDARDS govern what's right; PROTOCOLS govern how we coordinate; SOPs are step-by-step recipes.
    static let workflows: [LabWorkflowGroup] = [
        LabWorkflowGroup(
            title: "Tier governance (umbrella, 2026-05-23)",
            items: [
                LabWorkflowItem(title: "standards/approval-tiers.md — Tier 1/2/3 model", status: "ALOHA ✅ · TONY ⏳", statusColor: AppColors.accentWarning),
                LabWorkflowItem(title: "ADR-002.4-governance-gate-transition", status: "ALOHA ✅ · TONY ⏳", statusColor: AppColors.accentWarning)
            ]
        ),
        LabWorkflowGroup(
            title: "Project + ticket lifecycle",
            items: [
                LabWorkflowItem(title: "project-lifecycle-standard — 8 stages", status: "🟢 LIVE", statusColor: AppColors.accentSuccess),
                LabWorkflowItem(title: "ADR-013-board-folds-into-project", status: "🟢 LIVE", statusColor: AppColors.accentSuccess),
                LabWorkflowItem(title: "PROTOCOL-VERIFIED-CLOSE", status: "🟢 LIVE", statusColor: AppColors.accentSuccess),
                LabWorkflowItem(title: "PROTOCOL-INBOX-DRAIN", status: "DRAFT", statusColor: AppColors.accentCaptain)
            ]
        ),
        LabWorkflowGroup(
            title: "Sign-chain + attribution",
            items: [
                LabWorkflowItem(title: "ADR-002 — maintainer model (sign-chain mechanism)", status: "🟢 LIVE", statusColor: AppColors.accentSuccess),
                LabWorkflowItem(title: "ADR-002.3 — sign-chain integrity (envelope ≠ signature)", status: "DRAFT · TONY ⏳", statusColor: AppColors.accentCaptain),
                LabWorkflowItem(title: "SOP-VERIFICATION-RECIPES", status: "🟢 LIVE", statusColor: AppColors.accentSuccess),
                LabWorkflowItem(title: "SOP-SHARED-TOOLS", status: "🟢 LIVE", statusColor: AppColors.accentSuccess)
            ]
        ),
        LabWorkflowGroup(
            title: "Memory + documentation",
            items: [
                LabWorkflowItem(title: "agent-documentation-workflow-standard", status: "🟢 LIVE", statusColor: AppColors.accentSuccess),
                LabWorkflowItem(title: "SOP-MEMORY-UPDATE — verify, mark, point, date", status: "🟢 LIVE", statusColor: AppColors.accentSuccess),
                LabWorkflowItem(title: "charters/memory.md", status: "🟢 LIVE", statusColor: AppColors.accentSuccess)
            ]
        ),
        LabWorkflowGroup(
            title: "Comms",
            items: [
                LabWorkflowItem(title: "standards/imessage-reply-contract.md", status: "🟢 LIVE", statusColor: AppColors.accentSuccess)
            ]
        )
    ]

    static let retiredItems: [LabRetiredItem] = [
        LabRetiredItem(name: "MQTT bus",            reason: "Replaced by NATS (2026-04)"),
        LabRetiredItem(name: "Aurora / Shaka / Luna agents", reason: "Roster restructure 2026-05-22 (decision-note b6af3ef3)"),
        LabRetiredItem(name: "Old Project Tracker", reason: "Superseded by ORCA projects 2026-05-09"),
        LabRetiredItem(name: "Legacy SOPs (SOP-ALOHA-001/002/003, CHROMA_MAINTENANCE_SOP)", reason: "Pre-Backbone era; superseded by current canon")
    ]
}
