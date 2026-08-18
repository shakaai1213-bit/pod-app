import Foundation

public enum OrcaJSONValue: Codable, Equatable, Sendable {
    case object([String: OrcaJSONValue])
    case array([OrcaJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: OrcaJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([OrcaJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            throw DecodingError.typeMismatch(
                OrcaJSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported ORCA JSON value"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct OrcaEngineeringRoot: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let description: String
    public let access: String
    public let sourceMutation: Bool

    enum CodingKeys: String, CodingKey {
        case id, label, description, access
        case sourceMutation = "source_mutation"
    }
}

public struct OrcaEngineeringAction: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let kind: String
    public let requiresApproval: Bool
    public let mutatesSource: Bool
    public let defaultTimeoutSeconds: Int
    public let allowedRootIDs: [String]
    public let available: Bool
    public let blockedReasons: [String]

    enum CodingKeys: String, CodingKey {
        case id, label, kind, available
        case requiresApproval = "requires_approval"
        case mutatesSource = "mutates_source"
        case defaultTimeoutSeconds = "default_timeout_seconds"
        case allowedRootIDs = "allowed_root_ids"
        case blockedReasons = "blocked_reasons"
    }
}

public struct OrcaEngineeringHostStatus: Codable, Equatable, Sendable {
    public let hostID: String
    public let capabilityID: String
    public let state: String
    public let ready: Bool
    public let reason: String
    public let observedAt: String?
    public let expiresAt: String?
    public let evidenceRefs: [String]
    public let policySHA256: String

    enum CodingKeys: String, CodingKey {
        case state, ready, reason
        case hostID = "host_id"
        case capabilityID = "capability_id"
        case observedAt = "observed_at"
        case expiresAt = "expires_at"
        case evidenceRefs = "evidence_refs"
        case policySHA256 = "policy_sha256"
    }
}

public struct OrcaEngineeringWorkbenchContract: Codable, Equatable, Sendable {
    public let schema: String
    public let enabled: Bool
    public let mode: String
    public let host: OrcaEngineeringHostStatus
    public let workerLane: String
    public let policySHA256: String
    public let roots: [OrcaEngineeringRoot]
    public let actions: [OrcaEngineeringAction]
    public let lifecycle: [String]
    public let guarantees: [String]

    enum CodingKeys: String, CodingKey {
        case schema, enabled, mode, host, roots, actions, lifecycle, guarantees
        case workerLane = "worker_lane"
        case policySHA256 = "policy_sha256"
    }
}

public struct OrcaEngineeringOperationCreate: Codable, Equatable, Sendable {
    public let agentSlug: String
    public let actionID: String
    public let rootID: String
    public let relativePath: String
    public let searchQuery: String?
    public let arguments: [String]
    public let patch: String?
    public let timeoutSeconds: Int?
    public let parentRunID: String?
    public let conversationID: String?
    public let turnID: String?
    public let idempotencyKey: String
    public let source: String

    public init(
        agentSlug: String,
        actionID: String,
        rootID: String,
        relativePath: String = ".",
        searchQuery: String? = nil,
        arguments: [String] = [],
        patch: String? = nil,
        timeoutSeconds: Int? = nil,
        parentRunID: String? = nil,
        conversationID: String? = nil,
        turnID: String? = nil,
        idempotencyKey: String,
        source: String = "orca.console.engineering"
    ) {
        self.agentSlug = agentSlug
        self.actionID = actionID
        self.rootID = rootID
        self.relativePath = relativePath
        self.searchQuery = searchQuery
        self.arguments = arguments
        self.patch = patch
        self.timeoutSeconds = timeoutSeconds
        self.parentRunID = parentRunID
        self.conversationID = conversationID
        self.turnID = turnID
        self.idempotencyKey = idempotencyKey
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case arguments, patch, source
        case agentSlug = "agent_slug"
        case actionID = "action_id"
        case rootID = "root_id"
        case relativePath = "relative_path"
        case searchQuery = "search_query"
        case timeoutSeconds = "timeout_seconds"
        case parentRunID = "parent_run_id"
        case conversationID = "conversation_id"
        case turnID = "turn_id"
        case idempotencyKey = "idempotency_key"
    }
}

public struct OrcaEngineeringOperation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let ticketID: String
    public let parentRunID: String?
    public let traceID: String
    public let status: String
    public let actionID: String
    public let actionKind: String
    public let rootID: String
    public let relativePath: String
    public let workerLane: String
    public let agentSlug: String
    public let requiresApproval: Bool
    public let approvalID: String?
    public let approvalStatus: String?
    public let idempotencyKey: String
    public let outcome: String?
    public let evidence: String?
    public let artifacts: OrcaJSONValue?
    public let error: String?
    public let createdAt: String
    public let updatedAt: String
    public let startedAt: String?
    public let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, outcome, evidence, artifacts, error
        case ticketID = "ticket_id"
        case parentRunID = "parent_run_id"
        case traceID = "trace_id"
        case actionID = "action_id"
        case actionKind = "action_kind"
        case rootID = "root_id"
        case relativePath = "relative_path"
        case workerLane = "worker_lane"
        case agentSlug = "agent_slug"
        case requiresApproval = "requires_approval"
        case approvalID = "approval_id"
        case approvalStatus = "approval_status"
        case idempotencyKey = "idempotency_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

public struct OrcaEngineeringOperationCreateResult: Codable, Equatable, Sendable {
    public let created: Bool
    public let operation: OrcaEngineeringOperation
    public let host: OrcaEngineeringHostStatus
    public let message: String
}

public struct OrcaEngineeringWorkbenchSession: Codable, Equatable, Sendable {
    public let schema: String
    public let ticketID: String
    public let ticketTitle: String
    public let ticketStatus: String
    public let contract: OrcaEngineeringWorkbenchContract
    public let operations: [OrcaEngineeringOperation]
    public let counts: [String: Int]
    public let sources: [String]

    enum CodingKeys: String, CodingKey {
        case schema, contract, operations, counts, sources
        case ticketID = "ticket_id"
        case ticketTitle = "ticket_title"
        case ticketStatus = "ticket_status"
    }
}

public struct OrcaEngineeringApprovalDecision: Codable, Equatable, Sendable {
    public let decision: String
    public let note: String

    public init(decision: String, note: String) {
        self.decision = decision
        self.note = note
    }
}
