import Foundation
import SwiftData

// MARK: - Agent Directory

/// Static agent directory — each agent the user can chat with 1:1.
struct AgentInfo: Identifiable, Hashable, Sendable {
    enum Lane: String, Hashable, Sendable {
        case main
        case supportRuntime
        case dormantAdvisor
    }

    let id: String              // e.g. "aloha", "maui"
    let name: String
    let role: String
    let icon: String            // SF Symbol name
    let color: String           // hex color for avatar
    let endpoint: AgentEndpoint
    let isReachable: Bool       // false → row greyed out + tap shows "coming soon"
    let lane: Lane
    let guardrail: String

    struct AgentEndpoint: Hashable, Sendable {
        let baseURL: String     // Compute/OpenClaw-compatible gateway URL
        let authToken: String   // optional gateway auth token
    }
}

extension AgentInfo {
    // MARK: - Gateway URL constants (non-sensitive)
    private static let computeGateway = AppConfig.computeURL

    /// Pod chat routing v1: active and support agents use ORCA-backed compute
    /// triage chat. Dormant/archive agents are preserved outside the app
    /// surface until ORCA exposes them as explicit read-only records.
    static let team: [AgentInfo] = [
        AgentInfo(
            id: "aloha",
            name: "Aloha",
            role: "Tony-facing coordinator, intake, standards, ORCA operations, memory enforcement",
            icon: "doc.text",
            color: "EC4899",
            endpoint: .init(baseURL: computeGateway, authToken: ""),
            isReachable: true,
            lane: .main,
            guardrail: "Aloha is Tony's central coordinator. Keep memory, triage, standards, ORCA routing, and archive decisions grounded in Team-Wiki and ORCA. Do not claim final authority over Chief/Fund changes."
        ),
        AgentInfo(
            id: "maui",
            name: "Maui",
            role: "Engineering lead for Pod, ORCA backend, compute integration, and shipping",
            icon: "wrench.and.screwdriver",
            color: "F97316",
            endpoint: .init(baseURL: computeGateway, authToken: ""),
            isReachable: true,
            lane: .main,
            guardrail: "Maui should be decisive on engineering implementation, but must keep work tied to ORCA tickets, document meaningful changes in the chronogram, and avoid destructive operations."
        ),
        AgentInfo(
            id: "chief",
            name: "Chief",
            role: "Protected Fund and trading research lead",
            icon: "chart.line.uptrend.xyaxis",
            color: "22C55E",
            endpoint: .init(baseURL: computeGateway, authToken: ""),
            isReachable: true,
            lane: .main,
            guardrail: "Chief is protected. This Pod chat is not the live Chief runtime and has no access to P&L, positions, orders, wallets, exchange accounts, Chief memory, Chief Chroma, or trading systems. Never invent financial values, portfolio state, ticket ids, completed checks, or trading actions. Keep answers read-only and process-focused. For any Fund, trading, account, credential, strategy execution, or Chief Mac inspection request, tell Tony to create or attach an ORCA ticket for Chief plus Tony/Rooster review before any mutation."
        ),
        AgentInfo(
            id: "rooster",
            name: "Rooster",
            role: "Security, credentials, guardrails, Chief Mac protection",
            icon: "checkmark.shield",
            color: "EF4444",
            endpoint: .init(baseURL: computeGateway, authToken: ""),
            isReachable: true,
            lane: .main,
            guardrail: "Rooster handles security review and guardrails. Never expose secrets. Recommend rotations or access changes only as explicit review items for Tony."
        ),
        AgentInfo(
            id: "coral",
            name: "Coral",
            role: "Support-runtime for Shaka Mac watchdogs, daemons, compute observability",
            icon: "circle.hexagongrid",
            color: "06B6D4",
            endpoint: .init(baseURL: computeGateway, authToken: ""),
            isReachable: true,
            lane: .supportRuntime,
            guardrail: "Coral is support-runtime for Shaka Mac watchdogs, daemons, runtime health, compute observability, and support triage. This Pod chat is not the live Coral runtime and cannot inspect logs, restart daemons, query Chroma, or mutate ORCA by itself. For execution, create or attach an ORCA ticket and route through Agent Runs."
        ),
        AgentInfo(
            id: "reef",
            name: "Reef",
            role: "Support-runtime for Chief Mac watchdogs, mirrors, surfaces",
            icon: "waveform.path.ecg",
            color: "14B8A6",
            endpoint: .init(baseURL: computeGateway, authToken: ""),
            isReachable: true,
            lane: .supportRuntime,
            guardrail: "Reef is support-runtime for Chief Mac mirrors, daemons, surfaces, watchdogs, and Chief-Mac support triage. This Pod chat is not the live Reef runtime and has no authority to inspect or change Chief/Fund systems. Any Chief/Fund, trading, credential, or Chief Mac mutation requires ORCA ticket plus Chief/Tony/Rooster review."
        ),
    ]

