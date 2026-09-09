import Foundation

public enum OrcaRuntimeTimelineError: Error, Equatable, LocalizedError {
    case sequenceGap(expected: Int, actual: Int)
    case staleEvent(sequence: Int)
    case conflictingEvent(String)
    case conflictingTerminal(String)
    case invalidTerminalState(String)
    case cursorMismatch(expected: String?, actual: String?)
    case reconciliationMismatch(String)

    public var errorDescription: String? {
        switch self {
        case let .sequenceGap(expected, actual):
            return "Runtime event gap: expected sequence \(expected), received \(actual)."
        case let .staleEvent(sequence):
            return "Runtime event sequence \(sequence) is stale and was not previously acknowledged."
        case let .conflictingEvent(eventID):
            return "Runtime event \(eventID) conflicts with an acknowledged event."
        case let .conflictingTerminal(eventID):
            return "Runtime turn already has a different terminal event; rejected \(eventID)."
        case let .invalidTerminalState(state):
            return "Runtime terminal outcome used non-terminal state \(state)."
        case let .cursorMismatch(expected, actual):
            return "Runtime cursor mismatch: expected \(expected ?? "none"), received \(actual ?? "none")."
        case let .reconciliationMismatch(reason):
            return "Runtime reconciliation failed closed: \(reason)."
        }
    }
}

public struct OrcaRuntimeResumePoint: Equatable, Sendable {
    public let eventID: String?
    public let sequence: Int
    public let cursor: String?

    public init(eventID: String? = nil, sequence: Int = -1, cursor: String? = nil) {
        self.eventID = eventID
        self.sequence = sequence
        self.cursor = cursor
    }

    public var nextSequence: Int { sequence + 1 }
}

public struct OrcaRuntimeTimelineEvent: Equatable, Sendable {
    public let eventID: String
    public let sequence: Int
    public let cursor: String
    public let turnID: String
    public let eventType: String
    public let state: String?

    public init(
        eventID: String,
        sequence: Int,
        cursor: String,
        turnID: String,
        eventType: String,
        state: String?
    ) {
        self.eventID = eventID
        self.sequence = sequence
        self.cursor = cursor
        self.turnID = turnID
        self.eventType = eventType
        self.state = state
    }

    init(generated event: Components.Schemas.ChatRuntimeTimelineEventRead) {
        self.init(
            eventID: event.eventId,
            sequence: event.sequence,
            cursor: event.cursor,
            turnID: event.turnId,
            eventType: event.eventType.rawValue,
            state: event.state?.rawValue
        )
    }

    var isTerminal: Bool {
        ["turn.completed", "turn.failed", "turn.cancelled"].contains(eventType)
    }
}

public struct OrcaRuntimeTerminal: Equatable, Sendable {
    public let state: String
    public let summary: String
    public let errorCode: String?

    init(generated terminal: Components.Schemas.ChatRuntimeTerminalOutcomeRead) {
        state = terminal.state.rawValue
        summary = terminal.summary
        errorCode = terminal.errorCode
    }
}

public enum OrcaRuntimeEventApplyResult: Equatable, Sendable {
    case applied
    case duplicate
}

public struct OrcaRuntimeTimelineReducer: Sendable {
    public private(set) var events: [OrcaRuntimeTimelineEvent] = []
    public private(set) var resumePoint: OrcaRuntimeResumePoint
    public private(set) var terminal: OrcaRuntimeTerminal?

    private var eventsByID: [String: OrcaRuntimeTimelineEvent] = [:]
    private var eventsByCursor: [String: OrcaRuntimeTimelineEvent] = [:]
    private var terminalEventID: String?

    public init(resumePoint: OrcaRuntimeResumePoint = .init()) {
        self.resumePoint = resumePoint
    }

