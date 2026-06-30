import Foundation

enum WorkbenchReadView: String {
    case mine
    case project
    case ticket
    case task
}

actor WorkbenchRepository {
    private let api = APIClient.shared

    func load(view: WorkbenchReadView = .mine, id: String? = nil, limit: Int = 50) async throws -> WorkbenchEnvelope {
        var items = [
            URLQueryItem(name: "view", value: view.rawValue),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let id, !id.isEmpty {
            items.append(URLQueryItem(name: "id", value: id))
        }
        var components = URLComponents()
        components.queryItems = items
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await api.get(path: "/api/v1/agent/workbench\(query)", includeAgentToken: true)
    }

    func loadAgentTools(agentName: String, ticketId: String? = nil, taskId: String? = nil) async throws -> WorkbenchAgentToolsProjection {
        let normalizedAgent = agentName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedAgent.isEmpty else {
            throw APIError.message("Agent is required", code: 0)
        }

        var items: [URLQueryItem] = []
        if let ticketId, !ticketId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "ticket_id", value: ticketId))
        }
        if let taskId, !taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "task_id", value: taskId))
        }
        var components = URLComponents()
        components.queryItems = items
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await api.get(path: "/api/v1/agents/\(normalizedAgent)/tools\(query)")
    }

    func loadDataSources() async throws -> WorkbenchDataSourceRegistry {
        try await api.get(path: "/api/v1/workbench/data-sources")
    }

    func loadResearchFlywheel() async throws -> WorkbenchResearchFlywheel {
        try await api.get(path: "/api/v1/workbench/research-flywheel")
    }

    func stageFishFeed(_ request: WorkbenchFishFeedStageRequest) async throws -> WorkbenchFishFeedStageResponse {
        try await api.post(path: "/api/v1/workbench/fish-feed/stage", body: request)
    }

    func loadApprovalAttention(limit: Int = 25) async throws -> WorkbenchApprovalAttention {
        try await api.get(path: "/api/v1/tickets/approval-attention?limit=\(limit)")
    }

    func previewAgentAction(action: String) async throws -> WorkbenchPlaygroundPreview {
        try await previewAgentAction(
            WorkbenchAgentActionRequest(action: action)
        )
    }

    func previewAgentAction(_ request: WorkbenchAgentActionRequest) async throws -> WorkbenchPlaygroundPreview {
        try await api.post(
            path: "/api/v1/workbench/playground/preview",
            body: WorkbenchAgentActionPreviewRequest(
                previewType: "agent_action",
                payload: request
            )
        )
    }

    func executeAgentAction(_ request: WorkbenchAgentActionRequest) async throws -> WorkbenchAgentActionResponse {
        try await api.post(path: "/api/v1/agent/actions", body: request, includeAgentToken: true)
    }
}

struct WorkbenchApprovalAttention: Decodable, Hashable {
    let counts: WorkbenchApprovalAttentionCounts
    let items: [WorkbenchApprovalAttentionItem]
}

struct WorkbenchApprovalAttentionCounts: Decodable, Hashable {
    let total: Int
    let waitingForHumanState: Int
    let approvalGate: Int
    let waitingForHumanRun: Int

    enum CodingKeys: String, CodingKey {
        case total
        case waitingForHumanState = "waiting_for_human_state"
        case approvalGate = "approval_gate"
        case waitingForHumanRun = "waiting_for_human_run"
    }
}

struct WorkbenchApprovalAttentionItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let approvalState: String
    let approvalGate: String?
    let updatedAt: Date?
    let reasons: [String]
    let latestRun: WorkbenchApprovalAttentionRun?

    enum CodingKeys: String, CodingKey {
        case id, title, status, priority, reasons
        case approvalState = "approval_state"
        case approvalGate = "approval_gate"
        case updatedAt = "updated_at"
        case latestRun = "latest_run"
    }
}

struct WorkbenchApprovalAttentionRun: Decodable, Hashable {
    let id: String
    let status: String
    let runType: String
    let workerLane: String?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case runType = "run_type"
        case workerLane = "worker_lane"
        case updatedAt = "updated_at"
    }
}

struct WorkbenchAgentActionPreviewRequest: Encodable {
    let previewType: String
    let payload: WorkbenchAgentActionRequest

    enum CodingKeys: String, CodingKey {
        case previewType = "preview_type"
        case payload
    }
}

struct WorkbenchPlaygroundPreview: Decodable, Hashable {
    let schemaId: String
    let previewType: String
    let generatedAt: Date?
    let sideEffects: String
    let wouldWrite: Bool
    let wouldPublishNats: Bool
    let policy: [String: AgentRunJSONValue]
    let result: [String: AgentRunJSONValue]
    let warnings: [String]
    let blocked: Bool

    enum CodingKeys: String, CodingKey {
        case policy, result, warnings, blocked
        case schemaId = "schema_id"
        case previewType = "preview_type"
        case generatedAt = "generated_at"
        case sideEffects = "side_effects"
        case wouldWrite = "would_write"
        case wouldPublishNats = "would_publish_nats"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaId = try c.decodeIfPresent(String.self, forKey: .schemaId) ?? "orca.workbench.playground.preview.v1"
        previewType = try c.decodeIfPresent(String.self, forKey: .previewType) ?? "agent_action"
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
        sideEffects = try c.decodeIfPresent(String.self, forKey: .sideEffects) ?? "none"
        wouldWrite = try c.decodeIfPresent(Bool.self, forKey: .wouldWrite) ?? false
        wouldPublishNats = try c.decodeIfPresent(Bool.self, forKey: .wouldPublishNats) ?? false
        policy = (try? c.decodeIfPresent([String: AgentRunJSONValue].self, forKey: .policy)) ?? [:]
        result = (try? c.decodeIfPresent([String: AgentRunJSONValue].self, forKey: .result)) ?? [:]
        warnings = (try? c.decodeIfPresent([String].self, forKey: .warnings)) ?? []
        blocked = try c.decodeIfPresent(Bool.self, forKey: .blocked) ?? false
    }
}

struct WorkbenchAgentActionRequest: Encodable, Hashable {
    let action: String
    let idempotencyKey: String?
    let boardId: String?
    let taskId: String?
    let ticketId: String?
    let approvalId: String?
    let plannerItemId: String?
    let plannerAgentId: String?
    let taskUpdate: WorkbenchTaskUpdate?
    let comment: WorkbenchTaskComment?
    let plannerItem: WorkbenchPlannerItem?
    let plannerUpdate: WorkbenchPlannerUpdate?
    let approvalUpdate: WorkbenchApprovalUpdate?

