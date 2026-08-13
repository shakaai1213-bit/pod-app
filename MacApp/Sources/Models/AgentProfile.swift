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

    static let fallbackRoster: [AgentProfile] = [
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

    static func fromRuntime(
        id: String,
        name: String?,
        role: String?
    ) -> AgentProfile {
        let defaults = Dictionary(uniqueKeysWithValues: fallbackRoster.map { ($0.id, $0) })
        if let known = defaults[id] {
            return AgentProfile(
                id: id,
                name: name?.capitalized ?? known.name,
                role: role ?? known.role,
                symbol: known.symbol,
                accent: known.accent,
                lane: known.lane
            )
        }
        return AgentProfile(
            id: id,
            name: name?.capitalized ?? id.capitalized,
            role: role ?? "Named ORCA agent",
            symbol: "person.crop.circle",
            accent: .teal,
            lane: .support
        )
    }
}
