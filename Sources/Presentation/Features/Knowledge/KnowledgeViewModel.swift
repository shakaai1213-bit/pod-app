import Foundation
import os.log

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
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
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct WikiDocument: Identifiable, Codable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let title: String
    let section: String
    let sizeBytes: Int
    let updatedAt: Date
    let content: String?

    enum CodingKeys: String, CodingKey {
        case path, title, section, content
        case sizeBytes = "size_bytes"
        case updatedAt = "updated_at"
    }
}

struct DocRegistryItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let source: String
    let path: String
    let title: String
    let kind: String
    let owner: String?
    let sizeBytes: Int
    let updatedAt: Date
    let chromaStatus: String
    let chromaUpdatedAt: Date?
    let doctrineStatus: String?
    let requiredForAgents: [String]?
    let enforcedByPetal: String?
    let canonicalRef: String?
    let doctrineNote: String?

    enum CodingKeys: String, CodingKey {
        case id, source, path, title, kind, owner
        case sizeBytes = "size_bytes"
        case updatedAt = "updated_at"
        case chromaStatus = "chroma_status"
        case chromaUpdatedAt = "chroma_updated_at"
        case doctrineStatus = "doctrine_status"
        case requiredForAgents = "required_for_agents"
        case enforcedByPetal = "enforced_by_petal"
        case canonicalRef = "canonical_ref"
        case doctrineNote = "doctrine_note"
    }
}

struct DocRegistrySummary: Codable, Hashable, Sendable {
    let total: Int
    let bySource: [String: Int]
    let byKind: [String: Int]
    let byChromaStatus: [String: Int]
    let byDoctrineStatus: [String: Int]?
    let requiredCount: Int?

    enum CodingKeys: String, CodingKey {
        case total
        case bySource = "by_source"
        case byKind = "by_kind"
        case byChromaStatus = "by_chroma_status"
        case byDoctrineStatus = "by_doctrine_status"
        case requiredCount = "required_count"
    }
}

struct DocRegistryResponse: Codable, Hashable, Sendable {
    let summary: DocRegistrySummary
    let items: [DocRegistryItem]
}

struct DoctrineBundleSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let owner: String
    let purpose: String
    let requiredForAgents: [String]
    let requiredCount: Int
    let presentCount: Int
    let gapCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, owner, purpose
        case requiredForAgents = "required_for_agents"
        case requiredCount = "required_count"
        case presentCount = "present_count"
        case gapCount = "gap_count"
    }
}

struct DoctrineBundleListResponse: Codable, Hashable, Sendable {
    let total: Int
    let items: [DoctrineBundleSummary]
}

struct DoctrineBundleDetail: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let owner: String
    let description: String
    let requiredDocs: [DocRegistryItem]
    let gaps: [String]
    let summary: DocRegistrySummary

    enum CodingKeys: String, CodingKey {
        case id, title, owner, description, gaps, summary
        case requiredDocs = "required_docs"
    }
}

struct DoctrineReviewQueueResponse: Codable, Hashable, Sendable {
    let summary: DocRegistrySummary
    let items: [DocRegistryItem]
    let reviewers: [String]
    let releaseGate: String?

    enum CodingKeys: String, CodingKey {
        case summary, items, reviewers
        case releaseGate = "release_gate"
    }
}

enum DoctrineReviewAction: String, Codable, CaseIterable, Hashable, Sendable {
    case promoteToCanonical = "promote_to_canonical"
    case markDraft = "mark_draft"
    case markSuperseded = "mark_superseded"
    case markArchived = "mark_archived"
    case keepQuarantined = "keep_quarantined"

    var title: String {
        switch self {
        case .promoteToCanonical: return "Canonical"
        case .markDraft: return "Draft"
        case .markSuperseded: return "Superseded"
        case .markArchived: return "Archive"
        case .keepQuarantined: return "Keep"
        }
    }
}

struct DoctrineReviewActionRequest: Codable, Sendable {
    let docId: String
    let action: DoctrineReviewAction
    let reviewer: String
    let note: String?
    let requiredForAgents: [String]?
    let enforcedByPetal: String?

    enum CodingKeys: String, CodingKey {
        case docId = "doc_id"
        case action, reviewer, note
        case requiredForAgents = "required_for_agents"
        case enforcedByPetal = "enforced_by_petal"
    }
}

struct DoctrineReviewActionResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let reviewId: String
    let doc: DocRegistryItem
    let action: DoctrineReviewAction
    let doctrineStatus: String
    let auditPath: String

    enum CodingKeys: String, CodingKey {
        case ok, doc, action
        case reviewId = "review_id"
        case doctrineStatus = "doctrine_status"
        case auditPath = "audit_path"
    }
}

struct DoctrineReviewSyncItem: Codable, Hashable, Sendable {
    let docId: String
    let status: String
    let reviewedBy: String?
    let reviewedAt: String?
    let reviewId: String?
    let action: String?
    let note: String?
    let requiredForAgents: [String]
    let enforcedByPetal: String?
    let doc: DocRegistryItem?

    enum CodingKeys: String, CodingKey {
        case docId = "doc_id"
        case status
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case reviewId = "review_id"
        case action, note
        case requiredForAgents = "required_for_agents"
        case enforcedByPetal = "enforced_by_petal"
        case doc
    }
}

struct DoctrineReviewSyncPreviewResponse: Codable, Hashable, Sendable {
    let total: Int
    let byStatus: [String: Int]
    let items: [DoctrineReviewSyncItem]
    let overlayPath: String
    let auditPath: String
    let targetManifestPath: String
    let mode: String

    enum CodingKeys: String, CodingKey {
        case total
        case byStatus = "by_status"
        case items
        case overlayPath = "overlay_path"
        case auditPath = "audit_path"
        case targetManifestPath = "target_manifest_path"
        case mode
    }
}

struct DoctrineReviewSyncExportResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let exportId: String
    let total: Int
    let markdownPath: String
    let yamlPath: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok, total, message
        case exportId = "export_id"
        case markdownPath = "markdown_path"
        case yamlPath = "yaml_path"
    }
}

struct DoctrineReviewSyncExportsResponse: Codable, Hashable, Sendable {
    let total: Int
    let items: [DoctrineReviewSyncArtifact]
}

struct DoctrineReviewSyncArtifact: Codable, Identifiable, Hashable, Sendable {
    var id: String { exportId }
    let exportId: String
    let markdownPath: String
    let yamlPath: String?
    let updatedAt: Date
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case exportId = "export_id"
        case markdownPath = "markdown_path"
        case yamlPath = "yaml_path"
        case updatedAt = "updated_at"
        case sizeBytes = "size_bytes"
    }
}

struct PodRuntimeRegistryResponse: Codable, Hashable, Sendable {
    let generatedAt: Date?
    let summary: PodRuntimeRegistrySummary
    let items: [PodRuntimeReviewUnit]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case summary, items
    }
}

struct PodRuntimeRegistrySummary: Codable, Hashable, Sendable {
    let total: Int
    let byKind: [String: Int]
    let byStatus: [String: Int]
    let byOwner: [String: Int]
    let byClassification: [String: Int]

    enum CodingKeys: String, CodingKey {
        case total
        case byKind = "by_kind"
        case byStatus = "by_status"
        case byOwner = "by_owner"
        case byClassification = "by_classification"
    }
}

struct PodRuntimeReviewUnit: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: String
    let owner: String?
    let status: String
    let scriptPath: String?
    let launchAgentLabel: String?
    let cadence: String?
    let lastExitCode: Int?
    let pid: Int?
    let logPaths: [String]
    let statePaths: [String]
    let docs: [String]
    let classification: String?
    let classifiedBy: String?
    let classifiedAt: Date?
    let classificationNote: String?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, owner, status, cadence, pid, docs, classification
        case scriptPath = "script_path"
        case launchAgentLabel = "launch_agent_label"
        case lastExitCode = "last_exit_code"
        case logPaths = "log_paths"
        case statePaths = "state_paths"
        case classifiedBy = "classified_by"
        case classifiedAt = "classified_at"
        case classificationNote = "classification_note"
    }

    var needsReviewReasons: [String] {
        var reasons: [String] = []
        if classification == nil {
            reasons.append("unclassified")
        }
        if owner?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            reasons.append("needs owner")
        }
        if docs.isEmpty {
            reasons.append("needs docs")
        }
        if statePaths.isEmpty {
            reasons.append("needs ORCA state")
        }
        if let lastExitCode, lastExitCode != 0 {
            reasons.append("exit \(lastExitCode)")
        }
        if let classification, Self.followupClassifications.contains(classification) {
            reasons.append(classification.replacingOccurrences(of: "_", with: " "))
        }
        return Array(NSOrderedSet(array: reasons)) as? [String] ?? reasons
    }

    var needsReview: Bool {
        !needsReviewReasons.isEmpty
    }

    var reviewSort: Int {
        if classification == nil { return 0 }
        if owner == nil { return 1 }
        if docs.isEmpty { return 2 }
        if statePaths.isEmpty { return 3 }
        return 4
    }

    private static let followupClassifications = Set([
        "needs_owner",
        "needs_docs",
        "needs_orca_state",
        "merge",
        "retire"
    ])
}

struct PodRuntimeReviewQueueResponse: Codable, Hashable, Sendable {
    let total: Int
    let byReason: [String: Int]
    let items: [PodRuntimeReviewQueueItem]

    enum CodingKeys: String, CodingKey {
        case total, items
        case byReason = "by_reason"
    }
}

struct PodRuntimeReviewQueueItem: Codable, Identifiable, Hashable, Sendable {
    var id: String { unit.id }

    let unit: PodRuntimeReviewUnit
    let followupReasons: [String]
    let suggestedAction: String

    enum CodingKeys: String, CodingKey {
        case unit
        case followupReasons = "followup_reasons"
        case suggestedAction = "suggested_action"
    }
}