    var laneLabel: String {
        switch lane {
        case .main: return "Active"
        case .supportRuntime: return "Support"
        case .dormantAdvisor: return "Dormant"
        }
    }

    var availabilityText: String {
        if isReachable {
            return defaultDeliveryMode.displayLabel
        }
        switch lane {
        case .supportRuntime: return "Support lane"
        case .dormantAdvisor: return "Dormant - preserved memory"
        case .main: return "Unavailable"
        }
    }

    var defaultDeliveryMode: DMDeliveryMode {
        if ["aloha", "maui", "coral", "chief", "rooster", "reef"].contains(id) {
            return .liveInbox
        }
        return .compute
    }

    var boundaryText: String {
        switch id {
        case "aloha":
            return "Live inbox is the default Aloha path when her runtime is awake. Compute helper remains available for quick triage, but real continuity comes from ORCA/live inbox."
        case "maui":
            return "Compute triage for engineering guidance. Real implementation belongs on tickets, runs, commits, and verification."
        case "chief":
            return "Protected read-only lane. No live P&L, positions, wallets, orders, Chief memory, or trading actions from Pod chat."
        default:
            if lane == .supportRuntime {
                return "Support-runtime triage only. Logs, daemons, mirrors, and mutations require an ORCA ticket or Agent Run."
            }
            return "Direct chat is triage. Use ORCA for tools, approvals, mutations, and durable evidence."
        }
    }

    static func find(_ id: String) -> AgentInfo? {
        team.first { $0.id == id }
    }
}

// MARK: - SwiftData Models

enum DMDeliveryMode: String, Codable, Sendable {
    case auto
    case liveInbox = "agent_inbox"
    case compute
    case agentRun = "agent_run"
    case fallback
    case system
    case ticket

    static func parse(_ raw: String?) -> DMDeliveryMode? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "live_inbox", "live_agent", "live_agent_inbox":
            return .liveInbox
        default:
            return DMDeliveryMode(rawValue: normalized)
        }
    }

    var displayLabel: String {
        switch self {
        case .auto: return "Auto route"
        case .liveInbox: return "Live inbox handoff"
        case .compute: return "Compute helper"
        case .agentRun: return "Agent Run"
        case .fallback: return "Local guardrail fallback"
        case .system: return "Pod system"
        case .ticket: return "ORCA ticket"
        }
    }
}

enum DMResponseProvenance: String, Codable, Sendable {
    case liveInbox = "live_inbox"
    case coordinationReview = "coordination_review"
    case timeoutFallback = "timeout_fallback"
    case compute
    case agentRun = "agent_run"
    case fallback
    case system
    case ticket
    case protected

