import Foundation

public enum OrcaRuntimeSSEError: Error, Equatable, LocalizedError {
    case invalidUTF8
    case lineTooLong
    case missingEventID
    case invalidEventType(String)
    case eventIDMismatch(expected: String, actual: String)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "ORCA Runtime stream contained invalid UTF-8."
        case .lineTooLong:
            return "ORCA Runtime stream exceeded its bounded line length."
        case .missingEventID:
            return "ORCA Runtime stream omitted its reconciliation cursor."
        case let .invalidEventType(type):
            return "ORCA Runtime stream returned unsupported event type \(type)."
        case let .eventIDMismatch(expected, actual):
            return "ORCA Runtime stream cursor mismatch: expected \(expected), received \(actual)."
        case let .invalidPayload(reason):
            return "ORCA Runtime stream payload is invalid: \(reason)."
        }
    }
}

public struct OrcaRuntimeSSEFrame: Equatable, Sendable {
    public let eventID: String
    public let event: String
    public let data: Data

    public init(eventID: String, event: String, data: Data) {
        self.eventID = eventID
        self.event = event
        self.data = data
    }
}

public struct OrcaRuntimeSSEParser: Sendable {
    private static let maximumLineBytes = 1_048_576

    private var lineBytes: [UInt8] = []
    private var eventID: String?
    private var event = "message"
    private var dataLines: [String] = []

    public init() {}

    public mutating func consume(_ byte: UInt8) throws -> OrcaRuntimeSSEFrame? {
        if byte == 0x0A {
            return try consumeLine()
        }
        guard lineBytes.count < Self.maximumLineBytes else {
            throw OrcaRuntimeSSEError.lineTooLong
        }
        lineBytes.append(byte)
        return nil
    }

    public mutating func finish() throws -> OrcaRuntimeSSEFrame? {
        if !lineBytes.isEmpty {
            if let frame = try consumeLine() { return frame }
        }
        return try dispatchFrame()
    }

    private mutating func consumeLine() throws -> OrcaRuntimeSSEFrame? {
        if lineBytes.last == 0x0D {
            lineBytes.removeLast()
        }
        guard let line = String(bytes: lineBytes, encoding: .utf8) else {
            throw OrcaRuntimeSSEError.invalidUTF8
        }
        lineBytes.removeAll(keepingCapacity: true)
        if line.isEmpty {
            return try dispatchFrame()
        }
        if line.hasPrefix(":") { return nil }

        let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(pieces[0])
        var value = pieces.count == 2 ? String(pieces[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "id":
            guard !value.contains("\0") else {
                throw OrcaRuntimeSSEError.invalidPayload("event id contains a null byte")
            }
            eventID = value
        case "event":
            event = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
        return nil
    }

    private mutating func dispatchFrame() throws -> OrcaRuntimeSSEFrame? {
        guard !dataLines.isEmpty else {
            resetFrame()
            return nil
        }
        guard let eventID, !eventID.isEmpty else {
            throw OrcaRuntimeSSEError.missingEventID
        }
        let data = Data(dataLines.joined(separator: "\n").utf8)
        let frame = OrcaRuntimeSSEFrame(eventID: eventID, event: event, data: data)
        resetFrame()
        return frame
    }

    private mutating func resetFrame() {
        eventID = nil
        event = "message"
        dataLines.removeAll(keepingCapacity: true)
    }
}
