import Foundation

/// Scheduling state is independent of the UI's disposable runtime projection.
public struct OrcaConsolePollingPolicy {
    public private(set) var messageInterval: TimeInterval = 4
    public private(set) var healthyTurnOutstanding = false
    /// Message responsiveness survives reconcile errors, but is bounded from the send.
    public private(set) var awaitingReply = false
    public private(set) var awaitedTurnID: String?
    private var sentAt: Date?
    private let replyGraceSeconds: TimeInterval
    private var lastMemoryAt: Date?
    private var memoryDirty = true
    private var turnID: String?
    private var failureDelay: TimeInterval = 30
    private var retryAt: Date?
    private var serverDelaySeconds = 2
    private var terminalTurns: [String] = []

    public init(replyGraceSeconds: TimeInterval = 300) {
        self.replyGraceSeconds = replyGraceSeconds
    }

    public mutating func selected() {
        messageInterval = 4
        memoryDirty = true
    }

    public mutating func sent(now: Date = Date()) {
        selected()
        awaitingReply = true
        awaitedTurnID = nil
        sentAt = now
        failureDelay = 30
        retryAt = nil
        serverDelaySeconds = 2
    }

    /// Backend source of truth: workspace-mission-control/backend/app/schemas/chat.py:71–91
    /// (OpenClaw-Config 3d20202b): pending states and aliases precede the terminal set.
    public static func isReplyInHand(responseState: String?, terminalKind: OrcaRuntimeTerminalKind?) -> Bool {
        if terminalKind != nil { return true }
        let normalized: String?
        switch responseState {
        case "waiting_for_agent": normalized = "waiting_for_live_agent"
        case "delivery_degraded": normalized = "delivery_nats_failed"
        default: normalized = responseState
        }
        switch normalized {
        case "response_received", "fallback_presented", "ticket_required", "failed": return true
        case "waiting_for_live_agent", "compute_running", "claimed_by_agent", "working",
             "delivery_nats_failed", "agent_unresponsive", "recorded", nil: return false
        default: return false
        }
    }

    /// The latest successful send replaces the turn whose server state we await.
    public mutating func recordAwaitedTurn(_ id: String) {
        awaitedTurnID = id
    }

    /// Inspect server truth before the transcript projection drops response metadata.
    public static func hasPolledReply(awaitedTurnID: String?, messages: [OrcaRuntimeConversationMessage], oldIDs: Set<String>) -> Bool {
        messages.contains { message in
            if message.id == awaitedTurnID,
               isReplyInHand(responseState: message.responseState, terminalKind: nil) { return true }
            let nonUser = message.messageType.lowercased() == "system"
                || message.senderAgentID != nil || message.terminalKind != nil
            return !oldIDs.contains(message.id) && nonUser
                && isReplyInHand(responseState: message.responseState, terminalKind: message.terminalKind)
        }
    }

    public mutating func replyInHand() {
        awaitingReply = false
    }

    public mutating func messagesMerged(changed: Bool, replyArrived: Bool = false, now: Date = Date()) {
        if replyArrived || sentAt.map({ now.timeIntervalSince($0) >= replyGraceSeconds }) == true {
            awaitingReply = false
        }
        if changed { memoryDirty = true }
        messageInterval = changed || awaitingReply || healthyTurnOutstanding ? 4 : min(60, messageInterval * 2)
    }

    public mutating func messagesFailed() {
        awaitingReply = false
        healthyTurnOutstanding = false
        messagesMerged(changed: false)
    }

    public mutating func shouldFetchMemory(now: Date) -> Bool {
        guard memoryDirty || lastMemoryAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return false }
        memoryDirty = false
        lastMemoryAt = now // Failed fetches also consume the interval.
        return true
    }

    public mutating func shouldReconcile(turn: String, now: Date) -> Bool {
        if turnID != turn {
            turnID = turn
            failureDelay = 30
            retryAt = nil
            serverDelaySeconds = 2
        }
        return !terminalTurns.contains(turn) && (retryAt.map { now >= $0 } ?? true)
    }

    public mutating func failed(now: Date) {
        healthyTurnOutstanding = false
        retryAt = max(retryAt ?? now, now.addingTimeInterval(failureDelay))
        failureDelay = min(300, failureDelay * 2)
    }

    public mutating func updated(turn: String, terminal: Bool, stuck: Bool, hint: Int?, now: Date) {
        if terminal {
            if !terminalTurns.contains(turn) { terminalTurns.append(turn) }
            if terminalTurns.count > 64 { terminalTurns.removeFirst() }
        }
        if terminal || stuck { awaitingReply = false }
        healthyTurnOutstanding = !terminal && !stuck
        if !terminal {
            serverDelaySeconds = Self.pollDelay(hint ?? serverDelaySeconds, stuck: stuck)
            retryAt = now.addingTimeInterval(TimeInterval(serverDelaySeconds))
        }
    }

    public static func pollDelay(_ hint: Int?, stuck: Bool) -> Int {
        let seconds = min(120, max(2, hint ?? (stuck ? 30 : 2)))
        // Older backends use a healthy 2-second hint even for stuck turns.
        return stuck ? max(30, seconds) : seconds
    }
}
