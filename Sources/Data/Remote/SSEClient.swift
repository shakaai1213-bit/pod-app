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

        let delegate = SSEDelegate(continuation: continuation, manager: self, mode: .chat)
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()

        // Signal connected immediately — Task.sleep hangs on iOS 26 beta
        if !isCancelled {
            continuation.yield(.connected)
        }
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
    private let mode: SSEStreamManager.StreamMode

    private var eventType: String?
    private var eventData: String?

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
        // "connected" and "keepalive" are stream-agnostic.
        if type == "keepalive" {
            continuation.yield(.keepalive)
            return
        }
        if type == "connected" {
            continuation.yield(.connected)
            return
        }
        switch mode {
        case .chat:
            if type == "message", let jsonData = data.data(using: .utf8) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let payload = try? decoder.decode(MessageNewPayload.self, from: jsonData) {
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
                continuation.yield(.ticketLifecycle(envelope))
            }
            // Silent skip on undecodable — backend may add future event types
            // (e.g. heartbeat, schema bump); don't break the stream on those.
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

