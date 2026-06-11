import Foundation

// MARK: - Chat Channel Type

/// DTO-level channel type enum (singular forms to match API response)
enum DTOChatChannelType: String, Codable {
    case general
    case project
    case agent
    case research
    case alerts
    case direct

    // Handle API's "public" / "group" / "private" types by mapping to name-based type
    // The API uses channel.name (e.g. "general", "projects", "alerts") to determine type
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        // Try to match the standard enum cases first
        if let channelType = DTOChatChannelType(rawValue: rawValue) {
            self = channelType
        } else {
            // API returns "public", "group", "private" — default to general
            self = .general
        }
    }
}

// MARK: - User DTO

struct UserDTO: Codable, Identifiable {
    let id: String
    let name: String
    let email: String
    let preferredName: String?
    let role: String
    let isAgent: Bool
    let agentId: String?
    let avatarColor: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, role, timezone
        case preferredName = "preferred_name"
        case isAgent = "is_agent"
        case agentId = "agent_id"
        case avatarColor = "avatar_color"
    }
}

// MARK: - Channel DTO

struct ChannelDTO: Codable, Identifiable {
    let id: String
    let name: String
    let type: DTOChatChannelType
    let description: String?
    var unreadCount: Int = 0
    // API doesn't return isPinned — default to false
    var isPinned: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, type, description
        case unreadCount = "unread_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(DTOChatChannelType.self, forKey: .type) ?? .general
        description = try container.decodeIfPresent(String.self, forKey: .description)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }
}

// MARK: - Message DTO

struct MessageDTO: Codable, Identifiable {
    let id: String
    let channelId: String
    let authorId: String
    let authorName: String
    let content: String
    let timestamp: Date
    var isAgent: Bool
    let agentId: String?
    let reactions: [ReactionDTO]?
    let replyToId: String?
    let isThreadReply: Bool
    let threadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, content, isAgent, agentId, reactions, threadCount
        case channelId = "channel_id"
        case authorId = "sender_user_id"
        case authorName = "sender_name"
        case timestamp = "created_at"
        case replyToId = "reply_to_id"
        case isThreadReply = "is_thread_reply"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        channelId = try container.decode(String.self, forKey: .channelId)
        authorId = try container.decode(String.self, forKey: .authorId)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName) ?? "Unknown"
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        reactions = try container.decodeIfPresent([ReactionDTO].self, forKey: .reactions)
        replyToId = try container.decodeIfPresent(String.self, forKey: .replyToId)
        isThreadReply = try container.decodeIfPresent(Bool.self, forKey: .isThreadReply) ?? false
        threadCount = try container.decodeIfPresent(Int.self, forKey: .threadCount) ?? 0
        // Infer isAgent from presence of sender_agent_id
        isAgent = self.agentId != nil
    }
}

struct ReactionDTO: Codable {
    let emoji: String
    let count: Int
    let userIds: [String]

    enum CodingKeys: String, CodingKey {
        case emoji, count
        case userIds = "user_ids"
    }
}

// MARK: - Board DTO

struct BoardDTO: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let status: BoardStatus?
    let stage: String?
    let createdAt: Date
    let updatedAt: Date
    let taskCount: Int
    let completedTaskCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, status, stage, taskCount, completedTaskCount
        case description = "objective"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        status = try c.decodeIfPresent(BoardStatus.self, forKey: .status)
        stage = try c.decodeIfPresent(String.self, forKey: .stage)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        taskCount = try c.decodeIfPresent(Int.self, forKey: .taskCount) ?? 0
        completedTaskCount = try c.decodeIfPresent(Int.self, forKey: .completedTaskCount) ?? 0
    }
}

enum BoardStatus: String, Codable {
    case active
    case archived
    case completed
    case backlog
    case inProgress = "in_progress"
    case done
    case cancelled

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = BoardStatus(rawValue: rawValue) ?? .active
    }
}

// MARK: - Task DTO

struct TaskDTO: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let status: String?
    let stage: String?
    let assigneeId: String?
    let dueDate: Date?
    let priority: String?
    let tags: [String]?
    let assignedAgentId: String?
    let dueAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, stage, priority, tags
        case assigneeId = "assignee_id"
        case assignedAgentId = "assigned_agent_id"
        case dueDate = "due_date"
        case dueAt = "due_at"
    }
}

// MARK: - Identity Profile (nested in AgentDTO)

struct IdentityProfile: Codable {
    let role: String?
    let skills: String?   // comma-separated: "swift,swiftui,sqlite"

    /// Parses skills string into array, e.g. "swift,swiftui" → ["swift", "swiftui"]
    var skillsArray: [String] {
        skills?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    }
}