struct RuntimeClassificationSyncItem: Codable, Hashable, Sendable {
    let unitId: String
    let action: String
    let reviewedBy: String?
    let reviewedAt: String?
    let classificationId: String?
    let note: String?
    let unit: PodRuntimeReviewUnit?

    enum CodingKeys: String, CodingKey {
        case action, note, unit
        case unitId = "unit_id"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case classificationId = "classification_id"
    }
}

struct RuntimeClassificationSyncPreviewResponse: Codable, Hashable, Sendable {
    let total: Int
    let byAction: [String: Int]
    let items: [RuntimeClassificationSyncItem]
    let overlayPath: String
    let auditPath: String
    let mode: String

    enum CodingKeys: String, CodingKey {
        case total, items, mode
        case byAction = "by_action"
        case overlayPath = "overlay_path"
        case auditPath = "audit_path"
    }
}

struct RuntimeClassificationSyncExportResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let exportId: String
    let total: Int
    let markdownPath: String
    let yamlPath: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok, total, message
        case exportId = "export_id"
        case markdownPath = "markdown_path"
        case yamlPath = "yaml_path"
    }
}

struct RuntimeClassificationSyncExportsResponse: Codable, Hashable, Sendable {
    let total: Int
    let items: [RuntimeClassificationSyncArtifact]
}

struct RuntimeClassificationSyncArtifact: Codable, Identifiable, Hashable, Sendable {
    var id: String { exportId }
    let exportId: String
    let markdownPath: String
    let yamlPath: String?
    let updatedAt: Date
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case exportId = "export_id"
        case markdownPath = "markdown_path"
        case yamlPath = "yaml_path"
        case updatedAt = "updated_at"
        case sizeBytes = "size_bytes"
    }
}

struct RuntimeBurnDownExportResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let exportId: String
    let total: Int
    let unreviewed: Int
    let needsFollowup: Int
    let markdownPath: String
    let yamlPath: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok, total, unreviewed, message
        case exportId = "export_id"
        case needsFollowup = "needs_followup"
        case markdownPath = "markdown_path"
        case yamlPath = "yaml_path"
    }
}

struct RuntimeBurnDownExportsResponse: Codable, Hashable, Sendable {
    let total: Int
    let items: [RuntimeClassificationSyncArtifact]
}

struct NoteGovernanceAuditBucket: Codable, Hashable, Sendable {
    let key: String
    let count: Int
}

struct NoteGovernanceAuditResponse: Codable, Hashable, Sendable {
    let total: Int
    let decisionNotes: Int
    let findings: Int
    let missingOwner: Int
    let missingReviewer: Int
    let missingSignState: Int
    let missingTraceId: Int
    let missingSource: Int
    let decisionNotesMissingGovernance: Int
    let byNoteType: [NoteGovernanceAuditBucket]
    let bySignState: [NoteGovernanceAuditBucket]
    let recommendedNextAction: String

    enum CodingKeys: String, CodingKey {
        case total, findings
        case decisionNotes = "decision_notes"
        case missingOwner = "missing_owner"
        case missingReviewer = "missing_reviewer"
        case missingSignState = "missing_sign_state"
        case missingTraceId = "missing_trace_id"
        case missingSource = "missing_source"
        case decisionNotesMissingGovernance = "decision_notes_missing_governance"
        case byNoteType = "by_note_type"
        case bySignState = "by_sign_state"
        case recommendedNextAction = "recommended_next_action"
    }
}

struct NoteGovernanceQueueItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { note.id }
    let note: OrcaNote
    let missingFields: [String]
    let recommendedOwner: String?
    let recommendedReviewer: String?
    let recommendedSignState: String

    enum CodingKeys: String, CodingKey {
        case note
        case missingFields = "missing_fields"
        case recommendedOwner = "recommended_owner"
        case recommendedReviewer = "recommended_reviewer"
        case recommendedSignState = "recommended_sign_state"
    }
}

struct NoteGovernanceQueueResponse: Codable, Hashable, Sendable {
    let total: Int
    let items: [NoteGovernanceQueueItem]
    let mode: String
    let recommendedNextAction: String

    enum CodingKeys: String, CodingKey {
        case total, items, mode
        case recommendedNextAction = "recommended_next_action"
    }
}

struct NoteGovernanceExportResponse: Codable, Hashable, Sendable {
    let generatedAt: Date
    let markdownPath: String
    let totalItems: Int
    let audit: NoteGovernanceAuditResponse
    let mode: String
    let recommendedNextAction: String

    enum CodingKeys: String, CodingKey {
        case mode, audit
        case generatedAt = "generated_at"
        case markdownPath = "markdown_path"
        case totalItems = "total_items"
        case recommendedNextAction = "recommended_next_action"
    }
}

struct DailyLogExtractionCandidate: Codable, Identifiable, Hashable, Sendable {
    var id: String { candidateId ?? "\(agent)-\(date)-\(sourcePath ?? text)" }
    let candidateId: String?
    let agent: String
    let date: String
    let text: String
    let status: String
    let lifecycle: String?
    let reviewState: String?
    let sourcePath: String?
    let confidence: Double?
    let tags: [String]
    let ticketRef: String?
    let requiredReviewers: [String]
    let reviewReason: String?
    let sensitivityClass: String?
    let target: String?
    let targetPath: String?
    let decisionId: String?
    let deferUntil: Date?
    let reviewedBy: [String]
    let approvedBy: [String]
    let requiredApprovals: [String]
    let pendingApprovals: [String]
    let approvalMode: String?
    let minimumApprovals: Int?
    let reviewerNotes: String?
    let promotedAt: Date?
    let promotionTarget: String?
    let promotionTargetPath: String?
    let promotionArtifactPath: String?

    enum CodingKeys: String, CodingKey {
        case agent, date, text, status, confidence, tags
        case candidateId = "candidate_id"
        case lifecycle
        case reviewState = "review_state"
        case sourcePath = "source_path"
        case ticketRef = "ticket_ref"
        case requiredReviewers = "required_reviewers"
        case reviewReason = "review_reason"
        case sensitivityClass = "sensitivity_class"
        case target
        case targetPath = "target_path"
        case decisionId = "decision_id"
        case deferUntil = "defer_until"
        case reviewedBy = "reviewed_by"
        case approvedBy = "approved_by"
        case requiredApprovals = "required_approvals"
        case pendingApprovals = "pending_approvals"
        case approvalMode = "approval_mode"
        case minimumApprovals = "minimum_approvals"
        case reviewerNotes = "reviewer_notes"
        case promotedAt = "promoted_at"
        case promotionTarget = "promotion_target"
        case promotionTargetPath = "promotion_target_path"
        case promotionArtifactPath = "promotion_artifact_path"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidateId = try container.decodeIfPresent(String.self, forKey: .candidateId)
        agent = try container.decodeIfPresent(String.self, forKey: .agent) ?? "unknown"
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? "unknown"
        text = try container.decode(String.self, forKey: .text)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "candidate"
        lifecycle = try container.decodeIfPresent(String.self, forKey: .lifecycle)
        reviewState = try container.decodeIfPresent(String.self, forKey: .reviewState)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        ticketRef = try container.decodeIfPresent(String.self, forKey: .ticketRef)
        requiredReviewers = try container.decodeIfPresent([String].self, forKey: .requiredReviewers) ?? []
        reviewReason = try container.decodeIfPresent(String.self, forKey: .reviewReason)
        sensitivityClass = try container.decodeIfPresent(String.self, forKey: .sensitivityClass)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath)
        decisionId = try container.decodeIfPresent(String.self, forKey: .decisionId)
        deferUntil = try container.decodeIfPresent(Date.self, forKey: .deferUntil)
        reviewedBy = try container.decodeIfPresent([String].self, forKey: .reviewedBy) ?? []
        approvedBy = try container.decodeIfPresent([String].self, forKey: .approvedBy) ?? []
        requiredApprovals = try container.decodeIfPresent([String].self, forKey: .requiredApprovals) ?? []
        pendingApprovals = try container.decodeIfPresent([String].self, forKey: .pendingApprovals) ?? []
        approvalMode = try container.decodeIfPresent(String.self, forKey: .approvalMode)
        minimumApprovals = try container.decodeIfPresent(Int.self, forKey: .minimumApprovals)
        reviewerNotes = try container.decodeIfPresent(String.self, forKey: .reviewerNotes)
        promotedAt = try container.decodeIfPresent(Date.self, forKey: .promotedAt)
        promotionTarget = try container.decodeIfPresent(String.self, forKey: .promotionTarget)
        promotionTargetPath = try container.decodeIfPresent(String.self, forKey: .promotionTargetPath)
        promotionArtifactPath = try container.decodeIfPresent(String.self, forKey: .promotionArtifactPath)
    }

    var effectiveLifecycle: String {
        lifecycle ?? status
    }

    var isSensitive: Bool {
        switch sensitivityClass {
        case "security", "financial", "pii", "credential_like":
            return true
        default:
            return false
        }
    }
}

struct DailyLogExtractionRecord: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(agent)-\(date)-\(sourcePath ?? status)" }
    let agent: String
    let date: String
    let status: String
    let sourcePath: String?
    let candidateCount: Int
    let note: String?

    enum CodingKeys: String, CodingKey {
        case agent, date, status, note
        case sourcePath = "source_path"
        case candidateCount = "candidate_count"
    }
}

struct DailyLogExtractionSummary: Codable, Hashable, Sendable {
    let totalRecords: Int
    let byAgent: [String: Int]
    let byDate: [String: Int]
    let byStatus: [String: Int]
    let candidateMemoryItems: Int
    let expectedAgents: [String]
    let presentAgents: [String]
    let missingAgents: [String]
    let coverageStatus: String