    init(
        action: String,
        idempotencyKey: String? = nil,
        boardId: String? = nil,
        taskId: String? = nil,
        ticketId: String? = nil,
        approvalId: String? = nil,
        plannerItemId: String? = nil,
        plannerAgentId: String? = nil,
        taskUpdate: WorkbenchTaskUpdate? = nil,
        comment: WorkbenchTaskComment? = nil,
        plannerItem: WorkbenchPlannerItem? = nil,
        plannerUpdate: WorkbenchPlannerUpdate? = nil,
        approvalUpdate: WorkbenchApprovalUpdate? = nil
    ) {
        self.action = action
        self.idempotencyKey = idempotencyKey
        self.boardId = boardId
        self.taskId = taskId
        self.ticketId = ticketId
        self.approvalId = approvalId
        self.plannerItemId = plannerItemId
        self.plannerAgentId = plannerAgentId
        self.taskUpdate = taskUpdate
        self.comment = comment
        self.plannerItem = plannerItem
        self.plannerUpdate = plannerUpdate
        self.approvalUpdate = approvalUpdate
    }

    enum CodingKeys: String, CodingKey {
        case action
        case idempotencyKey = "idempotency_key"
        case boardId = "board_id"
        case taskId = "task_id"
        case ticketId = "ticket_id"
        case approvalId = "approval_id"
        case plannerItemId = "planner_item_id"
        case plannerAgentId = "planner_agent_id"
        case taskUpdate = "task_update"
        case comment
        case plannerItem = "planner_item"
        case plannerUpdate = "planner_update"
        case approvalUpdate = "approval_update"
    }
}

struct WorkbenchTaskUpdate: Encodable, Hashable {
    let status: String?
    let comment: String?
}

struct WorkbenchTaskComment: Encodable, Hashable {
    let message: String
    let actionRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case message
        case actionRequired = "action_required"
    }
}

struct WorkbenchPlannerItem: Encodable, Hashable {
    let title: String
    let body: String?
    let lane: String
    let priority: String
    let sourceType: String?
    let sourceRef: String?

    enum CodingKeys: String, CodingKey {
        case title, body, lane, priority
        case sourceType = "source_type"
        case sourceRef = "source_ref"
    }
}

struct WorkbenchPlannerUpdate: Encodable, Hashable {
    let title: String?
    let body: String?
    let lane: String?
    let priority: String?
    let status: String?
}

struct WorkbenchApprovalUpdate: Encodable, Hashable {
    let status: String
}

struct WorkbenchAgentActionResponse: Decodable, Hashable {
    let schemaId: String
    let ok: Bool
    let action: String
    let agent: String?
    let id: String?
    let objectType: String
    let objectId: String?
    let status: String?
    let detail: String?
    let resource: [String: AgentRunJSONValue]
    let result: [String: AgentRunJSONValue]
    let policy: [String: AgentRunJSONValue]

    enum CodingKeys: String, CodingKey {
        case ok, action, agent, id, status, detail, resource, result, policy
        case schemaId = "schema_id"
        case objectType = "object_type"
        case objectId = "object_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaId = try c.decodeIfPresent(String.self, forKey: .schemaId) ?? "orca.agent-action.v1"
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? "agent_action"
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        resource = (try? c.decodeIfPresent([String: AgentRunJSONValue].self, forKey: .resource)) ?? [:]
        result = (try? c.decodeIfPresent([String: AgentRunJSONValue].self, forKey: .result)) ?? [:]
        policy = (try? c.decodeIfPresent([String: AgentRunJSONValue].self, forKey: .policy)) ?? [:]
        objectType = try c.decodeIfPresent(String.self, forKey: .objectType)
            ?? resource["type"]?.displayValue
            ?? Self.objectType(for: action)
        objectId = try c.decodeIfPresent(String.self, forKey: .objectId)
            ?? id
            ?? resource["task_id"]?.displayValue
            ?? resource["ticket_id"]?.displayValue
            ?? resource["agent_id"]?.displayValue
    }

    private static func objectType(for action: String) -> String {
        if action.contains("planner") { return "planner_item" }
        if action.contains("ticket") { return "ticket" }
        if action.contains("task") { return "task" }
        return "object"
    }
}

struct WorkbenchAgentToolsProjection: Decodable, Hashable {
    let schema: String
    let schemaVersion: Int
    let source: String?
    let generatedAt: Date?
    let agent: WorkbenchAgentToolsAgent
    let workObject: WorkbenchAgentToolsWorkObject?
    let policy: [String: AgentRunJSONValue]
    let capabilities: [WorkbenchAgentToolCapability]
    let pendingToolRequests: [AgentRunJSONValue]
    let evidenceRefs: [AgentRunJSONValue]
    let runtimeProvenanceSchema: WorkbenchRuntimeProvenanceSchema?
    let gaps: [String]

    enum CodingKeys: String, CodingKey {
        case schema, source, agent, policy, capabilities, gaps
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case workObject = "work_object"
        case pendingToolRequests = "pending_tool_requests"
        case evidenceRefs = "evidence_refs"
        case runtimeProvenanceSchema = "runtime_provenance_schema"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema) ?? "orca.agent-tools.v1"
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        source = try c.decodeIfPresent(String.self, forKey: .source)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
        agent = try c.decodeIfPresent(WorkbenchAgentToolsAgent.self, forKey: .agent) ?? WorkbenchAgentToolsAgent()
        workObject = try c.decodeIfPresent(WorkbenchAgentToolsWorkObject.self, forKey: .workObject)
        policy = (try? c.decodeIfPresent([String: AgentRunJSONValue].self, forKey: .policy)) ?? [:]
        capabilities = (try? c.decodeIfPresent([WorkbenchAgentToolCapability].self, forKey: .capabilities)) ?? []
        pendingToolRequests = (try? c.decodeIfPresent([AgentRunJSONValue].self, forKey: .pendingToolRequests)) ?? []
        evidenceRefs = (try? c.decodeIfPresent([AgentRunJSONValue].self, forKey: .evidenceRefs)) ?? []
        runtimeProvenanceSchema = try c.decodeIfPresent(WorkbenchRuntimeProvenanceSchema.self, forKey: .runtimeProvenanceSchema)
        gaps = (try? c.decodeIfPresent([String].self, forKey: .gaps)) ?? []
    }

    var availableCapabilities: [WorkbenchAgentToolCapability] {
        capabilities.filter { $0.normalizedStatus == "available" }
    }

    var disabledCapabilities: [WorkbenchAgentToolCapability] {
        capabilities.filter { $0.normalizedStatus != "available" }
    }

    var protectedLevel: String {
        workObject?.protectedLevel
            ?? policy["protected_level"]?.displayValue
            ?? "open"
    }

    var richToolsPolicy: String {
        policy["rich_tools"]?.displayValue ?? "policy unavailable"
    }

    var provenanceSourceLabel: String {
        runtimeProvenanceSchema?.source ?? "orca.runtime-provenance.v1"
    }
}

