import Foundation

/// The canonical ticket feed. Header declarations are never used as author identity.
public struct OrcaTicketEntry: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let ticketID: String
    public let kind: String
    public let actorType: String
    public let actorAgentID: String?
    public let actorUserID: String?
    public let author: String
    public let credentialClass: String
    public let message: String
    public let model: String
    public let modelVerified: Bool
    public let approvalAuthority: Bool
    public let generation: Int
    public let createdAt: String
    public let correctsEventID: String?
    public let requestEntryID: String?
    public let details: Details

    public struct Details: Decodable, Equatable, Sendable {
        public let onBehalfOf: String?
        public let recipientAgentID: String?
        public let handoffEntryID: String?
        public let completed: String?
        public let remaining: String?
        public let definitionOfDone: String?
        public let verdict: String?
        public let prRef: String?
        public let headSHA: String?
        public let testsSummary: String?
        public let mutationSummary: String?
        public let evidence: [String]?
        public let targetStatus: String?
        public let approvalID: String?
        enum CodingKeys: String, CodingKey {
            case onBehalfOf = "on_behalf_of"
            case recipientAgentID = "recipient_agent_id", handoffEntryID = "handoff_entry_id"
            case completed, remaining, definitionOfDone = "definition_of_done", verdict
            case prRef = "pr_ref", headSHA = "head_sha", testsSummary = "tests_summary"
            case mutationSummary = "mutation_summary", evidence, targetStatus = "target_status", approvalID = "approval_id"
        }
    }
    enum CodingKeys: String, CodingKey {
        case id, ticketID = "ticket_id", kind, actorType = "actor_type", actorAgentID = "actor_agent_id"
        case actorUserID = "actor_user_id", author, credentialClass = "credential_class", message, model
        case modelVerified = "model_verified", approvalAuthority = "approval_authority", generation
        case createdAt = "created_at", correctsEventID = "corrects_event_id", requestEntryID = "request_entry_id", details
    }
    public var authorLabel: String {
        credentialClass == "legacy_unknown" ? "Unknown legacy author" : credentialClass == "fleet_bearer" ? "Fleet service" : author
    }
    public var modelLabel: String { modelVerified ? model : "Model unverified" }
    public var kindLabel: String { kind.replacingOccurrences(of: "_", with: " ").capitalized }
}

public struct OrcaTicketOwnership: Decodable, Equatable, Sendable {
    public let ticketID: String
    public let ownerAgentID: String?
    public let ownerUserID: String?
    public let generation: Int
    public let handoffEntryID: String?
    public let awaitingAcknowledgement: Bool
    public let acknowledgedAt: String?
    public let dueAt: String?
    public let overdue: Bool
    public let previousOwnerAgentID: String?
    enum CodingKeys: String, CodingKey {
        case ticketID = "ticket_id", ownerAgentID = "owner_agent_id", ownerUserID = "owner_user_id", generation
        case handoffEntryID = "handoff_entry_id", awaitingAcknowledgement = "awaiting_acknowledgement"
        case acknowledgedAt = "acknowledged_at", dueAt = "due_at", overdue, previousOwnerAgentID = "previous_owner_agent_id"
    }
}

public struct OrcaTicketEntryPermissions: Decodable, Equatable, Sendable {
    public let canClaim: Bool
    public let canComment: Bool
    public let canReview: Bool
    public let canHandoff: Bool
    public let canChangeStatus: Bool
    public let canAcknowledge: Bool
    enum CodingKeys: String, CodingKey {
        case canClaim = "can_claim"
        case canComment = "can_comment", canReview = "can_review", canHandoff = "can_handoff"
        case canChangeStatus = "can_change_status", canAcknowledge = "can_acknowledge"
    }
}

public struct OrcaTicketTimelinePage: Decodable, Equatable, Sendable {
    public let approvalRecords: [OrcaTicketApprovalRecord]
    public let items: [OrcaTicketEntry]
    public let legacyItems: [OrcaTicketEntry]
    public let ownership: OrcaTicketOwnership
    public let permissions: OrcaTicketEntryPermissions
    public let nextBeforeGeneration: Int?
    public let nextLegacyBeforeAt: String?
    public let nextLegacyBeforeID: String?
    enum CodingKeys: String, CodingKey {
        case approvalRecords = "approval_records"
        case items, legacyItems = "legacy_items", ownership, permissions
        case nextBeforeGeneration = "next_before_generation", nextLegacyBeforeAt = "next_legacy_before_at"
        case nextLegacyBeforeID = "next_legacy_before_id"
    }
    public var entries: [OrcaTicketEntry] {
        (items + legacyItems).sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }
}

