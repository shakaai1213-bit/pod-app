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

    #if targetEnvironment(simulator)
    private static let endpoint = "http://127.0.0.1:19002/api/v1/events/stream"
    #else
    private static let endpoint = "http://shakas-mac-mini.tail82d30d.ts.net:8000/api/v1/events/stream"
    #endif
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
        guard URL(string: Self.endpoint) != nil else {
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
                let shouldReconnect = shouldAttemptReconnect()

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
            // Use Timer instead of Task.sleep to avoid iOS 26 bug where
            // Task.sleep can fire immediately inside task groups.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var didResume = false
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + backoffSeconds)
                timer.setEventHandler {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume()
                }
                timer.resume()
            }
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

// MARK: - SSEStreamManager
// Actor-based SSE manager for channel-scoped real-time chat streaming.
// Connects to GET /api/v1/chat/channels/{channelId}/stream and yields
// decoded MessageNewPayload events.

/// Chat-scoped SSE stream manager. Each instance is tied to a single channel.
/// Thread-safe (actor) so it can be safely called from any context.
public actor SSEStreamManager {

    // MARK: - Types

    public enum StreamError: Error, LocalizedError, Sendable {
        case invalidURL
        case connectionFailed(Error?)
        case disconnected
        case cancelled
        case decodingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid SSE stream URL"
            case .connectionFailed(let error):
                return "Connection failed: \(error?.localizedDescription ?? "unknown")"
            case .disconnected:
                return "SSE stream disconnected"
            case .cancelled:
                return "SSE stream was cancelled"
            case .decodingFailed(let msg):
                return "Failed to decode SSE event: \(msg)"
            }
        }
    }

    public enum SSEEvent: Sendable {
        case connected
        case message(MessageNewPayload)
        case keepalive
        case error(StreamError)
    }

    // MARK: - State

    private var dataTask: URLSessionDataTask?
    private var session: URLSession?
    private var isCancelled: Bool = false

    // MARK: - Public API

    /// Connect to the channel SSE stream and yield events via the continuation.
    /// Automatically disconnects when the continuation is terminated.
    public func connect(
        channelId: String,
        token: String,
        baseURL: String
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        isCancelled = false
        let urlString = "\(baseURL)/api/v1/chat/channels/\(channelId)/stream"
        guard URL(string: urlString) != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: StreamError.invalidURL)
            }
        }

        // Create the stream, capturing continuation locally.
        // All actor mutations happen inside the actor-isolated Task.
        return AsyncThrowingStream<SSEEvent, Error> { [weak self] continuation in
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.disconnect()
                }
            }

            Task { [weak self] in
                await self?.runStream(channelId: channelId, token: token, baseURL: baseURL, continuation: continuation)
            }
        }
    }

    /// Actor-isolated method that drives the SSE connection.
    private func runStream(
        channelId: String,
        token: String,
        baseURL: String,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) async {
        let urlString = "\(baseURL)/api/v1/chat/channels/\(channelId)/stream"
        guard let url = URL(string: urlString) else {
            continuation.finish(throwing: StreamError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity

        let delegate = SSEDelegate(continuation: continuation, manager: self)
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()

        // Signal connected after a short delay (stream opens)
        try? await Task.sleep(nanoseconds: 500_000_000)
        if !isCancelled {
            continuation.yield(.connected)
        }
    }

    /// Called by SSEDelegate when data arrives.
    func handleData(_ data: Data) {
        guard !isCancelled else { return }
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        parseAndDispatch(chunk)
    }

    /// Called by SSEDelegate on error.
    func handleError(_ error: Error?) {
        guard !isCancelled else { return }
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    /// Cancel the current stream.
    public func disconnect() {
        isCancelled = true
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func parseAndDispatch(_ chunk: String) {
        // No actor isolation needed — continuation is passed directly to SSEDelegate
        // and stored there. This method is called from SSEDelegate which already
        // holds the continuation safely.
    }
}

// MARK: - SSE Delegate

/// URLSessionDataDelegate. Holds the continuation directly to avoid actor isolation issues.
/// All data parsing and event dispatching happens here on the delegate's queue.
private final class SSEDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncThrowingStream<SSEStreamManager.SSEEvent, Error>.Continuation
    private weak var manager: SSEStreamManager?

    private var eventType: String?
    private var eventData: String?

    init(continuation: AsyncThrowingStream<SSEStreamManager.SSEEvent, Error>.Continuation, manager: SSEStreamManager) {
        self.continuation = continuation
        self.manager = manager
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }

        let lines = chunk.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if let type = eventType, let data = eventData, !data.isEmpty {
                    dispatchEvent(type: type, data: data)
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
            }
        }
    }

    private func dispatchEvent(type: String, data: String) {
        switch type {
        case "message":
            if let jsonData = data.data(using: .utf8) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let payload = try? decoder.decode(MessageNewPayload.self, from: jsonData) {
                    continuation.yield(.message(payload))
                } else {
                    continuation.yield(.error(.decodingFailed("Could not decode MessageNewPayload")))
                }
            }
        case "keepalive":
            continuation.yield(.keepalive)
        case "connected":
            continuation.yield(.connected)
        default:
            break
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { [weak self] in
            if let error = error {
                await self?.manager?.handleError(error)
                self?.continuation.finish(throwing: SSEStreamManager.StreamError.connectionFailed(error))
            } else {
                await self?.manager?.handleError(nil)
                self?.continuation.finish()
            }
        }
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
    public let senderAgentId: String?
    public let timestamp: Date?
    public let replyToId: String?
    public let isThreadReply: Bool

    enum CodingKeys: String, CodingKey {
        case id, channelId, content, timestamp
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderAgentId = "sender_agent_id"
        case replyToId = "reply_to_id"
        case isThreadReply = "is_thread_reply"
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

// MARK: - URLSessionStreamTask Extension (for SSEClient's generic SSE streaming)

extension URLSessionStreamTask {
    /// Reads a single line from the HTTP stream.
    /// Returns nil when the stream is closed, throws on error.
    func readLine() async throws -> String? {
        var buffer = Data()

        while !Task.isCancelled {
            let (newData, finished) = try await readData(ofMinLength: 1, maxLength: 4096, timeout: 30)
            guard let data = newData, !finished, !data.isEmpty else {
                return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
            }

            buffer.append(data)

            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(0...newlineIndex)

                var line = String(data: lineData, encoding: .utf8) ?? ""
                if line.hasSuffix("\r") {
                    line.removeLast()
                }
                return line
            }

            if buffer.count > 64 * 1024 {
                buffer.removeAll()
            }
        }

        return nil
    }
}