struct WorkbenchAgentToolsAgent: Decodable, Hashable {
    let id: String?
    let name: String
    let status: String?
    let supportRuntime: String?
    let allowedRuntimes: [String]
    let runtimeHost: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case supportRuntime = "support_runtime"
        case allowedRuntimes = "allowed_runtimes"
        case runtimeHost = "runtime_host"
    }

    init(
        id: String? = nil,
        name: String = "agent",
        status: String? = nil,
        supportRuntime: String? = nil,
        allowedRuntimes: [String] = [],
        runtimeHost: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.supportRuntime = supportRuntime
        self.allowedRuntimes = allowedRuntimes
        self.runtimeHost = runtimeHost
    }
}

struct WorkbenchAgentToolsWorkObject: Decodable, Hashable {
    let type: String
    let id: String
    let title: String?
    let status: String?
    let priority: String?
    let protectedLevel: String?
    let workspaceContextEndpoint: String?

    enum CodingKeys: String, CodingKey {
        case type, id, title, status, priority
        case protectedLevel = "protected_level"
        case workspaceContextEndpoint = "workspace_context_endpoint"
    }
}

struct WorkbenchAgentToolCapability: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    let toolClass: String
    let status: String
    let mode: String?
    let endpoints: [String: String]
    let requiresApproval: Bool
    let blockedReasons: [String]
    let evidenceTypes: [String]
    let provenanceRequired: Bool

    enum CodingKeys: String, CodingKey {
        case id, label, status, mode, endpoints
        case toolClass = "tool_class"
        case requiresApproval = "requires_approval"
        case blockedReasons = "blocked_reasons"
        case evidenceTypes = "evidence_types"
        case provenanceRequired = "provenance_required"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? id.replacingOccurrences(of: "_", with: " ").capitalized
        toolClass = try c.decodeIfPresent(String.self, forKey: .toolClass) ?? id
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        endpoints = (try? c.decodeIfPresent([String: String].self, forKey: .endpoints)) ?? [:]
        requiresApproval = try c.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
        blockedReasons = (try? c.decodeIfPresent([String].self, forKey: .blockedReasons)) ?? []
        evidenceTypes = (try? c.decodeIfPresent([String].self, forKey: .evidenceTypes)) ?? []
        provenanceRequired = try c.decodeIfPresent(Bool.self, forKey: .provenanceRequired) ?? true
    }

    var normalizedStatus: String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct WorkbenchRuntimeProvenanceSchema: Decodable, Hashable {
    let source: String?
    let requiredWhen: String?
    let humanOrigin: String?
    let fields: [String]
    let display: WorkbenchRuntimeProvenanceDisplay?

    enum CodingKeys: String, CodingKey {
        case source, fields, display
        case requiredWhen = "required_when"
        case humanOrigin = "human_origin"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        requiredWhen = try c.decodeIfPresent(String.self, forKey: .requiredWhen)
        humanOrigin = try c.decodeIfPresent(String.self, forKey: .humanOrigin)
        fields = (try? c.decodeIfPresent([String].self, forKey: .fields)) ?? []
        display = try c.decodeIfPresent(WorkbenchRuntimeProvenanceDisplay.self, forKey: .display)
    }
}

struct WorkbenchRuntimeProvenanceDisplay: Decodable, Hashable {
    let primaryChips: [String]
    let secondaryChips: [String]

    enum CodingKeys: String, CodingKey {
        case primaryChips = "primary_chips"
        case secondaryChips = "secondary_chips"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryChips = (try? c.decodeIfPresent([String].self, forKey: .primaryChips)) ?? []
        secondaryChips = (try? c.decodeIfPresent([String].self, forKey: .secondaryChips)) ?? []
    }
}

struct WorkbenchFishFeedStageRequest: Encodable, Hashable {
    let fish: String
    let ownerAgent: String
    let directiveTitle: String
    let directiveSummary: String?
    let sourceTicketId: String?
    let lane: String
    let priority: String
    let traceId: String?

    init(
        fish: String = "starfish",
        ownerAgent: String = "maui",
        directiveTitle: String,
        directiveSummary: String? = nil,
        sourceTicketId: String? = nil,
        lane: String = "next",
        priority: String = "high",
        traceId: String? = nil
    ) {
        self.fish = fish
        self.ownerAgent = ownerAgent
        self.directiveTitle = directiveTitle
        self.directiveSummary = directiveSummary
        self.sourceTicketId = sourceTicketId
        self.lane = lane
        self.priority = priority
        self.traceId = traceId
    }

    enum CodingKeys: String, CodingKey {
        case fish
        case ownerAgent = "owner_agent"
        case directiveTitle = "directive_title"
        case directiveSummary = "directive_summary"
        case sourceTicketId = "source_ticket_id"
        case lane
        case priority
        case traceId = "trace_id"
    }
}

struct WorkbenchFishFeedStageResponse: Decodable, Hashable {
    let schemaId: String
    let mode: String
    let plannerItemId: String
    let ownerAgentId: String
    let ownerAgent: String
    let fish: String
    let sourceType: String
    let sourceRef: String
    let fishWoken: Bool
    let queueWritten: Bool
    let plannerItemCreated: Bool
    let workEventRecorded: Bool

