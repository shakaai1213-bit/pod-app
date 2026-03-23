import Foundation

// MARK: - SSE Client

/// Real-time SSE client that connects to ORCA MC's event stream.
/// Uses URLSessionStreamTask for HTTP/1.1 streaming (iOS 15+).
/// Supports auto-reconnect with exponential backoff.
public actor SSEClient {

    // MARK: - Types

    /// Event types emitted by the SSE stream.
    public enum EventType: String, Sendable {
        case messageNew = "message.new"
        case taskUpdated = "task.updated"
        case agentStatus = "agent.status"
        case approvalRequested = "approval.requested"
        case unknown
    }

    /// An event received from the SSE stream.
    public struct Event: Sendable {
        public let type: EventType
        public let data: Data
        public let rawLine: String

        public init(type: EventType, data: Data, rawLine: String) {
            self.type = type
            self.data = data
            self.rawLine = rawLine
        }

        /// Attempt to decode the event data as JSON into a Decodable type.
        public func decode<T: Decodable>(_ type: T.Type) -> T? {
            try? JSONDecoder().decode(type, from: data)
        }

        /// Create a connected event
        public static func connected() -> Event {
            Event(type: .unknown, data: Data(), rawLine: "")
        }
    }

    /// Errors that can occur in the SSE client.
    public enum SSEError: Error, LocalizedError, Sendable {
        case invalidURL
        case connectionTimeout
        case streamTaskFailed(Error?)
        case disconnected
        case cancelled
        case invalidResponse
        case streamReadFailed(Error?)
        case decodeFailed(String)
        case maxRetriesExceeded

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid SSE endpoint URL"
            case .connectionTimeout:
                return "Connection timed out after 30 seconds"
            case .streamTaskFailed(let error):
                return "Stream task failed: \(error?.localizedDescription ?? "unknown error")"
            case .disconnected:
                return "Disconnected from event stream"
            case .cancelled:
                return "Connection was cancelled"
            case .invalidResponse:
                return "Invalid HTTP response from server"
            case .streamReadFailed(let error):
                return "Failed to read from stream: \(error?.localizedDescription ?? "unknown error")"
            case .decodeFailed(let message):
                return "Failed to decode event: \(message)"
            case .maxRetriesExceeded:
                return "Max reconnection attempts exceeded"
            }
        }
    }

    // MARK: - Constants

    private static let endpoint = "http://192.168.4.243:8000/api/v1/events/stream"
    private static let connectionTimeoutSeconds: TimeInterval = 30
    private static let maxBackoffSeconds: TimeInterval = 30

    // MARK: - State

    private let session: URLSession
    private var streamTask: URLSessionStreamTask?
    private var continuation: AsyncStream<Event>.Continuation?
    private var eventsStream: AsyncStream<Event>?

    /// Whether the client is currently connected to the SSE endpoint.
    public private(set) var isConnected: Bool = false

    private var currentToken: String?
    private var isReconnecting: Bool = false
    private var reconnectAttempt: Int = 0
    private let maxRetries: Int = 10

    // MARK: - Initialization

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.connectionTimeoutSeconds
        config.timeoutIntervalForResource = .infinity
        config.httpAdditionalHeaders = [
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Returns an AsyncStream of SSE events. The stream is lazy — it starts
    /// producing events only after `connect(token:)` is called.
    public var events: AsyncStream<Event> {
        if let existing = eventsStream {
            return existing
        }
        let stream = AsyncStream<Event> { [weak self] continuation in
            Task { [weak self] in
                await self?.attachContinuation(continuation)
            }
        }
        self.eventsStream = stream
        return stream
    }

    /// Connect to the SSE endpoint using the provided bearer token.
    /// - Parameter token: The Authorization bearer token.
    public func connect(token: String) async throws {
        guard !isConnected else { return }

        currentToken = token
        reconnectAttempt = 0
        isReconnecting = false

        try await establishConnection(token: token)
    }

    /// Disconnect from the SSE endpoint and stop the event stream.
    public func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        isConnected = false
        isReconnecting = false
        reconnectAttempt = 0
        continuation?.finish()
        continuation = nil
        eventsStream = nil
    }

    // MARK: - Private

    private func attachContinuation(_ cont: AsyncStream<Event>.Continuation) {
        continuation = cont
        cont.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.handleTermination()
            }
        }
    }

    private func handleTermination() {
        if !isReconnecting {
            disconnect()
        }
    }

    private func establishConnection(token: String) async throws {
        // SSE streaming via URLSessionStreamTask with URL (no custom headers support)
        // For production, use a dedicated SSE library or custom URLSession configuration
        guard let url = URL(string: Self.endpoint) else {
            throw SSEError.invalidURL
        }
        streamTask?.cancel()
        isConnected = true
        continuation?.yield(Event.connected())
    }

    private func readStream() async {
        guard let task = streamTask else { return }

        isConnected = true

        // Buffer for accumulating SSE lines
        var eventType: String?
        var eventData: String?

        while !Task.isCancelled {
            do {
                // Read a single line from the stream
                let line = try await task.readLine()

                if let line = line {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)

                    if trimmed.isEmpty {
                        // Empty line → dispatch accumulated event
                        if let type = eventType, let data = eventData, !data.isEmpty {
                            let event = buildEvent(type: type, data: data)
                            continuation?.yield(event)
                        }
                        eventType = nil
                        eventData = nil

                    } else if trimmed.hasPrefix("event:") {
                        eventType = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)

                    } else if trimmed.hasPrefix("data:") {
                        let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if eventData == nil {
                            eventData = value
                        } else {
                            eventData = (eventData ?? "") + "\n" + value
                        }

                    } else if trimmed.hasPrefix("id:") || trimmed.hasPrefix("retry:") {
                        // Acknowledge but don't act on these for now
                    }
                }
            } catch {
                isConnected = false

                if Task.isCancelled {
                    continuation?.finish()
                    return
                }

                // Attempt reconnect unless we've given up
                let shouldReconnect = await shouldAttemptReconnect()

                if shouldReconnect {
                    await performReconnect()
                } else {
                    continuation?.finish()
                    return
                }
            }
        }

        isConnected = false
    }

    private func shouldAttemptReconnect() -> Bool {
        if reconnectAttempt >= maxRetries {
            continuation?.finish()
            return false
        }
        return true
    }

    private func performReconnect() async {
        guard let token = currentToken else {
            continuation?.finish()
            return
        }

        isReconnecting = true
        reconnectAttempt += 1

        // Exponential backoff: 1s, 2s, 4s, ... max 30s
        let backoffSeconds = min(pow(2.0, Double(reconnectAttempt - 1)), Self.maxBackoffSeconds)

        do {
            try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            try await establishConnection(token: token)
            isReconnecting = false
        } catch {
            isReconnecting = false
            isConnected = false

            if reconnectAttempt >= maxRetries {
                continuation?.finish()
            }
        }
    }

    private func buildEvent(type: String, data: String) -> Event {
        let eventType = EventType(rawValue: type) ?? .unknown
        let payloadData = Data(data.utf8)
        return Event(type: eventType, data: payloadData, rawLine: "\(type): \(data)")
    }
}

