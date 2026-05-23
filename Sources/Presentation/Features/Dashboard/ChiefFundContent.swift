import SwiftUI

// MARK: - Chief/Fund Canonical Bot Map
//
// Hardcoded read-only registry of Chief/Fund bots and runtime components.
// Canonical source-of-truth for Pod verified cards (ticket a5fb63c3 / 48450233).
// No P&L, no positions, no orders — visibility only.
// When /api/v1/chief/bot-map lands, replace static arrays with a fetch.

enum BotMode: String {
    case paper
    case readOnly = "read_only"
    case live

    var label: String {
        switch self {
        case .paper:    return "Paper"
        case .readOnly: return "Read-only"
        case .live:     return "Live"
        }
    }

    var color: Color {
        switch self {
        case .paper:    return AppColors.accentElectric
        case .readOnly: return AppColors.textSecondary
        case .live:     return AppColors.accentDanger
        }
    }

    var icon: String {
        switch self {
        case .paper:    return "doc.plaintext"
        case .readOnly: return "eye"
        case .live:     return "bolt.fill"
        }
    }
}

enum BotReviewGate: String {
    case chiefTony = "Chief + Tony"
    case roosterChief = "Rooster + Chief"
    case tony = "Tony only"
    case chiefOnly = "Chief only"
}

struct ChiefFundBot: Identifiable {
    let id: String
    let emoji: String
    let name: String
    let role: String
    let mode: BotMode
    let owner: String
    let launchPath: String?
    let killSwitch: String
    let reviewGate: BotReviewGate
    let notes: String?
}

// MARK: - Static registry

enum ChiefFundContent {

    static let bots: [ChiefFundBot] = [
        ChiefFundBot(
            id: "chief",
            emoji: "🦅",
            name: "Chief",
            role: "Trading Lead — backbone agent, runs fund research + strategy",
            mode: .paper,
            owner: "Tony",
            launchPath: "~/workspace-chief/ · wake_on_nats.py",
            killSwitch: "launchctl unload com.chief.agent (chief-mac)",
            reviewGate: .tony,
            notes: "Paper mode until Tony authorises live trading. All strategy decisions logged via ORCA tickets."
        ),
        ChiefFundBot(
            id: "chieffish",
            emoji: "🐠",
            name: "Chieffish",
            role: "Literature + web synthesis — Nemotron-driven, 15-min research sprints",
            mode: .paper,
            owner: "Chief",
            launchPath: "~/workspace-chief/chieffish/ · chieffish_runner.py",
            killSwitch: "SIGTERM chieffish_runner.py (chief-mac)",
            reviewGate: .chiefTony,
            notes: "Publishes structured findings to Chief. Read-only web synthesis — no orders, no mutations."
        ),
        ChiefFundBot(
            id: "octopus-arms",
            emoji: "🐙",
            name: "Octopus Arms",
            role: "Signal backtesting — Chief's private backtester, structured signal validation",
            mode: .paper,
            owner: "Chief",
            launchPath: "~/Chief/octopus_arms/ (chief-mac)",
            killSwitch: "Kill octopus_arms process (chief-mac)",
            reviewGate: .chiefTony,
            notes: "Q3-2026 goal: 30 validated trades at quarter-Kelly under vol-regime gate. No live execution."
        ),
        ChiefFundBot(
            id: "reef",
            emoji: "🐡",
            name: "Reef",
            role: "Chief-mac runtime watchdog — Coral's sister across the wire",
            mode: .readOnly,
            owner: "Reef",
            launchPath: "~/Reef/ · wake_on_nats.py (chief-mac)",
            killSwitch: "launchctl unload com.reef.agent (chief-mac)",
            reviewGate: .chiefOnly,
            notes: "Watchdogs + Surfaces on chief-mac. OpenClaw-only tier. Does not reach Claude."
        ),
        ChiefFundBot(
            id: "rooster",
            emoji: "🐓",
            name: "Rooster",
            role: "Head of Security — credentials, perimeter, daily security reports",
            mode: .readOnly,
            owner: "Tony",
            launchPath: "~/Rooster/ · wake_on_nats.py (chief-mac)",
            killSwitch: "launchctl unload com.rooster.agent (chief-mac)",
            reviewGate: .roosterChief,
            notes: "Claude-active. All credential / token / wallet operations require Rooster + Tony approval. Never acted on without explicit Tier 4 sign."
        ),
    ]

    static let guardrails: [String] = [
        "No P&L, positions, orders, wallets, or balance data in Pod",
        "Bot changes require Chief + Tony sign (Tier 4)",
        "All trading decisions paper-mode until Tony authorises live",
        "Risk-limit changes require Rooster + Chief review",
        "Kill switches are manual — no Pod tap triggers a shutdown",
    ]
}