    enum CodingKeys: String, CodingKey {
        case mode, fish
        case schemaId = "schema_id"
        case plannerItemId = "planner_item_id"
        case ownerAgentId = "owner_agent_id"
        case ownerAgent = "owner_agent"
        case sourceType = "source_type"
        case sourceRef = "source_ref"
        case fishWoken = "fish_woken"
        case queueWritten = "queue_written"
        case plannerItemCreated = "planner_item_created"
        case workEventRecorded = "work_event_recorded"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaId = try c.decodeIfPresent(String.self, forKey: .schemaId) ?? "orca.workbench.fish-feed-stage.v1"
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "staged_planner_only"
        plannerItemId = try c.decode(String.self, forKey: .plannerItemId)
        ownerAgentId = try c.decode(String.self, forKey: .ownerAgentId)
        ownerAgent = try c.decodeIfPresent(String.self, forKey: .ownerAgent) ?? "maui"
        fish = try c.decodeIfPresent(String.self, forKey: .fish) ?? "starfish"
        sourceType = try c.decodeIfPresent(String.self, forKey: .sourceType) ?? "fish_directive"
        sourceRef = try c.decodeIfPresent(String.self, forKey: .sourceRef) ?? "fish:starfish:manual:workbench"
        fishWoken = try c.decodeIfPresent(Bool.self, forKey: .fishWoken) ?? false
        queueWritten = try c.decodeIfPresent(Bool.self, forKey: .queueWritten) ?? false
        plannerItemCreated = try c.decodeIfPresent(Bool.self, forKey: .plannerItemCreated) ?? true
        workEventRecorded = try c.decodeIfPresent(Bool.self, forKey: .workEventRecorded) ?? true
    }
}

struct WorkbenchEnvelope: Decodable, Hashable {
    let schema: String
    let source: String?
    let mode: String
    let generatedAt: Date?
    let view: String
    let id: String?
    let viewer: WorkbenchAgentRef
    let healthStrip: WorkbenchHealthStrip?
    let buckets: WorkbenchBuckets
    let visibility: WorkbenchEnvelopeVisibility?

    enum CodingKeys: String, CodingKey {
        case schema, source, mode, view, id, viewer, buckets, visibility
        case generatedAt = "generated_at"
        case healthStrip = "health_strip"
    }
}

struct WorkbenchAgentRef: Decodable, Hashable {
    let id: String
    let name: String
    let boardId: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case boardId = "board_id"
    }
}

struct WorkbenchHealthStrip: Decodable, Hashable {
    let schema: String?
    let source: String?
    let generatedAt: Date?
    let activeAgentCount: Int
    let activeAgentRowsPresent: Int
    let wakeState: String?
    let staleWorkCount: Int
    let protectedWarningCount: Int

    enum CodingKeys: String, CodingKey {
        case schema, source
        case generatedAt = "generated_at"
        case activeAgentCount = "active_agent_count"
        case activeAgentRowsPresent = "active_agent_rows_present"
        case wakeState = "wake_state"
        case staleWorkCount = "stale_work_count"
        case protectedWarningCount = "protected_warning_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
        activeAgentCount = try c.decodeIfPresent(Int.self, forKey: .activeAgentCount) ?? 0
        activeAgentRowsPresent = try c.decodeIfPresent(Int.self, forKey: .activeAgentRowsPresent) ?? 0
        wakeState = try c.decodeIfPresent(String.self, forKey: .wakeState)
        staleWorkCount = try c.decodeIfPresent(Int.self, forKey: .staleWorkCount) ?? 0
        protectedWarningCount = try c.decodeIfPresent(Int.self, forKey: .protectedWarningCount) ?? 0
    }
}

struct WorkbenchBuckets: Decodable, Hashable {
    let workQueue: WorkbenchWorkQueue?
    let approvals: [WorkbenchApprovalRef]
    let chatRefs: WorkbenchChatRefs?
    let controls: WorkbenchControls?

    enum CodingKeys: String, CodingKey {
        case approvals, controls
        case workQueue = "work_queue"
        case chatRefs = "chat_refs"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workQueue = try c.decodeIfPresent(WorkbenchWorkQueue.self, forKey: .workQueue)
        approvals = (try? c.decodeIfPresent([WorkbenchApprovalRef].self, forKey: .approvals)) ?? []
        chatRefs = try c.decodeIfPresent(WorkbenchChatRefs.self, forKey: .chatRefs)
        controls = try c.decodeIfPresent(WorkbenchControls.self, forKey: .controls)
    }
}

struct WorkbenchWorkQueue: Decodable, Hashable {
    let schema: String?
    let source: String?
    let agentId: String?
    let agentName: String?
    let assignedToMe: [WorkbenchWorkItem]
    let waitingOnMe: [WorkbenchWorkItem]
    let waitingOnOthers: [WorkbenchWorkItem]
    let blockedByMe: [WorkbenchWorkItem]
    let blockingOthers: [WorkbenchWorkItem]
    let readyNow: [WorkbenchWorkItem]
    let staleOwnedWork: [WorkbenchWorkItem]
    let recentChanges: [WorkbenchWorkItem]
    let approvals: [WorkbenchApprovalRef]
    let watching: [WorkbenchWorkItem]
    let counts: [String: Int]
    let visibility: WorkbenchEnvelopeVisibility?

    enum CodingKeys: String, CodingKey {
        case schema, source, approvals, watching, counts, visibility
        case agentId = "agent_id"
        case agentName = "agent_name"
        case assignedToMe = "assigned_to_me"
        case waitingOnMe = "waiting_on_me"
        case waitingOnOthers = "waiting_on_others"
        case blockedByMe = "blocked_by_me"
        case blockingOthers = "blocking_others"
        case readyNow = "ready_now"
        case staleOwnedWork = "stale_owned_work"
        case recentChanges = "recent_changes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        agentId = try c.decodeIfPresent(String.self, forKey: .agentId)
        agentName = try c.decodeIfPresent(String.self, forKey: .agentName)
        assignedToMe = (try? c.decodeIfPresent([WorkbenchWorkItem].self, forKey: .assignedToMe)) ?? []
        waitingOnMe = (try? c.decodeIfPresent([WorkbenchWorkItem].self, forKey: .waitingOnMe)) ?? []
        waitingOnOthers = (try? c.decodeIfPresent([WorkbenchWorkItem].self, forKey: .waitingOnOthers)) ?? []
        blockedByMe = (try? c.decodeIfPresent([WorkbenchWorkItem].self, forKey: .blockedByMe)) ?? []
        blockingOthers = (try? c.decodeIfPresent([WorkbenchWorkItem].self, forKey: .blockingOthers)) ?? []
        readyNow = (try? c.decodeIfPresent([WorkbenchWorkItem].self, forKey: .readyNow)) ?? []
        staleOwnedWork = (try? c.decodeIfPresent([WorkbenchWorkItem].self, forKey: .staleOwnedWork)) ?? []
        recentChanges = (try? c.decodeIfPresent([WorkbenchWorkItem].self, forKey: .recentChanges)) ?? []
        approvals = (try? c.decodeIfPresent([WorkbenchApprovalRef].self, forKey: .approvals)) ?? []
        watching = (try? c.decodeIfPresent([WorkbenchWorkItem].self, forKey: .watching)) ?? []
        counts = try c.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        visibility = try c.decodeIfPresent(WorkbenchEnvelopeVisibility.self, forKey: .visibility)
    }
}

