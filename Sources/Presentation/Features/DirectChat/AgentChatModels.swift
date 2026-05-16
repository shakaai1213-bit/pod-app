import Foundation
import SwiftData

// MARK: - Agent Directory

/// Static agent directory — each agent the user can chat with 1:1.
struct AgentInfo: Identifiable, Hashable, Sendable {
    let id: String              // e.g. "aurora", "maui"
    let name: String
    let role: String
    let icon: String            // SF Symbol name
    let color: String           // hex color for avatar
    let endpoint: AgentEndpoint
    let isReachable: Bool       // false → row greyed out + tap shows "coming soon"

    struct AgentEndpoint: Hashable, Sendable {
        let baseURL: String     // OpenClaw gateway URL
        let authToken: String   // gateway auth token
    }
}

extension AgentInfo {
    // MARK: - Gateway URL constants (non-sensitive)
    private static let shakaMacGateway = "https://shakas-mac-mini.tail82d30d.ts.net"
    private static let chiefMacGateway = "https://chiefs-mac-mini.tail82d30d.ts.net"

    /// The team — hardcoded for v1. Will become config-driven.
    /// Auth tokens read from AgentSecrets (gitignored, see AgentSecrets.swift.template).
    /// M1 security per Rooster review 2026-05-07.
    ///
    /// Reachability state is hardcoded per `agent_gateway_healthcheck.py` truth as of
    /// 2026-05-07 (Path B per Shaka CEO call). Re-run the healthcheck script after any
    /// gateway/handler change and update isReachable: flags here.
    /// Currently reachable: Aurora, Aloha. Others have no server-side chat handler yet.
    static let team: [AgentInfo] = [
        AgentInfo(
            id: "aurora",
            name: "Aurora",
            role: "Mission Control",
            icon: "sparkles",
            color: "A855F7",
            endpoint: .init(
                baseURL: shakaMacGateway,
                authToken: AgentSecrets.shakaMacGatewayToken
            ),
            isReachable: true  // Has server-side chat handler (verified via healthcheck)
        ),
        AgentInfo(
            id: "maui",
            name: "Maui",
            role: "Engineering",
            icon: "wrench.and.screwdriver",
            color: "F97316",
            endpoint: .init(
                baseURL: shakaMacGateway,
                authToken: AgentSecrets.shakaMacGatewayToken
            ),
            isReachable: false  // No server-side handler (Claude session, not chat backend)
        ),
        AgentInfo(
            id: "aloha",
            name: "Aloha",
            role: "Communications",
            icon: "doc.text",
            color: "EC4899",
            endpoint: .init(
                baseURL: shakaMacGateway,
                authToken: AgentSecrets.shakaMacGatewayToken
            ),
            isReachable: true  // Has server-side chat handler (verified via healthcheck)
        ),
        AgentInfo(
            id: "luna",
            name: "Luna",
            role: "Research Coordinator",
            icon: "moon.stars",
            color: "6366F1",
            endpoint: .init(
                baseURL: chiefMacGateway,
                authToken: AgentSecrets.chiefMacGatewayToken
            ),
            isReachable: false  // chief-mac gateway daemon down (Reef reviving)
        ),
        AgentInfo(
            id: "chief",
            name: "Chief",
            role: "Head of Trading",
            icon: "chart.line.uptrend.xyaxis",
            color: "22C55E",
            endpoint: .init(
                baseURL: chiefMacGateway,
                authToken: AgentSecrets.chiefMacGatewayToken
            ),
            isReachable: false  // chief-mac gateway daemon down (Reef reviving)
        ),
        AgentInfo(
            id: "coral",
            name: "Coral",
            role: "Operations",
            icon: "circle.hexagongrid",
            color: "06B6D4",
            endpoint: .init(
                baseURL: shakaMacGateway,
                authToken: AgentSecrets.shakaMacGatewayToken
            ),
            isReachable: false  // No server-side handler (Claude session, not chat backend)
        ),
        AgentInfo(
            id: "rooster",
            name: "Rooster",
            role: "Head of Security",
            icon: "checkmark.shield",
            color: "EF4444",
            endpoint: .init(
                baseURL: chiefMacGateway,
                authToken: AgentSecrets.chiefMacGatewayToken
            ),
            isReachable: false  // chief-mac gateway daemon down (Reef reviving)
        ),
        AgentInfo(
            id: "reef",
            name: "Reef",
            role: "Watchdogs",
            icon: "waveform.path.ecg",
            color: "14B8A6",
            endpoint: .init(
                baseURL: chiefMacGateway,
                authToken: AgentSecrets.chiefMacGatewayToken
            ),
            isReachable: false  // chief-mac gateway daemon down (Reef reviving)
        ),
        AgentInfo(
            id: "shaka",
            name: "Shaka",
            role: "CEO",
            icon: "hands.sparkles",
            color: "FBBF24",
            endpoint: .init(
                baseURL: shakaMacGateway,
                authToken: AgentSecrets.shakaMacGatewayToken
            ),
            isReachable: false  // Person, not Claude session — no chat handler
        ),
    ]

    static func find(_ id: String) -> AgentInfo? {
        team.first { $0.id == id }
    }
}

// MARK: - SwiftData Models

@Model
final class DMConversation {
    @Attribute(.unique) var agentId: String
    var lastMessageText: String
    var lastMessageDate: Date
    var unreadCount: Int

    @Relationship(deleteRule: .cascade, inverse: \DMMessage.conversation)
    var messages: [DMMessage]

    init(agentId: String) {
        self.agentId = agentId
        self.lastMessageText = ""
        self.lastMessageDate = Date()
        self.unreadCount = 0
        self.messages = []
    }
}

@Model
final class DMMessage {
    var id: UUID
    var role: String            // "user" or "assistant"
    var content: String
    var timestamp: Date
    var isStreaming: Bool        // true while SSE is still arriving
    var tokenCount: Int?
    var modelUsed: String?
    var latencyMs: Int?

    var conversation: DMConversation?

    init(
        role: String,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}