    enum CodingKeys: String, CodingKey {
        case totalRecords = "total_records"
        case byAgent = "by_agent"
        case byDate = "by_date"
        case byStatus = "by_status"
        case candidateMemoryItems = "candidate_memory_items"
        case expectedAgents = "expected_agents"
        case presentAgents = "present_agents"
        case missingAgents = "missing_agents"
        case coverageStatus = "coverage_status"
    }

    init(
        totalRecords: Int,
        byAgent: [String: Int],
        byDate: [String: Int],
        byStatus: [String: Int],
        candidateMemoryItems: Int,
        expectedAgents: [String] = [],
        presentAgents: [String] = [],
        missingAgents: [String] = [],
        coverageStatus: String = "unknown"
    ) {
        self.totalRecords = totalRecords
        self.byAgent = byAgent
        self.byDate = byDate
        self.byStatus = byStatus
        self.candidateMemoryItems = candidateMemoryItems
        self.expectedAgents = expectedAgents
        self.presentAgents = presentAgents
        self.missingAgents = missingAgents
        self.coverageStatus = coverageStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalRecords = try container.decode(Int.self, forKey: .totalRecords)
        byAgent = try container.decode([String: Int].self, forKey: .byAgent)
        byDate = try container.decode([String: Int].self, forKey: .byDate)
        byStatus = try container.decode([String: Int].self, forKey: .byStatus)
        candidateMemoryItems = try container.decode(Int.self, forKey: .candidateMemoryItems)
        expectedAgents = try container.decodeIfPresent([String].self, forKey: .expectedAgents) ?? []
        presentAgents = try container.decodeIfPresent([String].self, forKey: .presentAgents) ?? []
        missingAgents = try container.decodeIfPresent([String].self, forKey: .missingAgents) ?? []
        coverageStatus = try container.decodeIfPresent(String.self, forKey: .coverageStatus) ?? "unknown"
    }
}

struct DailyLogExtractionResponse: Codable, Hashable, Sendable {
    let artifactPath: String?
    let artifactUpdatedAt: Date?
    let generatedAt: Date?
    let summary: DailyLogExtractionSummary
    let records: [DailyLogExtractionRecord]
    let candidateMemoryItems: [DailyLogExtractionCandidate]

    enum CodingKeys: String, CodingKey {
        case summary, records
        case artifactPath = "artifact_path"
        case artifactUpdatedAt = "artifact_updated_at"
        case generatedAt = "generated_at"
        case candidateMemoryItems = "candidate_memory_items"
    }
}

struct StorageHygieneTicketResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let created: Bool
    let ticket: StorageHygieneTicket
    let artifactPath: String?
    let candidateCount: Int
    let totalSizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case ok, created, ticket
        case artifactPath = "artifact_path"
        case candidateCount = "candidate_count"
        case totalSizeBytes = "total_size_bytes"
    }
}

struct MemoryPromotionTicketResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let created: Bool
    let ticket: StorageHygieneTicket
    let artifactPath: String?
    let candidateCount: Int

    enum CodingKeys: String, CodingKey {
        case ok, created, ticket
        case artifactPath = "artifact_path"
        case candidateCount = "candidate_count"
    }
}

struct MemoryCandidateActionResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let candidate: DailyLogExtractionCandidate
    let decisionId: String
    let overlayPath: String
    let auditPath: String

    enum CodingKeys: String, CodingKey {
        case ok, candidate
        case decisionId = "decision_id"
        case overlayPath = "overlay_path"
        case auditPath = "audit_path"
    }
}

struct MemoryQueryRequest: Codable, Sendable {
    let query: String
    let scopes: [String]
    let limit: Int
    let includeProtected: Bool

    enum CodingKeys: String, CodingKey {
        case query, scopes, limit
        case includeProtected = "include_protected"
    }
}

struct MemoryQueryResult: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(scope)|\(sourceRef)|\(title)|\(path ?? "")" }
    let scope: String
    let sourceType: String
    let sourceLabel: String
    let sourceRef: String
    let title: String
    let snippet: String
    let path: String?
    let score: Double
    let protected: Bool
    let provenance: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case scope, title, snippet, path, score, protected, provenance
        case sourceType = "source_type"
        case sourceLabel = "source_label"
        case sourceRef = "source_ref"
    }
}

struct MemoryQueryResponse: Codable, Hashable, Sendable {
    let query: String
    let total: Int
    let scopesUsed: [String]
    let skippedScopes: [String]
    let items: [MemoryQueryResult]

    enum CodingKeys: String, CodingKey {
        case query, total, items
        case scopesUsed = "scopes_used"
        case skippedScopes = "skipped_scopes"
    }
}

struct KnowledgePacketSearchResponse: Decodable, Hashable, Sendable {
    let results: [KnowledgePacketSearchResult]

    private enum CodingKeys: String, CodingKey {
        case items
        case results
        case packets
        case data
    }

    init(from decoder: Decoder) throws {
        if let array = try? [KnowledgePacketSearchResult](from: decoder) {
            results = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent([KnowledgePacketSearchResult].self, forKey: .items)
            ?? container.decodeIfPresent([KnowledgePacketSearchResult].self, forKey: .results)
            ?? container.decodeIfPresent([KnowledgePacketSearchResult].self, forKey: .packets)
            ?? container.decodeIfPresent([KnowledgePacketSearchResult].self, forKey: .data)
            ?? []
    }
}

struct KnowledgePacketSearchResult: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let lane: String
    let sourceType: String
    let body: String
    let evidenceRef: String?
    let createdAt: String?
    let score: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case packetId = "packet_id"
        case knowledgeId = "knowledge_id"
        case title
        case name
        case summary
        case lane
        case laneId = "lane_id"
        case sourceType = "source_type"
        case source
        case type
        case body
        case content
        case text
        case markdown
        case snippet
        case evidenceRef = "evidence_ref"
        case evidenceRefs = "evidence_refs"
        case evidence
        case ref
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .packetId)
            ?? container.decodeIfPresent(String.self, forKey: .knowledgeId)
            ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .summary)
            ?? "Untitled packet"
        lane = try container.decodeIfPresent(String.self, forKey: .lane)
            ?? container.decodeIfPresent(String.self, forKey: .laneId)
            ?? "knowledge"
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
            ?? container.decodeIfPresent(String.self, forKey: .source)
            ?? container.decodeIfPresent(String.self, forKey: .type)
            ?? "packet"
        body = try container.decodeIfPresent(String.self, forKey: .body)
            ?? container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .markdown)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decodeIfPresent(String.self, forKey: .snippet)
            ?? ""
        let evidenceRefs = try container.decodeIfPresent([String].self, forKey: .evidenceRefs)
        evidenceRef = try container.decodeIfPresent(String.self, forKey: .evidenceRef)
            ?? evidenceRefs?.first
            ?? container.decodeIfPresent(String.self, forKey: .evidence)
            ?? container.decodeIfPresent(String.self, forKey: .ref)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? container.decodeIfPresent(String.self, forKey: .updatedAt)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
    }

    var sourceIcon: String {
        switch sourceType.lowercased() {
        case "wiki", "doc", "document", "markdown": return "doc.richtext"
        case "memory", "memory_candidate": return "brain.head.profile"
        case "sonar", "message", "chat": return "bubble.left.and.bubble.right"
        case "ticket", "task": return "checklist"
        case "standard", "doctrine": return "books.vertical"
        default: return "shippingbox"
        }
    }

    var displayLane: String {
        lane.replacingOccurrences(of: "_", with: " ").uppercased()
    }
}

struct MemoryCandidateQueueSummary: Codable, Hashable, Sendable {
    let total: Int
    let byLifecycle: [String: Int]
    let bySensitivityClass: [String: Int]
    let byReviewState: [String: Int]

    enum CodingKeys: String, CodingKey {
        case total
        case byLifecycle = "by_lifecycle"
        case bySensitivityClass = "by_sensitivity_class"
        case byReviewState = "by_review_state"
    }
}

struct MemoryOpsResponse: Codable, Hashable, Sendable {
    let laneMode: String
    let durableTotal: Int
    let durableByLifecycle: [String: Int]
    let pendingReview: Int
    let sensitiveWaiting: Int
    let latestExtractCandidates: Int
    let presentAgents: [String]
    let missingAgents: [String]
    let coverageStatus: String
    let generatedAt: Date?
    let artifactPath: String?

    enum CodingKeys: String, CodingKey {
        case laneMode = "lane_mode"
        case durableTotal = "durable_total"
        case durableByLifecycle = "durable_by_lifecycle"
        case pendingReview = "pending_review"
        case sensitiveWaiting = "sensitive_waiting"
        case latestExtractCandidates = "latest_extract_candidates"
        case presentAgents = "present_agents"
        case missingAgents = "missing_agents"
        case coverageStatus = "coverage_status"
        case generatedAt = "generated_at"
        case artifactPath = "artifact_path"
    }
}

struct MemoryCandidateQueueResponse: Codable, Hashable, Sendable {
    let artifactPath: String
    let artifactUpdatedAt: Date
    let generatedAt: Date?
    let summary: MemoryCandidateQueueSummary
    let items: [DailyLogExtractionCandidate]
    let ops: MemoryOpsResponse?
    let overlayPath: String
    let auditPath: String
    let exportDir: String

    enum CodingKeys: String, CodingKey {
        case summary, items
        case artifactPath = "artifact_path"
        case artifactUpdatedAt = "artifact_updated_at"
        case generatedAt = "generated_at"
        case ops
        case overlayPath = "overlay_path"
        case auditPath = "audit_path"
        case exportDir = "export_dir"
    }
}

struct MemoryApproveRequest: Codable, Sendable {
    let reviewer: String
    let target: String
    let targetPath: String?
    let reviewerNotes: String?
    let editText: String?

    enum CodingKeys: String, CodingKey {
        case reviewer, target
        case targetPath = "target_path"
        case reviewerNotes = "reviewer_notes"
        case editText = "edit_text"
    }
}

struct MemoryRejectRequest: Codable, Sendable {
    let reviewer: String
    let reason: String
    let visibleToOriginator: Bool

