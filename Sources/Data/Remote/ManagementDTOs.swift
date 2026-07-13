import Foundation

struct ManagementSourceStateDTO: Decodable, Hashable {
    let state: String
    let detail: String
    let refs: [String]
}

struct ManagementEvidenceRefDTO: Decodable, Hashable {
    let kind: String
    let ref: String
    let occurredAt: Date?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case kind, ref, source
        case occurredAt = "occurred_at"
    }
}

struct ManagementBoardDirectoryDTO: Decodable, Identifiable, Hashable {
    let id: UUID
    let slug: String
    let name: String
}

struct ManagementBoardDirectoryResponseDTO: Decodable {
    let items: [ManagementBoardDirectoryDTO]

    init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            var result: [ManagementBoardDirectoryDTO] = []
            while !container.isAtEnd {
                result.append(try container.decode(ManagementBoardDirectoryDTO.self))
            }
            items = result
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([ManagementBoardDirectoryDTO].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey { case items }
}

struct BoardPlanPinDTO: Decodable, Identifiable, Hashable {
    let id: UUID
    let boardId: UUID
    let objectType: String
    let objectId: UUID
    let rank: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, rank
        case boardId = "board_id"
        case objectType = "object_type"
        case objectId = "object_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct BoardPlanPinRequestDTO: Encodable {
    let objectType: String
    let objectId: UUID
    let rank: Int
}

struct BoardPlanCardDTO: Decodable, Identifiable, Hashable {
    let id: String
    let objectType: String
    let objectId: UUID
    let title: String
    let subtitle: String?
    let column: String
    let canonicalState: String
    let priority: String?
    let ownerAgentId: UUID?
    let ownerName: String?
    let waitReason: String?
    let waitKind: String?
    let pinned: Bool
    let rank: Int
    let latestEvidence: ManagementEvidenceRefDTO?
    let evidenceState: String
    let projectIds: [UUID]
    let runIds: [UUID]
    let canonicalRef: String

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, column, priority, pinned, rank
        case objectType = "object_type"
        case objectId = "object_id"
        case canonicalState = "canonical_state"
        case ownerAgentId = "owner_agent_id"
        case ownerName = "owner_name"
        case waitReason = "wait_reason"
        case waitKind = "wait_kind"
        case latestEvidence = "latest_evidence"
        case evidenceState = "evidence_state"
        case projectIds = "project_ids"
        case runIds = "run_ids"
        case canonicalRef = "canonical_ref"
    }
}

struct BoardPlanLaneDTO: Decodable, Identifiable, Hashable {
    let key: String
    let title: String
    let cards: [BoardPlanCardDTO]
    var id: String { key }
}

struct BoardPlanResponseDTO: Decodable, Hashable {
    let computedAt: Date
    let boardId: UUID
    let boardName: String
    let boardSlug: String
    let selectionMode: String
    let pins: [BoardPlanPinDTO]
    let lanes: [BoardPlanLaneDTO]
    let counts: [String: Int]
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case pins, lanes, counts
        case computedAt = "computed_at"
        case boardId = "board_id"
        case boardName = "board_name"
        case boardSlug = "board_slug"
        case selectionMode = "selection_mode"
        case sourceRefs = "source_refs"
    }
}

struct AgentFocusItemDTO: Decodable, Identifiable, Hashable {
    let title: String
    let objectType: String
    let objectId: String
    let state: String
    let evidenceRef: String?
    var id: String { "\(objectType):\(objectId)" }

    enum CodingKeys: String, CodingKey {
        case title, state
        case objectType = "object_type"
        case objectId = "object_id"
        case evidenceRef = "evidence_ref"
    }
}

struct AgentFocusDTO: Decodable, Hashable {
    let objective: String?
    let items: [AgentFocusItemDTO]
    let stretch: [String]
    let roadmap: [String: String]
    let source: ManagementSourceStateDTO
}

struct AgentLoadDTO: Decodable, Hashable {
    let activeTickets: Int
    let activeTasks: Int
    let plannerItems: Int
    let activeRuns: Int
    let blocked: Int
    let stale: Int
    let capacity: Int?
    let capacityUnits: Int?
    let pressurePct: Double?
    let status: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case blocked, stale, capacity, status, reason
        case activeTickets = "active_tickets"
        case activeTasks = "active_tasks"
        case plannerItems = "planner_items"
        case activeRuns = "active_runs"
        case capacityUnits = "capacity_units"
        case pressurePct = "pressure_pct"
    }
}

struct AgentPlanItemDTO: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let lane: String
    let status: String
    let plannedFor: String?
    let sourceRef: String?

    enum CodingKeys: String, CodingKey {
        case id, title, lane, status
        case plannedFor = "planned_for"
        case sourceRef = "source_ref"
    }
}

struct AgentPlanDTO: Decodable, Hashable {
    let items: [AgentPlanItemDTO]
    let nextCommitment: String?
    let source: ManagementSourceStateDTO

    enum CodingKeys: String, CodingKey {
        case items, source
        case nextCommitment = "next_commitment"
    }
}

struct AgentDispatchItemDTO: Decodable, Identifiable, Hashable {
    let id: UUID
    let state: String
    let runType: String
    let provider: String?
    let host: String?
    let elapsedSeconds: Int?
    let ticketId: UUID?
    let evidenceRef: String?

    enum CodingKeys: String, CodingKey {
        case id, state, provider, host
        case runType = "run_type"
        case elapsedSeconds = "elapsed_seconds"
        case ticketId = "ticket_id"
        case evidenceRef = "evidence_ref"
    }
}

