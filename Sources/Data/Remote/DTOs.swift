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

struct MessageDTO: Decodable, Identifiable {
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
    let fileAttachment: ChatFileAttachment?

    enum CodingKeys: String, CodingKey {
        case id, content, isAgent, agentId, reactions, threadCount, metadata
        case channelId = "channel_id"
        case authorId = "sender_user_id"
        case authorName = "sender_name"
        case timestamp = "created_at"
        case replyToId = "reply_to_id"
        case isThreadReply = "is_thread_reply"
    }

    private struct Metadata: Decodable {
        let file: String?
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
        let metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata)
        fileAttachment = ChatFileAttachment(path: metadata?.file)
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
    let boardGroupId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, stage, taskCount, completedTaskCount
        case description = "objective"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case boardGroupId = "board_group_id"
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
        boardGroupId = try c.decodeIfPresent(String.self, forKey: .boardGroupId)
    }
}

struct BoardGroupDTO: Codable, Identifiable {
    let id: String
    let name: String
    let slug: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description
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
    let supportRuntime: String?
    let allowedRuntimes: [String]
    let runtimeHost: String?
    let lastAwakeProofAt: Date?
    let lastSleepProofAt: Date?
    let driftState: String?
    let tokenProfile: String?

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
        case supportRuntime = "support_runtime"
        case allowedRuntimes = "allowed_runtimes"
        case runtimeHost = "runtime_host"
        case lastAwakeProofAt = "last_awake_proof_at"
        case lastSleepProofAt = "last_sleep_proof_at"
        case driftState = "drift_state"
        case tokenProfile = "token_profile"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(AgentStatus.self, forKey: .status)
        currentTask = try container.decodeIfPresent(String.self, forKey: .currentTask)
        avatarColor = try container.decodeIfPresent(String.self, forKey: .avatarColor)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        isBoardLead = try container.decodeIfPresent(Bool.self, forKey: .isBoardLead)
        identityProfile = try container.decodeIfPresent(IdentityProfile.self, forKey: .identityProfile)
        rosterLane = try container.decodeIfPresent(String.self, forKey: .rosterLane)
        isDefaultRoutingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDefaultRoutingEnabled)
        quarantineState = try container.decodeIfPresent(String.self, forKey: .quarantineState)
        rosterNote = try container.decodeIfPresent(String.self, forKey: .rosterNote)
        supportRuntime = try container.decodeIfPresent(String.self, forKey: .supportRuntime)
        allowedRuntimes = try container.decodeIfPresent([String].self, forKey: .allowedRuntimes) ?? []
        runtimeHost = try container.decodeIfPresent(String.self, forKey: .runtimeHost)
        lastAwakeProofAt = try container.decodeIfPresent(Date.self, forKey: .lastAwakeProofAt)
        lastSleepProofAt = try container.decodeIfPresent(Date.self, forKey: .lastSleepProofAt)
        driftState = try container.decodeIfPresent(String.self, forKey: .driftState)
        tokenProfile = try container.decodeIfPresent(String.self, forKey: .tokenProfile)
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
    let file: String?
    let isUnread: Bool

    enum CodingKeys: String, CodingKey {
        case id, from, type, timestamp, headline, file
        case textPreview = "text_preview"
        case isUnread = "is_unread"
    }

    /// Best-effort display title: headline first, fall back to preview, then placeholder.
    var displayTitle: String {
        if !headline.isEmpty { return headline }
        if !textPreview.isEmpty { return textPreview }
        return "(no content)"
    }

    var fileDisplayName: String? {
        guard let file, !file.isEmpty else { return nil }
        return URL(fileURLWithPath: file).lastPathComponent
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

// MARK: - Agent Locker

struct AgentLockerPreferences: Decodable, Hashable {
    let pinnedTabs: [String]
    let pinnedTools: [String]
    enum CodingKeys: String, CodingKey {
        case pinnedTabs = "pinned_tabs"
        case pinnedTools = "pinned_tools"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pinnedTabs = (try? c.decodeIfPresent([String].self, forKey: .pinnedTabs)) ?? []
        pinnedTools = (try? c.decodeIfPresent([String].self, forKey: .pinnedTools)) ?? []
    }
    init(pinnedTabs: [String] = [], pinnedTools: [String] = []) {
        self.pinnedTabs = pinnedTabs
        self.pinnedTools = pinnedTools
    }
}

struct AgentLockerDTO: Decodable, Hashable {
    let schema: String?
    let source: String?
    let generatedAt: String?
    let agentProfile: LockerAgentProfile?
    let tools: LockerTools?
    let guardrails: [String]
    let startHere: StartHere
    let planner: Planner
    let orcaTasks: OrcaTasks
    let inbox: Inbox
    let heartbeat: Heartbeat
    let lockerMemory: LockerMemory
    let researchRail: ResearchRail
    let library: Library
    let escalation: Escalation
    let dashboards: [Dashboard]
    let feedback: Feedback
    let gaps: [String]
    let wakeMarkdown: String?
    let preferences: AgentLockerPreferences

    enum CodingKeys: String, CodingKey {
        case schema, source, planner, inbox, dashboards, feedback, gaps, heartbeat, library, escalation, guardrails, preferences
        case generatedAt = "generated_at"
        case agentProfile = "agent"
        case tools
        case startHere = "start_here"
        case orcaTasks = "orca_tasks"
        case lockerMemory = "locker_memory"
        case researchRail = "research_rail"
        case wakeMarkdown = "wake_markdown"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decodeIfPresent(String.self, forKey: .schema)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        agentProfile = try container.decodeIfPresent(LockerAgentProfile.self, forKey: .agentProfile)
        tools = try container.decodeIfPresent(LockerTools.self, forKey: .tools)
        guardrails = try container.decodeIfPresent([String].self, forKey: .guardrails) ?? []
        startHere = try container.decodeIfPresent(StartHere.self, forKey: .startHere) ?? StartHere()
        planner = try container.decodeIfPresent(Planner.self, forKey: .planner) ?? Planner()
        orcaTasks = try container.decodeIfPresent(OrcaTasks.self, forKey: .orcaTasks) ?? OrcaTasks()
        inbox = try container.decodeIfPresent(Inbox.self, forKey: .inbox) ?? Inbox()
        heartbeat = try container.decodeIfPresent(Heartbeat.self, forKey: .heartbeat) ?? Heartbeat()
        lockerMemory = try container.decodeIfPresent(LockerMemory.self, forKey: .lockerMemory) ?? LockerMemory()
        researchRail = try container.decodeIfPresent(ResearchRail.self, forKey: .researchRail) ?? ResearchRail()
        library = try container.decodeIfPresent(Library.self, forKey: .library) ?? Library()
        escalation = try container.decodeIfPresent(Escalation.self, forKey: .escalation) ?? Escalation()
        dashboards = try container.decodeIfPresent([Dashboard].self, forKey: .dashboards) ?? []
        feedback = try container.decodeIfPresent(Feedback.self, forKey: .feedback) ?? Feedback()
        gaps = try container.decodeIfPresent([String].self, forKey: .gaps) ?? []
        wakeMarkdown = try container.decodeIfPresent(String.self, forKey: .wakeMarkdown)
        preferences = (try? container.decodeIfPresent(AgentLockerPreferences.self, forKey: .preferences)) ?? AgentLockerPreferences()
    }

    // MARK: - Report Card types (M1 — identity, owns, tools, compliance)

    struct LockerAgentProfile: Decodable, Hashable {
        let id: String?
        let name: String?
        let status: String?
        let rosterLane: String?
        let title: String?
        let owns: [String]
        let protectedDomains: [String]

        enum CodingKeys: String, CodingKey {
            case id, name, status, title, owns
            case rosterLane = "roster_lane"
            case protectedDomains = "protected_domains"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            status = try c.decodeIfPresent(String.self, forKey: .status)
            rosterLane = try c.decodeIfPresent(String.self, forKey: .rosterLane)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            owns = try c.decodeIfPresent([String].self, forKey: .owns) ?? []
            protectedDomains = try c.decodeIfPresent([String].self, forKey: .protectedDomains) ?? []
        }
    }

    struct LockerTools: Decodable, Hashable {
        let available: [LockerTool]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            available = try c.decodeIfPresent([LockerTool].self, forKey: .available) ?? []
        }

        enum CodingKeys: String, CodingKey { case available }

        struct LockerTool: Decodable, Hashable, Identifiable {
            let label: String?
            let endpoint: String?
            let mode: String?
            var id: String { label ?? endpoint ?? UUID().uuidString }
        }
    }

    struct StartHere: Decodable, Hashable {
        let headline: String?
        let priority: String?
        let reason: String?
        let primaryAction: String?
        let blockedBy: String?
        let sourceRefs: [String: String?]

        enum CodingKeys: String, CodingKey {
            case headline, priority, reason
            case primaryAction = "primary_action"
            case blockedBy = "blocked_by"
            case sourceRefs = "source_refs"
        }

        init(headline: String? = nil, priority: String? = nil, reason: String? = nil, primaryAction: String? = nil, blockedBy: String? = nil, sourceRefs: [String: String?] = [:]) {
            self.headline = headline
            self.priority = priority
            self.reason = reason
            self.primaryAction = primaryAction
            self.blockedBy = blockedBy
            self.sourceRefs = sourceRefs
        }
    }

    struct Planner: Decodable, Hashable {
        let counts: Counts
        let lanes: Lanes
        let emptyReasons: [String: String?]

        enum CodingKeys: String, CodingKey {
            case counts, lanes
            case emptyReasons = "empty_reasons"
        }

        init(counts: Counts = Counts(), lanes: Lanes = Lanes(), emptyReasons: [String: String?] = [:]) {
            self.counts = counts
            self.lanes = lanes
            self.emptyReasons = emptyReasons
        }

        struct Counts: Decodable, Hashable {
            let now: Int
            let next: Int
            let blocked: Int
            let waiting: Int
            let review: Int
            let fyi: Int

            enum CodingKeys: String, CodingKey {
                case now, next, blocked, waiting, review, fyi
            }

            init(now: Int = 0, next: Int = 0, blocked: Int = 0, waiting: Int = 0, review: Int = 0, fyi: Int = 0) {
                self.now = now
                self.next = next
                self.blocked = blocked
                self.waiting = waiting
                self.review = review
                self.fyi = fyi
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                now = try container.decodeIfPresent(Int.self, forKey: .now) ?? 0
                next = try container.decodeIfPresent(Int.self, forKey: .next) ?? 0
                blocked = try container.decodeIfPresent(Int.self, forKey: .blocked) ?? 0
                waiting = try container.decodeIfPresent(Int.self, forKey: .waiting) ?? 0
                review = try container.decodeIfPresent(Int.self, forKey: .review) ?? 0
                fyi = try container.decodeIfPresent(Int.self, forKey: .fyi) ?? 0
            }
        }

        struct Lanes: Decodable, Hashable {
            let now: [WorkItem]
            let next: [WorkItem]
            let blocked: [WorkItem]
            let waiting: [WorkItem]
            let review: [WorkItem]
            let fyi: [WorkItem]

            init(now: [WorkItem] = [], next: [WorkItem] = [], blocked: [WorkItem] = [], waiting: [WorkItem] = [], review: [WorkItem] = [], fyi: [WorkItem] = []) {
                self.now = now
                self.next = next
                self.blocked = blocked
                self.waiting = waiting
                self.review = review
                self.fyi = fyi
            }
        }
    }

    struct WorkItem: Decodable, Hashable, Identifiable {
        let id: String?
        let title: String?
        let priority: String?
        let state: String?
        let status: String?
        let lane: String?
        let owner: String?
        let nextAction: String?
        let source: String?
        let whyShown: String?
        let blockedOn: String?
        let updatedAt: String?
        let ticketId: String?
        let reviewStatus: String?
        let summary: String?

        var stableId: String { id ?? title ?? summary ?? "item" }
        var displayTitle: String { title ?? summary ?? id ?? "Untitled item" }
        var displayState: String? { state ?? status ?? reviewStatus }

        enum CodingKeys: String, CodingKey {
            case id, title, priority, state, status, lane, owner, source, summary
            case nextAction = "next_action"
            case whyShown = "why_shown"
            case blockedOn = "blocked_on"
            case updatedAt = "updated_at"
            case ticketId = "ticket_id"
            case reviewStatus = "review_status"
        }
    }

    struct OrcaTasks: Decodable, Hashable {
        let assigned: [WorkItem]
        let activeRuns: [WorkItem]
        let reviewRequiredRuns: [WorkItem]
        let claimable: [WorkItem]
        let mentioned: [WorkItem]
        let stale: [WorkItem]
        let evidenceClose: [WorkItem]
        let emptyReasons: [String: String?]

        enum CodingKeys: String, CodingKey {
            case assigned, claimable, mentioned, stale
            case activeRuns = "active_runs"
            case reviewRequiredRuns = "review_required_runs"
            case evidenceClose = "evidence_close"
            case emptyReasons = "empty_reasons"
        }

        init(assigned: [WorkItem] = [], activeRuns: [WorkItem] = [], reviewRequiredRuns: [WorkItem] = [], claimable: [WorkItem] = [], mentioned: [WorkItem] = [], stale: [WorkItem] = [], evidenceClose: [WorkItem] = [], emptyReasons: [String: String?] = [:]) {
            self.assigned = assigned
            self.activeRuns = activeRuns
            self.reviewRequiredRuns = reviewRequiredRuns
            self.claimable = claimable
            self.mentioned = mentioned
            self.stale = stale
            self.evidenceClose = evidenceClose
            self.emptyReasons = emptyReasons
        }
    }

    struct Inbox: Decodable, Hashable {
        let actionCount: Int
        let staleCount: Int
        let bodyGapCount: Int
        let gap: String?
        let emptyReason: String?
        let threads: [Thread]

        enum CodingKeys: String, CodingKey {
            case gap, threads
            case emptyReason = "empty_reason"
            case actionCount = "action_count"
            case staleCount = "stale_count"
            case bodyGapCount = "body_gap_count"
        }

        init(actionCount: Int = 0, staleCount: Int = 0, bodyGapCount: Int = 0, gap: String? = nil, emptyReason: String? = nil, threads: [Thread] = []) {
            self.actionCount = actionCount
            self.staleCount = staleCount
            self.bodyGapCount = bodyGapCount
            self.gap = gap
            self.emptyReason = emptyReason
            self.threads = threads
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            actionCount = try container.decodeIfPresent(Int.self, forKey: .actionCount) ?? 0
            staleCount = try container.decodeIfPresent(Int.self, forKey: .staleCount) ?? 0
            bodyGapCount = try container.decodeIfPresent(Int.self, forKey: .bodyGapCount) ?? 0
            gap = try container.decodeIfPresent(String.self, forKey: .gap)
            emptyReason = try container.decodeIfPresent(String.self, forKey: .emptyReason)
            threads = try container.decodeIfPresent([Thread].self, forKey: .threads) ?? []
        }

        struct Thread: Decodable, Hashable, Identifiable {
            let id: String?
            let sender: String?
            let timestamp: String?
            let classification: String?
            let source: String?
            let bodyAvailable: Bool?
            let bodyUnavailableReason: String?
            let stale: Bool?
            let handled: Bool?
            let actionRequired: Bool?
            let replyLane: String?
            let sourceRefs: [String: String?]

            var stableId: String { id ?? sender ?? "thread" }

            enum CodingKeys: String, CodingKey {
                case id, sender, timestamp, classification, source, stale, handled
                case bodyAvailable = "body_available"
                case bodyUnavailableReason = "body_unavailable_reason"
                case actionRequired = "action_required"
                case replyLane = "reply_lane"
                case sourceRefs = "source_refs"
            }
        }
    }

    struct Heartbeat: Decodable, Hashable {
        let status: String?
        let currentSessionId: String?
        let lastHeartbeatAt: String?
        let awakeAt: String?
        let sleepAt: String?
        let currentWork: String?
        let blocker: String?
        let nextCheckpoint: String?
        let staleThreshold: String?
        let lastSleepProof: String?

        enum CodingKeys: String, CodingKey {
            case status, blocker
            case currentSessionId = "current_session_id"
            case lastHeartbeatAt = "last_heartbeat_at"
            case awakeAt = "awake_at"
            case sleepAt = "sleep_at"
            case currentWork = "current_work"
            case nextCheckpoint = "next_checkpoint"
            case staleThreshold = "stale_threshold"
            case lastSleepProof = "last_sleep_proof"
        }

        init(status: String? = nil, currentSessionId: String? = nil, lastHeartbeatAt: String? = nil, awakeAt: String? = nil, sleepAt: String? = nil, currentWork: String? = nil, blocker: String? = nil, nextCheckpoint: String? = nil, staleThreshold: String? = nil, lastSleepProof: String? = nil) {
            self.status = status
            self.currentSessionId = currentSessionId
            self.lastHeartbeatAt = lastHeartbeatAt
            self.awakeAt = awakeAt
            self.sleepAt = sleepAt
            self.currentWork = currentWork
            self.blocker = blocker
            self.nextCheckpoint = nextCheckpoint
            self.staleThreshold = staleThreshold
            self.lastSleepProof = lastSleepProof
        }
    }

    struct LockerMemory: Decodable, Hashable {
        let dailyLogRef: String?
        let dailyLogBytes: Int?
        let dailyMemoryLoaded: Bool?
        let lastSessionSummary: String?
        let openLoops: [String]
        let commitments: [String]
        let compactionSummary: String?
        let unresolvedBlockers: [String]
        let memoryCandidates: [WorkItem]
        let emptyReason: String?

        enum CodingKeys: String, CodingKey {
            case commitments
            case dailyLogRef = "daily_log_ref"
            case dailyLogBytes = "daily_log_bytes"
            case dailyMemoryLoaded = "daily_memory_loaded"
            case lastSessionSummary = "last_session_summary"
            case openLoops = "open_loops"
            case compactionSummary = "compaction_summary"
            case unresolvedBlockers = "unresolved_blockers"
            case memoryCandidates = "memory_candidates"
            case emptyReason = "empty_reason"
        }

        init(dailyLogRef: String? = nil, dailyLogBytes: Int? = nil, dailyMemoryLoaded: Bool? = nil, lastSessionSummary: String? = nil, openLoops: [String] = [], commitments: [String] = [], compactionSummary: String? = nil, unresolvedBlockers: [String] = [], memoryCandidates: [WorkItem] = [], emptyReason: String? = nil) {
            self.dailyLogRef = dailyLogRef
            self.dailyLogBytes = dailyLogBytes
            self.dailyMemoryLoaded = dailyMemoryLoaded
            self.lastSessionSummary = lastSessionSummary
            self.openLoops = openLoops
            self.commitments = commitments
            self.compactionSummary = compactionSummary
            self.unresolvedBlockers = unresolvedBlockers
            self.memoryCandidates = memoryCandidates
            self.emptyReason = emptyReason
        }
    }

    struct DashboardCard: Decodable, Hashable, Identifiable {
        let type: String?
        let id: String
        let title: String?
        let status: String?
        let priority: String?

        enum CodingKeys: String, CodingKey { case type, id, title, status, priority }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try? c.decodeIfPresent(String.self, forKey: .type)
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
            title = try? c.decodeIfPresent(String.self, forKey: .title)
            status = try? c.decodeIfPresent(String.self, forKey: .status)
            priority = try? c.decodeIfPresent(String.self, forKey: .priority)
        }
    }

    struct Dashboard: Decodable, Hashable, Identifiable {
        let id: String
        let title: String?
        let visibility: String?
        let status: String?
        let summary: String?
        let previewAvailable: Bool?
        let cards: [DashboardCard]
        let actions: [String]

        enum CodingKeys: String, CodingKey {
            case id, title, visibility, status, summary, cards, actions
            case previewAvailable = "preview_available"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            previewAvailable = try container.decodeIfPresent(Bool.self, forKey: .previewAvailable)
            cards = (try? container.decodeIfPresent([DashboardCard].self, forKey: .cards)) ?? []
            actions = (try? container.decodeIfPresent([String].self, forKey: .actions)) ?? []
        }
    }

    struct ResearchPacket: Decodable, Hashable {
        let id: String?
        let researchId: String?
        let title: String?
        let summary: String?
        let status: String?
        let reviewState: String?
        let domain: String?
        let requestedBy: String?
        let assignedTo: String?
        let updatedAt: String?
        let source: String?
        let nextAction: String?

        var stableId: String { id ?? researchId ?? title ?? "packet" }

        enum CodingKeys: String, CodingKey {
            case id, title, summary, status, source, domain
            case researchId = "research_id"
            case reviewState = "review_state"
            case requestedBy = "requested_by"
            case assignedTo = "assigned_to"
            case updatedAt = "updated_at"
            case nextAction = "next_action"
        }
    }

    struct ResearchRail: Decodable, Hashable {
        let activeRequests: [ResearchPacket]
        let activePackets: [ResearchPacket]
        let awaitingReview: [ResearchPacket]
        let reviewedRelevant: [ResearchPacket]
        let counts: Counts
        let source: String?
        let requestEndpoint: String?
        let packetEndpoint: String?
        let emptyReason: String?

        enum CodingKeys: String, CodingKey {
            case counts, source
            case activeRequests = "active_requests"
            case activePackets = "active_packets"
            case awaitingReview = "awaiting_review"
            case reviewedRelevant = "reviewed_relevant"
            case requestEndpoint = "request_endpoint"
            case packetEndpoint = "packet_endpoint"
            case emptyReason = "empty_reason"
        }

        init(activeRequests: [ResearchPacket] = [], activePackets: [ResearchPacket] = [], awaitingReview: [ResearchPacket] = [], reviewedRelevant: [ResearchPacket] = [], counts: Counts = Counts(), source: String? = nil, requestEndpoint: String? = nil, packetEndpoint: String? = nil, emptyReason: String? = nil) {
            self.activeRequests = activeRequests
            self.activePackets = activePackets
            self.awaitingReview = awaitingReview
            self.reviewedRelevant = reviewedRelevant
            self.counts = counts
            self.source = source
            self.requestEndpoint = requestEndpoint
            self.packetEndpoint = packetEndpoint
            self.emptyReason = emptyReason
        }

        struct Counts: Decodable, Hashable {
            let activeRequests: Int
            let activePackets: Int
            let awaitingReview: Int
            let reviewedRelevant: Int

            enum CodingKeys: String, CodingKey {
                case activeRequests = "active_requests"
                case activePackets = "active_packets"
                case awaitingReview = "awaiting_review"
                case reviewedRelevant = "reviewed_relevant"
            }

            init(activeRequests: Int = 0, activePackets: Int = 0, awaitingReview: Int = 0, reviewedRelevant: Int = 0) {
                self.activeRequests = activeRequests
                self.activePackets = activePackets
                self.awaitingReview = awaitingReview
                self.reviewedRelevant = reviewedRelevant
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                activeRequests = try container.decodeIfPresent(Int.self, forKey: .activeRequests) ?? 0
                activePackets = try container.decodeIfPresent(Int.self, forKey: .activePackets) ?? 0
                awaitingReview = try container.decodeIfPresent(Int.self, forKey: .awaitingReview) ?? 0
                reviewedRelevant = try container.decodeIfPresent(Int.self, forKey: .reviewedRelevant) ?? 0
            }
        }
    }

    struct Feedback: Decodable, Hashable {
        let endpoint: String?
        let status: String?
        let snapshotPolicy: String?
        let ratings: [String]

        enum CodingKeys: String, CodingKey {
            case endpoint, status, ratings
            case snapshotPolicy = "snapshot_policy"
        }

        init(endpoint: String? = nil, status: String? = nil, snapshotPolicy: String? = nil, ratings: [String] = []) {
            self.endpoint = endpoint
            self.status = status
            self.snapshotPolicy = snapshotPolicy
            self.ratings = ratings
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
            status = try c.decodeIfPresent(String.self, forKey: .status)
            snapshotPolicy = try c.decodeIfPresent(String.self, forKey: .snapshotPolicy)
            ratings = try c.decodeIfPresent([String].self, forKey: .ratings) ?? []
        }
    }

    struct LibraryDoc: Decodable, Hashable, Identifiable {
        var id: String { key }
        let key: String
        let path: String?
        let exists: Bool
        let safeToPreview: Bool?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case key, path, exists, reason
            case safeToPreview = "safe_to_preview"
        }

        init(key: String = "", path: String? = nil, exists: Bool = false, safeToPreview: Bool? = nil, reason: String? = nil) {
            self.key = key
            self.path = path
            self.exists = exists
            self.safeToPreview = safeToPreview
            self.reason = reason
        }
    }

    struct Library: Decodable, Hashable {
        let label: String?
        let documents: [LibraryDoc]
        let doctrineBundle: String?
        let source: String?

        enum CodingKeys: String, CodingKey {
            case label, documents, source
            case doctrineBundle = "doctrine_bundle"
        }

        init(label: String? = nil, documents: [LibraryDoc] = [], doctrineBundle: String? = nil, source: String? = nil) {
            self.label = label
            self.documents = documents
            self.doctrineBundle = doctrineBundle
            self.source = source
        }
    }

    struct EscalationAction: Decodable, Hashable, Identifiable {
        var id: String { label }
        let label: String
        let endpoint: String?
        let mode: String?

        init(label: String = "", endpoint: String? = nil, mode: String? = nil) {
            self.label = label
            self.endpoint = endpoint
            self.mode = mode
        }
    }

    struct Escalation: Decodable, Hashable {
        let actions: [EscalationAction]
        let mode: String?

        init(actions: [EscalationAction] = [], mode: String? = nil) {
            self.actions = actions
            self.mode = mode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try container.decodeIfPresent(String.self, forKey: .mode)
            // Handle both legacy [String] and new [{label,endpoint,mode}] formats
            if let structured = try? container.decodeIfPresent([EscalationAction].self, forKey: .actions) {
                actions = structured ?? []
            } else if let strings = try? container.decodeIfPresent([String].self, forKey: .actions) {
                actions = (strings ?? []).map { EscalationAction(label: $0, endpoint: nil, mode: nil) }
            } else {
                actions = []
            }
        }

        enum CodingKeys: String, CodingKey {
            case actions, mode
        }
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

// MARK: - Lead Plate

enum LeadPlateJSONValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: LeadPlateJSONValue])
    case array([LeadPlateJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: LeadPlateJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([LeadPlateJSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var compactDescription: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object(let value):
            let pairs = value.sorted(by: { $0.key < $1.key }).prefix(4).map { key, item in
                "\(key.displayLabel): \(item.scalarDescription)"
            }
            return pairs.isEmpty ? "object" : pairs.joined(separator: " · ")
        case .array(let value):
            let items = value.prefix(4).map(\.scalarDescription)
            return items.isEmpty ? "[]" : items.joined(separator: " · ")
        case .null:
            return "null"
        }
    }

    var scalarDescription: String {
        switch self {
        case .object(let value):
            return value["title"]?.scalarDescription
                ?? value["ticket_id"]?.scalarDescription
                ?? value["id"]?.scalarDescription
                ?? "object"
        case .array(let value):
            return "\(value.count) items"
        default:
            return compactDescription
        }
    }

    subscript(key: String) -> LeadPlateJSONValue? {
        if case .object(let value) = self {
            return value[key]
        }
        return nil
    }
}

struct LeadPlateReadDTO: Decodable {
    let lead: LeadPlateLeadDTO
    let summary: LeadPlateSummaryDTO
    let reports: [LeadPlateReportRowDTO]
    let decisionQueue: [LeadPlateDecisionTicketDTO]
    let source: LeadPlateSourceDTO

    enum CodingKeys: String, CodingKey {
        case lead, summary, reports, source
        case decisionQueue = "decision_queue"
    }
}

struct LeadPlateLeadDTO: Decodable {
    let leadId: String
    let leadName: String
    let ownedBoards: [LeadPlateBoardRefDTO]
    let ownedProjects: [[String: LeadPlateJSONValue]]
    let activeReportCount: Int

    enum CodingKeys: String, CodingKey {
        case leadId = "lead_id"
        case leadName = "lead_name"
        case ownedBoards = "owned_boards"
        case ownedProjects = "owned_projects"
        case activeReportCount = "active_report_count"
    }
}

struct LeadPlateBoardRefDTO: Decodable, Hashable, Identifiable {
    let boardId: String
    let boardName: String?

    var id: String { boardId }
    var displayName: String { boardName?.nilIfBlank ?? boardId }

    enum CodingKeys: String, CodingKey {
        case boardId = "board_id"
        case boardName = "board_name"
        case id
        case name
        case title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boardId = try container.decodeIfPresent(String.self, forKey: .boardId)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? "unknown-board"
        boardName = try container.decodeIfPresent(String.self, forKey: .boardName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .title)
    }
}

struct LeadPlateSummaryDTO: Decodable {
    let idle: Int
    let blocked: Int
    let decisionQueue: Int
    let staleClaim: Int
    let pressureStates: [String: Int]

    enum CodingKeys: String, CodingKey {
        case idle, blocked
        case decisionQueue = "decision_queue"
        case staleClaim = "stale_claim"
        case pressureStates = "pressure_states"
    }
}

struct LeadPlateReportRowDTO: Decodable, Identifiable {
    let agentId: String
    let agentName: String
    let boardRefs: [LeadPlateBoardRefDTO]
    let counts: LeadPlateCountsDTO
    let pressureState: String
    let pressureReasons: [[String: LeadPlateJSONValue]]
    let timeLedger: [String: LeadPlateJSONValue]
    let drilldownTicketRefs: [[String: LeadPlateJSONValue]]

    var id: String { agentId }

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case agentName = "agent_name"
        case boardRefs = "board_refs"
        case counts
        case pressureState = "pressure_state"
        case pressureReasons = "pressure_reasons"
        case timeLedger = "time_ledger"
        case drilldownTicketRefs = "drilldown_ticket_refs"
    }
}