// MARK: - Agent DTO

struct AgentDTO: Codable, Identifiable {
    let id: String
    let name: String
    let status: AgentStatus
    let lastSeenAt: Date?
    let isBoardLead: Bool?
    let identityProfile: IdentityProfile?
    let rosterLane: String?
    let isDefaultRoutingEnabled: Bool?
    let quarantineState: String?
    let rosterNote: String?

    // Optional fields the app uses but backend doesn't expose yet
    let currentTask: String?
    let avatarColor: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, currentTask, avatarColor
        case lastSeenAt = "last_seen_at"
        case isBoardLead = "is_board_lead"
        case identityProfile = "identity_profile"
        case rosterLane = "roster_lane"
        case isDefaultRoutingEnabled = "is_default_routing_enabled"
        case quarantineState = "quarantine_state"
        case rosterNote = "roster_note"
    }

    /// Derived role from identity_profile, falling back to name-based defaults
    var role: String {
        identityProfile?.role?.replacingOccurrences(of: "_", with: " ").capitalized
            ?? (name == "maui" ? "Head of Engineering" : nil)
            ?? "Agent"
    }

    /// Derived skills from identity_profile (comma-separated → array)
    var skills: [String] {
        identityProfile?.skillsArray ?? []
    }

    var domainRosterLane: AgentRosterLane {
        if let rosterLane, let lane = AgentRosterLane(rawValue: rosterLane) {
            return lane
        }
        return AgentRosterPolicy.defaultLane(for: name)
    }
}

// MARK: - POD-5 Inbox Tail (c797ada1)
// Mirrors backend app/api/agents.py InboxTailResponse + InboxTailEntry.
// Non-destructive read of ~/.openclaw/agents/<name>/inbox.jsonl + cursor.

struct InboxTailEntryDTO: Codable, Identifiable, Hashable {
    let id: String
    let from: String
    let type: String
    let timestamp: String
    let textPreview: String
    let headline: String
    let isUnread: Bool

    enum CodingKeys: String, CodingKey {
        case id, from, type, timestamp, headline
        case textPreview = "text_preview"
        case isUnread = "is_unread"
    }

    /// Best-effort display title: headline first, fall back to preview, then placeholder.
    var displayTitle: String {
        if !headline.isEmpty { return headline }
        if !textPreview.isEmpty { return textPreview }
        return "(no content)"
    }
}

struct InboxTailDTO: Codable, Hashable {
    let agent: String
    let inboxPath: String
    let exists: Bool
    let totalEntries: Int
    let unreadEntries: Int
    let inboxBytes: Int
    let cursorBytes: Int
    let cursorPresent: Bool
    let lastActivityTs: String
    let recent: [InboxTailEntryDTO]

    enum CodingKeys: String, CodingKey {
        case agent, exists, recent
        case inboxPath = "inbox_path"
        case totalEntries = "total_entries"
        case unreadEntries = "unread_entries"
        case inboxBytes = "inbox_bytes"
        case cursorBytes = "cursor_bytes"
        case cursorPresent = "cursor_present"
        case lastActivityTs = "last_activity_ts"
    }
}

// MARK: - Agent Activation Context

struct AgentActivationContextDTO: Codable, Hashable {
    let packet: Packet
    let agent: AgentSummary
    let startHere: StartHere
    let roster: [String: [String]]
    let work: Work
    let reviewQueues: ReviewQueues
    let notes: Notes
    let guardrails: [String]

    enum CodingKeys: String, CodingKey {
        case packet, agent, roster, work, notes, guardrails
        case startHere = "start_here"
        case reviewQueues = "review_queues"
    }

    struct Packet: Codable, Hashable {
        let id: String?
        let generatedAt: String?
        let ttlSeconds: Int?
        let contextVersion: Int?
        let source: String?
        let mode: String?
        let computePolicy: ComputePolicy?

        enum CodingKeys: String, CodingKey {
            case id, source, mode
            case generatedAt = "generated_at"
            case ttlSeconds = "ttl_seconds"
            case contextVersion = "context_version"
            case computePolicy = "compute_policy"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
            ttlSeconds = try container.decodeIfPresent(Int.self, forKey: .ttlSeconds)
            contextVersion = try container.decodeIfPresent(Int.self, forKey: .contextVersion)
            source = try container.decodeIfPresent(String.self, forKey: .source)
            mode = try container.decodeIfPresent(String.self, forKey: .mode)
            computePolicy = try? container.decodeIfPresent(ComputePolicy.self, forKey: .computePolicy)
        }
    }

