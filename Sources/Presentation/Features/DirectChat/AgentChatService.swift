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

    struct LockerWorkSpineProject: Sendable, Hashable, Identifiable {
        let id: String
        let name: String
        let status: String?
        let stage: String?
        let agentPacketEndpoint: String?
    }

    struct LockerWorkSpineItem: Sendable, Hashable, Identifiable {
        let id: String
        let kind: String
        let title: String
        let status: String?
        let priority: String?
        let projectId: String?
        let boardId: String?
        let sourceTicketId: String?
    }

    struct LockerWorkSpineSummary: Sendable, Hashable {
        let source: String?
        let projectCount: Int
        let ticketCount: Int
        let taskCount: Int
        let reviewRunCount: Int
        let blockedCount: Int
        let projects: [LockerWorkSpineProject]
        let tickets: [LockerWorkSpineItem]
        let tasks: [LockerWorkSpineItem]

        var hasWork: Bool {
            projectCount + ticketCount + taskCount + reviewRunCount > 0
                || !projects.isEmpty
                || !tickets.isEmpty
                || !tasks.isEmpty
        }

        var totalWorkCount: Int {
            ticketCount + taskCount + reviewRunCount
        }
    }

    struct ProjectAgentPacketTicket: Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let status: String?
        let priority: String?
        let ticketType: String?
    }

    struct ProjectAgentPacketTask: Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let status: String?
        let stage: String?
        let priority: String?
    }

    struct ProjectAgentPacketBrief: Sendable, Hashable, Identifiable {
        let id: String
        let projectName: String
        let projectStatus: String
        let projectStage: String?
        let boardIds: [String]
        let ticketCount: Int
        let workTaskCount: Int
        let tickets: [ProjectAgentPacketTicket]
        let workTasks: [ProjectAgentPacketTask]
    }

    struct LockerSummary: Sendable, Hashable {
        let source: String?
        let sessionStatus: String?
        let dailyLogRef: String?
        let dailyLogBytes: Int?
        let assignedTicketCount: Int
        let gaps: [String]
        let reportCardScore: Int
        let reportCardStatus: String?
        let chatChannelName: String?
        let chatExists: Bool
        let chatPolicyState: String?
        let chatPolicyLane: String?
        let chatPendingCount: Int
        let chatMessageCount: Int
        let chatCanPost: Bool
        let chatCanRun: Bool
        let chatAllowedActions: [String]
        let startHereHeadline: String?
        let divisionName: String?
        let divisionRole: String?
        let divisionLoopLabels: [String]
        let workSpine: LockerWorkSpineSummary

        var readinessText: String {
            var parts: [String] = []
            if let sessionStatus, !sessionStatus.isEmpty {
                parts.append(sessionStatus)
            }
            if reportCardScore > 0 {
                parts.append("\(reportCardScore)% locker")
            }
            parts.append("\(assignedTicketCount) ticket\(assignedTicketCount == 1 ? "" : "s")")
            if chatPendingCount > 0 {
                parts.append("\(chatPendingCount) pending")
            } else if chatMessageCount > 0 {
                parts.append("\(chatMessageCount) message\(chatMessageCount == 1 ? "" : "s")")
            }
            if let dailyLogBytes, dailyLogBytes > 0 {
                parts.append("\(dailyLogBytes) daily bytes")
            }
            if !gaps.isEmpty {
                parts.append("\(gaps.count) gap\(gaps.count == 1 ? "" : "s")")
            }
            if workSpine.hasWork {
                parts.append("\(workSpine.totalWorkCount) work")
            }
            return parts.joined(separator: " · ")
        }
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
        let deliveryError: String?
        let deliveryFailedHop: String?
        let deliveryEvidence: String?
        let triageId: String?
        let computeRunId: String?

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
            let deliveryError: String?
            let deliveryFailedHop: String?
            let deliveryEvidence: String?
            let triageId: String?
            let computeRunId: String?

            enum CodingKeys: String, CodingKey {
                case model, backend, tier, source, lane, provenance
                case tokenCount = "token_count"
                case traceId = "trace_id"
                case deliveryMode = "delivery_mode"
                case responseState = "response_state"
                case deliveryError = "delivery_error"
                case deliveryFailedHop = "delivery_failed_hop"
                case failedHop = "failed_hop"
                case deliveryEvidence = "delivery_evidence"
                case evidence
                case triageId = "triage_id"
                case computeRunId = "compute_run_id"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                model = try container.decodeIfPresent(String.self, forKey: .model)
                backend = try container.decodeIfPresent(String.self, forKey: .backend)
                tier = try container.decodeIfPresent(String.self, forKey: .tier)
                tokenCount = try container.decodeIfPresent(Int.self, forKey: .tokenCount)
                traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
                source = try container.decodeIfPresent(String.self, forKey: .source) ?? "orca.chat.direct"
                lane = try container.decodeIfPresent(String.self, forKey: .lane) ?? "direct_agent_inbox"
                deliveryMode = try container.decodeIfPresent(String.self, forKey: .deliveryMode)
                provenance = try container.decodeIfPresent(String.self, forKey: .provenance)
                responseState = try container.decodeIfPresent(String.self, forKey: .responseState)
                deliveryError = try? container.decodeIfPresent(String.self, forKey: .deliveryError)
                deliveryFailedHop = (try? container.decodeIfPresent(String.self, forKey: .deliveryFailedHop))
                    ?? (try? container.decodeIfPresent(String.self, forKey: .failedHop))
                deliveryEvidence = (try? container.decodeIfPresent(String.self, forKey: .deliveryEvidence))
                    ?? (try? container.decodeIfPresent(String.self, forKey: .evidence))
                triageId = try container.decodeIfPresent(String.self, forKey: .triageId)
                computeRunId = try container.decodeIfPresent(String.self, forKey: .computeRunId)
            }
        }
    }

    private struct AgentLockerResponse: Decodable {
        let packet: Packet?
        let session: Session?
        let memory: Memory?
        let work: Work?
        let gaps: [String]?

        struct Packet: Decodable {
            let source: String?
        }

        struct Session: Decodable {
            let status: String?
        }

        struct Memory: Decodable {
            let dailyLogRef: String?
            let dailyLogBytes: Int?

            enum CodingKeys: String, CodingKey {
                case dailyLogRef = "daily_log_ref"
                case dailyLogBytes = "daily_log_bytes"
            }
        }

        struct Work: Decodable {
            let assignedTicketCount: Int?

            enum CodingKeys: String, CodingKey {
                case assignedTicketCount = "assigned_ticket_count"
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

    func loadLockerSummary(limit: Int = 10) async throws -> LockerSummary {
        let response: AgentLockerDTO = try await APIClient.shared.get(
            path: "/api/v1/agents/\(agent.id)/locker-cockpit?limit=\(limit)"
        )
        let workSpine = Self.workSpineSummary(from: response.workSpine)
        return LockerSummary(
            source: response.source,
            sessionStatus: response.agentProfile?.status,
            dailyLogRef: response.lockerMemory.dailyLogRef,
            dailyLogBytes: response.lockerMemory.dailyLogBytes,
            assignedTicketCount: response.planner.counts.now + response.planner.counts.next + response.planner.counts.blocked,
            gaps: response.gaps,
            reportCardScore: response.reportCard.score,
            reportCardStatus: response.reportCard.status,
            chatChannelName: response.chat.channelName,
            chatExists: response.chat.exists,
            chatPolicyState: response.chat.policyState,
            chatPolicyLane: response.chat.policyLane,
            chatPendingCount: response.chat.pendingCount,
            chatMessageCount: response.chat.messageCount,
            chatCanPost: response.chat.canPost,
            chatCanRun: response.chat.canDispatchSchoolhouseRun,
            chatAllowedActions: response.chat.policyAllowedActions,
            startHereHeadline: response.startHere.headline,
            divisionName: response.divisionWorkflow?.division,
            divisionRole: response.divisionWorkflow?.role,
            divisionLoopLabels: response.divisionWorkflow?.operatingLoop.map(\.label) ?? [],
            workSpine: workSpine
        )
    }

    func fetchAgentPacket(endpoint: String) async throws -> ProjectAgentPacketBrief {
        let path = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw APIError(code: 0, message: "Missing project agent-packet endpoint")
        }

        let response: ProjectAgentPacketDTO = try await APIClient.shared.get(path: path)
        return Self.agentPacketBrief(from: response)
    }

    private static func workSpineSummary(from spine: AgentLockerDTO.WorkSpine) -> LockerWorkSpineSummary {
        LockerWorkSpineSummary(
            source: spine.source,
            projectCount: spine.counts.projects,
            ticketCount: spine.counts.tickets,
            taskCount: spine.counts.tasks,
            reviewRunCount: spine.counts.reviewRuns,
            blockedCount: spine.counts.blocked,
            projects: spine.projects.map {
                LockerWorkSpineProject(
                    id: $0.id,
                    name: $0.name ?? $0.id,
                    status: $0.status,
                    stage: $0.stage,
                    agentPacketEndpoint: $0.agentPacketEndpoint
                )
            },
            tickets: spine.tickets.map { Self.workSpineItem(from: $0, kind: "ticket") },
            tasks: spine.tasks.map { Self.workSpineItem(from: $0, kind: "task") }
        )
    }

    private static func agentPacketBrief(from packet: ProjectAgentPacketDTO) -> ProjectAgentPacketBrief {
        ProjectAgentPacketBrief(
            id: packet.project.id.uuidString,
            projectName: packet.project.name,
            projectStatus: packet.project.status,
            projectStage: packet.project.stage,
            boardIds: packet.boardIds.map(\.uuidString),
            ticketCount: packet.ticketCount,
            workTaskCount: packet.workTaskCount,
            tickets: packet.tickets.map {
                ProjectAgentPacketTicket(
                    id: $0.id,
                    title: $0.title,
                    status: $0.status,
                    priority: $0.priority,
                    ticketType: $0.ticketType
                )
            },
            workTasks: packet.workTasks.map {
                ProjectAgentPacketTask(
                    id: $0.id,
                    title: $0.title,
                    status: $0.status,
                    stage: $0.stage,
                    priority: $0.priority
                )
            }
        )
    }

    private static func workSpineItem(from item: AgentLockerDTO.WorkItem, kind: String) -> LockerWorkSpineItem {
        let sourceTicketId = item.sourceTicketId
            ?? sourceRef(item.sourceRefs, "source_ticket_id")
            ?? sourceRef(item.sourceRefs, "ticket_id")
            ?? item.ticketId
        return LockerWorkSpineItem(
            id: item.id ?? UUID().uuidString,
            kind: item.kind ?? kind,
            title: item.displayTitle,
            status: item.displayState,
            priority: item.priority,
            projectId: item.projectId ?? sourceRef(item.sourceRefs, "project_id"),
            boardId: item.boardId ?? sourceRef(item.sourceRefs, "board_id"),
            sourceTicketId: sourceTicketId
        )
    }

    private static func sourceRef(_ refs: [String: String?]?, _ key: String) -> String? {
        guard let value = refs?[key] else { return nil }
        return value
    }

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
                    let effectiveState = Self.effectiveResponseState(
                        content: content,
                        deliveryMode: parsedMode,
                        provenance: parsedProvenance,
                        responseState: parsedState
                    )
                    let isAsyncAck = parsedMode == .liveInbox
                        || parsedProvenance == .liveInbox
                        || parsedProvenance == .coordinationReview
                        || effectiveState == .computeRunning
                        || effectiveState == .waitingForLiveAgent
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
                        responseState: effectiveState?.rawValue ?? response.metadata.responseState,
                        deliveryError: response.metadata.deliveryError,
                        deliveryFailedHop: response.metadata.deliveryFailedHop,
                        deliveryEvidence: response.metadata.deliveryEvidence,
                        triageId: response.metadata.triageId,
                        computeRunId: response.metadata.computeRunId
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
            deliveryError: nil,
            deliveryFailedHop: nil,
            deliveryEvidence: nil,
            triageId: nil,
            computeRunId: nil
        )
        return ResponseChunk(content: content, metadata: metadata)
    }

    private static func provenance(for deliveryMode: String?, source: String?, lane: String?) -> String {
        DMResponseProvenance(deliveryMode: deliveryMode, source: source, lane: lane).rawValue
    }

    private static func effectiveResponseState(
        content: String,
        deliveryMode: DMDeliveryMode,
        provenance: DMResponseProvenance?,
        responseState: DMDeliveryState?
    ) -> DMDeliveryState? {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "recorded in orca and queued for compute response. the result will appear here shortly." {
            return deliveryMode == .liveInbox || provenance == .liveInbox ? .waitingForLiveAgent : .computeRunning
        }
        if normalized.hasPrefix("sent to ") && normalized.contains(" live nerve inbox") {
            return .waitingForLiveAgent
        }
        return responseState
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
