import Foundation

/// Sends messages through ORCA as agent-scoped chat.
actor AgentChatService {

    enum AgentChatError: Error, LocalizedError {
        case invalidURL
        case httpError(Int, String?)
        case noResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid agent endpoint URL"
            case .httpError(let code, let message):
                if let message, !message.isEmpty {
                    return "Agent returned HTTP \(code): \(message)"
                }
                return "Agent returned HTTP \(code)"
            case .noResponse: return "No response from agent"
            }
        }
    }

    private let agent: AgentInfo

    init(agent: AgentInfo) {
        self.agent = agent
    }

    struct ResponseChunk: Sendable {
        let content: String
        let metadata: ResponseMetadata?
    }

    struct ResponseMetadata: Sendable {
        let channelId: String
        let userMessageId: String
        let assistantMessageId: String
        let model: String?
        let backend: String?
        let tier: String?
        let tokenCount: Int?
        let traceId: String
        let source: String
        let lane: String
        let deliveryMode: String
        let provenance: String
        let responseState: String?
        let triageId: String?

        var displayName: String? {
            let route = tier ?? backend
            switch (route?.isEmpty == false ? route : nil, model?.isEmpty == false ? model : nil) {
            case let (route?, model?):
                return "\(route) · \(model)"
            case let (route?, nil):
                return route
            case let (nil, model?):
                return model
            default:
                return nil
            }
        }
    }

    private struct DirectAgentChatRequest: Encodable {
        let content: String
        let history: [HistoryMessage]
        let deliveryMode: String
        let asyncResponse: Bool
        let traceId: String?
        let triageId: String?
        let triageTraceId: String?
        let activeTicketId: String?
        let chatThreadId: String?

        struct HistoryMessage: Encodable {
            let role: String
            let content: String
        }

        enum CodingKeys: String, CodingKey {
            case content, history
            case deliveryMode = "delivery_mode"
            case asyncResponse = "async_response"
            case traceId = "trace_id"
            case triageId = "triage_id"
            case triageTraceId = "triage_trace_id"
            case activeTicketId = "active_ticket_id"
            case chatThreadId = "chat_thread_id"
        }
    }

    private struct DirectAgentChatResponse: Decodable {
        let channelId: String
        let userMessageId: String
        let assistantMessageId: String
        let content: String
        let metadata: DirectAgentChatMetadata

        enum CodingKeys: String, CodingKey {
            case content, metadata
            case channelId = "channel_id"
            case userMessageId = "user_message_id"
            case assistantMessageId = "assistant_message_id"
        }

        struct DirectAgentChatMetadata: Decodable {
            let model: String?
            let backend: String?
            let tier: String?
            let tokenCount: Int?
            let traceId: String
            let source: String
            let lane: String
            let deliveryMode: String?
            let provenance: String?
            let responseState: String?
            let triageId: String?

            enum CodingKeys: String, CodingKey {
                case model, backend, tier, source, lane, provenance
                case tokenCount = "token_count"
                case traceId = "trace_id"
                case deliveryMode = "delivery_mode"
                case responseState = "response_state"
                case triageId = "triage_id"
            }
        }
    }

    private struct ORCAChatMessage: Decodable {
        let id: String
        let senderAgentId: String?
        let content: String
        let messageType: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, content
            case senderAgentId = "sender_agent_id"
            case messageType = "message_type"
            case createdAt = "created_at"
        }
    }

    // MARK: - Send message via ORCA-controlled direct chat

    /// Sends a message to the ORCA direct-chat endpoint.
    /// Returns an AsyncThrowingStream so the UI can keep its streaming contract,
    /// even when ORCA returns a single non-streaming completion.
    func send(
        message: String,
        history: [(role: String, content: String)] = [],
        deliveryMode: DMDeliveryMode? = nil,
        triagePreview: DirectChatTriagePreview? = nil,
        activeTicketId: String? = nil,
        chatThreadId: String? = nil,
        traceId: String? = nil
    ) -> AsyncThrowingStream<ResponseChunk, Error> {
        return AsyncThrowingStream<ResponseChunk, Error> { continuation in
            Task {
                do {
                    let mode = deliveryMode ?? agent.defaultDeliveryMode
                    let body = DirectAgentChatRequest(
                        content: message,
                        history: history.suffix(20).map {
                            DirectAgentChatRequest.HistoryMessage(role: $0.role, content: $0.content)
                        },
                        deliveryMode: mode.rawValue,
                        asyncResponse: mode == .liveInbox,
                        traceId: traceId,
                        triageId: triagePreview?.id,
                        triageTraceId: triagePreview?.traceId,
                        activeTicketId: activeTicketId,
                        chatThreadId: chatThreadId
                    )
                    let response: DirectAgentChatResponse = try await APIClient.shared.post(
                        path: "/api/v1/chat/direct/\(agent.id)/send",
                        body: body
                    )
                    let content = response.content
                    let parsedState = DMDeliveryState.parse(response.metadata.responseState)
                    let parsedMode = DMDeliveryMode.parse(response.metadata.deliveryMode) ?? mode
                    let parsedProvenance = DMResponseProvenance.parse(response.metadata.provenance)
                    let isAsyncAck = parsedMode == .liveInbox
                        || parsedProvenance == .liveInbox
                        || parsedState == .computeRunning
                        || parsedState == .waitingForLiveAgent
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isAsyncAck {
                        continuation.finish(throwing: AgentChatError.noResponse)
                        return
                    }
                    let metadata = ResponseMetadata(
                        channelId: response.channelId,
                        userMessageId: response.userMessageId,
                        assistantMessageId: response.assistantMessageId,
                        model: response.metadata.model,
                        backend: response.metadata.backend,
                        tier: response.metadata.tier,
                        tokenCount: response.metadata.tokenCount,
                        traceId: response.metadata.traceId,
                        source: response.metadata.source,
                        lane: response.metadata.lane,
                        deliveryMode: response.metadata.deliveryMode ?? mode.rawValue,
                        provenance: parsedProvenance?.rawValue
                            ?? Self.provenance(for: response.metadata.deliveryMode, source: response.metadata.source, lane: response.metadata.lane),
                        responseState: parsedState?.rawValue ?? response.metadata.responseState,
                        triageId: response.metadata.triageId
                    )
                    continuation.yield(ResponseChunk(content: content, metadata: metadata))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private var systemPrompt: String {
        """
        You are \(agent.name) in Tony's Schoolhouse/ORCA lab.
        Role: \(agent.role).
        You are speaking in Pod chat. Be brief, direct, and useful.

        Current Pod chat capability:
        - You are a compute-backed agent persona, not the live OpenClaw agent process.
        - You can answer from the provided chat history and these guardrails.
        - You cannot directly read inboxes, browse files, query Chroma, mutate ORCA, send NATS, use tools, or update memory from this chat response.
        - Pod can create an ORCA ticket from the chat with Tony's explicit confirmation.
        - If this chat is already attached to an ORCA ticket, Pod can add Tony's follow-up as a ticket comment.
        - If Tony asks what you can do, be transparent about these limits and suggest the next real Pod/ORCA action.
        - Never invent ticket ids, file names, P&L, portfolio state, credentials, agent status, or completed actions.
        - If Tony asks for live state you cannot access, say you cannot see it from Pod chat and propose the next controlled check.

        Core lab rules:
        - ORCA is truth for tickets, projects, owners, blockers, approvals, and evidence.
        - Team-Wiki holds standards, SOPs, charters, audits, and the chronogram.
        - Daily memory is continuity; durable memory is curated.
        - Actionable work should point to an ORCA ticket/project or become one.
        - Do not delete, archive, overwrite identity, mutate security, or change Chief/Fund systems without review.
        - If Tony asks for work, give the next concrete ORCA/Pod step.

        Agent-specific guardrail:
        \(agent.guardrail)
        """
    }

    private static func computeTag(for agent: AgentInfo) -> String {
        // Direct chat is a lightweight triage surface. Protected-domain routing
        // belongs on ORCA tickets/runs; otherwise simple Chief/Rooster chat can
        // block behind slow specialist lanes before Tony gets any response.
        "classify"
    }

    // MARK: - Direct Claude API streaming (for agents with API keys)

    /// Streams a response directly from Claude API with agent-specific system prompt.
    /// Used when we want real-time streaming responses (not async OpenClaw injection).
    func streamDirect(
        message: String,
        history: [(role: String, content: String)] = [],
        apiKey: String,
        model: String = "claude-sonnet-4-6"
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let systemPrompt = """
                    You are \(agent.name), \(agent.role) on the ORCA platform.
                    You are having a 1:1 conversation with Tony (The Captain).
                    Be concise, direct, and helpful. Tony values brevity and execution over narration.
                    """

                    var messages: [[String: Any]] = []
                    // Include conversation history
                    for msg in history.suffix(20) {
                        messages.append(["role": msg.role, "content": msg.content])
                    }
                    messages.append(["role": "user", "content": message])

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 4096,
                        "system": systemPrompt,
                        "messages": messages,
                        "stream": true
                    ]

                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.timeoutInterval = 120
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        continuation.finish(throwing: AgentChatError.httpError(http.statusCode, nil))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let json = String(line.dropFirst(6))
                            if json == "[DONE]" { break }
                            if let text = Self.parseContentDelta(json) {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - SSE Parser

    private static func parseContentDelta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }
        struct Event: Decodable {
            let type: String?
            let delta: Delta?
            struct Delta: Decodable { let text: String? }
        }
        guard let event = try? JSONDecoder().decode(Event.self, from: data),
              event.type == "content_block_delta",
              let text = event.delta?.text else {
            return nil
        }
        return text
    }

    private static func parseChatCompletion(
        _ data: Data,
        traceId: String,
        source: String,
        lane: String
    ) throws -> ResponseChunk {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                    let refusal: String?
                }
                let message: Message?
                let text: String?
            }
            struct Usage: Decodable {
                let totalTokens: Int?

                enum CodingKeys: String, CodingKey {
                    case totalTokens = "total_tokens"
                }
            }
            struct Routing: Decodable {
                struct Router: Decodable {
                    let tierChosen: String?
                    let caller: String?

                    enum CodingKeys: String, CodingKey {
                        case tierChosen = "tier_chosen"
                        case caller
                    }
                }

                let backend: String?
                let model: String?
                let tier: String?
                let computeRouter: Router?

                enum CodingKeys: String, CodingKey {
                    case backend, model, tier
                    case computeRouter = "compute_router"
                }
            }

            let model: String?
            let choices: [Choice]
            let usage: Usage?
            let routing: Routing?

            enum CodingKeys: String, CodingKey {
                case model, choices, usage
                case routing = "_routing"
            }
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let content = response.choices.first?.message?.content
            ?? response.choices.first?.message?.refusal
            ?? response.choices.first?.text
            ?? ""
        let metadata = ResponseMetadata(
            channelId: "",
            userMessageId: "",
            assistantMessageId: "",
            model: response.routing?.model ?? response.model,
            backend: response.routing?.backend,
            tier: response.routing?.computeRouter?.tierChosen ?? response.routing?.tier,
            tokenCount: response.usage?.totalTokens,
            traceId: traceId,
            source: source,
            lane: lane,
            deliveryMode: DMDeliveryMode.compute.rawValue,
            provenance: DMResponseProvenance.compute.rawValue,
            responseState: DMDeliveryState.responseReceived.rawValue,
            triageId: nil
        )
        return ResponseChunk(content: content, metadata: metadata)
    }

    private static func provenance(for deliveryMode: String?, source: String?, lane: String?) -> String {
        DMResponseProvenance(deliveryMode: deliveryMode, source: source, lane: lane).rawValue
    }

    private static func errorSummary(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String { return detail }
            if let error = object["error"] as? String { return error }
            if let message = object["message"] as? String { return message }
        }
        return String(data: data, encoding: .utf8)?.prefix(180).description
    }
}