    enum CodingKeys: String, CodingKey {
        case reviewer, reason
        case visibleToOriginator = "visible_to_originator"
    }
}

struct MemoryDeferRequest: Codable, Sendable {
    let reviewer: String
    let reason: String
    let deferUntil: Date

    enum CodingKeys: String, CodingKey {
        case reviewer, reason
        case deferUntil = "defer_until"
    }
}

struct StorageHygieneTicket: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let status: String
    let approvalState: String?
    let workerLane: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case approvalState = "approval_state"
        case workerLane = "worker_lane"
    }
}

struct SkillLabSkill: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let slug: String
    let title: String
    let purpose: String
    let ownerAgent: String
    let safetyOwner: String
    let standardsOwner: String
    let domain: String
    let protected: Bool
    let status: String
    let activeVersionId: UUID?
    let latestCandidateId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, slug, title, purpose, domain, protected, status
        case ownerAgent = "owner_agent"
        case safetyOwner = "safety_owner"
        case standardsOwner = "standards_owner"
        case activeVersionId = "active_version_id"
        case latestCandidateId = "latest_candidate_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SkillLabPromotionCandidate: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let skillId: UUID
    let status: String
    let reviewState: String
    let requiredReviewers: [String]?
    let reviewersCompleted: [String]?
    let riskLevel: String
    let protected: Bool
    let summary: String?
    let diffSummary: String?
    let approvalGate: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, protected, summary
        case skillId = "skill_id"
        case reviewState = "review_state"
        case requiredReviewers = "required_reviewers"
        case reviewersCompleted = "reviewers_completed"
        case riskLevel = "risk_level"
        case diffSummary = "diff_summary"
        case approvalGate = "approval_gate"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SkillLabEvalRun: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let skillId: UUID
    let status: String
    let benchmarkName: String
    let optimizerRoute: String?
    let targetRoute: String?
    let validationScore: Double?
    let testScore: Double?
    let baselineScore: Double?
    let regressionCount: Int
    let accepted: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, accepted
        case skillId = "skill_id"
        case benchmarkName = "benchmark_name"
        case optimizerRoute = "optimizer_route"
        case targetRoute = "target_route"
        case validationScore = "validation_score"
        case testScore = "test_score"
        case baselineScore = "baseline_score"
        case regressionCount = "regression_count"
        case createdAt = "created_at"
    }
}

struct SkillLabEvalCase: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let skillId: UUID
    let benchmarkName: String
    let caseId: String
    let inputText: String
    let expectedOwnerAgent: String?
    let expectedWorkerLane: String?
    let expectedDeliveryMode: String?
    let expectedNeedsTicket: Bool?
    let expectedNeedsApproval: Bool?
    let expectedRiskLevel: String?
    let expectedNextAction: String?
    let protected: Bool
    let sourceRef: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, protected
        case skillId = "skill_id"
        case benchmarkName = "benchmark_name"
        case caseId = "case_id"
        case inputText = "input_text"
        case expectedOwnerAgent = "expected_owner_agent"
        case expectedWorkerLane = "expected_worker_lane"
        case expectedDeliveryMode = "expected_delivery_mode"
        case expectedNeedsTicket = "expected_needs_ticket"
        case expectedNeedsApproval = "expected_needs_approval"
        case expectedRiskLevel = "expected_risk_level"
        case expectedNextAction = "expected_next_action"
        case sourceRef = "source_ref"
        case createdAt = "created_at"
    }
}

struct SkillLabOverview: Codable, Hashable, Sendable {
    let status: String
    let route: String
    let policy: String
    let counts: [String: Int]
    let skills: [SkillLabSkill]
    let pendingPromotions: [SkillLabPromotionCandidate]
    let recentEvalRuns: [SkillLabEvalRun]

    enum CodingKeys: String, CodingKey {
        case status, route, policy, counts, skills
        case pendingPromotions = "pending_promotions"
        case recentEvalRuns = "recent_eval_runs"
    }
}

struct SkillLabDetail: Codable, Hashable, Sendable {
    let status: String
    let route: String
    let policy: String
    let skill: SkillLabSkill
    let versions: [SkillLabVersion]
    let evalCases: [SkillLabEvalCase]
    let evalRuns: [SkillLabEvalRun]
    let promotionCandidates: [SkillLabPromotionCandidate]
    let counts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case status, route, policy, skill, versions, counts
        case evalCases = "eval_cases"
        case evalRuns = "eval_runs"
        case promotionCandidates = "promotion_candidates"
    }
}

struct SkillLabVersion: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let skillId: UUID
    let version: String
    let status: String
    let skillText: String?
    let skillPath: String?
    let source: String
    let sourceRef: String?
    let benchmarkRef: String?
    let createdBy: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, version, status, source
        case skillId = "skill_id"
        case skillText = "skill_text"
        case skillPath = "skill_path"
        case sourceRef = "source_ref"
        case benchmarkRef = "benchmark_ref"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct OrcaNote: Codable, Identifiable, Hashable, Sendable {
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

    var scopeLabel: String {
        if let targetId, !targetId.isEmpty {
            return "\(targetType) · \(targetId)"
        }
        return targetType
    }

    var typeLabel: String {
        noteType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

enum OrcaNoteFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case decision
    case finding
    case system
    case project
    case agent
    case ticket
    case needsReview
    case signed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .decision: return "Decision"
        case .finding: return "Finding"
        case .system: return "System"
        case .project: return "Project"
        case .agent: return "Agent"
        case .ticket: return "Ticket"
        case .needsReview: return "Review"
        case .signed: return "Signed"
        }
    }

    var query: String {
        switch self {
        case .all:
            return ""
        case .decision:
            return "note_type=decision"
        case .finding:
            return "note_type=finding"
        case .system:
            return "target_type=system"
        case .project:
            return "target_type=project"
        case .agent:
            return "target_type=agent"
        case .ticket:
            return "target_type=ticket"
        case .needsReview:
            return "sign_state=needs_review"
        case .signed:
            return "sign_state=signed"
        }
    }

    var governanceExportNoteType: String? {
        switch self {
        case .decision:
            return "decision"
        case .finding:
            return "finding"
        default:
            return nil
        }
    }
}

private struct EmptyRequest: Encodable {}

private struct OrcaNoteCreateRequest: Encodable {
    let targetType: String
    let targetId: String?
    let noteType: String
    let title: String
    let body: String
    let tags: [String]
    let source: String
    let traceId: String
    let signState: String?

    enum CodingKeys: String, CodingKey {
        case title, body, tags, source
        case targetType = "target_type"
        case targetId = "target_id"
        case noteType = "note_type"
        case traceId = "trace_id"
        case signState = "sign_state"
    }
}

// MARK: - Knowledge ViewModel

@Observable
final class KnowledgeViewModel {

    // MARK: - Published State

    var standards: [Standard] = []
    var categories: [StandardCategory] = StandardCategory.allCases
    var selectedCategory: StandardCategory?
    var searchText: String = ""
    var recentStandards: [Standard] = []
    var favoriteStandards: [Standard] = []
    var todayChronogram: WikiDocument?
    var wikiDocuments: [WikiDocument] = []
    var selectedWikiDocument: WikiDocument?
    var docRegistrySummary: DocRegistrySummary?
    var docRegistryItems: [DocRegistryItem] = []
    var doctrineBundles: [DoctrineBundleSummary] = []
    var selectedDoctrineBundle: DoctrineBundleDetail?
    var reviewQueueSummary: DocRegistrySummary?
    var reviewQueueItems: [DocRegistryItem] = []
    var reviewQueueReviewers: [String] = []
    var reviewQueueReleaseGate: String?
    var reviewSyncPreview: DoctrineReviewSyncPreviewResponse?
    var reviewSyncExports: [DoctrineReviewSyncArtifact] = []
    var runtimeReviewSummary: PodRuntimeRegistrySummary?
    var runtimeReviewGeneratedAt: Date?
    var runtimeReviewReasonCounts: [String: Int] = [:]
    var runtimeReviewQueueItems: [PodRuntimeReviewQueueItem] = []
    var runtimeReviewUnits: [PodRuntimeReviewUnit] = []
    var runtimeSyncPreview: RuntimeClassificationSyncPreviewResponse?
    var runtimeSyncExports: [RuntimeClassificationSyncArtifact] = []
    var runtimeBurnDownExports: [RuntimeClassificationSyncArtifact] = []
    var dailyLogExtraction: DailyLogExtractionResponse?
    var memoryCandidateQueue: MemoryCandidateQueueResponse?
    var memoryOps: MemoryOpsResponse?
    var memoryQueryText: String = ""
    var memoryQueryResponse: MemoryQueryResponse?
    var knowledgePacketQueryText: String = ""
    var knowledgePacketResults: [KnowledgePacketSearchResult] = []
    var selectedKnowledgePacket: KnowledgePacketSearchResult?
    var notes: [OrcaNote] = []
    var noteGovernanceAudit: NoteGovernanceAuditResponse?
    var noteGovernanceQueue: NoteGovernanceQueueResponse?
    var noteGovernanceExport: NoteGovernanceExportResponse?
    var skillLabOverview: SkillLabOverview?
    var selectedSkillLabDetail: SkillLabDetail?
    var isLoading: Bool = false
    var isLoadingWiki: Bool = false
    var isLoadingWikiDocuments: Bool = false
    var isLoadingSelectedWikiDocument: Bool = false
    var isLoadingDocRegistry: Bool = false
    var isLoadingDoctrineBundles: Bool = false
    var isLoadingReviewQueue: Bool = false
    var isLoadingReviewSync: Bool = false
    var isLoadingRuntimeReviewQueue: Bool = false
    var isLoadingRuntimeSync: Bool = false
    var isLoadingMemoryCandidates: Bool = false
    var isLoadingMemoryQuery: Bool = false
    var isLoadingKnowledgePackets: Bool = false
    var isLoadingNotes: Bool = false
    var isLoadingSkillLab: Bool = false
    var isLoadingSkillLabDetail: Bool = false
    var isExportingReviewSync: Bool = false
    var isExportingRuntimeSync: Bool = false
    var isExportingRuntimeBurnDown: Bool = false
    var isGeneratingStorageHygieneTicket: Bool = false
    var isGeneratingMemoryPromotionTicket: Bool = false
    var memoryActionCandidateIds: Set<String> = []
    var isExportingNoteGovernance: Bool = false
    var reviewActionInFlightDocId: String?
    var errorMessage: String?
    var wikiErrorMessage: String?
    var wikiDocumentsErrorMessage: String?
    var docRegistryErrorMessage: String?
    var doctrineBundleErrorMessage: String?
    var reviewQueueErrorMessage: String?
    var runtimeReviewQueueErrorMessage: String?
    var reviewActionMessage: String?
    var reviewSyncMessage: String?
    var runtimeSyncMessage: String?
    var runtimeBurnDownMessage: String?
    var memoryCandidatesErrorMessage: String?
    var memoryQueryErrorMessage: String?
    var knowledgePacketErrorMessage: String?
    var notesErrorMessage: String?
    var noteGovernanceErrorMessage: String?
    var noteGovernanceExportMessage: String?
    var skillLabErrorMessage: String?
    var skillLabDetailErrorMessage: String?
    var storageHygieneMessage: String?
    var memoryPromotionMessage: String?
    var memoryActionMessage: String?
    var reviewerIdentity = "maui"