    struct ComputePolicy: Codable, Hashable {
        let defaultTag: String?
        let allowedTiers: [String]
        let fallbackAllowed: Bool?
        let caller: String?
        let source: String?
        let lane: String?
        let path: String?
        let intelligencePath: String?
        let workflowComputePath: String?
        let daemonComputePath: String?

        enum CodingKeys: String, CodingKey {
            case caller, source, lane, path
            case defaultTag = "default_tag"
            case allowedTiers = "allowed_tiers"
            case fallbackAllowed = "fallback_allowed"
            case intelligencePath = "intelligence_path"
            case workflowComputePath = "workflow_compute_path"
            case daemonComputePath = "daemon_compute_path"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            defaultTag = try container.decodeIfPresent(String.self, forKey: .defaultTag)
            allowedTiers = (try? container.decodeIfPresent([String].self, forKey: .allowedTiers)) ?? []
            fallbackAllowed = try container.decodeIfPresent(Bool.self, forKey: .fallbackAllowed)
            caller = try container.decodeIfPresent(String.self, forKey: .caller)
            source = try container.decodeIfPresent(String.self, forKey: .source)
            lane = try container.decodeIfPresent(String.self, forKey: .lane)
            path = try container.decodeIfPresent(String.self, forKey: .path)
            intelligencePath = try container.decodeIfPresent(String.self, forKey: .intelligencePath)
            workflowComputePath = try container.decodeIfPresent(String.self, forKey: .workflowComputePath)
            daemonComputePath = try container.decodeIfPresent(String.self, forKey: .daemonComputePath)
        }
    }

    struct AgentSummary: Codable, Hashable {
        let id: String
        let name: String
        let status: String?
        let rosterLane: String?
        let title: String?
        let defaultRoutingEnabled: Bool?
        let owns: [String]
        let protectedDomains: [String]
        let responsibilityDomains: [String]

        enum CodingKeys: String, CodingKey {
            case id, name, status, title, owns
            case rosterLane = "roster_lane"
            case defaultRoutingEnabled = "default_routing_enabled"
            case protectedDomains = "protected_domains"
            case responsibilityDomains = "responsibility_domains"
        }
    }

    struct StartHere: Codable, Hashable {
        let docs: [String]
        let manualChecks: [String]
        let startupStatusEndpoint: String?
        let responsibilityEndpoint: String?
        let assignedTicketsEndpoint: String?
        let reviewRequiredRunsEndpoint: String?
        let intelligenceEndpoints: [IntelligenceEndpoint]?

        enum CodingKeys: String, CodingKey {
            case docs
            case manualChecks = "manual_checks"
            case startupStatusEndpoint = "startup_status_endpoint"
            case responsibilityEndpoint = "responsibility_endpoint"
            case assignedTicketsEndpoint = "assigned_tickets_endpoint"
            case reviewRequiredRunsEndpoint = "review_required_runs_endpoint"
            case intelligenceEndpoints = "intelligence_endpoints"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            docs = try container.decodeIfPresent([String].self, forKey: .docs) ?? []
            manualChecks = try container.decodeIfPresent([String].self, forKey: .manualChecks) ?? []
            startupStatusEndpoint = try container.decodeIfPresent(String.self, forKey: .startupStatusEndpoint)
            responsibilityEndpoint = try container.decodeIfPresent(String.self, forKey: .responsibilityEndpoint)
            assignedTicketsEndpoint = try container.decodeIfPresent(String.self, forKey: .assignedTicketsEndpoint)
            reviewRequiredRunsEndpoint = try container.decodeIfPresent(String.self, forKey: .reviewRequiredRunsEndpoint)
            intelligenceEndpoints = Self.decodeIntelligenceEndpoints(from: container)
        }

        private static func decodeIntelligenceEndpoints(from container: KeyedDecodingContainer<CodingKeys>) -> [IntelligenceEndpoint]? {
            if let endpoints = try? container.decodeIfPresent([IntelligenceEndpoint].self, forKey: .intelligenceEndpoints) {
                return endpoints
            }
            if let names = try? container.decodeIfPresent([String].self, forKey: .intelligenceEndpoints) {
                return names.map { IntelligenceEndpoint(name: $0, path: nil) }
            }
            if let endpointsByName = try? container.decodeIfPresent([String: IntelligenceEndpoint].self, forKey: .intelligenceEndpoints) {
                return endpointsByName
                    .map { key, value in value.withFallbackName(key) }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
            if let pathsByName = try? container.decodeIfPresent([String: String].self, forKey: .intelligenceEndpoints) {
                return pathsByName
                    .map { IntelligenceEndpoint(name: $0.key, path: $0.value) }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
            return nil
        }
    }

    struct IntelligenceEndpoint: Codable, Hashable, Identifiable {
        let name: String?
        let path: String?

        var id: String { displayName }

        var displayName: String {
            if let name, !name.isEmpty { return name }
            if let path, !path.isEmpty { return path }
            return "intelligence"
        }

        enum CodingKeys: String, CodingKey {
            case name, path
        }

        init(name: String?, path: String?) {
            self.name = name
            self.path = path
        }

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                name = value
                path = nil
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            path = try container.decodeIfPresent(String.self, forKey: .path)
        }

        func withFallbackName(_ fallback: String) -> IntelligenceEndpoint {
            IntelligenceEndpoint(name: name?.isEmpty == false ? name : fallback, path: path)
        }
    }

