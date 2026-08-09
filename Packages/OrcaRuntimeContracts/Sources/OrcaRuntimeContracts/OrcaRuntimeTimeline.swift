import Foundation

public enum OrcaRuntimeTimelineError: Error, Equatable, LocalizedError {
    case sequenceGap(expected: Int, actual: Int)
    case staleEvent(sequence: Int)
    case conflictingEvent(String)
    case conflictingTerminal(String)
    case invalidTerminalState(String)
    case cursorMismatch(expected: String?, actual: String?)

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
        ["completed", "failed", "cancelled"].contains(state)
            || ["turn.completed", "turn.failed", "turn.cancelled"].contains(eventType)
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