    @discardableResult
    public mutating func apply(_ event: OrcaRuntimeTimelineEvent) throws -> OrcaRuntimeEventApplyResult {
        if event.eventID == resumePoint.eventID,
           event.sequence == resumePoint.sequence,
           event.cursor == resumePoint.cursor {
            return .duplicate
        }
        if let existing = eventsByID[event.eventID] {
            guard existing == event else {
                throw OrcaRuntimeTimelineError.conflictingEvent(event.eventID)
            }
            return .duplicate
        }
        if let existing = eventsByCursor[event.cursor] {
            guard existing == event else {
                throw OrcaRuntimeTimelineError.conflictingEvent(event.eventID)
            }
            return .duplicate
        }
        guard event.sequence >= resumePoint.nextSequence else {
            throw OrcaRuntimeTimelineError.staleEvent(sequence: event.sequence)
        }
        guard event.sequence == resumePoint.nextSequence else {
            throw OrcaRuntimeTimelineError.sequenceGap(
                expected: resumePoint.nextSequence,
                actual: event.sequence
            )
        }
        if event.isTerminal, let existingTerminal = terminalEventID,
           existingTerminal != event.eventID {
            throw OrcaRuntimeTimelineError.conflictingTerminal(event.eventID)
        }

        events.append(event)
        eventsByID[event.eventID] = event
        eventsByCursor[event.cursor] = event
        resumePoint = OrcaRuntimeResumePoint(
            eventID: event.eventID,
            sequence: event.sequence,
            cursor: event.cursor
        )
        if event.isTerminal {
            terminalEventID = event.eventID
        }
        return .applied
    }

    public mutating func apply(
        _ turn: Components.Schemas.ChatRuntimeTurnRead
    ) throws -> [OrcaRuntimeEventApplyResult] {
        let results = try (turn.events ?? []).map {
            try apply(OrcaRuntimeTimelineEvent(generated: $0))
        }
        guard turn.latestCursor == resumePoint.cursor else {
            throw OrcaRuntimeTimelineError.cursorMismatch(
                expected: resumePoint.cursor,
                actual: turn.latestCursor
            )
        }
        if let outcome = turn.terminalOutcome {
            let mapped = OrcaRuntimeTerminal(generated: outcome)
            guard ["completed", "failed", "cancelled"].contains(mapped.state) else {
                throw OrcaRuntimeTimelineError.invalidTerminalState(mapped.state)
            }
            if let terminal, terminal != mapped {
                throw OrcaRuntimeTimelineError.conflictingTerminal(turn.turnId)
            }
            terminal = mapped
        }
        return results
    }
}

public struct OrcaRuntimeReconciliationUpdate: Equatable, Sendable {
    public let turn: Components.Schemas.ChatRuntimeTurnRead
    public let cursor: String
    public let cursorState: Components.Schemas.ChatRuntimeCursorState
    public let appliedEventIDs: [String]
    public let rebuilt: Bool
    public let terminalBecameVisible: Bool
    public let pollAfterSeconds: Int?

    public init(
        turn: Components.Schemas.ChatRuntimeTurnRead,
        cursor: String,
        cursorState: Components.Schemas.ChatRuntimeCursorState,
        appliedEventIDs: [String],
        rebuilt: Bool,
        terminalBecameVisible: Bool,
        pollAfterSeconds: Int?
    ) {
        self.turn = turn
        self.cursor = cursor
        self.cursorState = cursorState
        self.appliedEventIDs = appliedEventIDs
        self.rebuilt = rebuilt
        self.terminalBecameVisible = terminalBecameVisible
        self.pollAfterSeconds = pollAfterSeconds
    }
}

public struct OrcaRuntimeTurnReconciler: Sendable {
    public let turnID: String
    public private(set) var turn: Components.Schemas.ChatRuntimeTurnRead?
    public private(set) var reconciliationCursor: String?
    public private(set) var timeline = OrcaRuntimeTimelineReducer()

    private var terminalWasDelivered = false

