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

    struct AgentEndpoint: Hashable, Sendable {
        let baseURL: String     // OpenClaw gateway URL
        let authToken: String   // gateway auth token
    }
}

extension AgentInfo {
    /// The team — hardcoded for v1. Will become config-driven.
    static let team: [AgentInfo] = [
        AgentInfo(
            id: "aurora",
            name: "Aurora",
            role: "Mission Control",
            icon: "sparkles",
            color: "A855F7",
            endpoint: .init(
                baseURL: "http://127.0.0.1:18789",
                authToken: "S43piRnUxdxlKSHG2cLOLYjGUV_yYYOh"
            )
        ),
        AgentInfo(
            id: "maui",
            name: "Maui",
            role: "Engineering",
            icon: "wrench.and.screwdriver",
            color: "F97316",
            endpoint: .init(
                baseURL: "http://127.0.0.1:18789",
                authToken: "S43piRnUxdxlKSHG2cLOLYjGUV_yYYOh"
            )
        ),
        AgentInfo(
            id: "aloha",
            name: "Aloha",
            role: "Communications",
            icon: "doc.text",
            color: "EC4899",
            endpoint: .init(
                baseURL: "http://127.0.0.1:18789",
                authToken: "S43piRnUxdxlKSHG2cLOLYjGUV_yYYOh"
            )
        ),
        AgentInfo(
            id: "luna",
            name: "Luna",
            role: "Research Coordinator",
            icon: "moon.stars",
            color: "6366F1",
            endpoint: .init(
                baseURL: "http://100.80.44.41:18789",
                authToken: "f5f8b8d5b029e78783d1b7ac6ecb075b078731b4b4ac3e059562d4cf2f838e90"
            )
        ),
        AgentInfo(
            id: "chief",
            name: "Chief",
            role: "Head of Trading",
            icon: "chart.line.uptrend.xyaxis",
            color: "22C55E",
            endpoint: .init(
                baseURL: "http://100.80.44.41:18789",
                authToken: "f5f8b8d5b029e78783d1b7ac6ecb075b078731b4b4ac3e059562d4cf2f838e90"
            )
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