struct AgentDispatchDTO: Decodable, Hashable {
    let items: [AgentDispatchItemDTO]
    let source: ManagementSourceStateDTO
}

struct ThemeAlignmentDTO: Decodable, Hashable {
    let themes: [String]
    let numerator: Int
    let denominator: Int
    let unclassified: Int
    let ratioPct: Double?
    let state: String
    let detail: String
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case themes, numerator, denominator, unclassified, state, detail
        case ratioPct = "ratio_pct"
        case sourceRefs = "source_refs"
    }
}

struct AgentManagementCardDTO: Decodable, Identifiable, Hashable {
    let agentId: UUID?
    let agentName: String
    let displayName: String
    let title: String?
    let lifecycleStatus: String
    let wakeStatus: String
    let wakeAt: Date?
    let provider: String?
    let runtimeHost: String?
    let latestEvidenceAt: Date?
    let latestEvidenceRef: String?
    let focus: AgentFocusDTO
    let load: AgentLoadDTO
    let plan: AgentPlanDTO
    let dispatch: AgentDispatchDTO
    let theme: ThemeAlignmentDTO
    var id: String { agentName }

    enum CodingKeys: String, CodingKey {
        case title, provider, focus, load, plan, dispatch, theme
        case agentId = "agent_id"
        case agentName = "agent_name"
        case displayName = "display_name"
        case lifecycleStatus = "lifecycle_status"
        case wakeStatus = "wake_status"
        case wakeAt = "wake_at"
        case runtimeHost = "runtime_host"
        case latestEvidenceAt = "latest_evidence_at"
        case latestEvidenceRef = "latest_evidence_ref"
    }
}

struct AgentManagementResponseDTO: Decodable, Hashable {
    let computedAt: Date
    let agents: [AgentManagementCardDTO]
    let completeCount: Int
    let unknownCount: Int

    enum CodingKeys: String, CodingKey {
        case agents
        case computedAt = "computed_at"
        case completeCount = "complete_count"
        case unknownCount = "unknown_count"
    }
}

struct ProjectMilestoneManagementDTO: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let state: String
    let ownerAgentId: UUID?
    let ownerName: String?
    let waitReason: String?
    let dependencyIds: [String]?
    let acceptanceCriteria: [String]
    let linkedTicketIds: [UUID]
    let linkedTaskIds: [UUID]
    let linkedRunIds: [UUID]
    let evidenceRefs: [ManagementEvidenceRefDTO]
    let latestEvidenceAt: Date?
    let evidenceState: String
    let completionCredit: Double

    enum CodingKeys: String, CodingKey {
        case id, title, state
        case ownerAgentId = "owner_agent_id"
        case ownerName = "owner_name"
        case waitReason = "wait_reason"
        case dependencyIds = "dependency_ids"
        case acceptanceCriteria = "acceptance_criteria"
        case linkedTicketIds = "linked_ticket_ids"
        case linkedTaskIds = "linked_task_ids"
        case linkedRunIds = "linked_run_ids"
        case evidenceRefs = "evidence_refs"
        case latestEvidenceAt = "latest_evidence_at"
        case evidenceState = "evidence_state"
        case completionCredit = "completion_credit"
    }
}

struct ProjectCommandRoomResponseDTO: Decodable, Hashable {
    let computedAt: Date
    let projectId: UUID
    let name: String
    let status: String
    let stage: String
    let boardIds: [UUID]
    let milestones: [ProjectMilestoneManagementDTO]
    let completionPct: Double?
    let completionState: String
    let latestEvidenceAt: Date?
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case name, status, stage, milestones
        case computedAt = "computed_at"
        case projectId = "project_id"
        case boardIds = "board_ids"
        case completionPct = "completion_pct"
        case completionState = "completion_state"
        case latestEvidenceAt = "latest_evidence_at"
        case sourceRefs = "source_refs"
    }
}

struct LoopGaugeCellDTO: Decodable, Identifiable, Hashable {
    let key: String
    let title: String
    let status: String
    let value: Double
    let unit: String
    let freshnessAt: Date
    let cause: String
    let sourceRef: String
    let drillRef: String
    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, title, status, value, unit, cause
        case freshnessAt = "freshness_at"
        case sourceRef = "source_ref"
        case drillRef = "drill_ref"
    }
}

struct LoopAtlasLaneDTO: Decodable, Identifiable, Hashable {
    let key: String
    let title: String
    let status: String
    let count: Int
    let freshnessAt: Date
    let cause: String
    let drillRefs: [String]
    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, title, status, count, cause
        case freshnessAt = "freshness_at"
        case drillRefs = "drill_refs"
    }
}

struct CaptainDecisionDTO: Decodable, Identifiable, Hashable {
    let id: UUID
    let objectType: String
    let title: String
    let reason: String
    let ownerName: String?
    let waitingSince: Date
    let canonicalRef: String

    enum CodingKeys: String, CodingKey {
        case id, title, reason
        case objectType = "object_type"
        case ownerName = "owner_name"
        case waitingSince = "waiting_since"
        case canonicalRef = "canonical_ref"
    }
}

struct LoopAtlasResponseDTO: Decodable, Hashable {
    let computedAt: Date
    let gauge: [LoopGaugeCellDTO]
    let lanes: [LoopAtlasLaneDTO]
    let captainQueue: [CaptainDecisionDTO]
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case gauge, lanes
        case computedAt = "computed_at"
        case captainQueue = "captain_queue"
        case sourceRefs = "source_refs"
    }
}