struct LeadPlateCountsDTO: Decodable {
    let open: Int
    let claimed: Int
    let inProgress: Int
    let blocked: Int
    let staleClaim: Int
    let idle: Int
    let decisionQueue: Int
    let totalOpenWorkload: Int

    enum CodingKeys: String, CodingKey {
        case open, claimed, blocked, idle
        case inProgress = "in_progress"
        case staleClaim = "stale_claim"
        case decisionQueue = "decision_queue"
        case totalOpenWorkload = "total_open_workload"
    }
}

struct LeadPlateDecisionTicketDTO: Decodable, Identifiable {
    let ticketId: String
    let title: String
    let agentId: String?
    let agentName: String?
    let status: String
    let approvalState: String
    let boardId: String?
    let priority: String?
    let updatedAt: String?

    var id: String { ticketId }

    enum CodingKeys: String, CodingKey {
        case title, status, priority
        case ticketId = "ticket_id"
        case agentId = "agent_id"
        case agentName = "agent_name"
        case approvalState = "approval_state"
        case boardId = "board_id"
        case updatedAt = "updated_at"
    }
}

struct LeadPlateSourceDTO: Decodable {
    let sources: [String]
    let provenance: [String: LeadPlateJSONValue]
    let gaps: [[String: LeadPlateJSONValue]]
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var displayLabel: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