    struct Work: Codable, Hashable {
        let assignedTicketCount: Int
        let assignedTickets: [Ticket]

        enum CodingKeys: String, CodingKey {
            case assignedTicketCount = "assigned_ticket_count"
            case assignedTickets = "assigned_tickets"
        }
    }

    struct Ticket: Codable, Hashable, Identifiable {
        let id: String
        let title: String
        let status: String?
        let priority: String?
        let ticketType: String?
        let computeTag: String?
        let approvalState: String?
        let autonomyLevel: String?
        let workerLane: String?
        let toolPolicy: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, title, status, priority
            case ticketType = "ticket_type"
            case computeTag = "compute_tag"
            case approvalState = "approval_state"
            case autonomyLevel = "autonomy_level"
            case workerLane = "worker_lane"
            case toolPolicy = "tool_policy"
            case updatedAt = "updated_at"
        }
    }

    struct ReviewQueues: Codable, Hashable {
        let agentReviewRequiredCount: Int
        let agentReviewRequiredRuns: [ReviewRun]
        let globalReviewRequiredCount: Int
        let globalReviewRequiredEndpoint: String?

        enum CodingKeys: String, CodingKey {
            case agentReviewRequiredCount = "agent_review_required_count"
            case agentReviewRequiredRuns = "agent_review_required_runs"
            case globalReviewRequiredCount = "global_review_required_count"
            case globalReviewRequiredEndpoint = "global_review_required_endpoint"
        }
    }

    struct ReviewRun: Codable, Hashable, Identifiable {
        let id: String
        let ticketId: String?
        let status: String?
        let runType: String?
        let traceId: String?
        let workerLane: String?
        let toolPolicy: String?
        let reviewStatus: String?
        let outcome: String?
        let error: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, status, outcome, error
            case ticketId = "ticket_id"
            case runType = "run_type"
            case traceId = "trace_id"
            case workerLane = "worker_lane"
            case toolPolicy = "tool_policy"
            case reviewStatus = "review_status"
            case updatedAt = "updated_at"
        }
    }

    struct Notes: Codable, Hashable {
        let recentWorkNotes: [WorkNote]
        let workNotesEndpoint: String?
        let findingLandingRule: String?

        enum CodingKeys: String, CodingKey {
            case recentWorkNotes = "recent_work_notes"
            case workNotesEndpoint = "work_notes_endpoint"
            case findingLandingRule = "finding_landing_rule"
        }
    }

    struct WorkNote: Codable, Hashable, Identifiable {
        let id: String
        let message: String
        let traceId: String?
        let source: String?
        let lane: String?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, message, source, lane
            case traceId = "trace_id"
            case createdAt = "created_at"
        }
    }
}

enum AgentStatus: String, Codable {
    case online
    case busy
    case idle
    case offline
    case error
    case provisioning
    case active

    // One unknown status string must never nuke the whole roster decode
    // (2026-06-11: backend started returning "active"; the dashboard showed
    // "No agents available" + count 0 while the presence strip showed 5).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AgentStatus(rawValue: raw.lowercased()) ?? .offline
    }
}

// MARK: - Send Message Request

struct SendMessageRequest: Encodable {
    let content: String
    let replyToId: String?

    enum CodingKeys: String, CodingKey {
        case content
        case replyToId = "reply_to_id"
    }
}

// MARK: - Paginated Response Wrapper

struct PaginatedResponse<T: Codable>: Codable {
    let items: [T]
    let total: Int
    let limit: Int?
    let offset: Int?
}

// MARK: - Projects

