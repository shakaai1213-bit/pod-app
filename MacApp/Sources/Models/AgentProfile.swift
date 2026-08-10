import Foundation

struct AgentProfile: Identifiable, Hashable, Sendable {
    enum Lane: String, Sendable {
        case primary = "Primary"
        case support = "Support"
        case protected = "Protected"
    }

    let id: String
    let name: String
    let role: String
    let symbol: String
    let accent: Accent
    let lane: Lane

    enum Accent: String, Sendable {
        case pink
        case orange
        case violet
        case green
        case red
        case cyan
        case teal
    }

    static let roster: [AgentProfile] = [
        AgentProfile(
            id: "aloha",
            name: "Aloha",
            role: "Coordination and memory",
            symbol: "doc.text",
            accent: .pink,
            lane: .primary
        ),
        AgentProfile(
            id: "maui",
            name: "Maui",
            role: "Engineering lead",
            symbol: "wrench.and.screwdriver",
            accent: .orange,
            lane: .primary
        ),
        AgentProfile(
            id: "shaka",
            name: "Shaka",
            role: "Operating picture",
            symbol: "scope",
            accent: .violet,
            lane: .primary
        ),
        AgentProfile(
            id: "chief",
            name: "Chief",
            role: "Fund and research",
            symbol: "chart.line.uptrend.xyaxis",
            accent: .green,
            lane: .protected
        ),
        AgentProfile(
            id: "rooster",
            name: "Rooster",
            role: "Security and release",
            symbol: "checkmark.shield",
            accent: .red,
            lane: .primary
        ),
        AgentProfile(
            id: "coral",
            name: "Coral",
            role: "Operations and surfaces",
            symbol: "circle.hexagongrid",
            accent: .cyan,
            lane: .support
        ),
        AgentProfile(
            id: "reef",
            name: "Reef",
            role: "Runtime support",
            symbol: "waveform.path.ecg",
            accent: .teal,
            lane: .support
        ),
    ]
}