    static func parse(_ raw: String?) -> DMResponseProvenance? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "coordination", "coordination_review", "review_coordination":
            return .coordinationReview
        case "timeout_fallback", "compute_timeout_fallback", "fallback_after_timeout":
            return .timeoutFallback
        case "agent_inbox", "direct_agent_inbox":
            return .liveInbox
        case "local_guardrail", "local_fallback":
            return .fallback
        default:
            return DMResponseProvenance(rawValue: normalized)
        }
    }

    init(deliveryMode: String?, source: String?, lane: String?) {
        let delivery = DMDeliveryMode.parse(deliveryMode)
        switch delivery {
        case .auto: self = .compute
        case .liveInbox: self = .liveInbox
        case .compute: self = .compute
        case .agentRun: self = .agentRun
        case .fallback: self = .fallback
        case .system: self = .system
        case .ticket: self = .ticket
        case nil:
            let raw = [source, lane].compactMap { $0?.lowercased() }.joined(separator: " ")
            if raw.contains("protected") {
                self = .protected
            } else if raw.contains("coordination_review") || raw.contains("coordination") {
                self = .coordinationReview
            } else if raw.contains("timeout_fallback") || (raw.contains("fallback") && raw.contains("timeout")) {
                self = .timeoutFallback
            } else if raw.contains("fallback") || raw.contains("local_guardrail") {
                self = .fallback
            } else if raw.contains("ticket") {
                self = .ticket
            } else if raw.contains("agent_run") || raw.contains("dispatch") {
                self = .agentRun
            } else if raw.contains("direct_agent_inbox") || raw.contains("live") {
                self = .liveInbox
            } else if raw.contains("system") {
                self = .system
            } else {
                self = .compute
            }
        }
    }

    var displayLabel: String {
        switch self {
        case .coordinationReview: return "Coordination review handoff"
        case .timeoutFallback: return "Compute fallback after timeout"
        case .liveInbox: return "Sent to inbox; waiting"
        case .compute: return "Compute helper, not live runtime"
        case .agentRun: return "ORCA Agent Run"
        case .fallback: return "Local guardrail fallback"
        case .system: return "Pod system notice"
        case .ticket: return "ORCA ticket evidence"
        case .protected: return "Protected lane guardrail"
        }
    }
}

enum DMDeliveryState: String, Codable, Sendable {
    case sending
    case routing
    case computeRunning = "compute_running"
    case agentRunQueued = "agent_run_queued"
    case agentRunRunning = "agent_run_running"
    case waitingForLiveAgent = "waiting_for_live_agent"
    case claimedByAgent = "claimed_by_agent"
    case responseReceived = "response_received"
    case deliveryNatsFailed = "delivery_nats_failed"
    case agentUnresponsive = "agent_unresponsive"
    case failed
    case fallbackPresented = "fallback_presented"
    case timedOut = "timed_out"

    static func parse(_ raw: String?) -> DMDeliveryState? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "nats_failed", "nats_delivery_failed", "delivery_failed_nats":
            return .deliveryNatsFailed
        case "agent_unreachable", "unreachable", "no_agent_response":
            return .agentUnresponsive
        case "waiting_for_agent", "agent_pending", "live_pending", "live_inbox_pending":
            return .waitingForLiveAgent
        case "accepted", "pending", "queued", "running", "in_progress", "async_pending", "compute_pending", "compute_accepted":
            return .computeRunning
        case "agent_run_pending", "agent_run_accepted", "dispatch_queued", "execution_queued":
            return .agentRunQueued
        case "agent_run_active", "dispatch_running", "execution_running":
            return .agentRunRunning
        case "complete", "completed", "done", "responded":
            return .responseReceived
        default:
            return DMDeliveryState(rawValue: normalized)
        }
    }

    var displayLabel: String {
        switch self {
        case .sending: return "Sending"
        case .routing: return "Routing"
        case .computeRunning: return "Compute accepted; waiting"
        case .agentRunQueued: return "Agent Run queued"
        case .agentRunRunning: return "Agent Run running"
        case .waitingForLiveAgent: return "Live inbox accepted; waiting"
        case .claimedByAgent: return "Live agent claimed"
        case .responseReceived: return "Final reply received"
        case .deliveryNatsFailed: return "Not delivered - NATS failed"
        case .agentUnresponsive: return "Not delivered - agent unreachable"
        case .failed: return "Failed"
        case .fallbackPresented: return "Local fallback shown"
        case .timedOut: return "Still waiting"
        }
    }
}

enum DMUserMessageDeliveryState: String, Codable, Sendable {
    case sending
    case sent
    case failed

    static func parse(_ raw: String?) -> DMUserMessageDeliveryState? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DMUserMessageDeliveryState(rawValue: normalized)
    }
}

struct DirectChatProgressStep: Identifiable, Hashable, Sendable {
    enum State: String, Hashable, Sendable {
        case pending
        case current
        case done
        case failed
    }

    let id: String
    let title: String
    let icon: String
    let state: State
}

struct DirectChatTicketContinuity: Sendable, Hashable {
    let ticket: Ticket
    let summary: TicketListSummary?
    let comments: [TicketComment]
    let runs: [AgentRun]

    var statusLabel: String {
        ticket.status.label
    }

    var priorityLabel: String {
        ticket.priority.label
    }