    public init(turnID: String, persistedCursor: String? = nil) {
        self.turnID = turnID
        reconciliationCursor = persistedCursor
    }

    @discardableResult
    public mutating func apply(
        _ envelope: Components.Schemas.ChatRuntimeTurnReconciliationRead
    ) throws -> OrcaRuntimeReconciliationUpdate {
        try validateEnvelope(envelope)

        let nextTurn = envelope.turn
        let nextEvents = nextTurn.events ?? []
        let delta = envelope.eventsAfterCursor ?? []
        let previousEvents = turn?.events ?? []
        let wasTerminal = terminalWasDelivered
        let rebuilt: Bool
        let appliedEventIDs: [String]

        switch envelope.cursorState {
        case .initial, .resetRequired:
            try Self.require(delta == nextEvents, "snapshot delta is not complete")
            try Self.require(
                Self.preservesHistory(previousEvents, in: nextEvents),
                "authoritative snapshot rewrote acknowledged history"
            )
            var replacement = OrcaRuntimeTimelineReducer()
            _ = try replacement.apply(nextTurn)
            timeline = replacement
            rebuilt = true
            appliedEventIDs = nextEvents.map(\.eventId)

        case .current:
            try Self.require(delta.isEmpty, "current cursor returned event deltas")
            if turn == nil {
                var replacement = OrcaRuntimeTimelineReducer()
                _ = try replacement.apply(nextTurn)
                timeline = replacement
                rebuilt = true
                appliedEventIDs = nextEvents.map(\.eventId)
            } else {
                try Self.require(previousEvents == nextEvents, "current cursor rewrote event history")
                rebuilt = false
                appliedEventIDs = []
            }

        case .advanced:
            if turn == nil {
                try Self.require(
                    Self.isSuffix(delta, of: nextEvents),
                    "advanced delta is not a suffix of the authoritative timeline"
                )
                var replacement = OrcaRuntimeTimelineReducer()
                _ = try replacement.apply(nextTurn)
                timeline = replacement
                rebuilt = true
                appliedEventIDs = nextEvents.map(\.eventId)
            } else {
                try Self.require(
                    Self.preservesHistory(previousEvents, in: nextEvents),
                    "advanced snapshot rewrote acknowledged history"
                )
                let expectedDelta = Array(nextEvents.dropFirst(previousEvents.count))
                try Self.require(delta == expectedDelta, "advanced delta does not match new events")
                for event in delta {
                    _ = try timeline.apply(OrcaRuntimeTimelineEvent(generated: event))
                }
                try Self.require(
                    timeline.resumePoint.cursor == nextTurn.latestCursor,
                    "advanced timeline did not reach the authoritative event cursor"
                )
                if let outcome = nextTurn.terminalOutcome {
                    let mapped = OrcaRuntimeTerminal(generated: outcome)
                    if let terminal = timeline.terminal {
                        try Self.require(terminal == mapped, "terminal outcome changed after delivery")
                    } else {
                        var complete = OrcaRuntimeTimelineReducer()
                        _ = try complete.apply(nextTurn)
                        timeline = complete
                    }
                }
                rebuilt = false
                appliedEventIDs = delta.map(\.eventId)
            }
        }

        turn = nextTurn
        reconciliationCursor = envelope.reconciliationCursor
        let isTerminal = envelope.terminal
        if isTerminal {
            terminalWasDelivered = true
        }
        return OrcaRuntimeReconciliationUpdate(
            turn: nextTurn,
            cursor: envelope.reconciliationCursor,
            cursorState: envelope.cursorState,
            appliedEventIDs: appliedEventIDs,
            rebuilt: rebuilt,
            terminalBecameVisible: isTerminal && !wasTerminal,
            pollAfterSeconds: envelope.pollAfterSeconds
        )
    }

