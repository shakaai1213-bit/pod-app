import Foundation

/// Scheduling state is independent of the UI's disposable runtime projection.
public struct OrcaConsolePollingPolicy {
    public private(set) var messageInterval: TimeInterval = 4
    public private(set) var healthyTurnOutstanding = false
    private var lastMemoryAt: Date?
    private var memoryDirty = true
    private var turnID: String?
    private var failureDelay: TimeInterval = 30
    private var retryAt: Date?
    private var serverDelaySeconds = 2
    private var terminalTurns: [String] = []

    public init() {}

    public mutating func selected() {
        messageInterval = 4
        memoryDirty = true
    }

    public mutating func sent() {
        selected()
        healthyTurnOutstanding = true
        failureDelay = 30
        retryAt = nil
        serverDelaySeconds = 2
    }

    public mutating func messagesMerged(changed: Bool) {
        if changed { memoryDirty = true }
        messageInterval = changed || healthyTurnOutstanding ? 4 : min(60, messageInterval * 2)
    }

    public mutating func messagesFailed() {
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