    var latestRun: AgentRun? {
        runs.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    var sortedRuns: [AgentRun] {
        runs.sorted { $0.updatedAt > $1.updatedAt }
    }

    var latestRunLabel: String {
        if let latestRun {
            return "\(latestRun.runType.replacingOccurrences(of: "_", with: " ")) · \(latestRun.status.label)"
        }
        if let latestRun = summary?.latestRun {
            return "\(latestRun.runType.replacingOccurrences(of: "_", with: " ")) · \(latestRun.status.label)"
        }
        return "No Agent Runs yet"
    }

    var evidenceLabel: String {
        let commentCount = summary?.commentCount ?? comments.count
        let runCount = summary?.runCount ?? runs.count
        let failed = summary?.failedRunCount ?? runs.filter { $0.status == .failed }.count
        var parts = ["\(commentCount) comments", "\(runCount) runs"]
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }

    var latestActivityLabel: String {
        if let latestActivity = summary?.latestActivity, !latestActivity.isEmpty {
            return latestActivity
        }
        if let latest = comments.sorted(by: { $0.createdAt > $1.createdAt }).first {
            return latest.message
        }
        return ticket.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var nextActionLabel: String {
        if let nextAction = summary?.nextAction, !nextAction.isEmpty {
            return nextAction
        }
        if let approvalState = ticket.approvalState, approvalState.contains("waiting") {
            return "Waiting for approval"
        }
        return "Use Tickets for dispatch, approval, and review controls"
    }

    var routePacketLabel: String? {
        guard let packet = summary?.latestRoutePacket, !packet.isEmpty else { return nil }
        let keys = ["route_mode", "route", "suggested_compute_route", "worker_lane", "tool_policy", "approval_required"]
        let parts = keys.compactMap { key -> String? in
            guard let value = packet[key]?.displayValue,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "\(key.replacingOccurrences(of: "_", with: " ")): \(value)"
        }
        return parts.prefix(3).joined(separator: " · ")
    }

    var approvalLabel: String? {
        if let count = summary?.approvalCount, count > 0 {
            return "\(count) approval\(count == 1 ? "" : "s")"
        }
        if let approvalState = ticket.approvalState, !approvalState.isEmpty {
            return approvalState.replacingOccurrences(of: "_", with: " ")
        }
        return nil
    }
}

struct DirectChatTriagePreview: Identifiable, Hashable, Sendable {
    let id: String
    let traceId: String?
    let targetAgentId: String
    let sourceText: String
    let intentType: String
    let recommendedLane: String
    let riskLevel: String
    let needsTicket: Bool
    let needsApproval: Bool
    let suggestedOwner: String
    let suggestedWorker: String?
    let suggestedComputeRoute: String
    let deliveryMode: String
    let autonomyLevel: String
    let nextAction: String
    let reason: String
    let approvalGate: String?
    let approvalState: String?
    let workerLane: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let confidence: Double?
    let tags: [String]

    var intentLabel: String {
        intentType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var riskLabel: String {
        riskLevel.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var nextActionLabel: String {
        nextAction.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var deliveryLabel: String {
        DMDeliveryMode.parse(deliveryMode)?.displayLabel
            ?? deliveryMode.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

@Model
final class DMConversation {
    @Attribute(.unique) var agentId: String
    var lastMessageText: String
    var lastMessageDate: Date
    var unreadCount: Int
    var activeTicketId: String?
    var activeTicketTitle: String?
    var orcaChannelId: String?

    @Relationship(deleteRule: .cascade, inverse: \DMMessage.conversation)
    var messages: [DMMessage]

    init(agentId: String) {
        self.agentId = agentId
        self.lastMessageText = ""
        self.lastMessageDate = Date()
        self.unreadCount = 0
        self.activeTicketId = nil
        self.activeTicketTitle = nil
        self.orcaChannelId = nil
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
    var traceId: String?
    var source: String?
    var lane: String?
    var deliveryMode: String?
    var provenance: String?
    var deliveryState: String?
    var userDeliveryState: String?
    var remoteMessageId: String?
    var computeRunId: String?
    var triageId: String?
    var triageTraceId: String?

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
        self.traceId = nil
        self.source = nil
        self.lane = nil
        self.deliveryMode = nil
        self.provenance = nil
        self.deliveryState = nil
        self.userDeliveryState = nil
        self.remoteMessageId = nil
        self.computeRunId = nil
        self.triageId = nil
        self.triageTraceId = nil
    }
}