    // MARK: - Computed

    var filteredStandards: [Standard] {
        var result = standards

        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { s in
                s.title.lowercased().contains(query) ||
                s.tags.contains { $0.lowercased().contains(query) } ||
                s.authorName.lowercased().contains(query)
            }
        }

        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    var categoryCounts: [StandardCategory: Int] {
        Dictionary(grouping: standards, by: \.category).mapValues(\.count)
    }

    var runtimeNeedsOwnerCount: Int {
        runtimeReviewReasonCounts["needs_owner"]
            ?? runtimeReviewReasonCounts["needs owner"]
            ?? runtimeReviewQueueItems.filter { $0.followupReasons.contains("needs_owner") || $0.followupReasons.contains("needs owner") }.count
    }

    var runtimeNeedsDocsCount: Int {
        runtimeReviewReasonCounts["needs_docs"]
            ?? runtimeReviewReasonCounts["needs docs"]
            ?? runtimeReviewQueueItems.filter { $0.followupReasons.contains("needs_docs") || $0.followupReasons.contains("needs docs") }.count
    }

    var memoryLifecycleCounts: [String: Int] {
        Dictionary(grouping: memoryCandidateQueue?.items ?? [], by: \.effectiveLifecycle).mapValues(\.count)
    }

    var durableLifecycleCounts: [String: Int] {
        memoryOps?.durableByLifecycle ?? [:]
    }

    var durablePendingCount: Int {
        (memoryCandidateQueue?.items ?? []).filter {
            let lifecycle = $0.effectiveLifecycle.lowercased()
            return lifecycle == "candidate" || lifecycle == "pending" || lifecycle == "waiting_sensitive_review"
        }.count
    }

    // MARK: - Private

    private let recentStorageKey = "pod.recentStandards"
    private let favoritesStorageKey = "pod.favoriteStandards"

    // MARK: - Init

    init() {
        loadLocalFavorites()
        loadRecentStandards()
    }

    func configureReviewerIdentity(from name: String?) {
        let fallback = "maui"
        let cleaned = (name ?? fallback)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        reviewerIdentity = cleaned.isEmpty ? fallback : cleaned
    }

    // MARK: - Load

    func loadStandards() async {
        isLoading = true
        errorMessage = nil

        do {
            let response: PaginatedResponse<Standard> = try await APIClient.shared.get(path: "/api/v1/standards")
            await MainActor.run {
                self.standards = response.items
                self.recomputeDerived()
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.standards = []
                self.errorMessage = "Standards are unavailable from ORCA."
                self.isLoading = false
            }
        }
    }

    func loadWikiContext() async {
        isLoadingWiki = true
        wikiErrorMessage = nil

        do {
            let chronogram: WikiDocument = try await APIClient.shared.get(path: "/api/v1/wiki/chronogram/today")
            await MainActor.run {
                self.todayChronogram = chronogram
                self.isLoadingWiki = false
            }
        } catch {
            await MainActor.run {
                self.wikiErrorMessage = error.localizedDescription
                self.isLoadingWiki = false
            }
        }
    }