struct ProjectDTO: Codable, Identifiable {
    let id: UUID
    let boardId: UUID?
    let boardIds: [UUID]?
    let name: String
    let goal: String?
    let description: String?
    let status: String  // backlog, in-progress, done, archived
    let priority: Int   // 1 (highest) to 5 (lowest)
    let projectedCost: Double?
    let actualCost: Double?
    let createdBy: UUID?
    let assignedTo: UUID?
    let createdAt: Date
    let updatedAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let dueDate: Date?
    let stage: String?
    var automationEnabled: Bool? = nil
    var proposedMilestones: [ProjectMilestoneProposalDTO]? = nil
    var milestones: [ProjectMilestoneDTO]? = nil
    var lastGenerationRunId: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, goal, description, status, priority, stage
        case boardId = "board_id"
        case boardIds = "board_ids"
        case projectedCost = "projected_cost"
        case actualCost = "actual_cost"
        case createdBy = "created_by"
        case assignedTo = "assigned_to"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case dueDate = "due_date"
        case automationEnabled = "automation_enabled"
        case proposedMilestones = "proposed_milestones"
        case milestones
        case lastGenerationRunId = "last_generation_run_id"
    }
}

struct ProjectMilestoneProposalDTO: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var description: String?
    var status: String?
    var dependencies: [String]?
    var route: String?
    var model: String?
    var artifactHash: String?
    var runId: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, dependencies, route, model
        case milestoneId = "milestone_id"
        case outcome
        case dependsOn = "depends_on"
        case artifactHash = "artifact_hash"
        case runId = "run_id"
        case sourceRunId = "source_run_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .milestoneId)
            ?? UUID().uuidString
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .outcome)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies)
            ?? container.decodeIfPresent([String].self, forKey: .dependsOn)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        artifactHash = try container.decodeIfPresent(String.self, forKey: .artifactHash)
        runId = try container.decodeIfPresent(String.self, forKey: .runId)
            ?? container.decodeIfPresent(String.self, forKey: .sourceRunId)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(dependencies, forKey: .dependencies)
        try container.encodeIfPresent(route, forKey: .route)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(artifactHash, forKey: .artifactHash)
        try container.encodeIfPresent(runId, forKey: .runId)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

struct ProjectMilestoneDTO: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var description: String?
    var status: String?
    var acceptedAt: Date?
    var sourceRunId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case milestoneId = "milestone_id"
        case outcome
        case acceptedAt = "accepted_at"
        case sourceRunId = "source_run_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .milestoneId)
            ?? UUID().uuidString
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .outcome)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        acceptedAt = try container.decodeIfPresent(Date.self, forKey: .acceptedAt)
        sourceRunId = try container.decodeIfPresent(String.self, forKey: .sourceRunId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(acceptedAt, forKey: .acceptedAt)
        try container.encodeIfPresent(sourceRunId, forKey: .sourceRunId)
    }
}

struct ProjectTaskDTO: Codable, Identifiable {
    let id: UUID
    let projectId: UUID
    let title: String
    let description: String?
    let status: String  // backlog, in-progress, done, blocked, cancelled
    let priority: Int
    let parentTaskId: UUID?
    let createdBy: UUID?
    let assignedTo: UUID?
    let createdAt: Date
    let updatedAt: Date
    let dueDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority
        case projectId = "project_id"
        case parentTaskId = "parent_task_id"
        case createdBy = "created_by"
        case assignedTo = "assigned_to"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dueDate = "due_date"
    }
}

struct ProjectTaskUpdateRequest: Encodable {
    let title: String?
    let description: String?
    let status: String?
    let priority: Int?
    let dueDate: Date?
    let assignedTo: UUID?
    let parentTaskId: UUID?

    enum CodingKeys: String, CodingKey {
        case title, description, status, priority
        case dueDate = "due_date"
        case assignedTo = "assigned_to"
        case parentTaskId = "parent_task_id"
    }
}

struct ProjectNoteDTO: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let organizationId: UUID?
    let targetType: String
    let targetId: String?
    let noteType: String
    let title: String
    let body: String
    let tags: [String]?
    let createdBy: String?
    let source: String?
    let traceId: String?
    let owner: String?
    let reviewer: String?
    let signState: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body, tags, source, owner, reviewer
        case organizationId = "organization_id"
        case targetType = "target_type"
        case targetId = "target_id"
        case noteType = "note_type"
        case createdBy = "created_by"
        case traceId = "trace_id"
        case signState = "sign_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var typeLabel: String {
        noteType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct ProjectCreateRequest: Encodable {
    let name: String
    let goal: String?
    let description: String?
    let priority: Int?
    let stage: String?
    let dueDate: Date?
    let boardId: String?

    enum CodingKeys: String, CodingKey {
        case name, goal, description, priority, stage
        case dueDate = "due_date"
        case boardId = "board_id"
    }
}