struct WorkbenchWorkItem: Decodable, Identifiable, Hashable {
    let kind: String
    let id: String
    let eventId: String?
    let eventType: String?
    let safeTitle: String
    let status: String?
    let priority: String?
    let nextAction: String?
    let route: String?
    let room: String?
    let cascadeAction: String?
    let sourceRefs: [String: AgentRunJSONValue]
    let contentPolicy: String?
    let visibility: WorkbenchItemVisibility?
    let blockedOn: String?
    let waitingOn: String?
    let stale: Bool
    let staleAfterHours: Int?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case kind, id, status, priority, route, room, stale
        case eventId = "event_id"
        case eventType = "event_type"
        case safeTitle = "safe_title"
        case nextAction = "next_action"
        case cascadeAction = "cascade_action"
        case sourceRefs = "source_refs"
        case contentPolicy = "content_policy"
        case visibility
        case blockedOn = "blocked_on"
        case waitingOn = "waiting_on"
        case staleAfterHours = "stale_after_hours"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "work"
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        eventId = try c.decodeIfPresent(String.self, forKey: .eventId)
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType)
        safeTitle = try c.decodeIfPresent(String.self, forKey: .safeTitle) ?? "Work item"
        status = try c.decodeIfPresent(String.self, forKey: .status)
        priority = try c.decodeIfPresent(String.self, forKey: .priority)
        nextAction = try c.decodeIfPresent(String.self, forKey: .nextAction)
        route = try c.decodeIfPresent(String.self, forKey: .route)
        room = try c.decodeIfPresent(String.self, forKey: .room)
        cascadeAction = try c.decodeIfPresent(String.self, forKey: .cascadeAction)
        sourceRefs = (try? c.decodeIfPresent([String: AgentRunJSONValue].self, forKey: .sourceRefs)) ?? [:]
        contentPolicy = try c.decodeIfPresent(String.self, forKey: .contentPolicy)
        visibility = try c.decodeIfPresent(WorkbenchItemVisibility.self, forKey: .visibility)
        blockedOn = try c.decodeIfPresent(String.self, forKey: .blockedOn)
        waitingOn = try c.decodeIfPresent(String.self, forKey: .waitingOn)
        stale = try c.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        staleAfterHours = try c.decodeIfPresent(Int.self, forKey: .staleAfterHours)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    var sourceTicketId: String? {
        sourceRefs["ticket_id"]?.workbenchStringValue
    }

    var sourceTaskId: String? {
        sourceRefs["task_id"]?.workbenchStringValue
    }

    var boardId: String? {
        sourceRefs["board_id"]?.workbenchStringValue
    }

    var isProtected: Bool {
        visibility?.protected == true || visibility?.body == "pointer_only"
    }
}

struct WorkbenchItemVisibility: Decodable, Hashable {
    let protected: Bool?
    let protectedScope: String?
    let protectedLevel: String?
    let body: String?
    let bodyPolicy: String?
    let redactedFields: [String]

    enum CodingKeys: String, CodingKey {
        case protected, body
        case protectedScope = "protected_scope"
        case protectedLevel = "protected_level"
        case bodyPolicy = "body_policy"
        case redactedFields = "redacted_fields"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        protected = try c.decodeIfPresent(Bool.self, forKey: .protected)
        protectedScope = try c.decodeIfPresent(String.self, forKey: .protectedScope)
        protectedLevel = try c.decodeIfPresent(String.self, forKey: .protectedLevel)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        bodyPolicy = try c.decodeIfPresent(String.self, forKey: .bodyPolicy)
        redactedFields = (try? c.decodeIfPresent([String].self, forKey: .redactedFields)) ?? []
    }
}

struct WorkbenchApprovalRef: Decodable, Identifiable, Hashable {
    let id: String
    let status: String?
    let actionType: String?
    let targetType: String?
    let targetRef: String?
    let visibility: WorkbenchItemVisibility?

    enum CodingKeys: String, CodingKey {
        case id, status, visibility
        case actionType = "action_type"
        case targetType = "target_type"
        case targetRef = "target_ref"
    }
}

struct WorkbenchChatRefs: Decodable, Hashable {
    let source: String?
    let channels: [WorkbenchChatChannelRef]
}

struct WorkbenchChatChannelRef: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String?
    let policyLaneType: String?
    let policyProtectedLevel: String?
    let messageCount: Int
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case name, type
        case id = "channel_id"
        case policyLaneType = "policy_lane_type"
        case policyProtectedLevel = "policy_protected_level"
        case messageCount = "message_count"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "channel"
        type = try c.decodeIfPresent(String.self, forKey: .type)
        policyLaneType = try c.decodeIfPresent(String.self, forKey: .policyLaneType)
        policyProtectedLevel = try c.decodeIfPresent(String.self, forKey: .policyProtectedLevel)
        messageCount = try c.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct WorkbenchControls: Decodable, Hashable {
    let schema: String?
    let actionsEndpoint: String?
    let playgroundPreviewEndpoint: String?
    let view: String?
    let objectId: String?
    let supportedControls: [String]

    enum CodingKeys: String, CodingKey {
        case schema, view
        case actionsEndpoint = "actions_endpoint"
        case playgroundPreviewEndpoint = "playground_preview_endpoint"
        case objectId = "object_id"
        case supportedControls = "supported_controls"
    }
}

struct WorkbenchEnvelopeVisibility: Decodable, Hashable {
    let protectedDefault: String?
    let contentPolicy: String?
    let leakDetector: String?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case body
        case protectedDefault = "protected_default"
        case contentPolicy = "content_policy"
        case leakDetector = "leak_detector"
    }
}

struct WorkbenchDataSourceRegistry: Decodable, Hashable {
    let schemaId: String?
    let knowledgeManifestSchemaId: String?
    let source: String?
    let mode: String?
    let traceId: String?
    let generatedAt: Date?
    let bodyPolicy: WorkbenchDataSourceBodyPolicy?
    let summary: WorkbenchDataSourceSummary
    let sources: [WorkbenchDataSource]