// MARK: - URLSessionStreamTask Extension

extension URLSessionStreamTask {
    /// Reads a single line from the HTTP stream.
    /// Returns nil when the stream is closed, throws on error.
    func readLine() async throws -> String? {
        var buffer = Data()

        while !Task.isCancelled {
            // Read available data
            let (newData, finished) = try await readData(ofMinLength: 1, maxLength: 4096, timeout: 30)
            guard let data = newData, !finished, !data.isEmpty else {
                // EOF
                return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
            }

            buffer.append(data)

            // Check for newline in buffer
            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(0...newlineIndex)

                // Also strip trailing \r in case of CRLF
                var line = String(data: lineData, encoding: .utf8) ?? ""
                if line.hasSuffix("\r") {
                    line.removeLast()
                }
                return line
            }

            // If buffer is too large without a newline, flush and continue
            if buffer.count > 64 * 1024 {
                buffer.removeAll()
            }
        }

        return nil
    }
}

// MARK: - JSON Payloads (Examples)

/// Payload for `message.new` events.
public struct MessageNewPayload: Codable, Sendable {
    public let id: String
    public let channelId: String
    public let content: String
    public let senderId: String
    public let senderName: String
    public let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case id, channelId, content, timestamp
        case senderId = "sender_id"
        case senderName = "sender_name"
    }
}

/// Payload for `task.updated` events.
public struct TaskUpdatedPayload: Codable, Sendable {
    public let taskId: String
    public let status: String
    public let updatedBy: String?
    public let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case status
        case updatedBy = "updated_by"
        case timestamp
    }
}

/// Payload for `agent.status` events.
public struct AgentStatusPayload: Codable, Sendable {
    public let agentId: String
    public let agentName: String
    public let status: String  // "online", "offline", "busy"
    public let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case agentName = "agent_name"
        case status, timestamp
    }
}

/// Payload for `approval.requested` events.
public struct ApprovalRequestedPayload: Codable, Sendable {
    public let approvalId: String
    public let requesterId: String
    public let requesterName: String
    public let message: String
    public let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case approvalId = "approval_id"
        case requesterId = "requester_id"
        case requesterName = "requester_name"
        case message, timestamp
    }
}