public struct OrcaTicketEntryInput: Encodable, Sendable {
    public var kind: String
    public var message: String
    public var idempotencyKey: UUID
    public var expectedGeneration: Int
    public var onBehalfOf: String?
    public var correctsEventID: UUID?
    public var recipientAgentID: UUID?
    public var handoffEntryID: UUID?
    public var completed: String?
    public var remaining: String?
    public var definitionOfDone: String?
    public var verdict: String?
    public var prRef: String?
    public var headSHA: String?
    public var testsSummary: String?
    public var mutationSummary: String?
    public var evidence: [String]?
    public var targetStatus: String?
    public init(kind: String, message: String, idempotencyKey: UUID, expectedGeneration: Int) {
        self.kind = kind; self.message = message; self.idempotencyKey = idempotencyKey; self.expectedGeneration = expectedGeneration
    }
    enum CodingKeys: String, CodingKey {
        case kind, message, idempotencyKey = "idempotency_key", expectedGeneration = "expected_generation"
        case onBehalfOf = "on_behalf_of"
        case correctsEventID = "corrects_event_id", recipientAgentID = "recipient_agent_id", handoffEntryID = "handoff_entry_id"
        case completed, remaining, definitionOfDone = "definition_of_done", verdict, prRef = "pr_ref", headSHA = "head_sha"
        case testsSummary = "tests_summary", mutationSummary = "mutation_summary", evidence, targetStatus = "target_status"
    }
}
public struct OrcaTicketEntryWriteResponse: Decodable, Sendable {
    public let entry: OrcaTicketEntry
    public let ownership: OrcaTicketOwnership
    public let replayed: Bool
}
public struct OrcaTicketRecipient: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}

public struct OrcaTicketTimelineCursor: Sendable {
    public let generation: Int?
    public let legacyAt: String?
    public let legacyID: String?
    public init(page: OrcaTicketTimelinePage) {
        generation = page.nextBeforeGeneration; legacyAt = page.nextLegacyBeforeAt; legacyID = page.nextLegacyBeforeID
    }
    public var hasMore: Bool { generation != nil || legacyID != nil }
    public static func path(ticketID: String, cursor: Self? = nil) -> String? {
        guard let id = UUID(uuidString: ticketID) else { return nil }
        var parts = URLComponents(); parts.path = "/api/v1/tickets/\(id.uuidString.lowercased())/entries"
        if let cursor {
            var values: [URLQueryItem] = [
                .init(name: "include_typed", value: cursor.generation == nil ? "false" : "true"),
                .init(name: "include_legacy", value: cursor.legacyID == nil ? "false" : "true")]
            if let generation = cursor.generation { values.append(.init(name: "before_generation", value: String(generation))) }
            if let at = cursor.legacyAt, let id = cursor.legacyID {
                values.append(.init(name: "legacy_before_at", value: at)); values.append(.init(name: "legacy_before_id", value: id))
            }
            parts.queryItems = values
        }
        return parts.string
    }
}
public extension OrcaTicketTimelinePage {
    func belongs(to ticketID: String) -> Bool {
        ownership.ticketID.lowercased() == ticketID.lowercased() && entries.allSatisfy { $0.ticketID.lowercased() == ticketID.lowercased() }
    }
}

public struct OrcaTicketApprovalRecord: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let ticketID: String
    public let status: String
    public let actionType: String
    public let declaredDecider: String?
    public let signedRecordState: String
    public let modelVerified: Bool
    public let approvalAuthority: Bool
    public let createdAt: String
    public let pointer: String
    enum CodingKeys: String, CodingKey {
        case id, ticketID = "ticket_id", status, actionType = "action_type", declaredDecider = "declared_decider"
        case signedRecordState = "signed_record_state", modelVerified = "model_verified"
        case approvalAuthority = "approval_authority", createdAt = "created_at", pointer
    }
}

/// Known rejections are distinct from transport failures whose commit is unknown.
public enum OrcaTicketTimelineError: Error, Sendable {
    case conflict, accessDenied, notActivated, invalidResponse
    public static func rejection(status: Int) -> Self? {
        switch status { case 409: .conflict; case 401, 403: .accessDenied; case 503: .notActivated; default: nil }
    }
}