    enum CodingKeys: String, CodingKey {
        case source, mode, summary, sources
        case schemaId = "schema_id"
        case knowledgeManifestSchemaId = "knowledge_manifest_schema_id"
        case traceId = "trace_id"
        case generatedAt = "generated_at"
        case bodyPolicy = "body_policy"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaId = try c.decodeIfPresent(String.self, forKey: .schemaId)
        knowledgeManifestSchemaId = try c.decodeIfPresent(String.self, forKey: .knowledgeManifestSchemaId)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        traceId = try c.decodeIfPresent(String.self, forKey: .traceId)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
        bodyPolicy = try c.decodeIfPresent(WorkbenchDataSourceBodyPolicy.self, forKey: .bodyPolicy)
        summary = try c.decodeIfPresent(WorkbenchDataSourceSummary.self, forKey: .summary) ?? .empty
        sources = (try? c.decodeIfPresent([WorkbenchDataSource].self, forKey: .sources)) ?? []
    }
}

struct WorkbenchDataSourceBodyPolicy: Decodable, Hashable {
    let defaultPolicy: String?
    let protected: String?
    let scannerGuard: String?

    enum CodingKeys: String, CodingKey {
        case protected
        case defaultPolicy = "default"
        case scannerGuard = "scanner_guard"
    }
}

struct WorkbenchDataSourceSummary: Decodable, Hashable {
    static let empty = WorkbenchDataSourceSummary(
        sourceCount: 0,
        blockedCount: 0,
        protectedCount: 0,
        unknownCount: 0,
        bodyReadCount: 0,
        bodyCopyCount: 0,
        embeddingCount: 0,
        protectedBlockCount: 0,
        errorCount: 0
    )

    let sourceCount: Int
    let blockedCount: Int
    let protectedCount: Int
    let unknownCount: Int
    let bodyReadCount: Int
    let bodyCopyCount: Int
    let embeddingCount: Int
    let protectedBlockCount: Int
    let errorCount: Int

    enum CodingKeys: String, CodingKey {
        case sourceCount = "source_count"
        case blockedCount = "blocked_count"
        case protectedCount = "protected_count"
        case unknownCount = "unknown_count"
        case bodyReadCount = "body_read_count"
        case bodyCopyCount = "body_copy_count"
        case embeddingCount = "embedding_count"
        case protectedBlockCount = "protected_block_count"
        case errorCount = "error_count"
    }

    init(
        sourceCount: Int,
        blockedCount: Int,
        protectedCount: Int,
        unknownCount: Int,
        bodyReadCount: Int,
        bodyCopyCount: Int,
        embeddingCount: Int,
        protectedBlockCount: Int,
        errorCount: Int
    ) {
        self.sourceCount = sourceCount
        self.blockedCount = blockedCount
        self.protectedCount = protectedCount
        self.unknownCount = unknownCount
        self.bodyReadCount = bodyReadCount
        self.bodyCopyCount = bodyCopyCount
        self.embeddingCount = embeddingCount
        self.protectedBlockCount = protectedBlockCount
        self.errorCount = errorCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceCount = try c.decodeIfPresent(Int.self, forKey: .sourceCount) ?? 0
        blockedCount = try c.decodeIfPresent(Int.self, forKey: .blockedCount) ?? 0
        protectedCount = try c.decodeIfPresent(Int.self, forKey: .protectedCount) ?? 0
        unknownCount = try c.decodeIfPresent(Int.self, forKey: .unknownCount) ?? 0
        bodyReadCount = try c.decodeIfPresent(Int.self, forKey: .bodyReadCount) ?? 0
        bodyCopyCount = try c.decodeIfPresent(Int.self, forKey: .bodyCopyCount) ?? 0
        embeddingCount = try c.decodeIfPresent(Int.self, forKey: .embeddingCount) ?? 0
        protectedBlockCount = try c.decodeIfPresent(Int.self, forKey: .protectedBlockCount) ?? 0
        errorCount = try c.decodeIfPresent(Int.self, forKey: .errorCount) ?? 0
    }
}

struct WorkbenchDataSource: Decodable, Identifiable, Hashable {
    let sourceId: String
    let displayName: String
    let kind: String
    let ownerAgent: String?
    let reviewers: [String]
    let dataClass: String?
    let sensitivity: String?
    let freshness: WorkbenchDataSourceFreshness?
    let healthStatus: String?
    let allowedReaders: [String]
    let allowedWriters: [String]
    let bodyPolicy: String?
    let embeddingPolicy: String?
    let retentionPolicy: String?
    let surfaceDestinations: [String]
    let consumptionPath: String?
    let status: String?
    let blockers: [WorkbenchDataSourceBlocker]
    let evidenceRefs: [String]
    let scanner: WorkbenchDataSourceScanner?

    var id: String { sourceId }

    enum CodingKeys: String, CodingKey {
        case kind, reviewers, freshness, status, blockers, scanner
        case sourceId = "source_id"
        case displayName = "display_name"
        case ownerAgent = "owner_agent"
        case dataClass = "data_class"
        case sensitivity
        case healthStatus = "health_status"
        case allowedReaders = "allowed_readers"
        case allowedWriters = "allowed_writers"
        case bodyPolicy = "body_policy"
        case embeddingPolicy = "embedding_policy"
        case retentionPolicy = "retention_policy"
        case surfaceDestinations = "surface_destinations"
        case consumptionPath = "consumption_path"
        case evidenceRefs = "evidence_refs"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceId = try c.decodeIfPresent(String.self, forKey: .sourceId) ?? UUID().uuidString
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? sourceId
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "source"
        ownerAgent = try c.decodeIfPresent(String.self, forKey: .ownerAgent)
        reviewers = (try? c.decodeIfPresent([String].self, forKey: .reviewers)) ?? []
        dataClass = try c.decodeIfPresent(String.self, forKey: .dataClass)
        sensitivity = try c.decodeIfPresent(String.self, forKey: .sensitivity)
        freshness = try c.decodeIfPresent(WorkbenchDataSourceFreshness.self, forKey: .freshness)
        healthStatus = try c.decodeIfPresent(String.self, forKey: .healthStatus)
        allowedReaders = (try? c.decodeIfPresent([String].self, forKey: .allowedReaders)) ?? []
        allowedWriters = (try? c.decodeIfPresent([String].self, forKey: .allowedWriters)) ?? []
        bodyPolicy = try c.decodeIfPresent(String.self, forKey: .bodyPolicy)
        embeddingPolicy = try c.decodeIfPresent(String.self, forKey: .embeddingPolicy)
        retentionPolicy = try c.decodeIfPresent(String.self, forKey: .retentionPolicy)
        surfaceDestinations = (try? c.decodeIfPresent([String].self, forKey: .surfaceDestinations)) ?? []
        consumptionPath = try c.decodeIfPresent(String.self, forKey: .consumptionPath)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        blockers = (try? c.decodeIfPresent([WorkbenchDataSourceBlocker].self, forKey: .blockers)) ?? []
        evidenceRefs = (try? c.decodeIfPresent([String].self, forKey: .evidenceRefs)) ?? []
        scanner = try c.decodeIfPresent(WorkbenchDataSourceScanner.self, forKey: .scanner)
    }
}

