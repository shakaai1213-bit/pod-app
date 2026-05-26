import Foundation


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
        case ticketLifecycle(TicketLifecycleEnvelope)
        case keepalive
        case error(StreamError)
    }

    public enum ConnectionState: String, Sendable {
        case idle
        case connecting
        case connected
        case reconnecting
        case stale
        case failed
        case disconnected
    }

    public struct StreamHealth: Sendable {
        public let state: ConnectionState
        public let lastConnectedAt: Date?
        public let lastEventAt: Date?
        public let lastErrorDescription: String?
        public let reconnectAttempt: Int

        public var isStale: Bool {
            guard state == .connected, let lastEventAt else { return state == .stale }
            return Date().timeIntervalSince(lastEventAt) > 30
        }
    }

    /// Stream mode determines how `SSEDelegate` decodes the `data:` body.
    /// `/chat/channels/<id>/stream` emits `event: message` with MessageNewPayload;
    /// `/tickets/stream` emits envelopes whose SSE event-name is the envelope
    /// type (e.g. "fyi") and whose data is a TicketLifecycleEnvelope.
    enum StreamMode: Sendable {
        case chat
        case tickets
    }

    // MARK: - State

    private var dataTask: URLSessionDataTask?
    private var session: URLSession?
    private var isCancelled: Bool = false
    private var health = StreamHealth(
        state: .idle,
        lastConnectedAt: nil,
        lastEventAt: nil,
        lastErrorDescription: nil,
        reconnectAttempt: 0
    )

    // MARK: - Public API

    /// Connect to the channel SSE stream and yield events via the continuation.
    /// Automatically disconnects when the continuation is terminated.
    public func connect(
        channelId: String,
        token: String,
        baseURL: String
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        isCancelled = false
        markConnecting()
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

        let delegate = SSEDelegate(continuation: continuation, manager: self, mode: .chat)
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()

        // The delegate yields .connected only after the HTTP response is
        // validated or a backend "connected" SSE event arrives.
    }

    /// Connect to the team-wide ticket lifecycle SSE stream.
    /// Backend: `/api/v1/tickets/stream` fans the `team.tickets.events` NATS
    /// subject (created-no-assignee, claimed, in_progress, closed, cancelled,
    /// status transitions). Assignee-routed lifecycle events go through the
    /// agent's NATS inbox, not this stream.
    /// Caller consumes events on the returned AsyncThrowingStream.
    public func connectTickets(
        token: String,
        baseURL: String
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        isCancelled = false
        markConnecting()
        let urlString = "\(baseURL)/api/v1/tickets/stream"
        guard URL(string: urlString) != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: StreamError.invalidURL)
            }
        }

        return AsyncThrowingStream<SSEEvent, Error> { [weak self] continuation in
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.disconnect()
                }
            }

            Task { [weak self] in
                await self?.runTicketsStream(token: token, baseURL: baseURL, continuation: continuation)
            }
        }
    }

    private func runTicketsStream(
        token: String,
        baseURL: String,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) async {
        let urlString = "\(baseURL)/api/v1/tickets/stream"
        guard let url = URL(string: urlString) else {
            continuation.finish(throwing: StreamError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity

        let delegate = SSEDelegate(continuation: continuation, manager: self, mode: .tickets)
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()

        // The delegate yields .connected only after the HTTP response is
        // validated or a backend "connected" SSE event arrives.
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
        markFailed(error)
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    /// Cancel the current stream.
    public func disconnect() {
        isCancelled = true
        health = StreamHealth(
            state: .disconnected,
            lastConnectedAt: health.lastConnectedAt,
            lastEventAt: health.lastEventAt,
            lastErrorDescription: nil,
            reconnectAttempt: health.reconnectAttempt
        )
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    public func currentHealth() -> StreamHealth {
        if health.isStale {
            return StreamHealth(
                state: .stale,
                lastConnectedAt: health.lastConnectedAt,
                lastEventAt: health.lastEventAt,
                lastErrorDescription: health.lastErrorDescription,
                reconnectAttempt: health.reconnectAttempt
            )
        }
        return health
    }

    func markConnected() {
        let now = Date()
        health = StreamHealth(
            state: .connected,
            lastConnectedAt: now,
            lastEventAt: now,
            lastErrorDescription: nil,
            reconnectAttempt: 0
        )
    }

    func markEvent() {
        health = StreamHealth(
            state: health.state == .connected ? .connected : health.state,
            lastConnectedAt: health.lastConnectedAt,
            lastEventAt: Date(),
            lastErrorDescription: health.lastErrorDescription,
            reconnectAttempt: health.reconnectAttempt
        )
    }

    func markReconnecting() {
        health = StreamHealth(
            state: .reconnecting,
            lastConnectedAt: health.lastConnectedAt,
            lastEventAt: health.lastEventAt,
            lastErrorDescription: health.lastErrorDescription,
            reconnectAttempt: health.reconnectAttempt + 1
        )
    }

    private func markConnecting() {
        health = StreamHealth(
            state: .connecting,
            lastConnectedAt: health.lastConnectedAt,
            lastEventAt: health.lastEventAt,
            lastErrorDescription: nil,
            reconnectAttempt: health.reconnectAttempt
        )
    }

    private func markFailed(_ error: Error?) {
        health = StreamHealth(
            state: error == nil ? .disconnected : .failed,
            lastConnectedAt: health.lastConnectedAt,
            lastEventAt: health.lastEventAt,
            lastErrorDescription: error?.localizedDescription,
            reconnectAttempt: health.reconnectAttempt
        )
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
    private let mode: SSEStreamManager.StreamMode

    private var eventType: String?
    private var eventData: String?
    private var didYieldConnected = false
    private var lineBuffer = ""

    init(continuation: AsyncThrowingStream<SSEStreamManager.SSEEvent, Error>.Continuation,
         manager: SSEStreamManager,
         mode: SSEStreamManager.StreamMode) {
        self.continuation = continuation
        self.manager = manager
        self.mode = mode
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }

        lineBuffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
        let hasCompleteTrailingLine = lineBuffer.hasSuffix("\n")
        var lines = lineBuffer.components(separatedBy: "\n")
        lineBuffer = hasCompleteTrailingLine ? "" : (lines.popLast() ?? "")

        for line in lines {
            processLine(line)
        }
    }

    private func processLine(_ line: String) {
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

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            continuation.yield(.error(.connectionFailed(nil)))
            continuation.finish(throwing: SSEStreamManager.StreamError.connectionFailed(nil))
            completionHandler(.cancel)
            return
        }

        guard 200...299 ~= http.statusCode else {
            let error = SSEStreamManager.StreamError.decodingFailed("SSE HTTP \(http.statusCode)")
            continuation.yield(.error(error))
            continuation.finish(throwing: error)
            completionHandler(.cancel)
            return
        }

        yieldConnectedOnce()
        completionHandler(.allow)
    }

    private func dispatchEvent(type: String, data: String) {
        // "connected" and "keepalive" are stream-agnostic.
        if type == "keepalive" {
            Task { [weak manager] in await manager?.markEvent() }
            continuation.yield(.keepalive)
            return
        }
        if type == "connected" {
            yieldConnectedOnce()
            return
        }
        switch mode {
        case .chat:
            if type == "message", let jsonData = data.data(using: .utf8) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let payload = try? decoder.decode(MessageNewPayload.self, from: jsonData) {
                    Task { [weak manager] in await manager?.markEvent() }
                    continuation.yield(.message(payload))
                } else {
                    continuation.yield(.error(.decodingFailed("Could not decode MessageNewPayload")))
                }
            }
        case .tickets:
            // Backend emits SSE event name = envelope `type`. For `/tickets/stream`
            // (fans team.tickets.events) the payload is type=fyi, occasionally
            // type=alert. Either way, the data body is the lifecycle envelope.
            guard let jsonData = data.data(using: .utf8) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let envelope = try? decoder.decode(TicketLifecycleEnvelope.self, from: jsonData) {
                Task { [weak manager] in await manager?.markEvent() }
                continuation.yield(.ticketLifecycle(envelope))
            }
            // Silent skip on undecodable — backend may add future event types
            // (e.g. heartbeat, schema bump); don't break the stream on those.
        }
    }

    private func yieldConnectedOnce() {
        guard !didYieldConnected else { return }
        didYieldConnected = true
        Task { [weak manager] in await manager?.markConnected() }
        continuation.yield(.connected)
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
    public let senderId: String?
    public let senderName: String?
    public let senderAgentId: String?
    public let timestamp: Date?
    public let replyToId: String?
    public let isThreadReply: Bool
    public let traceId: String?
    public let source: String?
    public let lane: String?
    public let messageType: String?
    public let deliveryMode: String?
    public let provenance: String?
    public let responseState: String?
    public let triageId: String?
    public let triageTraceId: String?

    enum CodingKeys: String, CodingKey {
        case id, channelId, content
        case channelIdSnake = "channel_id"
        case senderId = "sender_id"
        case senderUserId = "sender_user_id"
        case senderName = "sender_name"
        case senderAgentId = "sender_agent_id"
        case timestamp
        case createdAt = "created_at"
        case replyToId = "reply_to_id"
        case isThreadReply = "is_thread_reply"
        case traceId = "trace_id"
        case source, lane, provenance
        case messageType = "message_type"
        case deliveryMode = "delivery_mode"
        case responseState = "response_state"
        case triageId = "triage_id"
        case triageTraceId = "triage_trace_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
            ?? container.decode(String.self, forKey: .channelIdSnake)
        content = try container.decode(String.self, forKey: .content)
        senderId = try container.decodeIfPresent(String.self, forKey: .senderId)
            ?? container.decodeIfPresent(String.self, forKey: .senderUserId)
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
        senderAgentId = try container.decodeIfPresent(String.self, forKey: .senderAgentId)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
            ?? container.decodeIfPresent(Date.self, forKey: .createdAt)
        replyToId = try container.decodeIfPresent(String.self, forKey: .replyToId)
        isThreadReply = try container.decodeIfPresent(Bool.self, forKey: .isThreadReply) ?? false
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        lane = try container.decodeIfPresent(String.self, forKey: .lane)
        messageType = try container.decodeIfPresent(String.self, forKey: .messageType)
        deliveryMode = try container.decodeIfPresent(String.self, forKey: .deliveryMode)
        provenance = try container.decodeIfPresent(String.self, forKey: .provenance)
        responseState = try container.decodeIfPresent(String.self, forKey: .responseState)
        triageId = try container.decodeIfPresent(String.self, forKey: .triageId)
        triageTraceId = try container.decodeIfPresent(String.self, forKey: .triageTraceId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(channelId, forKey: .channelIdSnake)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(senderId, forKey: .senderId)
        try container.encodeIfPresent(senderName, forKey: .senderName)
        try container.encodeIfPresent(senderAgentId, forKey: .senderAgentId)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(replyToId, forKey: .replyToId)
        try container.encode(isThreadReply, forKey: .isThreadReply)
        try container.encodeIfPresent(traceId, forKey: .traceId)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(lane, forKey: .lane)
        try container.encodeIfPresent(messageType, forKey: .messageType)
        try container.encodeIfPresent(deliveryMode, forKey: .deliveryMode)
        try container.encodeIfPresent(provenance, forKey: .provenance)
        try container.encodeIfPresent(responseState, forKey: .responseState)
        try container.encodeIfPresent(triageId, forKey: .triageId)
        try container.encodeIfPresent(triageTraceId, forKey: .triageTraceId)
    }
}

/// Payload for ticket lifecycle events on `/api/v1/tickets/stream`.
/// Mirrors the envelope shape published by `services/tickets_publisher.py`
/// to the `team.tickets.events` NATS subject. Field set is intentionally
/// small — caller typically does a full `load()` refresh on receipt.
public struct TicketLifecycleEnvelope: Codable, Sendable {
    public let id: String?
    public let type: String?
    public let text: String?
    public let metadata: Metadata?

    public struct Metadata: Codable, Sendable {
        /// Lifecycle action: created | claimed | in_progress | closed | cancelled | stale | escalated
        public let action: String?
        public let ticketId: String?
        public let boardId: String?

        enum CodingKeys: String, CodingKey {
            case action
            case ticketId = "ticket_id"
            case boardId  = "board_id"
        }
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