    private func validateEnvelope(
        _ envelope: Components.Schemas.ChatRuntimeTurnReconciliationRead
    ) throws {
        try Self.require(
            envelope.contractVersion == .orca_chatRuntime_turnReconciliation_v1,
            "contract version is missing or unsupported"
        )
        try Self.require(envelope.turnId == turnID, "envelope belongs to another turn")
        try Self.require(envelope.turn.turnId == turnID, "snapshot belongs to another turn")
        try OrcaRuntimeClient.validateRuntimeTurn(envelope.turn, expectedTurnID: turnID)

        let events = envelope.turn.events ?? []
        let latestSequence = events.last?.sequence ?? -1
        try Self.require(
            Self.isTurnBoundCursor(
                envelope.reconciliationCursor,
                turnID: turnID,
                sequence: latestSequence
            ),
            "server cursor is not bound to this turn and sequence"
        )

        let terminalStates: Set<Components.Schemas.ChatRuntimeProgressState> = [
            .completed, .failed, .cancelled,
        ]
        let isTerminal = terminalStates.contains(envelope.turn.state)
        try Self.require(envelope.terminal == isTerminal, "terminal flag contradicts turn state")
        try Self.require(
            (envelope.turn.terminalOutcome != nil) == isTerminal,
            "terminal outcome contradicts turn state"
        )
        if isTerminal {
            try Self.require(envelope.pollAfterSeconds == nil, "terminal turn requested another poll")
        } else {
            try Self.require(
                envelope.pollAfterSeconds.map { (1...60).contains($0) } == true,
                "active turn omitted its bounded poll interval"
            )
        }

        switch envelope.cursorState {
        case .initial:
            try Self.require(envelope.requestedCursor == nil, "initial response echoed a cursor")
            try Self.require(envelope.changed, "initial response was marked unchanged")
        case .current:
            try Self.require(
                envelope.requestedCursor == envelope.reconciliationCursor,
                "current response did not echo the current cursor"
            )
            try Self.require(!envelope.changed, "current response was marked changed")
        case .advanced:
            try Self.require(envelope.requestedCursor != nil, "advanced response omitted its request cursor")
            try Self.require(
                envelope.requestedCursor != envelope.reconciliationCursor,
                "advanced response did not advance"
            )
            try Self.require(envelope.changed, "advanced response was marked unchanged")
        case .resetRequired:
            try Self.require(envelope.requestedCursor != nil, "reset response omitted its rejected cursor")
            try Self.require(
                envelope.requestedCursor != envelope.reconciliationCursor,
                "reset response accepted its rejected cursor"
            )
            try Self.require(envelope.changed, "reset response was marked unchanged")
        }

        if let expected = reconciliationCursor,
           envelope.cursorState == .current || envelope.cursorState == .advanced {
            try Self.require(
                envelope.requestedCursor == expected,
                "response does not continue the acknowledged reconciliation cursor"
            )
        }
    }

    private static func preservesHistory(
        _ acknowledged: [Components.Schemas.ChatRuntimeTimelineEventRead],
        in current: [Components.Schemas.ChatRuntimeTimelineEventRead]
    ) -> Bool {
        acknowledged.count <= current.count
            && Array(current.prefix(acknowledged.count)) == acknowledged
    }

    private static func isSuffix(
        _ suffix: [Components.Schemas.ChatRuntimeTimelineEventRead],
        of events: [Components.Schemas.ChatRuntimeTimelineEventRead]
    ) -> Bool {
        suffix.count <= events.count && Array(events.suffix(suffix.count)) == suffix
    }

    private static func isTurnBoundCursor(
        _ cursor: String,
        turnID: String,
        sequence: Int
    ) -> Bool {
        let prefix = "runtime-turn:\(turnID):\(sequence):"
        guard cursor.hasPrefix(prefix) else { return false }
        let digest = cursor.dropFirst(prefix.count)
        return digest.count == 24 && digest.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ reason: String) throws {
        guard condition() else {
            throw OrcaRuntimeTimelineError.reconciliationMismatch(reason)
        }
    }
}