struct WorkbenchDataSourceFreshness: Decodable, Hashable {
    let observedAt: Date?
    let modifiedAt: Date?
    let heartbeatRef: String?

    enum CodingKeys: String, CodingKey {
        case observedAt = "observed_at"
        case modifiedAt = "modified_at"
        case heartbeatRef = "heartbeat_ref"
    }
}

struct WorkbenchDataSourceBlocker: Decodable, Hashable {
    let reason: String?
    let requiredApprovals: [String]

    enum CodingKeys: String, CodingKey {
        case reason
        case requiredApprovals = "required_approvals"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        requiredApprovals = (try? c.decodeIfPresent([String].self, forKey: .requiredApprovals)) ?? []
    }
}

struct WorkbenchDataSourceScanner: Decodable, Hashable {
    let scannerId: String?
    let status: String?
    let bodyReadCount: Int
    let bodyCopyCount: Int
    let embeddingCount: Int
    let protectedBlockCount: Int
    let errorCount: Int

    enum CodingKeys: String, CodingKey {
        case status
        case scannerId = "scanner_id"
        case bodyReadCount = "body_read_count"
        case bodyCopyCount = "body_copy_count"
        case embeddingCount = "embedding_count"
        case protectedBlockCount = "protected_block_count"
        case errorCount = "error_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scannerId = try c.decodeIfPresent(String.self, forKey: .scannerId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        bodyReadCount = try c.decodeIfPresent(Int.self, forKey: .bodyReadCount) ?? 0
        bodyCopyCount = try c.decodeIfPresent(Int.self, forKey: .bodyCopyCount) ?? 0
        embeddingCount = try c.decodeIfPresent(Int.self, forKey: .embeddingCount) ?? 0
        protectedBlockCount = try c.decodeIfPresent(Int.self, forKey: .protectedBlockCount) ?? 0
        errorCount = try c.decodeIfPresent(Int.self, forKey: .errorCount) ?? 0
    }
}

struct WorkbenchResearchFlywheel: Decodable, Hashable {
    let schemaId: String?
    let source: String?
    let mode: String?
    let sideEffects: String?
    let generatedAt: Date?
    let bodyPolicy: WorkbenchResearchBodyPolicy?
    let fish: WorkbenchFishFleet?
    let referenceCandidates: WorkbenchReferenceCandidates?
    let researchRail: WorkbenchResearchRail?
    let flywheel: WorkbenchResearchFlywheelPolicy?

    enum CodingKeys: String, CodingKey {
        case source, mode, fish, flywheel
        case schemaId = "schema_id"
        case sideEffects = "side_effects"
        case generatedAt = "generated_at"
        case bodyPolicy = "body_policy"
        case referenceCandidates = "reference_candidates"
        case researchRail = "research_rail"
    }
}

struct WorkbenchResearchBodyPolicy: Decodable, Hashable {
    let sourceBodiesRead: Bool
    let sourceBodiesCopied: Bool
    let embeddingsCreated: Bool
    let fishWoken: Bool
    let memoryPromoted: Bool
    let protectedResearch: String?

    enum CodingKeys: String, CodingKey {
        case sourceBodiesRead = "source_bodies_read"
        case sourceBodiesCopied = "source_bodies_copied"
        case embeddingsCreated = "embeddings_created"
        case fishWoken = "fish_woken"
        case memoryPromoted = "memory_promoted"
        case protectedResearch = "protected_research"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceBodiesRead = try c.decodeIfPresent(Bool.self, forKey: .sourceBodiesRead) ?? false
        sourceBodiesCopied = try c.decodeIfPresent(Bool.self, forKey: .sourceBodiesCopied) ?? false
        embeddingsCreated = try c.decodeIfPresent(Bool.self, forKey: .embeddingsCreated) ?? false
        fishWoken = try c.decodeIfPresent(Bool.self, forKey: .fishWoken) ?? false
        memoryPromoted = try c.decodeIfPresent(Bool.self, forKey: .memoryPromoted) ?? false
        protectedResearch = try c.decodeIfPresent(String.self, forKey: .protectedResearch)
    }
}

struct WorkbenchFishFleet: Decodable, Hashable {
    let schema: String?
    let generatedAt: Date?
    let source: String?
    let summary: WorkbenchFishSummary
    let fish: [WorkbenchFishStatus]

    enum CodingKeys: String, CodingKey {
        case schema, source, summary, fish
        case generatedAt = "generated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        summary = try c.decodeIfPresent(WorkbenchFishSummary.self, forKey: .summary) ?? .empty
        fish = (try? c.decodeIfPresent([WorkbenchFishStatus].self, forKey: .fish)) ?? []
    }
}

struct WorkbenchFishSummary: Decodable, Hashable {
    static let empty = WorkbenchFishSummary(count: 0, producing: 0, idle: 0, blocked: 0, autoresearchReady: 0)

    let count: Int
    let producing: Int
    let idle: Int
    let blocked: Int
    let autoresearchReady: Int

    enum CodingKeys: String, CodingKey {
        case count, producing, idle, blocked
        case autoresearchReady = "autoresearch_ready"
    }

    init(count: Int, producing: Int, idle: Int, blocked: Int, autoresearchReady: Int) {
        self.count = count
        self.producing = producing
        self.idle = idle
        self.blocked = blocked
        self.autoresearchReady = autoresearchReady
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        producing = try c.decodeIfPresent(Int.self, forKey: .producing) ?? 0
        idle = try c.decodeIfPresent(Int.self, forKey: .idle) ?? 0
        blocked = try c.decodeIfPresent(Int.self, forKey: .blocked) ?? 0
        autoresearchReady = try c.decodeIfPresent(Int.self, forKey: .autoresearchReady) ?? 0
    }
}

struct WorkbenchFishStatus: Decodable, Identifiable, Hashable {
    let fish: String
    let owner: String?
    let modes: [String]
    let modeStatus: [String: String]
    let runtimeStatus: String?
    let statusReason: String?
    let directiveSlug: String?
    let sprint: WorkbenchFishSprint?
    let findings: WorkbenchFishFindings?
    let indexedFindings: Int?
    let indexFresh: Bool?
    let queue: WorkbenchFishQueue?
    let autoresearch: WorkbenchFishAutoresearch?