    func loadWikiDocuments(query: String? = nil, section: String? = nil) async {
        isLoadingWikiDocuments = true
        wikiDocumentsErrorMessage = nil

        var components = URLComponents()
        components.path = "/api/v1/wiki/docs"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "80")
        ]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components.queryItems?.append(URLQueryItem(name: "query", value: query))
        }
        if let section, !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components.queryItems?.append(URLQueryItem(name: "section", value: section))
        }

        do {
            let docs: [WikiDocument] = try await APIClient.shared.get(path: components.string ?? "/api/v1/wiki/docs?limit=80")
            await MainActor.run {
                self.wikiDocuments = docs
                self.isLoadingWikiDocuments = false
            }
        } catch {
            await MainActor.run {
                self.wikiDocuments = []
                self.wikiDocumentsErrorMessage = error.localizedDescription
                self.isLoadingWikiDocuments = false
            }
        }
    }

    func openWikiDocument(_ summary: WikiDocument) async {
        selectedWikiDocument = summary
        isLoadingSelectedWikiDocument = true
        wikiDocumentsErrorMessage = nil

        let encodedPath = summary.path
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")

        do {
            let doc: WikiDocument = try await APIClient.shared.get(path: "/api/v1/wiki/docs/\(encodedPath)")
            await MainActor.run {
                self.selectedWikiDocument = doc
                self.isLoadingSelectedWikiDocument = false
            }
        } catch {
            await MainActor.run {
                self.wikiDocumentsErrorMessage = error.localizedDescription
                self.isLoadingSelectedWikiDocument = false
            }
        }
    }

    func loadDocRegistry() async {
        isLoadingDocRegistry = true
        docRegistryErrorMessage = nil

        do {
            let registry: DocRegistryResponse = try await APIClient.shared.get(path: "/api/v1/doc-registry?required_for=all&limit=40")
            await MainActor.run {
                self.docRegistrySummary = registry.summary
                self.docRegistryItems = registry.items
                self.isLoadingDocRegistry = false
            }
        } catch {
            await MainActor.run {
                self.docRegistryErrorMessage = error.localizedDescription
                self.isLoadingDocRegistry = false
            }
        }
    }

    func loadDoctrineBundles() async {
        isLoadingDoctrineBundles = true
        doctrineBundleErrorMessage = nil

        do {
            let response: DoctrineBundleListResponse = try await APIClient.shared.get(path: "/api/v1/doc-registry/bundles")
            let preferred = response.items.first { $0.id == "schoolhouse-control-plane" } ?? response.items.first
            let detail: DoctrineBundleDetail?
            if let preferred {
                detail = try await APIClient.shared.get(path: "/api/v1/doc-registry/bundles/\(preferred.id)")
            } else {
                detail = nil
            }

            await MainActor.run {
                self.doctrineBundles = response.items
                self.selectedDoctrineBundle = detail
                self.isLoadingDoctrineBundles = false
            }
        } catch {
            await MainActor.run {
                self.doctrineBundleErrorMessage = error.localizedDescription
                self.isLoadingDoctrineBundles = false
            }
        }
    }

    func loadDoctrineBundle(id: String) async {
        isLoadingDoctrineBundles = true
        doctrineBundleErrorMessage = nil

        do {
            let detail: DoctrineBundleDetail = try await APIClient.shared.get(path: "/api/v1/doc-registry/bundles/\(id)")
            await MainActor.run {
                self.selectedDoctrineBundle = detail
                self.isLoadingDoctrineBundles = false
            }
        } catch {
            await MainActor.run {
                self.doctrineBundleErrorMessage = error.localizedDescription
                self.isLoadingDoctrineBundles = false
            }
        }
    }

    func loadReviewQueue() async {
        isLoadingReviewQueue = true
        reviewQueueErrorMessage = nil

        do {
            let queue: DoctrineReviewQueueResponse = try await APIClient.shared.get(path: "/api/v1/doc-registry/review-queue?limit=20")
            await MainActor.run {
                self.reviewQueueSummary = queue.summary
                self.reviewQueueItems = queue.items
                self.reviewQueueReviewers = queue.reviewers
                self.reviewQueueReleaseGate = queue.releaseGate
                self.isLoadingReviewQueue = false
            }
        } catch {
            await MainActor.run {
                self.reviewQueueErrorMessage = error.localizedDescription
                self.isLoadingReviewQueue = false
            }
        }
    }

    func loadRuntimeReviewQueue() async {
        isLoadingRuntimeReviewQueue = true
        runtimeReviewQueueErrorMessage = nil

        do {
            async let registryRequest: PodRuntimeRegistryResponse = APIClient.shared.get(path: "/api/v1/runtime-registry?limit=120")
            async let queueRequest: PodRuntimeReviewQueueResponse = APIClient.shared.get(path: "/api/v1/runtime-registry/review-queue?limit=120")
            let registry = try await registryRequest
            let queue = try await queueRequest
            let units = queue.items.map(\.unit)
            await MainActor.run {
                self.runtimeReviewSummary = registry.summary
                self.runtimeReviewGeneratedAt = registry.generatedAt
                self.runtimeReviewReasonCounts = queue.byReason
                self.runtimeReviewQueueItems = queue.items
                self.runtimeReviewUnits = units
                self.isLoadingRuntimeReviewQueue = false
            }
        } catch {
            await MainActor.run {
                self.runtimeReviewSummary = nil
                self.runtimeReviewGeneratedAt = nil
                self.runtimeReviewReasonCounts = [:]
                self.runtimeReviewQueueItems = []
                self.runtimeReviewUnits = []
                self.runtimeReviewQueueErrorMessage = error.localizedDescription
                self.isLoadingRuntimeReviewQueue = false
            }
        }
    }

    func loadReviewSyncPreview() async {
        isLoadingReviewSync = true
        reviewQueueErrorMessage = nil

        do {
            async let previewRequest: DoctrineReviewSyncPreviewResponse = APIClient.shared.get(path: "/api/v1/doc-registry/review-sync/preview?limit=20")
            async let exportsRequest: DoctrineReviewSyncExportsResponse = APIClient.shared.get(path: "/api/v1/doc-registry/review-sync/exports?limit=5")
            let preview = try await previewRequest
            let exports = try await exportsRequest
            await MainActor.run {
                self.reviewSyncPreview = preview
                self.reviewSyncExports = exports.items
                self.isLoadingReviewSync = false
            }
        } catch {
            await MainActor.run {
                self.reviewQueueErrorMessage = error.localizedDescription
                self.reviewSyncExports = []
                self.isLoadingReviewSync = false
            }
        }
    }

    func loadRuntimeSyncPreview() async {
        isLoadingRuntimeSync = true
        runtimeReviewQueueErrorMessage = nil

        do {
            async let previewRequest: RuntimeClassificationSyncPreviewResponse = APIClient.shared.get(path: "/api/v1/runtime-registry/classification-sync/preview?limit=20")
            async let exportsRequest: RuntimeClassificationSyncExportsResponse = APIClient.shared.get(path: "/api/v1/runtime-registry/classification-sync/exports?limit=5")
            async let burnDownExportsRequest: RuntimeBurnDownExportsResponse = APIClient.shared.get(path: "/api/v1/runtime-registry/burn-down/exports?limit=5")
            let preview = try await previewRequest
            let exports = try await exportsRequest
            let burnDownExports = try await burnDownExportsRequest
            await MainActor.run {
                self.runtimeSyncPreview = preview
                self.runtimeSyncExports = exports.items
                self.runtimeBurnDownExports = burnDownExports.items
                self.isLoadingRuntimeSync = false
            }
        } catch {
            await MainActor.run {
                self.runtimeReviewQueueErrorMessage = error.localizedDescription
                self.runtimeSyncExports = []
                self.runtimeBurnDownExports = []
                self.isLoadingRuntimeSync = false
            }
        }
    }

    func loadSkillLab() async {
        isLoadingSkillLab = true
        skillLabErrorMessage = nil

        do {
            let overview: SkillLabOverview = try await APIClient.shared.get(path: "/api/v1/skill-lab")
            await MainActor.run {
                self.skillLabOverview = overview
                self.isLoadingSkillLab = false
            }
        } catch {
            await MainActor.run {
                self.skillLabErrorMessage = error.localizedDescription
                self.isLoadingSkillLab = false
            }
        }
    }

    func openSkillLabDetail(_ skill: SkillLabSkill) async {
        selectedSkillLabDetail = nil
        isLoadingSkillLabDetail = true
        skillLabDetailErrorMessage = nil

        do {
            let detail: SkillLabDetail = try await APIClient.shared.get(path: "/api/v1/skill-lab/skills/\(skill.id.uuidString)")
            await MainActor.run {
                self.selectedSkillLabDetail = detail
                self.isLoadingSkillLabDetail = false
            }
        } catch {
            await MainActor.run {
                self.skillLabDetailErrorMessage = error.localizedDescription
                self.isLoadingSkillLabDetail = false
            }
        }
    }

    func loadMemoryCandidates() async {
        isLoadingMemoryCandidates = true
        memoryCandidatesErrorMessage = nil

        do {
            async let extractionTask: DailyLogExtractionResponse = APIClient.shared.get(path: "/api/v1/daily-log-extractions/latest")
            async let queueTask: MemoryCandidateQueueResponse = APIClient.shared.get(path: "/api/v1/memory/candidates")
            let (extraction, queue) = try await (extractionTask, queueTask)
            await MainActor.run {
                self.dailyLogExtraction = extraction
                self.memoryCandidateQueue = queue
                self.memoryOps = queue.ops
                self.isLoadingMemoryCandidates = false
            }
        } catch {
            await MainActor.run {
                self.dailyLogExtraction = nil
                self.memoryCandidateQueue = nil
                self.memoryOps = nil
                self.memoryCandidatesErrorMessage = error.localizedDescription
                self.isLoadingMemoryCandidates = false
            }
        }
    }

    func queryMemory() async {
        let query = memoryQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            await MainActor.run {
                self.memoryQueryResponse = nil
                self.memoryQueryErrorMessage = nil
            }
            return
        }

        isLoadingMemoryQuery = true
        memoryQueryErrorMessage = nil
        defer { isLoadingMemoryQuery = false }

        do {
            let response: MemoryQueryResponse = try await APIClient.shared.post(
                path: "/api/v1/memory/query",
                body: MemoryQueryRequest(
                    query: query,
                    scopes: ["durable", "starfish", "research", "chief_graph"],
                    limit: 8,
                    includeProtected: true
                )
            )
            await MainActor.run {
                self.memoryQueryResponse = response
                self.memoryQueryErrorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.memoryQueryResponse = nil
                self.memoryQueryErrorMessage = "Memory search unavailable: \(error.localizedDescription)"
            }
        }
    }

    func searchKnowledgePackets() async {
        let query = knowledgePacketQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            await MainActor.run {
                self.knowledgePacketResults = []
                self.knowledgePacketErrorMessage = nil
            }
            return
        }

        isLoadingKnowledgePackets = true
        knowledgePacketErrorMessage = nil
        defer { isLoadingKnowledgePackets = false }

        do {
            let request = try await APIClient.shared.buildRequest(
                path: "/api/v1/knowledge/packets",
                queryItems: [
                    URLQueryItem(name: "query", value: query)
                ]
            )
            let response: KnowledgePacketSearchResponse = try await APIClient.shared.perform(request)
            await MainActor.run {
                self.knowledgePacketResults = response.results
                self.knowledgePacketErrorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.knowledgePacketResults = []
                self.knowledgePacketErrorMessage = "Knowledge search unavailable: \(error.localizedDescription)"
            }
        }
    }

    func loadNotes(filter: OrcaNoteFilter = .all) async {
        isLoadingNotes = true
        notesErrorMessage = nil

        do {
            var path = filter == .finding ? "/api/v1/notes/findings?limit=20" : "/api/v1/notes?limit=20"
            if filter != .finding && !filter.query.isEmpty {
                path += "&\(filter.query)"
            }
            let items: [OrcaNote] = try await APIClient.shared.get(path: path)
            let audit: NoteGovernanceAuditResponse = try await APIClient.shared.get(path: "/api/v1/notes/governance/audit")
            let queue: NoteGovernanceQueueResponse = try await APIClient.shared.get(path: "/api/v1/notes/governance/queue?limit=20")
            await MainActor.run {
                self.notes = items
                self.noteGovernanceAudit = audit
                self.noteGovernanceQueue = queue
                self.isLoadingNotes = false
            }
        } catch {
            await MainActor.run {
                self.notes = []
                self.notesErrorMessage = error.localizedDescription
                self.noteGovernanceAudit = nil
                self.noteGovernanceQueue = nil
                self.isLoadingNotes = false
            }
        }
    }

    func createSystemNote(title: String, body: String, noteType: String) async -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanBody.isEmpty else { return false }

        do {
            let request = OrcaNoteCreateRequest(
                targetType: "system",
                targetId: nil,
                noteType: noteType,
                title: cleanTitle,
                body: cleanBody,
                tags: ["pod", "knowledge", noteType],
                source: "pod.knowledge.notes",
                traceId: "pod-knowledge-note-\(Int(Date().timeIntervalSince1970))",
                signState: "draft"
            )
            let created: OrcaNote = try await APIClient.shared.post(
                path: "/api/v1/notes/system/global",
                body: request
            )
            await MainActor.run {
                self.notes.insert(created, at: 0)
            }
            return true
        } catch {
            await MainActor.run {
                self.notesErrorMessage = "Couldn't save ORCA note: \(error.localizedDescription)"
            }
            return false
        }
    }

    func exportNoteGovernance(filter: OrcaNoteFilter = .all) async {
        isExportingNoteGovernance = true
        noteGovernanceErrorMessage = nil
        noteGovernanceExportMessage = nil
        defer { isExportingNoteGovernance = false }

        do {
            var path = "/api/v1/notes/governance/export"
            if let noteType = filter.governanceExportNoteType {
                path += "?note_type=\(noteType)"
            }
            let export: NoteGovernanceExportResponse = try await APIClient.shared.post(
                path: path,
                body: EmptyRequest()
            )
            await MainActor.run {
                self.noteGovernanceExport = export
                self.noteGovernanceExportMessage = "Exported \(export.totalItems) notes needing governance review."
            }
            await loadNotes(filter: filter)
        } catch {
            await MainActor.run {
                self.noteGovernanceErrorMessage = "Note governance export unavailable: \(error.localizedDescription)"
            }
        }
    }

    func generateStorageHygieneTicket() async {
        isGeneratingStorageHygieneTicket = true
        storageHygieneMessage = nil
        defer { isGeneratingStorageHygieneTicket = false }

        do {
            let response: StorageHygieneTicketResponse = try await APIClient.shared.post(
                path: "/api/v1/memory-organization/storage-hygiene-ticket",
                body: EmptyRequest()
            )
            await MainActor.run {
                let verb = response.created ? "Created" : "Updated"
                self.storageHygieneMessage = "\(verb) \(response.ticket.id): \(response.candidateCount) candidates, \(Self.byteCount(response.totalSizeBytes))."
            }
        } catch {
            await MainActor.run {
                self.storageHygieneMessage = "Storage hygiene ticket unavailable: \(error.localizedDescription)"
            }
        }
    }

    func generateMemoryPromotionTicket() async {
        isGeneratingMemoryPromotionTicket = true
        memoryPromotionMessage = nil
        defer { isGeneratingMemoryPromotionTicket = false }

        do {
            let response: MemoryPromotionTicketResponse = try await APIClient.shared.post(
                path: "/api/v1/daily-log-extractions/promotion-review-ticket",
                body: EmptyRequest()
            )
            await MainActor.run {
                let verb = response.created ? "Created" : "Updated"
                self.memoryPromotionMessage = "\(verb) \(response.ticket.id): \(response.candidateCount) candidates."
            }
        } catch {
            await MainActor.run {
                self.memoryPromotionMessage = "Memory promotion review unavailable: \(error.localizedDescription)"
            }
        }
    }

    func approveMemoryCandidate(_ candidate: DailyLogExtractionCandidate, target: String, targetPath: String? = nil) async {
        guard let candidateId = candidate.candidateId, !candidateId.isEmpty else { return }
        await MainActor.run {
            memoryActionCandidateIds.insert(candidateId)
            memoryActionMessage = nil
        }
        defer {
            Task { @MainActor in
                self.memoryActionCandidateIds.remove(candidateId)
            }
        }

        do {
            let path = "/api/v1/memory/candidates/\(candidateId)/approve"
            let response: MemoryCandidateActionResponse = try await APIClient.shared.post(
                path: path,
                body: MemoryApproveRequest(
                    reviewer: reviewerIdentity,
                    target: target,
                    targetPath: targetPath,
                    reviewerNotes: "Approved from Pod Knowledge.",
                    editText: nil
                )
            )
            await MainActor.run {
                self.replaceMemoryCandidate(response.candidate)
                let lifecycle = response.candidate.effectiveLifecycle.replacingOccurrences(of: "_", with: " ")
                self.memoryActionMessage = "Candidate \(candidateId) \(lifecycle)."
            }
        } catch {
            await MainActor.run {
                self.memoryActionMessage = "Memory approve unavailable: \(error.localizedDescription)"
            }
        }
    }

    func rejectMemoryCandidate(_ candidate: DailyLogExtractionCandidate) async {
        guard let candidateId = candidate.candidateId, !candidateId.isEmpty else { return }
        await MainActor.run {
            memoryActionCandidateIds.insert(candidateId)
            memoryActionMessage = nil
        }
        defer {
            Task { @MainActor in
                self.memoryActionCandidateIds.remove(candidateId)
            }
        }

        do {
            let path = "/api/v1/memory/candidates/\(candidateId)/reject"
            let response: MemoryCandidateActionResponse = try await APIClient.shared.post(
                path: path,
                body: MemoryRejectRequest(
                    reviewer: reviewerIdentity,
                    reason: "Rejected from Pod Knowledge review.",
                    visibleToOriginator: true
                )
            )
            await MainActor.run {
                self.replaceMemoryCandidate(response.candidate)
                self.memoryActionMessage = "Candidate \(candidateId) rejected."
            }
        } catch {
            await MainActor.run {
                self.memoryActionMessage = "Memory reject unavailable: \(error.localizedDescription)"
            }
        }
    }

    func deferMemoryCandidate(_ candidate: DailyLogExtractionCandidate) async {
        guard let candidateId = candidate.candidateId, !candidateId.isEmpty else { return }
        await MainActor.run {
            memoryActionCandidateIds.insert(candidateId)
            memoryActionMessage = nil
        }
        defer {
            Task { @MainActor in
                self.memoryActionCandidateIds.remove(candidateId)
            }
        }

        do {
            let path = "/api/v1/memory/candidates/\(candidateId)/defer"
            let response: MemoryCandidateActionResponse = try await APIClient.shared.post(
                path: path,
                body: MemoryDeferRequest(
                    reviewer: reviewerIdentity,
                    reason: "Deferred from Pod Knowledge review.",
                    deferUntil: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                )
            )
            await MainActor.run {
                self.replaceMemoryCandidate(response.candidate)
                self.memoryActionMessage = "Candidate \(candidateId) deferred."
            }
        } catch {
            await MainActor.run {
                self.memoryActionMessage = "Memory defer unavailable: \(error.localizedDescription)"
            }
        }
    }

    private func replaceMemoryCandidate(_ updated: DailyLogExtractionCandidate) {
        if let queue = memoryCandidateQueue {
            let updatedItems = queue.items.map { candidate in
                candidate.id == updated.id ? updated : candidate
            }
            let byLifecycle = Dictionary(grouping: updatedItems, by: \.effectiveLifecycle).mapValues(\.count)
            let bySensitivityClass = Dictionary(grouping: updatedItems, by: { $0.sensitivityClass ?? "unknown" }).mapValues(\.count)
            let byReviewState = Dictionary(grouping: updatedItems, by: { $0.reviewState ?? "unknown" }).mapValues(\.count)
            memoryCandidateQueue = MemoryCandidateQueueResponse(
                artifactPath: queue.artifactPath,
                artifactUpdatedAt: queue.artifactUpdatedAt,
                generatedAt: queue.generatedAt,
                summary: MemoryCandidateQueueSummary(
                    total: updatedItems.count,
                    byLifecycle: byLifecycle,
                    bySensitivityClass: bySensitivityClass,
                    byReviewState: byReviewState
                ),
                items: updatedItems,
                ops: queue.ops,
                overlayPath: queue.overlayPath,
                auditPath: queue.auditPath,
                exportDir: queue.exportDir
            )
        }
        guard var extraction = dailyLogExtraction else { return }
        extraction = DailyLogExtractionResponse(
            artifactPath: extraction.artifactPath,
            artifactUpdatedAt: extraction.artifactUpdatedAt,
            generatedAt: extraction.generatedAt,
            summary: extraction.summary,
            records: extraction.records,
            candidateMemoryItems: extraction.candidateMemoryItems.map { candidate in
                candidate.id == updated.id ? updated : candidate
            }
        )
        dailyLogExtraction = extraction
    }

    private static func byteCount(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    func exportReviewSync() async {
        isExportingReviewSync = true
        reviewQueueErrorMessage = nil
        reviewSyncMessage = nil

        do {
            let export: DoctrineReviewSyncExportResponse = try await APIClient.shared.post(
                path: "/api/v1/doc-registry/review-sync/export",
                body: EmptyRequest()
            )
            await MainActor.run {
                self.reviewSyncMessage = "Exported \(export.total) decisions: \(export.exportId)"
                self.isExportingReviewSync = false
            }
            await loadReviewSyncPreview()
        } catch {
            await MainActor.run {
                self.reviewQueueErrorMessage = error.localizedDescription
                self.isExportingReviewSync = false
            }
        }
    }

    func exportRuntimeSync() async {
        isExportingRuntimeSync = true
        runtimeReviewQueueErrorMessage = nil
        runtimeSyncMessage = nil

        do {
            let export: RuntimeClassificationSyncExportResponse = try await APIClient.shared.post(
                path: "/api/v1/runtime-registry/classification-sync/export",
                body: EmptyRequest()
            )
            await MainActor.run {
                self.runtimeSyncMessage = export.message.isEmpty
                    ? "Exported \(export.total) runtime decisions: \(export.exportId)"
                    : export.message
                self.isExportingRuntimeSync = false
            }
            await loadRuntimeSyncPreview()
        } catch {
            await MainActor.run {
                self.runtimeReviewQueueErrorMessage = error.localizedDescription
                self.isExportingRuntimeSync = false
            }
        }
    }

    func exportRuntimeBurnDown() async {
        isExportingRuntimeBurnDown = true
        runtimeReviewQueueErrorMessage = nil
        runtimeBurnDownMessage = nil

        do {
            let export: RuntimeBurnDownExportResponse = try await APIClient.shared.post(
                path: "/api/v1/runtime-registry/burn-down/export",
                body: EmptyRequest()
            )
            await MainActor.run {
                self.runtimeBurnDownMessage = "Exported \(export.total) units, \(export.needsFollowup) needing follow-up: \(export.exportId)"
                self.isExportingRuntimeBurnDown = false
            }
            await loadRuntimeSyncPreview()
        } catch {
            await MainActor.run {
                self.runtimeReviewQueueErrorMessage = error.localizedDescription
                self.isExportingRuntimeBurnDown = false
            }
        }
    }

    func applyReviewAction(_ action: DoctrineReviewAction, to item: DocRegistryItem) async {
        reviewActionInFlightDocId = item.id
        reviewQueueErrorMessage = nil
        reviewActionMessage = nil

        let note: String
        switch action {
        case .promoteToCanonical:
            note = "Approved from Pod doctrine review queue."
        case .markDraft:
            note = "Marked draft from Pod doctrine review queue."
        case .markSuperseded:
            note = "Marked superseded from Pod doctrine review queue."
        case .markArchived:
            note = "Marked archived from Pod doctrine review queue."
        case .keepQuarantined:
            note = "Kept quarantined from Pod doctrine review queue."
        }

        let request = DoctrineReviewActionRequest(
            docId: item.id,
            action: action,
            reviewer: reviewerIdentity,
            note: note,
            requiredForAgents: action == .promoteToCanonical ? [] : nil,
            enforcedByPetal: nil
        )

        do {
            let response: DoctrineReviewActionResponse = try await APIClient.shared.post(
                path: "/api/v1/doc-registry/review-actions",
                body: request
            )
            await MainActor.run {
                self.reviewActionMessage = "\(response.doc.title): \(response.doctrineStatus)"
                self.reviewActionInFlightDocId = nil
            }
            await loadDocRegistry()
            await loadReviewQueue()
            await loadReviewSyncPreview()
        } catch {
            await MainActor.run {
                self.reviewQueueErrorMessage = error.localizedDescription
                self.reviewActionInFlightDocId = nil
            }
        }
    }

    func loadStandard(id: UUID) async -> Standard? {
        do {
            let standard: Standard = try await APIClient.shared.get(path: "/api/v1/standards/\(id.uuidString)")
            await MainActor.run {
                if let idx = standards.firstIndex(where: { $0.id == id }) {
                    standards[idx] = standard
                } else {
                    standards.append(standard)
                }
                addToRecent(standard)
            }
            return standard
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    // MARK: - Create

    func createStandard(_ standard: Standard) async -> Bool {
        do {
            let created: Standard = try await APIClient.shared.post(
                path: "/api/v1/standards",
                body: standard
            )
            await MainActor.run {
                standards.append(created)
                self.recomputeDerived()
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Update

    func updateStandard(_ standard: Standard) async -> Bool {
        do {
            let updated: Standard = try await APIClient.shared.put(
                path: "/api/v1/standards/\(standard.id.uuidString)",
                body: standard
            )
            await MainActor.run {
                if let idx = standards.firstIndex(where: { $0.id == standard.id }) {
                    standards[idx] = updated
                }
                self.recomputeDerived()
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Delete

    func deleteStandard(id: UUID) async -> Bool {
        do {
            try await APIClient.shared.delete(path: "/api/v1/standards/\(id.uuidString)")
            await MainActor.run {
                standards.removeAll { $0.id == id }
                self.recomputeDerived()
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Favorite

    func toggleFavorite(id: UUID) async {
        if let idx = standards.firstIndex(where: { $0.id == id }) {
            standards[idx].isFavorite.toggle()
            await MainActor.run {
                recomputeDerived()
                persistFavorites()
            }
        }
    }

    // MARK: - Search

    func searchStandards(_ query: String) async -> [Standard] {
        guard !query.isEmpty else { return [] }

        do {
            let results: [Standard] = try await APIClient.shared.get(
                path: "/api/v1/standards/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
            )
            return results
        } catch {
            return []
        }
    }

    // MARK: - Recent

    private func addToRecent(_ standard: Standard) {
        recentStandards.removeAll { $0.id == standard.id }
        recentStandards.insert(standard, at: 0)
        if recentStandards.count > 20 {
            recentStandards = Array(recentStandards.prefix(20))
        }
        persistRecent()
    }

    private func loadRecentStandards() {
        if let data = UserDefaults.standard.data(forKey: recentStorageKey),
           let decoded = try? JSONDecoder().decode([Standard].self, from: data) {
            recentStandards = decoded
        }
    }

    private func persistRecent() {
        if let encoded = try? JSONEncoder().encode(recentStandards) {
            UserDefaults.standard.set(encoded, forKey: recentStorageKey)
        }
    }

    // MARK: - Favorites

    private func loadLocalFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesStorageKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            let ids = Set(decoded)
            for i in standards.indices {
                standards[i].isFavorite = ids.contains(standards[i].id)
            }
        }
    }

    private func persistFavorites() {
        let ids = standards.filter(\.isFavorite).map(\.id)
        if let encoded = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(encoded, forKey: favoritesStorageKey)
        }
    }

    // MARK: - Derived

    private func recomputeDerived() {
        favoriteStandards = standards.filter(\.isFavorite)
    }

    // MARK: - Helpers

    func standard(for id: UUID) -> Standard? {
        standards.first { $0.id == id }
    }

    func relatedStandards(for standard: Standard) -> [Standard] {
        standard.relatedStandardIds.compactMap { id in
            standards.first { $0.id == id }
        }
    }

    // MARK: - Mock Data Safe Access

    /// Access MockData.standards with a safety wrapper.
    /// Note: SIGTRAP crashes in static init cannot be caught — this is a best-effort fallback.
    private static func safeMockStandards() -> [Standard] {
        let novaId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001") ?? UUID()
        let now = Date()

        return [
            Standard(
                id: UUID(uuidString: "BBBBBBBB-0001-0000-0000-000000000001") ?? UUID(),
                title: "SOP-001: Submitting a Ticket to Maui",
                category: .playbooks,
                content: """
# CHEAT-SOP-001: Submitting a Ticket to Maui

**For:** All agents | **Full SOP:** `docs/SOP/SOP-001-SUBMITTING-TICKETS.md`

---

## What Your Ticket Needs

- **Title** — one line, 80 chars max
- **Type** — `feature` | `bugfix` | `script` | `data_pipeline` | `research` | `refactor`
- **Priority** — `critical` | `high` | `normal` | `low`
- **Description** — what needs to be built or fixed
- **Acceptance Criteria** — at least 2 checkable conditions that prove it's done

---

## Where the Template Lives

```
~/.openclaw/workspace/tickets/TEMPLATE.md
```

Copy it. Name your file: `TICKET-NNN-short-name.md`
Drop it in: `~/.openclaw/workspace/tickets/`

---

## NATS Subjects

| Direction | Subject |
|-----------|---------|
| New ticket → Maui | Drop file + Aloha fires `service-requests.created` |
| Maui claims it | `service-requests.claimed` |
| Progress updates | `service-requests.progress` |
| Direct message to Maui | `agents.maui.query` |

---

## What Happens Next

1. Aloha detects new ticket file → notifies Maui via NATS
2. Maui reads it and opens a Stage 2 review conversation with you
3. You confirm scope → Stage 3 approval (you say yes before any code starts)
4. Maui writes a pre-work doc, then executes
5. Maui notifies you when done → you test → you sign off → Aloha closes it

---

**Key Rule: No sign-off from you = ticket stays open. Aloha does not close without confirmation.**
""",
                authorId: novaId,
                authorName: "Nova",
                tags: ["tickets", "workflow", "maui", "sop"],
                version: 1,
                createdAt: now,
                updatedAt: now,
                isFavorite: false
            ),

            Standard(
                id: UUID(uuidString: "BBBBBBBB-0002-0000-0000-000000000001") ?? UUID(),
                title: "SOP-002: Maui's Engineering Workflow",
                category: .playbooks,
                content: """
# CHEAT-SOP-002: Maui's Engineering Workflow

**For:** Maui (primary) + anyone tracking a ticket | **Full SOP:** `docs/SOP/SOP-ENGINEERING-TICKET-WORKFLOW.md`

---

## The 6-Stage Flow

```
[1] TICKET CREATED ──▶ [2] MAUI REVIEWS ──▶ [3] REQUESTER APPROVES
                                                       │
                              ┌────────────────────────┘
                              ▼
                      [4] MAUI DOCUMENTS INTENT
                              │
                              ▼
                          [5] EXECUTE
                              │
                              ▼
                      [6] SIGN-OFF → CLOSED
```

---

## One Line Per Stage

| Stage | Who Acts | Output |
|-------|----------|--------|
| 1 — Ticket Created | Requester | File at `~/.openclaw/workspace/tickets/TICKET-NNN.md` |
| 2 — Maui Reviews | Maui + Requester | Questions answered, scope confirmed |
| 3 — Approach Approved | Requester | Explicit go-ahead (NATS or direct) |
| 4 — Pre-Work Doc | Maui | `~/.openclaw/workspace-maui/docs/WORK-TICKET-NNN.md` |
| 5 — Execute | Maui | Code + progress updates via NATS |
| 6 — Sign-Off | Requester | Confirms done → Aloha closes + archives |

---

## Key Rule

> **No code before Stage 3 approval. No exceptions.**

---

## NATS Subjects (Progress Updates)

| Event | Subject |
|-------|---------|
| Ticket detected | `service-requests.created` (Aloha publishes) |
| Maui claims ticket | `service-requests.claimed` |
| Progress (25/50/75/100%) | `service-requests.progress` |
| Reach Maui directly | `agents.maui.query` |

---

**Stalled ticket?** Aloha pings if any stage sits >24h without movement. Escalates to Shaka after 48h at `todo`.
""",
                authorId: novaId,
                authorName: "Nova",
                tags: ["engineering", "maui", "workflow", "sop"],
                version: 1,
                createdAt: now,
                updatedAt: now,
                isFavorite: false
            ),

            Standard(
                id: UUID(uuidString: "BBBBBBBB-0003-0000-0000-000000000001") ?? UUID(),
                title: "Ticket Lifecycle: Visual Reference",
                category: .runbooks,
                content: """
# CHEAT: Ticket Lifecycle

**For:** Everyone | Visual reference for the full journey of any engineering ticket.

---

## Full Lifecycle

```
REQUESTER                 MAUI                    ALOHA

Creates ticket            ·                       ·
TICKET-NNN.md  ─────────────────────────────▶  Detects file
                          ·                    Fires NATS →
                          ◀────────────────────────────────
                  Stage 2: Reviews ticket
                  Asks clarifying questions ──▶
Answers questions ◀──────

Stage 3: APPROVAL ───────▶ Maui gets go-ahead
(sign-off #1)              No code until this happens

                          Stage 4: Writes pre-work doc
                          WORK-TICKET-NNN.md

                          Stage 5: Executes work
                          Progress via NATS (25/50/75/100%)

                  "Done. Please review." ───────────────▶
Reviews + tests ◀──────────────────────────────────────

Stage 6: SIGN-OFF ───────────────────────────▶ Aloha closes
(sign-off #2)                                  Archives ticket
                                               Work doc = perm record
```

---

## Status Flow

```
todo → in-review → approved → in-progress → done
                                           (or cancelled)
```

---

## Sign-Off Requirements

| # | Who Signs | What They're Approving |
|---|-----------|------------------------|
| 1 | Requester | Maui's proposed approach (Stage 3) |
| 2 | Requester | Completed deliverable (Stage 6) |

**Aloha will not close a ticket without sign-off #2 confirmed.**
""",
                authorId: novaId,
                authorName: "Nova",
                tags: ["tickets", "lifecycle", "workflow", "reference"],
                version: 1,
                createdAt: now,
                updatedAt: now,
                isFavorite: false
            ),
        ]
    }
}
