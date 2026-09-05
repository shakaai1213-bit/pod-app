import Foundation

public struct OrcaAgentProfile: Identifiable, Hashable, Sendable {
    public enum Lane: String, Codable, Sendable {
        case primary
        case support
        case protected
    }

    public enum Accent: String, Codable, Sendable {
        case pink
        case orange
        case violet
        case green
        case red
        case cyan
        case teal
    }

    public let id: String
    public let name: String
    public let role: String
    public let symbol: String
    public let colorHex: String
    public let accent: Accent
    public let lane: Lane
    public let fallbackGuardrail: String

    public init(
        id: String,
        name: String,
        role: String,
        symbol: String,
        colorHex: String,
        accent: Accent,
        lane: Lane,
        fallbackGuardrail: String
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.symbol = symbol
        self.colorHex = colorHex
        self.accent = accent
        self.lane = lane
        self.fallbackGuardrail = fallbackGuardrail
    }

    public static let fallbackRoster: [OrcaAgentProfile] = [
        OrcaAgentProfile(
            id: "aloha",
            name: "Aloha",
            role: "Coordination, intake, standards, and memory",
            symbol: "doc.text",
            colorHex: "EC4899",
            accent: .pink,
            lane: .primary,
            fallbackGuardrail: "Keep coordination, memory, standards, and ORCA routing grounded in ORCA and Team-Wiki. Chief and Fund changes retain their recorded authority gates."
        ),
        OrcaAgentProfile(
            id: "maui",
            name: "Maui",
            role: "Engineering lead for ORCA, Pod, Console, and compute",
            symbol: "wrench.and.screwdriver",
            colorHex: "F97316",
            accent: .orange,
            lane: .primary,
            fallbackGuardrail: "Tie implementation to canonical work, durable evidence, and verification. Do not represent an isolated change as merged or deployed."
        ),
        OrcaAgentProfile(
            id: "shaka",
            name: "Shaka",
            role: "Operating picture, priorities, and cross-agent alignment",
            symbol: "scope",
            colorHex: "8B5CF6",
            accent: .violet,
            lane: .primary,
            fallbackGuardrail: "Ground the operating picture in ORCA, Schoolhouse, Locker, and durable evidence. Human approval remains Tony's alone."
        ),
        OrcaAgentProfile(
            id: "chief",
            name: "Chief",
            role: "Protected Fund and research lead",
            symbol: "chart.line.uptrend.xyaxis",
            colorHex: "22C55E",
            accent: .green,
            lane: .protected,
            fallbackGuardrail: "The Fund lane is protected. Never invent financial state or perform trading, credential, account, wallet, strategy, or Chief-host mutations without the recorded ORCA authority and approval gates."
        ),
        OrcaAgentProfile(
            id: "rooster",
            name: "Rooster",
            role: "Security, credentials, guardrails, and release",
            symbol: "checkmark.shield",
            colorHex: "EF4444",
            accent: .red,
            lane: .primary,
            fallbackGuardrail: "Never expose secrets. Keep rotations, access changes, security decisions, and releases inside their explicit review and signature contracts."
        ),
        OrcaAgentProfile(
            id: "coral",
            name: "Coral",
            role: "Operations, surfaces, watchdogs, and runtime observability",
            symbol: "circle.hexagongrid",
            colorHex: "06B6D4",
            accent: .cyan,
            lane: .support,
            fallbackGuardrail: "Keep work in ORCA and return bounded worker results as evidence. Never claim an isolated worktree was merged or deployed or cross a protected boundary without its recorded gate."
        ),
        OrcaAgentProfile(
            id: "reef",
            name: "Reef",
            role: "Runtime support, host health, watchdogs, and mirrors",
            symbol: "waveform.path.ecg",
            colorHex: "14B8A6",
            accent: .teal,
            lane: .support,
            fallbackGuardrail: "Support-runtime triage is bounded. Chief, Fund, credential, trading, and host mutations require their canonical ticket and authority gates."
        ),
    ]

    public static var ids: Set<String> { Set(fallbackRoster.map(\.id)) }

    public static func known(_ id: String) -> OrcaAgentProfile? {
        fallbackRoster.first { $0.id == id.lowercased() }
    }

    public static func fromRuntime(id: String, name: String?, role: String?) -> OrcaAgentProfile {
        let normalized = id.lowercased()
        if let known = known(normalized) {
            return OrcaAgentProfile(
                id: normalized,
                name: name?.capitalized ?? known.name,
                role: role ?? known.role,
                symbol: known.symbol,
                colorHex: known.colorHex,
                accent: known.accent,
                lane: known.lane,
                fallbackGuardrail: known.fallbackGuardrail
            )
        }
        return OrcaAgentProfile(
            id: normalized,
            name: name?.capitalized ?? normalized.capitalized,
            role: role ?? "Named ORCA agent",
            symbol: "person.crop.circle",
            colorHex: "14B8A6",
            accent: .teal,
            lane: .support,
            fallbackGuardrail: "Use the agent's live ORCA configuration and recorded authority."
        )
    }
}