    var id: String { fish }

    enum CodingKeys: String, CodingKey {
        case fish, owner, modes, sprint, findings, queue, autoresearch
        case modeStatus = "mode_status"
        case runtimeStatus = "runtime_status"
        case statusReason = "status_reason"
        case directiveSlug = "directive_slug"
        case indexedFindings = "indexed_findings"
        case indexFresh = "index_fresh"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fish = try c.decodeIfPresent(String.self, forKey: .fish) ?? UUID().uuidString
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        modes = (try? c.decodeIfPresent([String].self, forKey: .modes)) ?? []
        modeStatus = (try? c.decodeIfPresent([String: String].self, forKey: .modeStatus)) ?? [:]
        runtimeStatus = try c.decodeIfPresent(String.self, forKey: .runtimeStatus)
        statusReason = try c.decodeIfPresent(String.self, forKey: .statusReason)
        directiveSlug = try c.decodeIfPresent(String.self, forKey: .directiveSlug)
        sprint = try c.decodeIfPresent(WorkbenchFishSprint.self, forKey: .sprint)
        findings = try c.decodeIfPresent(WorkbenchFishFindings.self, forKey: .findings)
        indexedFindings = try c.decodeIfPresent(Int.self, forKey: .indexedFindings)
        indexFresh = try c.decodeIfPresent(Bool.self, forKey: .indexFresh)
        queue = try c.decodeIfPresent(WorkbenchFishQueue.self, forKey: .queue)
        autoresearch = try c.decodeIfPresent(WorkbenchFishAutoresearch.self, forKey: .autoresearch)
    }
}

struct WorkbenchFishSprint: Decodable, Hashable {
    let completedSubqCount: Int?
    let current: Int?
    let max: Int?

    enum CodingKeys: String, CodingKey {
        case current, max
        case completedSubqCount = "completed_subq_count"
    }
}

struct WorkbenchFishFindings: Decodable, Hashable {
    let count: Int
    let latestMtime: Date?

    enum CodingKeys: String, CodingKey {
        case count
        case latestMtime = "latest_mtime"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        latestMtime = try c.decodeIfPresent(Date.self, forKey: .latestMtime)
    }
}

struct WorkbenchFishQueue: Decodable, Hashable {
    let pendingCount: Int
    let hasNext: Bool

    enum CodingKeys: String, CodingKey {
        case pendingCount = "pending_count"
        case hasNext = "has_next"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pendingCount = try c.decodeIfPresent(Int.self, forKey: .pendingCount) ?? 0
        hasNext = try c.decodeIfPresent(Bool.self, forKey: .hasNext) ?? false
    }
}

struct WorkbenchFishAutoresearch: Decodable, Hashable {
    let configured: Bool
    let rows: Int?
    let metricName: String?
    let decisionCounts: [String: Int]
    let latest: WorkbenchFishAutoresearchLatest?

    enum CodingKeys: String, CodingKey {
        case configured, rows, latest
        case metricName = "metric_name"
        case decisionCounts = "decision_counts"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configured = try c.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        rows = try c.decodeIfPresent(Int.self, forKey: .rows)
        metricName = try c.decodeIfPresent(String.self, forKey: .metricName)
        decisionCounts = try c.decodeIfPresent([String: Int].self, forKey: .decisionCounts) ?? [:]
        latest = try c.decodeIfPresent(WorkbenchFishAutoresearchLatest.self, forKey: .latest)
    }
}

struct WorkbenchFishAutoresearchLatest: Decodable, Hashable {
    let runId: String?
    let status: String?
    let decision: String?
    let completedAt: Date?
    let metricName: String?

    enum CodingKeys: String, CodingKey {
        case status, decision
        case runId = "run_id"
        case completedAt = "completed_at"
        case metricName = "metric_name"
    }
}

struct WorkbenchReferenceCandidates: Decodable, Hashable {
    let summary: WorkbenchReferenceSummary?

    enum CodingKeys: String, CodingKey {
        case summary
    }
}

struct WorkbenchReferenceSummary: Decodable, Hashable {
    let instanceCount: Int
    let byFish: [String: Int]
    let byReferenceSubclass: [String: Int]
    let reviewFlags: [String: Int]
    let promotionMode: String?

    enum CodingKeys: String, CodingKey {
        case instanceCount = "instance_count"
        case byFish = "by_fish"
        case byReferenceSubclass = "by_reference_subclass"
        case reviewFlags = "review_flags"
        case promotionMode = "promotion_mode"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instanceCount = try c.decodeIfPresent(Int.self, forKey: .instanceCount) ?? 0
        byFish = try c.decodeIfPresent([String: Int].self, forKey: .byFish) ?? [:]
        byReferenceSubclass = try c.decodeIfPresent([String: Int].self, forKey: .byReferenceSubclass) ?? [:]
        reviewFlags = try c.decodeIfPresent([String: Int].self, forKey: .reviewFlags) ?? [:]
        promotionMode = try c.decodeIfPresent(String.self, forKey: .promotionMode)
    }
}

struct WorkbenchResearchRail: Decodable, Hashable {
    let source: String?
    let counts: WorkbenchResearchRailCounts?

    enum CodingKeys: String, CodingKey {
        case source, counts
    }
}

struct WorkbenchResearchRailCounts: Decodable, Hashable {
    let requests: Int
    let packets: Int
    let awaitingReview: Int
    let activeRequests: Int

    enum CodingKeys: String, CodingKey {
        case requests, packets
        case awaitingReview = "awaiting_review"
        case activeRequests = "active_requests"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0
        packets = try c.decodeIfPresent(Int.self, forKey: .packets) ?? 0
        awaitingReview = try c.decodeIfPresent(Int.self, forKey: .awaitingReview) ?? 0
        activeRequests = try c.decodeIfPresent(Int.self, forKey: .activeRequests) ?? 0
    }
}

struct WorkbenchResearchFlywheelPolicy: Decodable, Hashable {
    let plannerWriteMode: String?
    let memoryPromotionMode: String?
    let recommendedReviewLoop: String?

    enum CodingKeys: String, CodingKey {
        case plannerWriteMode = "planner_write_mode"
        case memoryPromotionMode = "memory_promotion_mode"
        case recommendedReviewLoop = "recommended_review_loop"
    }
}

private extension AgentRunJSONValue {
    var workbenchStringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object, .array, .null:
            return nil
        }
    }
}
