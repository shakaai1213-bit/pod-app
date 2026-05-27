import Foundation
import SwiftUI

// MARK: - Ticket Domain Model

struct Ticket: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let description: String?
    let status: TicketStatus
    let priority: TicketPriority
    let assigneeAgentId: String?
    let assigneeAgentName: String?
    let ticketType: String?
    let tags: [String]?
    let source: String?
    let sourceChatURL: String?
    let sourceThreadURL: String?
    let computeTag: String?
    let approvalState: String?
    let approvalGate: String?
    let autonomyLevel: String?
    let workerLane: String?
    let toolPolicy: String?
    let acceptanceCriteria: [String]?
    let desiredOutcome: String?
    let triageId: String?
    let triageTraceId: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let chatThreadId: String?
    let parentTicketId: String?       // POD-4: subtask hierarchy
    let lessonsLearned: String?       // POD-4: lessons-learned capture
    let createdAt: Date
    let updatedAt: Date
    let claimedAt: Date?
    let startedAt: Date?
    let resolvedAt: Date?
    let resolutionNotes: String?

    init(
        id: String,
        title: String,
        description: String?,
        status: TicketStatus,
        priority: TicketPriority,
        assigneeAgentId: String?,
        assigneeAgentName: String?,
        ticketType: String?,
        tags: [String]?,
        source: String? = nil,
        sourceChatURL: String? = nil,
        sourceThreadURL: String? = nil,
        computeTag: String?,
        approvalState: String? = nil,
        approvalGate: String? = nil,
        autonomyLevel: String? = nil,
        workerLane: String? = nil,
        toolPolicy: String? = nil,
        acceptanceCriteria: [String]? = nil,
        desiredOutcome: String? = nil,
        triageId: String? = nil,
        triageTraceId: String? = nil,
        recommendedRuntime: String? = nil,
        recommendedSurface: String? = nil,
        runtimeReason: String? = nil,
        handoffSubject: String? = nil,
        chatThreadId: String? = nil,
        parentTicketId: String?,
        lessonsLearned: String?,
        createdAt: Date,
        updatedAt: Date,
        claimedAt: Date?,
        startedAt: Date?,
        resolvedAt: Date?,
        resolutionNotes: String?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.assigneeAgentId = assigneeAgentId
        self.assigneeAgentName = assigneeAgentName
        self.ticketType = ticketType
        self.tags = tags
        self.source = source
        self.sourceChatURL = sourceChatURL
        self.sourceThreadURL = sourceThreadURL
        self.computeTag = computeTag
        self.approvalState = approvalState
        self.approvalGate = approvalGate
        self.autonomyLevel = autonomyLevel
        self.workerLane = workerLane
        self.toolPolicy = toolPolicy
        self.acceptanceCriteria = acceptanceCriteria
        self.desiredOutcome = desiredOutcome
        self.triageId = triageId
        self.triageTraceId = triageTraceId
        self.recommendedRuntime = recommendedRuntime
        self.recommendedSurface = recommendedSurface
        self.runtimeReason = runtimeReason
        self.handoffSubject = handoffSubject
        self.chatThreadId = chatThreadId
        self.parentTicketId = parentTicketId
        self.lessonsLearned = lessonsLearned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.claimedAt = claimedAt
        self.startedAt = startedAt
        self.resolvedAt = resolvedAt
        self.resolutionNotes = resolutionNotes
    }
}

struct TicketComment: Identifiable, Sendable, Hashable {
    let id: String
    let ticketId: String?
    let message: String
    let agentId: String?
    let eventType: String
    let traceId: String?
    let source: String?
    let lane: String?
    let createdAt: Date
}

struct TicketNoteRecord: Identifiable, Sendable, Hashable {
    let id: String
    let targetType: String
    let targetId: String?
    let noteType: String
    let title: String
    let body: String
    let tags: [String]
    let createdBy: String?
    let source: String?
    let traceId: String?
    let owner: String?
    let reviewer: String?
    let signState: String?
    let createdAt: Date
    let updatedAt: Date

    var typeLabel: String {
        noteType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct TicketApprovalRecord: Identifiable, Sendable, Hashable {
    let id: String
    let ticketId: String
    let boardId: String
    let actionType: String
    let status: String
    let confidence: Double
    let reason: String?
    let source: String?
    let lane: String?
    let traceId: String?
    let createdAt: Date
    let resolvedAt: Date?
    let linkedAt: Date

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct ApprovalRegistryResponse: Decodable, Sendable, Hashable {
    let actionTypes: [String: ApprovalRegistrySpec]
    let count: Int
    let schemaVersion: String?

    enum CodingKeys: String, CodingKey {
        case count
        case actionTypes = "action_types"
        case schemaVersion = "schema_version"
    }
}

struct ApprovalRegistrySpec: Decodable, Sendable, Hashable {
    let authority: String?
    let secondary: String?
    let noCascade: Bool
    let description: String?

    enum CodingKeys: String, CodingKey {
        case authority, secondary, description
        case noCascade = "no_cascade"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authority = try container.decodeIfPresent(String.self, forKey: .authority)
        secondary = try container.decodeIfPresent(String.self, forKey: .secondary)
        noCascade = try container.decodeIfPresent(Bool.self, forKey: .noCascade) ?? false
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    var authorityLabel: String {
        let primary = authority?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryValue = secondary?.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if let primary, !primary.isEmpty {
            parts.append("authority \(primary)")
        }
        if let secondaryValue, !secondaryValue.isEmpty, !noCascade {
            parts.append("fallback \(secondaryValue)")
        }
        if noCascade {
            parts.append("no cascade")
        }
        return parts.isEmpty ? "authority not declared" : parts.joined(separator: " / ")
    }
}

enum AgentRunJSONValue: Decodable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AgentRunJSONValue])
    case array([AgentRunJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AgentRunJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AgentRunJSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var displayValue: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return "\(value)"
        case .double(let value): return "\(value)"
        case .bool(let value): return value ? "true" : "false"
        case .object(let value): return "\(value.count) fields"
        case .array(let value): return "\(value.count) items"
        case .null: return "null"
        }
    }
}

struct AgentRun: Identifiable, Sendable, Hashable {
    let id: String
    let ticketId: String
    let agentId: String?
    let status: AgentRunStatus
    let runType: String
    let traceId: String?
    let computeTag: String?
    let caller: String?
    let source: String?
    let lane: String?
    let workerLane: String?
    let toolPolicy: String?
    let backend: String?
    let model: String?
    let tier: String?
    let latencyMs: Int?
    let tokenCount: Int?
    let inputSummary: String?
    let outcome: String?
    let evidence: String?
    let error: String?
    let artifacts: [String: AgentRunJSONValue]?
    let guardrails: [String: AgentRunJSONValue]?
    let reviewStatus: String?
    let reviewedBy: String?
    let reviewedAt: Date?
    let reviewNote: String?
    let createdAt: Date
    let updatedAt: Date
    let startedAt: Date?
    let completedAt: Date?

    var elapsedLabel: String? {
        let end = completedAt ?? (status == .running ? Date() : nil)
        guard let startedAt, let end else { return nil }
        let seconds = max(0, Int(end.timeIntervalSince(startedAt)))
        if seconds < 60 { return "\(seconds)s elapsed" }
        if seconds < 3_600 { return "\(seconds / 60)m elapsed" }
        return "\(seconds / 3_600)h elapsed"
    }

    var hasReviewEvidence: Bool {
        let hasEvidenceText = evidence?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasOutcomeText = outcome?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasArtifacts = artifacts?.isEmpty == false
        return hasEvidenceText || hasOutcomeText || hasArtifacts
    }

    var operationalSourceLabel: String? {
        let parts = [
            backend.map { "backend \($0)" },
            model.map { "model \($0)" },
            tier.map { "tier \($0)" }
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.prefix(3).joined(separator: " / ")
    }

    var operationalRouteLabel: String {
        let parts = [
            runType.replacingOccurrences(of: "_", with: " "),
            workerLane.map { "worker \($0)" },
            toolPolicy.map { "policy \($0)" },
            source.map { "source \($0)" }
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.prefix(4).joined(separator: " / ")
    }

    var runtimeHandoffLabel: String? {
        let runtime = routeValue("recommended_runtime")
        let surface = routeValue("recommended_surface")
        let subject = routeValue("handoff_subject")
        guard let runtime, !runtime.isEmpty else { return nil }
        let surfaceText = (surface?.isEmpty == false) ? " via \(surface!)" : ""
        let subjectText = (subject?.isEmpty == false) ? " · \(subject!)" : ""
        return "\(runtime)\(surfaceText)\(subjectText)"
    }

    private func routeValue(_ key: String) -> String? {
        if let value = guardrails?[key]?.displayValue, !value.isEmpty, value != "null" {
            return value
        }
        if let value = artifacts?[key]?.displayValue, !value.isEmpty, value != "null" {
            return value
        }
        if case .object(let route)? = artifacts?["runtime_route"],
           let value = route[key]?.displayValue,
           !value.isEmpty,
           value != "null" {
            return value
        }
        return nil
    }
}

struct AgentRunTraceEvent: Identifiable, Sendable, Hashable {
    let id: String
    let ticketId: String?
    let eventType: String
    let message: String
    let source: String?
    let lane: String?
    let createdAt: Date
}

struct AgentRunTrace: Sendable, Hashable {
    let traceId: String
    let agentRuns: [AgentRun]
    let events: [AgentRunTraceEvent]
    let computeRuns: [ComputeRunRecord]
    let chatMessages: [AgentRunTraceChatMessage]
    let notes: [TicketNoteRecord]
}

struct AgentRunArtifactSummary: Identifiable, Sendable, Hashable {
    var id: String { key }
    let key: String
    let value: String
    let kind: String
    let safeToPreview: Bool
    let exists: Bool?
    let sizeBytes: Int?
    let preview: String?
    let reason: String?
}

struct ComputeRunRecord: Identifiable, Sendable, Hashable {
    let id: String
    let traceId: String?
    let surface: String
    let taskHint: String
    let route: String
    let requestedRoute: String?
    let actualTier: String?
    let actualBackend: String?
    let model: String?
    let backend: String?
    let status: String
    let fallbackUsed: Bool
    let latencyMs: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let outputPreview: String?
    let error: String?
    let createdAt: Date
}

struct AgentRunTraceChatMessage: Identifiable, Sendable, Hashable {
    let id: String
    let channelId: String
    let content: String
    let messageType: String
    let source: String?
    let lane: String?
    let deliveryMode: String?
    let provenance: String?
    let responseState: String?
    let triageId: String?
    let triageTraceId: String?
    let createdAt: Date
}

struct BacklogGroomingSummary: Decodable, Sendable, Hashable {
    let total: Int
    let counts: [String: Int]
    let countsByReviewAction: [String: Int]?
    let countsBySuggestedOwner: [String: Int]?
    let items: [BacklogGroomingItem]

    var keepCount: Int { counts["keep", default: 0] }
    var needsHumanCount: Int { counts["needs-human", default: 0] }
    var staleTestCount: Int { counts["stale-test", default: 0] }
    var duplicateCount: Int { counts["duplicate", default: 0] }
    var supersededCount: Int { counts["superseded", default: 0] }

    var reviewActionCounts: [String: Int] { countsByReviewAction ?? [:] }
    var suggestedOwnerCounts: [String: Int] { countsBySuggestedOwner ?? [:] }

    enum CodingKeys: String, CodingKey {
        case total
        case counts
        case countsByReviewAction = "counts_by_review_action"
        case countsBySuggestedOwner = "counts_by_suggested_owner"
        case items
    }
}

struct BacklogGroomingItem: Decodable, Identifiable, Sendable, Hashable {
    let ticketId: String
    let title: String
    let status: String
    let classification: String
    let reason: String
    let confidence: String?
    let signals: [String]?
    let duplicateTicketIds: [String]?
    let suggestedOwner: String?
    let suggestedWorkerLane: String?
    let suggestedToolPolicy: String?
    let suggestedApprovalState: String?
    let suggestedApprovalGate: String?
    let suggestedAutonomyLevel: String?
    let assignmentSuggestion: BacklogAssignmentSuggestion?
    let healthFlags: [String]?
    let existingCommentCount: Int?
    let latestCommentAt: Date?
    let latestCommentPreview: String?
    let commentsFirstReview: Bool?
    let reviewAction: String?
    let reprocessPreview: String?

    var id: String { ticketId }

    enum CodingKeys: String, CodingKey {
        case ticketId = "ticket_id"
        case title
        case status
        case classification
        case reason
        case confidence
        case signals
        case duplicateTicketIds = "duplicate_ticket_ids"
        case suggestedOwner = "suggested_owner"
        case suggestedWorkerLane = "suggested_worker_lane"
        case suggestedToolPolicy = "suggested_tool_policy"
        case suggestedApprovalState = "suggested_approval_state"
        case suggestedApprovalGate = "suggested_approval_gate"
        case suggestedAutonomyLevel = "suggested_autonomy_level"
        case assignmentSuggestion = "assignment_suggestion"
        case healthFlags = "health_flags"
        case existingCommentCount = "existing_comment_count"
        case latestCommentAt = "latest_comment_at"
        case latestCommentPreview = "latest_comment_preview"
        case commentsFirstReview = "comments_first_review"
        case reviewAction = "review_action"
        case reprocessPreview = "reprocess_preview"
    }
}

struct BacklogAssignmentSuggestion: Decodable, Sendable, Hashable {
    let owner: String?
    let routeReason: String?
    let workerLane: String?
    let toolPolicy: String?
    let approvalState: String?
    let approvalGate: String?
    let autonomyLevel: String?

    enum CodingKeys: String, CodingKey {
        case owner
        case routeReason = "route_reason"
        case workerLane = "worker_lane"
        case toolPolicy = "tool_policy"
        case approvalState = "approval_state"
        case approvalGate = "approval_gate"
        case autonomyLevel = "autonomy_level"
    }
}

struct BacklogGroomingCommentRequest: Encodable, Sendable {
    let limit: Int
    let includeClosed: Bool
    let force: Bool
}

struct BacklogGroomingCommentResult: Decodable, Sendable, Hashable {
    let total: Int
    let commented: Int
    let skippedExisting: Int
    let counts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case total
        case commented
        case skippedExisting = "skipped_existing"
        case counts
    }
}

struct WorkControlBackfillSummary: Decodable, Sendable, Hashable {
    let total: Int
    let needsBackfill: Int
    let clean: Int
    let countsByMissingField: [String: Int]
    let items: [WorkControlBackfillItem]

    enum CodingKeys: String, CodingKey {
        case total
        case needsBackfill = "needs_backfill"
        case clean
        case countsByMissingField = "counts_by_missing_field"
        case items
    }
}

struct WorkControlBackfillItem: Decodable, Identifiable, Sendable, Hashable {
    let ticketId: String
    let title: String
    let status: String
    let classification: String
    let missingFields: [String]
    let healthFlags: [String]
    let notes: [String]

    var id: String { ticketId }

    enum CodingKeys: String, CodingKey {
        case ticketId = "ticket_id"
        case title
        case status
        case classification
        case missingFields = "missing_fields"
        case healthFlags = "health_flags"
        case notes
    }
}

struct WorkControlIntegritySummary: Decodable, Sendable, Hashable {
    let total: Int
    let clean: Int
    let issues: Int
    let countsByIssue: [String: Int]
    let countsByField: [String: Int]
    let items: [WorkControlIntegrityItem]

    var sourceLinkGapCount: Int {
        let itemCount = items.filter(\.hasSourceLinkGap).count
        if itemCount > 0 { return itemCount }
        return countsByField["source_chat_or_thread_link"]
            ?? countsByIssue["source_chat_or_thread_link"]
            ?? 0
    }

    var triageLinkGapCount: Int {
        let itemCount = items.filter(\.hasTriageLinkGap).count
        if itemCount > 0 { return itemCount }
        return max(
            countsByField["triage_id"] ?? countsByIssue["triage_id"] ?? 0,
            countsByField["triage_trace_id"] ?? countsByIssue["triage_trace_id"] ?? 0
        )
    }

    var otherGapCount: Int {
        max(0, issues - sourceLinkGapCount - triageLinkGapCount)
    }

    enum CodingKeys: String, CodingKey {
        case total
        case clean
        case complete
        case passed
        case valid
        case ok
        case issues
        case incomplete
        case failing
        case invalid
        case violations
        case needsReview = "needs_review"
        case counts
        case countsByMissingField = "counts_by_missing_field"
        case countsByIssue = "counts_by_issue"
        case countsByViolation = "counts_by_violation"
        case countsByProblem = "counts_by_problem"
        case countsByField = "counts_by_field"
        case items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([WorkControlIntegrityItem].self, forKey: .items) ?? []
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? items.count
        clean = try c.decodeIfPresent(Int.self, forKey: .clean)
            ?? c.decodeIfPresent(Int.self, forKey: .complete)
            ?? c.decodeIfPresent(Int.self, forKey: .passed)
            ?? c.decodeIfPresent(Int.self, forKey: .valid)
            ?? c.decodeIfPresent(Int.self, forKey: .ok)
            ?? max(0, total - items.count)
        countsByIssue = try c.decodeIfPresent([String: Int].self, forKey: .countsByIssue)
            ?? c.decodeIfPresent([String: Int].self, forKey: .countsByMissingField)
            ?? c.decodeIfPresent([String: Int].self, forKey: .countsByViolation)
            ?? c.decodeIfPresent([String: Int].self, forKey: .countsByProblem)
            ?? c.decodeIfPresent([String: Int].self, forKey: .counts)
            ?? [:]
        countsByField = try c.decodeIfPresent([String: Int].self, forKey: .countsByField)
            ?? c.decodeIfPresent([String: Int].self, forKey: .countsByMissingField)
            ?? [:]
        let issueCount = try c.decodeIfPresent(Int.self, forKey: .issues)
        let incompleteCount = try c.decodeIfPresent(Int.self, forKey: .incomplete)
        let failingCount = try c.decodeIfPresent(Int.self, forKey: .failing)
        let invalidCount = try c.decodeIfPresent(Int.self, forKey: .invalid)
        let violationCount = try c.decodeIfPresent(Int.self, forKey: .violations)
        let needsReviewCount = try c.decodeIfPresent(Int.self, forKey: .needsReview)
        let decodedIssues = issueCount ?? incompleteCount ?? failingCount ?? invalidCount ?? violationCount ?? needsReviewCount
        let countedIssues = countsByIssue.values.reduce(0, +)
        issues = decodedIssues ?? (countedIssues > 0 ? countedIssues : max(0, total - clean))
    }
}

struct WorkControlIntegrityItem: Decodable, Identifiable, Sendable, Hashable {
    let ticketId: String
    let title: String
    let status: String?
    let issues: [String]
    let fields: [String]
    let notes: [String]

    var id: String { ticketId }

    var hasSourceLinkGap: Bool {
        fields.contains("source_chat_or_thread_link")
            || fields.contains("source_chat_url")
            || fields.contains("source_thread_url")
            || issues.contains("source_chat_or_thread_link")
    }

    var hasTriageLinkGap: Bool {
        fields.contains("triage_id")
            || fields.contains("triage_trace_id")
            || issues.contains("triage_id")
            || issues.contains("triage_trace_id")
    }

    enum CodingKeys: String, CodingKey {
        case ticketId = "ticket_id"
        case id
        case title
        case status
        case issues
        case violations
        case problems
        case fields
        case issueFields = "issue_fields"
        case missingFields = "missing_fields"
        case notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ticketId = try c.decodeIfPresent(String.self, forKey: .ticketId)
            ?? c.decodeIfPresent(String.self, forKey: .id)
            ?? "unknown"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ticketId
        status = try c.decodeIfPresent(String.self, forKey: .status)
        issues = try c.decodeIfPresent([String].self, forKey: .issues)
            ?? c.decodeIfPresent([String].self, forKey: .violations)
            ?? c.decodeIfPresent([String].self, forKey: .problems)
            ?? []
        fields = try c.decodeIfPresent([String].self, forKey: .fields)
            ?? c.decodeIfPresent([String].self, forKey: .issueFields)
            ?? c.decodeIfPresent([String].self, forKey: .missingFields)
            ?? []
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

struct LegacyLinkageExportResult: Decodable, Sendable, Hashable {
    let message: String
    let path: String?
    let counts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case message
        case path
        case exportPath = "export_path"
        case filePath = "file_path"
        case artifactPath = "artifact_path"
        case markdownPath = "markdown_path"
        case counts
        case countsByMissingField = "counts_by_missing_field"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? "Legacy linkage export completed."
        let directPath = try c.decodeIfPresent(String.self, forKey: .path)
        let exportPath = try c.decodeIfPresent(String.self, forKey: .exportPath)
        let filePath = try c.decodeIfPresent(String.self, forKey: .filePath)
        let artifactPath = try c.decodeIfPresent(String.self, forKey: .artifactPath)
        let markdownPath = try c.decodeIfPresent(String.self, forKey: .markdownPath)
        path = directPath ?? exportPath ?? filePath ?? artifactPath ?? markdownPath

        let directCounts = try c.decodeIfPresent([String: Int].self, forKey: .counts)
        let missingFieldCounts = try c.decodeIfPresent([String: Int].self, forKey: .countsByMissingField)
        counts = directCounts ?? missingFieldCounts ?? [:]
    }
}

enum AgentRunStatus: String, Sendable, CaseIterable {
    case queued
    case running
    case succeeded
    case failed
    case blocked
    case waitingForHuman = "waiting_for_human"
    case retrying
    case cancelled

    var label: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var icon: String {
        switch self {
        case .queued:    return "clock"
        case .running:   return "bolt.circle.fill"
        case .succeeded: return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        case .blocked:   return "hand.raised.fill"
        case .waitingForHuman: return "person.crop.circle.badge.exclamationmark"
        case .retrying:  return "arrow.triangle.2.circlepath"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .queued:    return AppColors.textTertiary
        case .running:   return AppColors.accentAgent
        case .succeeded: return AppColors.accentSuccess
        case .failed:    return AppColors.accentDanger
        case .blocked:   return Color.orange
        case .waitingForHuman: return Color.orange
        case .retrying:  return AppColors.accentAgent
        case .cancelled: return AppColors.textTertiary
        }
    }
}

enum TicketStatus: String, Sendable, CaseIterable {
    case open
    case claimed
    case inProgress = "in_progress"
    case closed
    case cancelled

    var label: String {
        switch self {
        case .open:       return "Open"
        case .claimed:    return "Claimed"
        case .inProgress: return "In Progress"
        case .closed:     return "Closed"
        case .cancelled:  return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .open:       return AppColors.accentElectric
        case .claimed:    return AppColors.accentAgent
        case .inProgress: return AppColors.accentAgent
        case .closed:     return AppColors.accentSuccess
        case .cancelled:  return AppColors.textTertiary
        }
    }

    var icon: String {
        switch self {
        case .open:       return "circle"
        case .claimed:    return "hand.raised.fill"
        case .inProgress: return "arrow.clockwise.circle.fill"
        case .closed:     return "checkmark.circle.fill"
        case .cancelled:  return "xmark.circle.fill"
        }
    }

    var isTerminal: Bool {
        self == .closed || self == .cancelled
    }
}

enum TicketPriority: String, Sendable, CaseIterable {
    case low
    case normal
    case medium
    case high
    case urgent

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .low:    return AppColors.textTertiary
        case .normal: return AppColors.textSecondary
        case .medium: return AppColors.accentElectric
        case .high:   return Color.orange
        case .urgent: return AppColors.accentDanger
        }
    }

    var icon: String {
        switch self {
        case .low:    return "arrow.down"
        case .normal: return "minus"
        case .medium: return "arrow.up"
        case .high:   return "exclamationmark"
        case .urgent: return "exclamationmark.2"
        }
    }
}

enum TicketsLiveStatus: Sendable, Equatable {
    case connected
    case reconnecting
    case stopped
    case stale

    var label: String {
        switch self {
        case .connected: return "Live connected"
        case .reconnecting: return "Live reconnecting"
        case .stopped: return "Live stopped"
        case .stale: return "Live stale"
        }
    }

    var icon: String {
        switch self {
        case .connected: return "dot.radiowaves.left.and.right"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .stopped: return "pause.circle"
        case .stale: return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .connected: return AppColors.accentSuccess
        case .reconnecting: return AppColors.accentWarning
        case .stopped: return AppColors.textTertiary
        case .stale: return Color.orange
        }
    }
}

enum TicketSavedView: String, Sendable, CaseIterable {
    case needsHuman
    case dispatchable
    case running
    case waitingApproval
    case ticketFlow
    case noiseReview
    case operationalDebt
    case needsScope
    case reviewMermaid
    case failedRuns
    case stale
    case recentlyCompleted
    case myLane
    case alohaTriage
    case coralRuntime
    case reefRuntime
    case chiefFund
    case podBugs

    var label: String {
        switch self {
        case .needsHuman: return "Needs Human"
        case .dispatchable: return "Dispatchable"
        case .running: return "Running"
        case .waitingApproval: return "Waiting Approval"
        case .ticketFlow: return "Flow"
        case .noiseReview: return "Noise Review"
        case .operationalDebt: return "Ops Debt"
        case .needsScope: return "Needs Scope"
        case .reviewMermaid: return "Review Mermaid"
        case .failedRuns: return "Failed Runs"
        case .stale: return "Stale"
        case .recentlyCompleted: return "Recently Completed"
        case .myLane: return "Maui Lane"
        case .alohaTriage: return "Aloha Triage"
        case .coralRuntime: return "Coral Runtime"
        case .reefRuntime: return "Reef Runtime"
        case .chiefFund: return "Chief/Fund"
        case .podBugs: return "Pod Bugs"
        }
    }
}

struct TicketListSignal: Sendable, Hashable {
    let label: String
    let detail: String
    let icon: String
    let color: Color
}

struct TicketOperationalDebt: Identifiable, Sendable, Hashable {
    let id: String
    let label: String
    let detail: String
    let icon: String
    let color: Color
    let priority: Int
}

struct TicketActionContext: Sendable, Hashable {
    let owner: String
    let workerLane: String
    let toolPolicy: String
    let computeTag: String
}

struct TicketDispatchPreview: Sendable, Hashable {
    let ticketId: String
    let ownerAgentId: String?
    let workerLane: String
    let toolPolicy: String
    let computeTag: String
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let approvalRequired: Bool
    let protectedLane: Bool
    let nextState: String
    let blockers: [String]
    let preview: String
}

struct TicketEvidenceSummary: Sendable, Hashable {
    let commentCount: Int
    let runCount: Int
    let failedRunCount: Int
    let approvalCount: Int
    let dispatchCount: Int
    let queuedRunCount: Int
    let runningRunCount: Int
    let waitingRunCount: Int
    let retryingRunCount: Int
    let latestRunStatus: AgentRunStatus?
    let latestRunRoute: String?
    let latestRoutePacket: [String: AgentRunJSONValue]?
    let blockers: [String]
    let nextAction: String?
    let finalVerification: String
    let finalVerificationColor: Color
}

struct TicketWorkerHealthSummary: Sendable, Hashable {
    let lane: String
    let total: Int
    let good: Int
    let stale: Int
    let error: Int
    let latestValue: String?

    var isUnknown: Bool { total == 0 }

    var label: String {
        if isUnknown { return "No live tag" }
        if error > 0 { return "\(error) error" }
        if stale > 0 { return "\(stale) stale" }
        if good > 0 { return "Good" }
        return "Observed"
    }
}

struct TicketListSummary: Sendable, Hashable {
    let ticketId: String
    let commentCount: Int
    let runCount: Int
    let failedRunCount: Int
    let approvalCount: Int
    let dispatchCount: Int
    let workerReviewRequiredCount: Int
    let queuedRunCount: Int
    let runningRunCount: Int
    let waitingRunCount: Int
    let retryingRunCount: Int
    let latestRun: TicketListRunSummary?
    let latestActivity: String?
    let latestActivityAt: Date?
    let latestIntelligenceAt: Date?
    let latestRoutePacket: [String: AgentRunJSONValue]?
    let blockers: [String]
    let nextAction: String?

    struct TicketListRunSummary: Sendable, Hashable {
        let id: String
        let status: AgentRunStatus
        let runType: String
        let workerLane: String?
        let backend: String?
        let model: String?
        let reviewStatus: String?
        let reviewedBy: String?
        let reviewedAt: Date?
        let updatedAt: Date
    }
}

struct TicketFlowReview: Sendable, Hashable {
    let counts: TicketFlowCounts
    let items: [TicketFlowItem]
}

struct TicketFlowCounts: Sendable, Hashable {
    let total: Int
    let dispatchable: Int
    let noiseReview: Int
    let protected: Int
    let byFlowState: [String: Int]
    let byOwnerAgent: [String: Int]
    let bySupportLane: [String: Int]
}

struct TicketFlowItem: Identifiable, Sendable, Hashable {
    var id: String { ticketId }
    let ticketId: String
    let title: String
    let status: String
    let priority: String
    let flowState: String
    let nextAction: String
    let ownerAgent: String
    let supportLane: String?
    let workerLane: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let approvalState: String
    let approvalGate: String?
    let autonomyLevel: String
    let dispatchable: Bool
    let noiseReview: Bool
    let protected: Bool
    let blockers: [String]
    let reasons: [String]
    let updatedAt: Date
}

private struct TicketFlowReviewDTO: Decodable {
    let counts: TicketFlowCountsDTO
    let items: [TicketFlowItemDTO]

    func toDomain() -> TicketFlowReview {
        TicketFlowReview(
            counts: counts.toDomain(),
            items: items.map { $0.toDomain() }
        )
    }
}

private struct TicketFlowCountsDTO: Decodable {
    let total: Int?
    let dispatchable: Int?
    let noiseReview: Int?
    let protected: Int?
    let byFlowState: [String: Int]?
    let byOwnerAgent: [String: Int]?
    let bySupportLane: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case total, dispatchable, protected
        case noiseReview = "noise_review"
        case byFlowState = "by_flow_state"
        case byOwnerAgent = "by_owner_agent"
        case bySupportLane = "by_support_lane"
    }

    func toDomain() -> TicketFlowCounts {
        TicketFlowCounts(
            total: total ?? 0,
            dispatchable: dispatchable ?? 0,
            noiseReview: noiseReview ?? 0,
            protected: protected ?? 0,
            byFlowState: byFlowState ?? [:],
            byOwnerAgent: byOwnerAgent ?? [:],
            bySupportLane: bySupportLane ?? [:]
        )
    }
}

private struct TicketFlowItemDTO: Decodable {
    let ticketId: String
    let title: String?
    let status: String?
    let priority: String?
    let flowState: String?
    let nextAction: String?
    let ownerAgent: String?
    let supportLane: String?
    let workerLane: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let approvalState: String?
    let approvalGate: String?
    let autonomyLevel: String?
    let dispatchable: Bool?
    let noiseReview: Bool?
    let protected: Bool?
    let blockers: [String]?
    let reasons: [String]?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case title, status, priority, dispatchable, protected, blockers, reasons
        case ticketId = "ticket_id"
        case flowState = "flow_state"
        case nextAction = "next_action"
        case ownerAgent = "owner_agent"
        case supportLane = "support_lane"
        case workerLane = "worker_lane"
        case recommendedRuntime = "recommended_runtime"
        case recommendedSurface = "recommended_surface"
        case runtimeReason = "runtime_reason"
        case handoffSubject = "handoff_subject"
        case approvalState = "approval_state"
        case approvalGate = "approval_gate"
        case autonomyLevel = "autonomy_level"
        case noiseReview = "noise_review"
        case updatedAt = "updated_at"
    }

    func toDomain() -> TicketFlowItem {
        TicketFlowItem(
            ticketId: ticketId,
            title: title ?? "Untitled ticket",
            status: status ?? "unknown",
            priority: priority ?? "normal",
            flowState: flowState ?? "unknown",
            nextAction: nextAction ?? "Review",
            ownerAgent: ownerAgent ?? "unassigned",
            supportLane: supportLane,
            workerLane: workerLane,
            recommendedRuntime: recommendedRuntime,
            recommendedSurface: recommendedSurface,
            runtimeReason: runtimeReason,
            handoffSubject: handoffSubject,
            approvalState: approvalState ?? "not_required",
            approvalGate: approvalGate,
            autonomyLevel: autonomyLevel ?? "inspect_only",
            dispatchable: dispatchable ?? false,
            noiseReview: noiseReview ?? false,
            protected: protected ?? false,
            blockers: blockers ?? [],
            reasons: reasons ?? [],
            updatedAt: updatedAt ?? .distantPast
        )
    }
}

// MARK: - TicketDTO

struct TicketDTO: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let priority: String
    let assigneeAgentId: String?
    let ticketType: String?
    let tags: [String]?
    let source: String?
    let sourceChatURL: String?
    let sourceThreadURL: String?
    let computeTag: String?
    let approvalState: String?
    let approvalGate: String?
    let autonomyLevel: String?
    let workerLane: String?
    let toolPolicy: String?
    let acceptanceCriteria: [String]?
    let desiredOutcome: String?
    let triageId: String?
    let triageTraceId: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let chatThreadId: String?
    let parentTicketId: String?     // POD-4
    let lessonsLearned: String?    // POD-4
    let createdAt: Date
    let updatedAt: Date
    let claimedAt: Date?
    let startedAt: Date?
    let resolvedAt: Date?
    let resolutionNotes: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority, tags, source
        case sourceChatURL     = "source_chat_url"
        case sourceThreadURL   = "source_thread_url"
        case assigneeAgentId    = "assignee_agent_id"
        case ticketType         = "ticket_type"
        case computeTag         = "compute_tag"
        case approvalState      = "approval_state"
        case approvalGate       = "approval_gate"
        case autonomyLevel      = "autonomy_level"
        case workerLane         = "worker_lane"
        case toolPolicy         = "tool_policy"
        case acceptanceCriteria = "acceptance_criteria"
        case desiredOutcome     = "desired_outcome"
        case triageId           = "triage_id"
        case triageTraceId      = "triage_trace_id"
        case recommendedRuntime = "recommended_runtime"
        case recommendedSurface = "recommended_surface"
        case runtimeReason      = "runtime_reason"
        case handoffSubject     = "handoff_subject"
        case chatThreadId       = "chat_thread_id"
        case parentTicketId     = "parent_ticket_id"
        case lessonsLearned     = "lessons_learned"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
        case claimedAt          = "claimed_at"
        case startedAt          = "started_at"
        case resolvedAt         = "resolved_at"
        case resolutionNotes    = "resolution_notes"
    }

    func toDomain(agentName: String? = nil) -> Ticket {
        Ticket(
            id: id,
            title: title,
            description: description,
            status: TicketStatus(rawValue: status) ?? .open,
            priority: TicketPriority(rawValue: priority) ?? .normal,
            assigneeAgentId: assigneeAgentId,
            assigneeAgentName: agentName,
            ticketType: ticketType,
            tags: tags,
            source: source,
            sourceChatURL: sourceChatURL,
            sourceThreadURL: sourceThreadURL,
            computeTag: computeTag,
            approvalState: approvalState,
            approvalGate: approvalGate,
            autonomyLevel: autonomyLevel,
            workerLane: workerLane,
            toolPolicy: toolPolicy,
            acceptanceCriteria: acceptanceCriteria,
            desiredOutcome: desiredOutcome,
            triageId: triageId,
            triageTraceId: triageTraceId,
            recommendedRuntime: recommendedRuntime,
            recommendedSurface: recommendedSurface,
            runtimeReason: runtimeReason,
            handoffSubject: handoffSubject,
            chatThreadId: chatThreadId,
            parentTicketId: parentTicketId,
            lessonsLearned: lessonsLearned,
            createdAt: createdAt,
            updatedAt: updatedAt,
            claimedAt: claimedAt,
            startedAt: startedAt,
            resolvedAt: resolvedAt,
            resolutionNotes: resolutionNotes
        )
    }
}

// MARK: - TicketsViewModel

@Observable
final class TicketsViewModel {
    var tickets: [Ticket] = []
    var isLoading = false
    var errorMessage: String?
    var selectedStatus: TicketStatus? = nil  // nil = show all
    var selectedSavedView: TicketSavedView?
    var showCreateSheet = false
    var groomingSummary: BacklogGroomingSummary?
    var backlogReprocessDryRun: BacklogGroomingSummary?
    var workControlBackfillSummary: WorkControlBackfillSummary?
    var workControlIntegritySummary: WorkControlIntegritySummary?
    var workControlReviewExportResult: LegacyLinkageExportResult?
    var workControlReviewExportMessage: String?
    var legacyLinkageExportResult: LegacyLinkageExportResult?
    var legacyLinkageExportMessage: String?
    var agentRunReviewExportResult: LegacyLinkageExportResult?
    var agentRunReviewExportMessage: String?
    var agentRunReviewQueue: [AgentRun] = []
    var agentRunReviewQueueErrorMessage: String?
    var isLoadingAgentRunReviewQueue = false
    var groomingErrorMessage: String?
    var backlogReprocessErrorMessage: String?
    var groomingActionMessage: String?
    var isPostingGroomingComments = false
    var isExportingWorkControlReview = false
    var isExportingLegacyLinkage = false
    var isExportingAgentRunReview = false

    // For create form
    var newTitle = ""
    var newDescription = ""
    var newPriority = TicketPriority.normal
    var newAssigneeAgentId = ""
    var newTicketType = "support"
    var newTags = ""
    var newComputeTag = "classify"
    var newApprovalState = "not_required"
    var newApprovalGate = ""
    var newAutonomyLevel = "inspect_only"
    var newWorkerLane = "mermaid"
    var newToolPolicy = "bounded_workspace_edits_owner_review"
    var newAcceptanceCriteria = ""
    var newDoneMeans = ""
    var newBoardId = ""
    var newBoardOptions: [TicketBoardOption] = []
    var isLoadingBoardOptions = false
    var boardOptionsMessage: String?
    var roughIntake = ""
    var isDrafting = false
    var draftMessage: String?
    var isPreviewingDirection = false
    var directionPreview: TicketDirectionPreview?
    var directionPreviewMessage: String?
    var isCreating = false
    var isDispatching = false
    var dispatchMessage: String?
    var ticketCommentsByTicketId: [String: [TicketComment]] = [:]
    var commentErrorsByTicketId: [String: String] = [:]
    var loadingCommentTicketIds: Set<String> = []
    var ticketNotesByTicketId: [String: [TicketNoteRecord]] = [:]
    var ticketNoteErrorsByTicketId: [String: String] = [:]
    var loadingTicketNoteIds: Set<String> = []
    var ticketApprovalsByTicketId: [String: [TicketApprovalRecord]] = [:]
    var ticketApprovalErrorsByTicketId: [String: String] = [:]
    var loadingTicketApprovalIds: Set<String> = []
    var approvalRegistrySpecs: [String: ApprovalRegistrySpec] = [:]
    var approvalRegistryErrorMessage: String?
    var isLoadingApprovalRegistry = false
    var agentRunsByTicketId: [String: [AgentRun]] = [:]
    var agentRunErrorsByTicketId: [String: String] = [:]
    var loadingAgentRunTicketIds: Set<String> = []
    var tracesById: [String: AgentRunTrace] = [:]
    var traceErrorsById: [String: String] = [:]
    var loadingTraceIds: Set<String> = []
    var artifactSummariesByRunId: [String: [AgentRunArtifactSummary]] = [:]
    var artifactSummaryErrorsByRunId: [String: String] = [:]
    var loadingArtifactRunIds: Set<String> = []
    var computeRunsByTraceId: [String: [ComputeRunRecord]] = [:]
    var ticketSummariesByTicketId: [String: TicketListSummary] = [:]
    var ticketFlowReview: TicketFlowReview?
    var ticketFlowByTicketId: [String: TicketFlowItem] = [:]
    var ticketFlowErrorMessage: String?
    var dispatchPreviewsByTicketId: [String: TicketDispatchPreview] = [:]
    var dispatchPreviewErrorsByTicketId: [String: String] = [:]
    var workerQueuesByLane: [String: [AgentRun]] = [:]
    var workerQueueErrorsByLane: [String: String] = [:]
    var runtimeHealthTags: [StateTagDTO] = []
    var runtimeHealthErrorMessage: String?
    var liveStatus: TicketsLiveStatus = .stopped
    var liveStatusDetail = "Ticket stream is stopped."
    var lastLiveEventAt: Date?

    private let api = APIClient.shared

    // b9bbe115 SSE leg: live ticket lifecycle subscription to /api/v1/tickets/stream
    // (fans team.tickets.events). Ticket-scoped events patch the affected row
    // and evidence summary in place; payloads without ticket_id still fall back
    // to a full reload.
    private var sseManager: SSEStreamManager?
    private var sseListenTask: Task<Void, Never>?
    private var liveStalenessTask: Task<Void, Never>?

    // POD-4: Subtask tree
    var rootTickets: [Ticket] {
        tickets.filter { $0.parentTicketId == nil }
    }

    func ticket(withId ticketId: String) -> Ticket? {
        tickets.first { $0.id == ticketId }
    }

    var filteredRootTickets: [Ticket] {
        filtered.filter { $0.parentTicketId == nil }
    }

    func subtasks(of ticket: Ticket) -> [Ticket] {
        tickets.filter { $0.parentTicketId == ticket.id }
    }

    func filteredSubtasks(of ticket: Ticket) -> [Ticket] {
        filtered.filter { $0.parentTicketId == ticket.id }
    }

    var filtered: [Ticket] {
        var result = statusFilteredTickets
        if let selectedSavedView {
            result = result.filter { matches($0, savedView: selectedSavedView) }
        }
        return result
    }

    var statusFilteredTickets: [Ticket] {
        guard let selectedStatus else { return tickets }
        return tickets.filter { $0.status == selectedStatus }
    }

    func count(for savedView: TicketSavedView) -> Int {
        statusFilteredTickets.filter { matches($0, savedView: savedView) }.count
    }

    var emptyStateTitle: String {
        if let selectedSavedView, let selectedStatus {
            return "No \(selectedStatus.label.lowercased()) \(selectedSavedView.label.lowercased()) tickets"
        }
        if let selectedSavedView {
            return "No \(selectedSavedView.label.lowercased()) tickets"
        }
        if let selectedStatus {
            return "No \(selectedStatus.label.lowercased()) tickets"
        }
        return "No tickets yet"
    }

    var emptyStateSubtitle: String {
        if selectedSavedView != nil || selectedStatus != nil {
            return "Adjust filters or create a ticket to assign work to an agent."
        }
        return "Create a ticket to assign work to an agent."
    }

    var openCount: Int    { tickets.filter { $0.status == .open }.count }
    var activeCount: Int  { tickets.filter { $0.status == .claimed || $0.status == .inProgress }.count }

    func groomingItem(for ticketId: String) -> BacklogGroomingItem? {
        groomingSummary?.items.first { $0.ticketId == ticketId }
    }

    func operationalDebts(for ticket: Ticket) -> [TicketOperationalDebt] {
        var debts: [TicketOperationalDebt] = []

        if let integrity = workControlIntegritySummary?.items.first(where: { $0.ticketId == ticket.id }) {
            if integrity.hasSourceLinkGap {
                debts.append(TicketOperationalDebt(
                    id: "source-link",
                    label: "Source link",
                    detail: "chat/thread missing",
                    icon: "link.badge.plus",
                    color: AppColors.accentDanger,
                    priority: 10
                ))
            }

            if integrity.hasTriageLinkGap {
                debts.append(TicketOperationalDebt(
                    id: "triage-link",
                    label: "Triage link",
                    detail: "Merman id/trace missing",
                    icon: "arrow.triangle.branch",
                    color: AppColors.accentWarning,
                    priority: 20
                ))
            }

            let otherFields = integrity.fields
                .filter { !Self.isPrimaryLinkageField($0) }
                .map(Self.displayLabel)
            if !otherFields.isEmpty {
                debts.append(TicketOperationalDebt(
                    id: "integrity-fields",
                    label: "Integrity",
                    detail: Self.compactList(otherFields),
                    icon: "checklist.unchecked",
                    color: AppColors.textTertiary,
                    priority: 50
                ))
            }
        }

        if let backfill = workControlBackfillSummary?.items.first(where: { $0.ticketId == ticket.id }) {
            let missingFields = backfill.missingFields
                .filter { !Self.isPrimaryLinkageField($0) }
                .map(Self.displayLabel)
            if !missingFields.isEmpty {
                debts.append(TicketOperationalDebt(
                    id: "backfill",
                    label: "Backfill",
                    detail: Self.compactList(missingFields),
                    icon: "list.bullet.clipboard",
                    color: AppColors.accentAgent,
                    priority: 55
                ))
            }
        }

        let summary = ticketSummariesByTicketId[ticket.id]
        if let reviewCount = summary?.workerReviewRequiredCount, reviewCount > 0 {
            debts.append(TicketOperationalDebt(
                id: "run-review",
                label: "Run review",
                detail: "\(reviewCount) worker result\(reviewCount == 1 ? "" : "s")",
                icon: "checkmark.seal",
                color: AppColors.accentWarning,
                priority: 30
            ))
        } else if needsOwnerReview(for: ticket) {
            debts.append(TicketOperationalDebt(
                id: "run-review",
                label: "Run review",
                detail: "Mermaid result waiting",
                icon: "checkmark.seal",
                color: AppColors.accentWarning,
                priority: 30
            ))
        }

        let failedRunCount = max(
            summary?.failedRunCount ?? 0,
            agentRuns(for: ticket.id).filter { $0.status == .failed || $0.status == .blocked }.count
        )
        if failedRunCount > 0 {
            debts.append(TicketOperationalDebt(
                id: "failed-runs",
                label: "Run failed",
                detail: "\(failedRunCount) failed/blocked",
                icon: "exclamationmark.triangle",
                color: AppColors.accentDanger,
                priority: 40
            ))
        }

        return debts.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.label < rhs.label
        }
    }

    func matches(_ ticket: Ticket, savedView: TicketSavedView) -> Bool {
        let haystack = "\(ticket.title) \(ticket.description ?? "") \(ticket.assigneeAgentName ?? "") \(ticket.ticketType ?? "") \(ticket.computeTag ?? "")"
            .lowercased()
        let grooming = groomingItem(for: ticket.id)
        let flow = ticketFlowByTicketId[ticket.id]
        switch savedView {
        case .needsHuman:
            let approvalState = ticket.approvalState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ticket.status != .closed && ticket.status != .cancelled
                && !Self.isClearedApprovalState(approvalState)
                && (
                    grooming?.classification == "needs-human"
                    || grooming?.suggestedApprovalState == "waiting_for_human"
                    || ticket.priority == .urgent
                    || ticket.priority == .high
                    || haystack.contains("approval")
                    || haystack.contains("waiting_for_human")
                    || haystack.contains("needs human")
                )
        case .dispatchable:
            return ticket.status != .closed && ticket.status != .cancelled
                && (
                    grooming?.classification == "keep"
                    || ticket.assigneeAgentId != nil
                )
                && (grooming?.suggestedApprovalState ?? ticket.approvalState) != "waiting_for_human"
                && !(grooming?.suggestedWorkerLane ?? SchoolhouseTicketDispatchService.workerLane(for: ticket)).hasPrefix("protected-")
        case .running:
            let latestStatus = ticketSummariesByTicketId[ticket.id]?.latestRun?.status
            return ticket.status == .claimed
                || ticket.status == .inProgress
                || latestStatus == .queued
                || latestStatus == .running
                || latestStatus == .retrying
                || agentRuns(for: ticket.id).contains { $0.status == .queued || $0.status == .running || $0.status == .retrying }
        case .waitingApproval:
            let approvalState = ticket.approvalState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let approvalGate = ticket.approvalGate?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let latestStatus = ticketSummariesByTicketId[ticket.id]?.latestRun?.status
            return ticket.status != .closed && ticket.status != .cancelled
                && (
                    approvalState == "waiting_for_human"
                    || approvalState == "needs_approval"
                    || approvalGate?.isEmpty == false
                    || latestStatus == .waitingForHuman
                    || agentRuns(for: ticket.id).contains { $0.status == .waitingForHuman }
                    || haystack.contains("waiting for human")
                    || haystack.contains("waiting_for_human")
                )
        case .ticketFlow:
            return ticket.status != .closed && ticket.status != .cancelled
                && flow != nil
        case .noiseReview:
            return ticket.status != .closed && ticket.status != .cancelled
                && (flow?.noiseReview == true || flow?.flowState == "noise_review")
        case .operationalDebt:
            return !operationalDebts(for: ticket).isEmpty
        case .needsScope:
            let criteria = ticket.acceptanceCriteria ?? []
            let outcome = ticket.desiredOutcome?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ticket.status != .closed && ticket.status != .cancelled
                && (
                    criteria.isEmpty
                    || outcome?.isEmpty != false
                    || haystack.contains("needs scope")
                    || haystack.contains("underspecified")
                    || grooming?.healthFlags?.contains("needs_scope") == true
                )
        case .reviewMermaid:
            let latestSummary = ticketSummariesByTicketId[ticket.id]?.latestRun
            let detailRuns = agentRuns(for: ticket.id)
            return ticket.status != .closed && ticket.status != .cancelled
                && (
                    needsOwnerReview(for: ticket)
                    || latestSummary?.workerLane == "mermaid"
                    || detailRuns.contains { $0.workerLane == "mermaid" && ($0.status == .succeeded || $0.status == .waitingForHuman || $0.status == .failed || $0.status == .blocked) }
                    || haystack.contains("mermaid")
                )
        case .failedRuns:
            let summary = ticketSummariesByTicketId[ticket.id]
            return (summary?.failedRunCount ?? 0) > 0
                || summary?.latestRun?.status == .failed
                || summary?.latestRun?.status == .blocked
                || agentRuns(for: ticket.id).contains { $0.status == .failed || $0.status == .blocked }
                || haystack.contains("failed run")
                || haystack.contains("dispatch failed")
        case .stale:
            return ticket.status != .closed && ticket.status != .cancelled
                && (ticket.updatedAt.timeIntervalSinceNow < -72 * 60 * 60 || grooming?.healthFlags?.contains("health_review") == true)
        case .recentlyCompleted:
            return (ticket.status == .closed || ticket.status == .cancelled)
                && ticket.updatedAt.timeIntervalSinceNow > -72 * 60 * 60
        case .myLane:
            return ticket.status != .closed && ticket.status != .cancelled
                && (
                    haystack.contains("maui")
                    || ticket.workerLane == "mermaid"
                    || ticket.assigneeAgentName?.lowercased().contains("maui") == true
                    || ticket.computeTag?.lowercased().contains("engineering") == true
                )
        case .alohaTriage:
            return ticket.status != .closed && ticket.status != .cancelled
                && (
                    haystack.contains("aloha")
                    || ticket.ticketType == "triage"
                    || grooming?.classification == "needs-human"
                    || grooming?.suggestedOwner?.lowercased() == "aloha"
                    || flow?.ownerAgent == "aloha"
                )
        case .coralRuntime:
            return ticket.status != .closed && ticket.status != .cancelled
                && (
                    flow?.ownerAgent == "coral"
                    || flow?.supportLane == "coral-support-runtime"
                    || haystack.contains("coral")
                    || haystack.contains("watchdog")
                    || haystack.contains("petal")
                    || haystack.contains("daemon")
                )
        case .reefRuntime:
            return ticket.status != .closed && ticket.status != .cancelled
                && (
                    flow?.ownerAgent == "reef"
                    || flow?.supportLane == "reef-support-runtime"
                    || haystack.contains("reef")
                    || haystack.contains("chief mac")
                    || haystack.contains("mirror")
                )
        case .chiefFund:
            return haystack.contains("chief") || haystack.contains("fund") || haystack.contains("trading") || haystack.contains("p&l") || (grooming?.suggestedWorkerLane ?? SchoolhouseTicketDispatchService.workerLane(for: ticket)) == "protected-chief-review" || flow?.ownerAgent == "chief"
        case .podBugs:
            return haystack.contains("pod") && (ticket.ticketType == "bug" || haystack.contains("bug") || haystack.contains("broken") || haystack.contains("not working"))
        }
    }

    // MARK: - Load

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let dtos = try await loadTicketDTOs(includeTerminalTickets: true)

            // Fetch agent names for tickets with assignee_agent_id
            let agentIds = Set(dtos.compactMap { $0.assigneeAgentId })
            var agentNames: [String: String] = [:]

            if !agentIds.isEmpty {
                do {
                    let response: PaginatedResponse<AgentDTO> = try await api.get(path: "/api/v1/agents")
                    for agent in response.items {
                        if agent.domainRosterLane == .activeMain || agent.domainRosterLane == .supportRuntime {
                            agentNames[agent.id] = agent.name
                        } else {
                            agentNames[agent.id] = "Dormant: \(agent.name.capitalized)"
                        }
                    }
                } catch {
                    // Ignore agent fetch errors, we'll show IDs instead
                }
            }

            tickets = dtos.map { dto in
                let agentName = dto.assigneeAgentId.flatMap { agentNames[$0] }
                return dto.toDomain(agentName: agentName)
            }.sorted { $0.createdAt > $1.createdAt }
            await loadTicketSummaries(limit: limitForSummaries)
            await loadTicketFlowReview(limit: limitForSummaries)
            await loadGroomingSummary()
            await loadBacklogReprocessDryRun()
            await loadWorkControlBackfillSummary()
            await loadWorkControlIntegritySummary()
            await loadAgentRunReviewQueue()
            await loadRuntimeHealthTags()
        } catch let apiError as APIError {
            // 2026-05-07 plumbing fix: no more silent mock fallback. Surface the real error.
            tickets = []
            errorMessage = Self.userFacingMessage(for: apiError)
        } catch {
            tickets = []
            errorMessage = "Couldn't load tickets. Pull to retry."
        }
    }

    private func loadTicketDTOs(includeTerminalTickets: Bool) async throws -> [TicketDTO] {
        do {
            return try await api.get(path: "/api/v1/tickets?include_closed=\(includeTerminalTickets)")
        } catch {
            if includeTerminalTickets {
                return try await api.get(path: "/api/v1/tickets")
            }
            throw error
        }
    }

    private var limitForSummaries: Int {
        max(100, tickets.count)
    }

    @MainActor
    func loadTicketSummaries(limit: Int = 100) async {
        do {
            let dtos: [TicketListSummaryDTO] = try await api.get(path: "/api/v1/tickets/summaries?limit=\(limit)")
            ticketSummariesByTicketId = Dictionary(uniqueKeysWithValues: dtos.map { dto in
                (dto.ticketId, dto.toDomain())
            })
        } catch {
            ticketSummariesByTicketId = [:]
        }
    }

    @MainActor
    func loadTicketFlowReview(limit: Int = 100) async {
        ticketFlowErrorMessage = nil
        do {
            let dto: TicketFlowReviewDTO = try await api.get(path: "/api/v1/tickets/flow-review?limit=\(limit)&include_closed=false")
            let review = dto.toDomain()
            ticketFlowReview = review
            ticketFlowByTicketId = review.items.reduce(into: [:]) { partialResult, item in
                partialResult[item.ticketId] = item
            }
        } catch {
            ticketFlowReview = nil
            ticketFlowByTicketId = [:]
            ticketFlowErrorMessage = "Ticket flow review unavailable."
        }
    }

    @MainActor
    private func refreshTicketFlow(ticketId: String, includeClosed: Bool = true) async {
        do {
            let dto: TicketFlowReviewDTO = try await api.get(path: "/api/v1/tickets/flow-review?ticket_id=\(ticketId)&limit=1&include_closed=\(includeClosed)")
            if let flow = dto.toDomain().items.first {
                ticketFlowByTicketId[ticketId] = flow
                ticketFlowErrorMessage = nil
            } else {
                ticketFlowByTicketId.removeValue(forKey: ticketId)
            }
        } catch {
            ticketFlowByTicketId.removeValue(forKey: ticketId)
            ticketFlowErrorMessage = "Ticket flow review unavailable."
        }
    }

    @MainActor
    private func resolveAgentName(for agentId: String?) async -> String? {
        guard let agentId, !agentId.isEmpty else { return nil }
        do {
            let response: PaginatedResponse<AgentDTO> = try await api.get(path: "/api/v1/agents")
            guard let agent = response.items.first(where: { $0.id == agentId }) else { return agentId }
            if agent.domainRosterLane == .activeMain || agent.domainRosterLane == .supportRuntime {
                return agent.name
            }
            return "Dormant: \(agent.name.capitalized)"
        } catch {
            return agentId
        }
    }

    @MainActor
    private func refreshTicketFromLifecycleEvent(_ envelope: TicketLifecycleEnvelope) async {
        guard let ticketId = envelope.metadata?.ticketId, !ticketId.isEmpty else {
            await load()
            return
        }

        do {
            let dto: TicketDTO = try await api.get(path: "/api/v1/tickets/\(ticketId)")
            let currentAgentName = tickets.first(where: { $0.id == ticketId })?.assigneeAgentName
            let resolvedAgentName: String?
            if let currentAgentName {
                resolvedAgentName = currentAgentName
            } else {
                resolvedAgentName = await resolveAgentName(for: dto.assigneeAgentId)
            }
            let ticket = dto.toDomain(agentName: resolvedAgentName)
            if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
                tickets[index] = ticket
            } else {
                tickets.insert(ticket, at: 0)
            }
            tickets.sort { $0.createdAt > $1.createdAt }

            let summary: TicketListSummaryDTO = try await api.get(path: "/api/v1/tickets/\(ticketId)/summary")
            ticketSummariesByTicketId[ticketId] = summary.toDomain()
            await refreshTicketFlow(ticketId: ticketId)

            liveStatusDetail = "Updated \(ticket.title) from live stream."
        } catch {
            liveStatusDetail = "Live ticket update received; refreshing the list."
            await load()
        }
    }

    @MainActor
    func loadGroomingSummary() async {
        groomingErrorMessage = nil
        do {
            groomingSummary = try await api.get(path: "/api/v1/tickets/backlog-grooming/dry-run?limit=100&include_closed=false")
        } catch {
            groomingSummary = nil
            groomingErrorMessage = "Backlog grooming summary unavailable."
        }
    }

    @MainActor
    func loadBacklogReprocessDryRun() async {
        backlogReprocessErrorMessage = nil
        do {
            backlogReprocessDryRun = try await api.get(path: "/api/v1/tickets/backlog-grooming/reprocess/dry-run?limit=100&include_closed=false")
        } catch {
            backlogReprocessDryRun = nil
            backlogReprocessErrorMessage = "Backlog reprocess dry-run unavailable."
        }
    }

    @MainActor
    func loadWorkControlBackfillSummary() async {
        do {
            workControlBackfillSummary = try await api.get(path: "/api/v1/tickets/work-control/backfill/dry-run?limit=100&include_closed=false")
        } catch {
            workControlBackfillSummary = nil
        }
    }

    @MainActor
    func loadWorkControlIntegritySummary() async {
        do {
            workControlIntegritySummary = try await api.get(path: "/api/v1/tickets/work-control/integrity?limit=100&include_closed=false")
        } catch {
            do {
                workControlIntegritySummary = try await api.get(path: "/api/v1/tickets/work-control/integrity")
            } catch {
                workControlIntegritySummary = nil
            }
        }
    }

    @MainActor
    func loadAgentRunReviewQueue() async {
        guard !isLoadingAgentRunReviewQueue else { return }
        isLoadingAgentRunReviewQueue = true
        agentRunReviewQueueErrorMessage = nil
        defer { isLoadingAgentRunReviewQueue = false }

        do {
            let dtos: [AgentRunDTO] = try await api.get(path: "/api/v1/agent-runs?review_required=true")
            agentRunReviewQueue = dtos
                .map { $0.toDomain() }
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch let apiError as APIError {
            agentRunReviewQueue = []
            agentRunReviewQueueErrorMessage = Self.userFacingMessage(for: apiError)
        } catch {
            agentRunReviewQueue = []
            agentRunReviewQueueErrorMessage = "Agent run review queue unavailable."
        }
    }

    @MainActor
    func exportAgentRunReviewQueue() async {
        guard !isExportingAgentRunReview else { return }
        isExportingAgentRunReview = true
        agentRunReviewExportMessage = nil
        agentRunReviewExportResult = nil
        defer { isExportingAgentRunReview = false }

        do {
            let result: LegacyLinkageExportResult = try await api.post(
                path: "/api/v1/agent-runs/review-queue/export",
                body: EmptyRequestBody()
            )
            agentRunReviewExportResult = result
            agentRunReviewExportMessage = result.message
        } catch let apiError as APIError {
            agentRunReviewExportMessage = "Couldn't export Agent Run review queue: \(Self.userFacingMessage(for: apiError))"
        } catch {
            agentRunReviewExportMessage = "Couldn't export Agent Run review queue."
        }
    }

    @MainActor
    func postBacklogGroomingComments() async {
        guard !isPostingGroomingComments else { return }
        isPostingGroomingComments = true
        groomingActionMessage = nil
        defer { isPostingGroomingComments = false }

        do {
            let result: BacklogGroomingCommentResult = try await api.post(
                path: "/api/v1/tickets/backlog-grooming/dry-run/comments",
                body: BacklogGroomingCommentRequest(limit: 100, includeClosed: false, force: false)
            )
            groomingActionMessage = "Added \(result.commented) review comments; \(result.skippedExisting) already had dry-run notes."
            await loadTicketSummaries(limit: limitForSummaries)
            await loadGroomingSummary()
        } catch let apiError as APIError {
            groomingActionMessage = "Couldn't write grooming comments: \(Self.userFacingMessage(for: apiError))"
        } catch {
            groomingActionMessage = "Couldn't write grooming comments."
        }
    }

    @MainActor
    func exportWorkControlIntegrityReview() async {
        guard !isExportingWorkControlReview else { return }
        isExportingWorkControlReview = true
        workControlReviewExportMessage = nil
        workControlReviewExportResult = nil
        defer { isExportingWorkControlReview = false }

        do {
            let result: LegacyLinkageExportResult = try await api.post(
                path: "/api/v1/tickets/work-control/integrity/export",
                body: EmptyRequestBody()
            )
            workControlReviewExportResult = result
            workControlReviewExportMessage = result.message
        } catch let apiError as APIError {
            workControlReviewExportMessage = "Couldn't export work-control review: \(Self.userFacingMessage(for: apiError))"
        } catch {
            workControlReviewExportMessage = "Couldn't export work-control review."
        }
    }

    @MainActor
    func exportLegacyLinkageDryRun() async {
        guard !isExportingLegacyLinkage else { return }
        isExportingLegacyLinkage = true
        legacyLinkageExportMessage = nil
        legacyLinkageExportResult = nil
        defer { isExportingLegacyLinkage = false }

        do {
            let result: LegacyLinkageExportResult = try await api.post(
                path: "/api/v1/tickets/legacy-linkage/backfill/dry-run/export",
                body: EmptyRequestBody()
            )
            legacyLinkageExportResult = result
            legacyLinkageExportMessage = result.message
        } catch let apiError as APIError {
            legacyLinkageExportMessage = "Couldn't export legacy linkage dry-run: \(Self.userFacingMessage(for: apiError))"
        } catch {
            legacyLinkageExportMessage = "Couldn't export legacy linkage dry-run."
        }
    }

    @MainActor
    func loadRuntimeHealthTags() async {
        runtimeHealthErrorMessage = nil
        do {
            let response: StateRegistryResponse = try await api.get(path: "/api/v1/state-registry?limit=80")
            runtimeHealthTags = response.items
        } catch {
            runtimeHealthTags = []
            runtimeHealthErrorMessage = "Runtime health unavailable."
        }
    }

    func healthTags(for ticket: Ticket) -> [StateTagDTO] {
        let haystack = [
            ticket.title,
            ticket.description ?? "",
            ticket.assigneeAgentName ?? "",
            ticket.computeTag ?? "",
            ticket.ticketType ?? ""
        ].joined(separator: " ").lowercased()

        let basePrefixes = ["orca.", "nats.", "compute.", "memory.", "worker."]
        var tags = runtimeHealthTags.filter { tag in
            basePrefixes.contains { tag.tagId.hasPrefix($0) }
        }

        if haystack.contains("aloha") {
            tags += runtimeHealthTags.filter { $0.tagId.hasPrefix("agent.aloha") }
        }
        if haystack.contains("maui") || haystack.contains("pod") || haystack.contains("backend") {
            tags += runtimeHealthTags.filter { $0.tagId.hasPrefix("agent.maui") }
        }
        if haystack.contains("chief") || haystack.contains("fund") || haystack.contains("trading") {
            tags += runtimeHealthTags.filter { $0.tagId.hasPrefix("agent.chief") || $0.tagId.hasPrefix("surface.pod.chief") }
        }
        if haystack.contains("security") || haystack.contains("token") || haystack.contains("credential") {
            tags += runtimeHealthTags.filter { $0.tagId.hasPrefix("agent.rooster") }
        }

        var seen = Set<String>()
        return tags
            .filter { seen.insert($0.tagId).inserted }
            .sorted { lhs, rhs in
                if lhs.stale != rhs.stale { return lhs.stale && !rhs.stale }
                if (lhs.quality == "error") != (rhs.quality == "error") { return lhs.quality == "error" }
                return lhs.tagId < rhs.tagId
            }
            .prefix(8)
            .map { $0 }
    }

    func workerHealthSummary(for ticket: Ticket) -> TicketWorkerHealthSummary {
        let lane = SchoolhouseTicketDispatchService.workerLane(for: ticket)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !lane.isEmpty else {
            return TicketWorkerHealthSummary(lane: "unknown", total: 0, good: 0, stale: 0, error: 0, latestValue: nil)
        }

        let matches = runtimeHealthTags.filter { tag in
            let id = tag.tagId.lowercased()
            return id.hasPrefix("worker.\(lane)")
                || id.hasPrefix("agent.\(lane)")
                || id.contains(".\(lane).")
                || id.contains(".\(lane)_")
        }
        let good = matches.filter { $0.quality?.lowercased() == "good" && !$0.stale }.count
        let stale = matches.filter(\.stale).count
        let error = matches.filter { $0.quality?.lowercased() == "error" }.count
        let latest = matches
            .sorted { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
            .last?
            .valueText

        return TicketWorkerHealthSummary(
            lane: lane,
            total: matches.count,
            good: good,
            stale: stale,
            error: error,
            latestValue: latest
        )
    }

    @MainActor
    func loadWorkerQueue(workerLane: String) async {
        let lane = workerLane.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lane.isEmpty else { return }
        let encodedLane = lane.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? lane
        do {
            let dtos: [AgentRunDTO] = try await api.get(path: "/api/v1/agent-runs/worker-queue?worker_lane=\(encodedLane)&status_filter=queued&limit=25")
            workerQueuesByLane[lane] = dtos.map { $0.toDomain() }
            workerQueueErrorsByLane[lane] = nil
        } catch let apiError as APIError {
            workerQueuesByLane[lane] = []
            workerQueueErrorsByLane[lane] = Self.userFacingMessage(for: apiError)
        } catch {
            workerQueuesByLane[lane] = []
            workerQueueErrorsByLane[lane] = "Worker queue unavailable."
        }
    }

    func workerQueue(for lane: String) -> [AgentRun] {
        workerQueuesByLane[lane.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? []
    }

    func workerQueueError(for lane: String) -> String? {
        workerQueueErrorsByLane[lane.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    func actionContext(for ticket: Ticket) -> TicketActionContext {
        TicketActionContext(
            owner: ticket.assigneeAgentName ?? ticket.assigneeAgentId ?? "Unassigned",
            workerLane: SchoolhouseTicketDispatchService.workerLane(for: ticket),
            toolPolicy: SchoolhouseTicketDispatchService.toolPolicy(for: ticket),
            computeTag: SchoolhouseTicketDispatchService.normalizeComputeTag(ticket.computeTag)
        )
    }

    func ticketListSignal(for ticket: Ticket) -> TicketListSignal {
        if ticket.status == .closed || ticket.status == .cancelled {
            return TicketListSignal(
                label: ticket.status.label,
                detail: evidenceSummary(for: ticket).finalVerification,
                icon: ticket.status.icon,
                color: ticket.status.color
            )
        }

        if let flow = ticketFlowByTicketId[ticket.id] {
            return TicketListSignal(
                label: Self.flowStateLabel(flow.flowState),
                detail: Self.flowDetail(flow),
                icon: Self.flowStateIcon(flow.flowState, protected: flow.protected),
                color: Self.flowStateColor(flow.flowState, protected: flow.protected)
            )
        }

        let localBlockers = Self.localEvidenceBlockers(ticket: ticket, runs: agentRuns(for: ticket.id))
        if localBlockers.contains("waiting_for_human") {
            return TicketListSignal(
                label: "Needs Approval",
                detail: ticket.approvalGate ?? ticket.workerLane ?? "waiting for human",
                icon: "person.crop.circle.badge.exclamationmark",
                color: Color.orange
            )
        }
        if localBlockers.contains("protected_lane") {
            return TicketListSignal(
                label: "Protected",
                detail: ticket.workerLane ?? "protected lane",
                icon: "lock.shield",
                color: AppColors.accentDanger
            )
        }
        if localBlockers.contains("failed_run") {
            return TicketListSignal(
                label: "Run Failed",
                detail: "review evidence before retry",
                icon: "exclamationmark.triangle",
                color: AppColors.accentDanger
            )
        }
        if localBlockers.contains("missing_acceptance_criteria") || localBlockers.contains("missing_desired_outcome") {
            return TicketListSignal(
                label: "Needs Scope",
                detail: "add outcome and acceptance criteria",
                icon: "doc.badge.gearshape",
                color: Color.orange
            )
        }

        if needsOwnerReview(for: ticket) {
            return TicketListSignal(
                label: "Review Mermaid",
                detail: "owner decision needed",
                icon: "checkmark.seal",
                color: Color.orange
            )
        }

        if let summary = ticketSummariesByTicketId[ticket.id],
           summary.workerReviewRequiredCount > 0 || summary.blockers.contains("worker_review_required") {
            return TicketListSignal(
                label: "Review Mermaid",
                detail: "\(summary.workerReviewRequiredCount) worker result\(summary.workerReviewRequiredCount == 1 ? "" : "s") need owner review",
                icon: "checkmark.seal",
                color: Color.orange
            )
        }

        if let summary = ticketSummariesByTicketId[ticket.id],
           let run = summary.latestRun {
            let detail = [
                run.workerLane,
                run.backend ?? run.model
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(2)
                .joined(separator: " / ")
            return TicketListSignal(
                label: "Run \(run.status.label)",
                detail: detail.isEmpty ? run.runType.replacingOccurrences(of: "_", with: " ") : detail,
                icon: run.status.icon,
                color: run.status.color
            )
        }

        let runs = agentRuns(for: ticket.id)
        if let run = runs.sorted(by: { $0.updatedAt < $1.updatedAt }).last {
            let detail = [
                run.workerLane,
                run.backend ?? run.model,
                run.elapsedLabel
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(2)
                .joined(separator: " / ")
            return TicketListSignal(
                label: "Run \(run.status.label)",
                detail: detail.isEmpty ? run.runType.replacingOccurrences(of: "_", with: " ") : detail,
                icon: run.status.icon,
                color: run.status.color
            )
        }

        if let approvalState = ticket.approvalState?.trimmingCharacters(in: .whitespacesAndNewlines),
           !approvalState.isEmpty,
           !Self.isClearedApprovalState(approvalState) {
            let needsApproval = Self.isApprovalSignal(approvalState)
            return TicketListSignal(
                label: needsApproval ? "Needs Approval" : approvalState.replacingOccurrences(of: "_", with: " ").capitalized,
                detail: ticket.workerLane ?? ticket.toolPolicy ?? "approval state",
                icon: needsApproval ? "person.crop.circle.badge.exclamationmark" : "checkmark.shield",
                color: needsApproval ? Color.orange : AppColors.accentAgent
            )
        }

        let context = actionContext(for: ticket)
        if context.workerLane.hasPrefix("protected-") {
            return TicketListSignal(
                label: "Protected",
                detail: context.workerLane,
                icon: "lock.shield",
                color: AppColors.accentDanger
            )
        }
        return TicketListSignal(
            label: "Dispatchable",
            detail: context.workerLane,
            icon: "bolt.badge.clock",
            color: AppColors.accentAgent
        )
    }

    func needsOwnerReview(for ticket: Ticket) -> Bool {
        guard ticket.status != .closed && ticket.status != .cancelled else { return false }

        let detailRuns = agentRuns(for: ticket.id)
            .filter { $0.workerLane == "mermaid" || $0.runType.contains("execution") }
            .sorted { $0.updatedAt < $1.updatedAt }

        if let latest = detailRuns.last {
            return latest.workerLane == "mermaid"
                && latest.status == .succeeded
                && latest.reviewStatus?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }

        if let latestSummary = ticketSummariesByTicketId[ticket.id]?.latestRun {
            return latestSummary.workerLane == "mermaid" && latestSummary.status == .succeeded
        }

        return false
    }

    func latestTicketActivity(for ticket: Ticket) -> String? {
        if let summary = ticketSummariesByTicketId[ticket.id],
           let latestActivity = summary.latestActivity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latestActivity.isEmpty {
            return "\(latestActivity.prefix(92))"
        }

        let comments = comments(for: ticket.id).map {
            (date: $0.createdAt, label: $0.message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let runs = agentRuns(for: ticket.id).map {
            (date: $0.updatedAt, label: "\($0.runType.replacingOccurrences(of: "_", with: " ")) \($0.status.label)")
        }
        guard let latest = (comments + runs).sorted(by: { $0.date < $1.date }).last else {
            return nil
        }
        let clipped = latest.label.isEmpty ? "Activity recorded" : latest.label
        return "\(clipped.prefix(92))"
    }

    func evidenceSummary(for ticket: Ticket) -> TicketEvidenceSummary {
        let comments = comments(for: ticket.id)
        let runs = agentRuns(for: ticket.id)
        let approvals = approvals(for: ticket.id)
        let listSummary = ticketSummariesByTicketId[ticket.id]
        let latestRun = runs.sorted { $0.updatedAt < $1.updatedAt }.last
        let latestListRun = listSummary?.latestRun
        let approvalCount = comments.filter { Self.isApprovalSignal($0.message) || Self.isApprovalSignal($0.eventType) }.count
            + runs.filter { $0.status == .waitingForHuman || Self.isApprovalSignal($0.toolPolicy ?? "") }.count
            + approvals.count
        let dispatchCount = comments.filter { Self.isDispatchSignal($0.message) || Self.isDispatchSignal($0.eventType) || Self.isDispatchSignal($0.lane ?? "") }.count
            + runs.filter { Self.isDispatchSignal($0.runType) || Self.isDispatchSignal($0.caller ?? "") || Self.isDispatchSignal($0.lane ?? "") }.count
        let verification = Self.finalVerificationLabel(ticket: ticket, comments: comments, runs: runs)

        return TicketEvidenceSummary(
            commentCount: max(comments.count, listSummary?.commentCount ?? 0),
            runCount: max(runs.count, listSummary?.runCount ?? 0),
            failedRunCount: max(runs.filter { $0.status == .failed || $0.status == .blocked }.count, listSummary?.failedRunCount ?? 0),
            approvalCount: max(approvalCount, listSummary?.approvalCount ?? 0),
            dispatchCount: max(dispatchCount, listSummary?.dispatchCount ?? 0),
            queuedRunCount: max(runs.filter { $0.status == .queued }.count, listSummary?.queuedRunCount ?? 0),
            runningRunCount: max(runs.filter { $0.status == .running }.count, listSummary?.runningRunCount ?? 0),
            waitingRunCount: max(runs.filter { $0.status == .waitingForHuman }.count, listSummary?.waitingRunCount ?? 0),
            retryingRunCount: max(runs.filter { $0.status == .retrying }.count, listSummary?.retryingRunCount ?? 0),
            latestRunStatus: latestRun?.status ?? latestListRun?.status,
            latestRunRoute: latestRun.flatMap(Self.routeLabel(for:)) ?? latestListRun.flatMap(Self.routeLabel(for:)),
            latestRoutePacket: listSummary?.latestRoutePacket,
            blockers: listSummary?.blockers ?? Self.localEvidenceBlockers(ticket: ticket, runs: runs),
            nextAction: listSummary?.nextAction ?? Self.localNextAction(ticket: ticket, runs: runs),
            finalVerification: verification.label,
            finalVerificationColor: verification.color
        )
    }

    private static func localEvidenceBlockers(ticket: Ticket, runs: [AgentRun]) -> [String] {
        var blockers: [String] = []
        if ticket.acceptanceCriteria?.isEmpty != false {
            blockers.append("missing_acceptance_criteria")
        }
        if ticket.desiredOutcome?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            blockers.append("missing_desired_outcome")
        }
        if ticket.approvalState == "waiting_for_human" {
            blockers.append("waiting_for_human")
        }
        if ticket.workerLane?.hasPrefix("protected-") == true {
            blockers.append("protected_lane")
        }
        if runs.contains(where: { $0.status == .failed || $0.status == .blocked }) {
            blockers.append("failed_run")
        }
        return blockers
    }

    private static func flowDetail(_ flow: TicketFlowItem) -> String {
        let lane = flow.supportLane ?? flow.workerLane
        let owner = flow.ownerAgent.capitalized
        if let lane, !lane.isEmpty {
            return "\(owner) / \(lane)"
        }
        return flow.nextAction
    }

    private static func flowStateLabel(_ state: String) -> String {
        switch state {
        case "noise_review": return "Noise Review"
        case "needs_approval": return "Needs Approval"
        case "needs_scope": return "Needs Scope"
        case "needs_dispatch_plan": return "Needs Plan"
        case "needs_owner_review": return "Owner Review"
        case "ready_for_dispatch": return "Dispatchable"
        case "ready_to_close": return "Ready To Close"
        case "running": return "Running"
        case "blocked": return "Blocked"
        case "in_progress": return "In Progress"
        case "closed": return "Closed"
        case "cancelled": return "Cancelled"
        default:
            return state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func flowStateIcon(_ state: String, protected: Bool) -> String {
        if protected { return "lock.shield" }
        switch state {
        case "noise_review": return "exclamationmark.bubble"
        case "needs_approval": return "person.crop.circle.badge.exclamationmark"
        case "needs_scope": return "doc.badge.gearshape"
        case "needs_dispatch_plan": return "list.bullet.clipboard"
        case "needs_owner_review": return "checkmark.seal"
        case "ready_for_dispatch": return "bolt.badge.clock"
        case "ready_to_close": return "checkmark.circle"
        case "running": return "arrow.clockwise.circle"
        case "blocked": return "exclamationmark.triangle"
        default: return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    private static func flowStateColor(_ state: String, protected: Bool) -> Color {
        if protected { return AppColors.accentDanger }
        switch state {
        case "noise_review", "blocked": return AppColors.accentDanger
        case "needs_approval", "needs_scope", "needs_dispatch_plan", "needs_owner_review": return Color.orange
        case "ready_for_dispatch", "ready_to_close": return AppColors.accentAgent
        case "running", "in_progress": return AppColors.accentElectric
        case "closed": return AppColors.accentSuccess
        case "cancelled": return AppColors.textTertiary
        default: return AppColors.textSecondary
        }
    }

    private static func localNextAction(ticket: Ticket, runs: [AgentRun]) -> String? {
        let blockers = localEvidenceBlockers(ticket: ticket, runs: runs)
        if ticket.status == .closed || ticket.status == .cancelled {
            return "No action: ticket is terminal."
        }
        if blockers.contains("waiting_for_human") || blockers.contains("protected_lane") {
            return "Human approval/review required before dispatch."
        }
        if blockers.contains("missing_acceptance_criteria") || blockers.contains("missing_desired_outcome") {
            return "Add scope before worker dispatch."
        }
        if blockers.contains("failed_run") {
            return "Review failed run evidence and retry only if safe."
        }
        if runs.isEmpty {
            return "Ready for dispatch preview."
        }
        if let latest = runs.sorted(by: { $0.updatedAt < $1.updatedAt }).last {
            if latest.status == .succeeded {
                return "Review worker evidence and accept or close."
            }
            if [.queued, .running, .retrying].contains(latest.status) {
                return "Wait for worker run to complete."
            }
        }
        return "Review latest activity."
    }

    private static func routeLabel(for run: TicketListSummary.TicketListRunSummary) -> String? {
        let values = [
            run.workerLane.map { "worker \($0)" },
            run.backend,
            run.model,
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.prefix(3).joined(separator: " / ")
    }

    private static func routeLabel(for run: AgentRun) -> String? {
        let values = [
            run.workerLane.map { "worker \($0)" },
            run.toolPolicy,
            run.computeTag.map { "tag \($0)" },
            run.backend
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.prefix(3).joined(separator: " / ")
    }

    private static func isPrimaryLinkageField(_ value: String) -> Bool {
        [
            "source_chat_or_thread_link",
            "source_chat_url",
            "source_thread_url",
            "triage_id",
            "triage_trace_id"
        ].contains(value)
    }

    private static func displayLabel(_ rawValue: String) -> String {
        rawValue.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private static func compactList(_ values: [String], limit: Int = 3) -> String {
        let visible = values.prefix(limit).joined(separator: ", ")
        let remaining = values.count - min(values.count, limit)
        guard remaining > 0 else { return visible }
        return "\(visible) +\(remaining)"
    }

    private static func finalVerificationLabel(
        ticket: Ticket,
        comments: [TicketComment],
        runs: [AgentRun]
    ) -> (label: String, color: Color) {
        if let notes = ticket.resolutionNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            return ("Resolution notes", AppColors.accentSuccess)
        }
        if comments.contains(where: { isVerificationSignal($0.message) || isVerificationSignal($0.eventType) }) {
            return ("Verification comment", AppColors.accentSuccess)
        }
        if runs.contains(where: { $0.status == .succeeded && hasText($0.evidence) }) {
            return ("Run evidence", AppColors.accentSuccess)
        }
        if runs.contains(where: { $0.status == .succeeded && hasText($0.outcome) }) {
            return ("Run outcome", AppColors.accentSuccess)
        }
        if ticket.status == .closed {
            return ("Closed, verify evidence", AppColors.accentWarning)
        }
        return ("Pending", AppColors.textTertiary)
    }

    private static func hasText(_ value: String?) -> Bool {
        !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isApprovalSignal(_ value: String) -> Bool {
        let lower = value.lowercased()
        if isClearedApprovalState(lower) {
            return false
        }
        return lower.contains("approval")
            || lower.contains("waiting_for_human")
            || lower.contains("needs human")
            || lower.contains("protected")
    }

    private static func isClearedApprovalState(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return false
        }
        return [
            "approved",
            "human_approved",
            "approved_by_human",
            "not_required",
            "not-required",
            "none",
            "cleared"
        ].contains(normalized)
    }

    private static func isDispatchSignal(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("dispatch")
            || lower.contains("agent_run")
            || lower.contains("schoolhouse")
    }

    private static func isVerificationSignal(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("verify")
            || lower.contains("verification")
            || lower.contains("validated")
            || lower.contains("resolution")
            || lower.contains("done means")
    }

    // MARK: - Error classification

    private static func userFacingMessage(for error: APIError) -> String {
        switch error.code {
        case 401, 403:
            return "Signed out. Sign in to see your tickets."
        case 404:
            return "Tickets endpoint not found. Backend may be out of date."
        case 500...599:
            return "Server returned \(error.code). Engineers notified."
        case 0:
            return "Can't reach backend. Check your connection."
        default:
            return error.message.isEmpty ? "Couldn't load tickets (\(error.code))." : error.message
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return userFacingMessage(for: apiError)
        }
        return error.localizedDescription
    }

    // MARK: - Mock Fallback (DEBUG previews only — 2026-05-07: no longer hit in production)

    #if DEBUG
    static var mockTickets: [Ticket] {
        let now = Date()
        return [
            Ticket(
                id: "TICKET-001",
                title: "Voice Companion Tab (Whisplay)",
                description: "Add Whisplay voice companion as a dedicated tab in the Pod app.",
                status: .open,
                priority: .medium,
                assigneeAgentId: "maui",
                assigneeAgentName: "Maui",
                ticketType: "feature",
                tags: ["pod", "voice"],
                computeTag: "code",
                parentTicketId: nil,
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-86400),
                updatedAt: now.addingTimeInterval(-86400),
                claimedAt: nil, startedAt: nil, resolvedAt: nil, resolutionNotes: nil
            ),
            Ticket(
                id: "TICKET-002",
                title: "Connect Projects Tab to Live Ticket Data",
                description: "Replace mock data in Projects tab with live data from ticket API.",
                status: .inProgress,
                priority: .medium,
                assigneeAgentId: "maui",
                assigneeAgentName: "Maui",
                ticketType: "feature",
                tags: ["pod", "projects"],
                computeTag: "code",
                parentTicketId: nil,
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-72000),
                updatedAt: now.addingTimeInterval(-3600),
                claimedAt: now.addingTimeInterval(-72000), startedAt: now.addingTimeInterval(-3600),
                resolvedAt: nil, resolutionNotes: nil
            ),
            Ticket(
                id: "TICKET-003",
                title: "Both Apps Showing Demo Data",
                description: "iPhone and iPad showing demo agents (Kai, Orca, Pulse). Need real team mock data.",
                status: .open,
                priority: .high,
                assigneeAgentId: "maui",
                assigneeAgentName: "Maui",
                ticketType: "bugfix",
                tags: ["pod", "demo-data"],
                computeTag: "code",
                parentTicketId: nil,
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-3600),
                updatedAt: now.addingTimeInterval(-1800),
                claimedAt: nil, startedAt: nil, resolvedAt: nil, resolutionNotes: nil
            ),
            Ticket(
                id: "TICKET-004",
                title: "Pod Trading Dashboard",
                description: "Add Trading tab with P&L, Octopus/Squid, Oracle, Earnings, and macro predictions.",
                status: .open,
                priority: .high,
                assigneeAgentId: "maui",
                assigneeAgentName: "Maui",
                ticketType: "feature",
                tags: ["fund", "pod"],
                computeTag: "financial",
                parentTicketId: nil,
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-1800),
                updatedAt: now.addingTimeInterval(-1800),
                claimedAt: nil, startedAt: nil, resolvedAt: nil, resolutionNotes: nil
            ),
            // POD-4 subtask example
            Ticket(
                id: "TICKET-001-SUB",
                title: "Design Whisplay voice UX",
                description: "Design the voice companion tab UI and interaction flow.",
                status: .open,
                priority: .medium,
                assigneeAgentId: "maui",
                assigneeAgentName: "Maui",
                ticketType: "design",
                tags: ["pod", "voice", "design"],
                computeTag: "general",
                parentTicketId: "TICKET-001",
                lessonsLearned: nil,
                createdAt: now.addingTimeInterval(-80000),
                updatedAt: now.addingTimeInterval(-80000),
                claimedAt: nil, startedAt: nil, resolvedAt: nil, resolutionNotes: nil
            )
        ]
    }
    #endif

    // MARK: - Create

    @MainActor
    func loadBoardOptions() async {
        if isLoadingBoardOptions { return }
        isLoadingBoardOptions = true
        boardOptionsMessage = nil
        defer { isLoadingBoardOptions = false }

        do {
            let response: TicketBoardListResponse = try await api.get(path: "/api/v1/boards")
            newBoardOptions = response.items
                .map(\.option)
                .sorted { lhs, rhs in
                    let lhsIndex = TicketBoardOption.preferredSlugs.firstIndex(of: lhs.slug) ?? Int.max
                    let rhsIndex = TicketBoardOption.preferredSlugs.firstIndex(of: rhs.slug) ?? Int.max
                    if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                    return lhs.displayName < rhs.displayName
                }
            if newBoardId.isEmpty {
                newBoardId = Self.defaultBoardId(from: newBoardOptions, ticketType: newTicketType, tags: newTags)
            }
            if newBoardOptions.isEmpty {
                boardOptionsMessage = "ORCA returned no boards. Board selection is required before create."
            }
        } catch {
            newBoardOptions = []
            boardOptionsMessage = "ORCA boards unavailable. Board selection is required before create."
        }
    }

    @MainActor
    func draftTicketFromIntake(agents: [AgentDTO]) async {
        let intake = roughIntake.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !intake.isEmpty else { return }

        isDrafting = true
        draftMessage = nil
        defer { isDrafting = false }

        do {
            let draft = try await ComputeTicketDraftService.draft(from: intake)
            newTitle = draft.title
            newDescription = draft.description
            newPriority = draft.priority
            newTicketType = draft.ticketType
            newTags = draft.tags.joined(separator: ", ")
            newComputeTag = draft.computeTag
            newBoardId = Self.defaultBoardId(from: newBoardOptions, ticketType: newTicketType, tags: newTags)
            newAcceptanceCriteria = Self.defaultAcceptanceCriteria(from: draft.description)
            newDoneMeans = Self.defaultDoneMeans(from: draft.description)
            newAssigneeAgentId = Self.agentId(for: draft.suggestedAgentId, agents: agents) ?? ""
            draftMessage = draft.suggestedAgentId.isEmpty
                ? "Draft filled by compute."
                : "Draft filled by compute. Suggested owner: \(draft.suggestedAgentId)."
        } catch {
            let draft = ComputeTicketDraftService.localDraft(from: intake)
            newTitle = draft.title
            newDescription = draft.description
            newPriority = draft.priority
            newTicketType = draft.ticketType
            newTags = draft.tags.joined(separator: ", ")
            newComputeTag = draft.computeTag
            newBoardId = Self.defaultBoardId(from: newBoardOptions, ticketType: newTicketType, tags: newTags)
            newAcceptanceCriteria = Self.defaultAcceptanceCriteria(from: draft.description)
            newDoneMeans = Self.defaultDoneMeans(from: draft.description)
            newAssigneeAgentId = Self.agentId(for: draft.suggestedAgentId, agents: agents) ?? ""
            draftMessage = "Compute was unavailable, so Pod used a local triage draft."
        }
    }

    @MainActor
    func previewDirection(agents: [AgentDTO]) async {
        let intake = [
            roughIntake,
            newTitle,
            newDescription,
            newTags
        ]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !intake.isEmpty else { return }

        isPreviewingDirection = true
        directionPreviewMessage = nil
        defer { isPreviewingDirection = false }

        do {
            let request = MermanTicketDirectionRequest(
                surface: "pod_ticket_create",
                target: nil,
                text: intake,
                context: [
                    "source": "pod_ticket_create",
                    "existing_assignee_agent_id": newAssigneeAgentId,
                    "ticket_type": newTicketType,
                    "compute_tag": newComputeTag
                ]
            )
            let response: MermanTicketDirectionResponse = try await api.post(
                path: "/api/v1/schoolhouse/triage",
                body: request
            )
            let preview = TicketDirectionPreview(response: response)
            directionPreview = preview
            directionPreviewMessage = "ORCA suggests \(preview.ownerDisplay) · \(preview.nextActionDisplay)."
            applyDirectionPreview(preview, agents: agents)
        } catch {
            directionPreview = nil
            directionPreviewMessage = "ORCA direction unavailable. Keep this as draft or route manually."
        }
    }

    @MainActor
    private func applyDirectionPreview(_ preview: TicketDirectionPreview, agents: [AgentDTO]) {
        if let agentId = Self.agentId(for: preview.suggestedOwner, agents: agents) {
            newAssigneeAgentId = agentId
        }
        if !preview.suggestedComputeRoute.isEmpty {
            newComputeTag = preview.suggestedComputeRoute
        }
        if let worker = preview.suggestedWorker, !worker.isEmpty {
            newWorkerLane = worker
            newToolPolicy = Self.toolPolicy(forWorkerLane: worker)
            newTags = Self.mergingTags(newTags, ["worker:\(worker)"])
        }
        newTags = Self.mergingTags(newTags, preview.tags)
        if newBoardId.isEmpty {
            newBoardId = Self.defaultBoardId(from: newBoardOptions, ticketType: newTicketType, tags: newTags)
        }
        newApprovalState = preview.needsApproval ? "waiting_for_human" : "not_required"
        newApprovalGate = preview.approvalGate ?? ""
        newAutonomyLevel = preview.needsApproval ? "protected_approval_required" : "inspect_only"

        if preview.needsApproval {
            newAcceptanceCriteria = Self.appendMissingLine(
                "Protected-domain approval is recorded before mutation.",
                to: newAcceptanceCriteria
            )
        }
        if preview.needsTicket {
            newAcceptanceCriteria = Self.appendMissingLine(
                "Owner confirms ORCA direction before dispatch.",
                to: newAcceptanceCriteria
            )
        }
    }

    @MainActor
    func createTicket() async {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !newBoardId.isEmpty else {
            boardOptionsMessage = "Choose an ORCA board before creating this ticket."
            return
        }
        isCreating = true
        defer { isCreating = false }

        let body = CreateTicketBody(
            title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            description: Self.composedDescription(
                description: newDescription,
                acceptanceCriteria: newAcceptanceCriteria,
                doneMeans: newDoneMeans
            ),
            priority: Self.apiPriority(newPriority),
            assigneeAgentId: newAssigneeAgentId.isEmpty ? nil : newAssigneeAgentId,
            ticketType: newTicketType.isEmpty ? nil : newTicketType,
            tags: Self.parseTags(newTags),
            computeTag: newComputeTag.isEmpty ? nil : newComputeTag,
            approvalState: Self.nilIfBlank(newApprovalState),
            approvalGate: Self.nilIfBlank(newApprovalGate),
            autonomyLevel: Self.nilIfBlank(newAutonomyLevel),
            workerLane: Self.nilIfBlank(newWorkerLane),
            toolPolicy: Self.nilIfBlank(newToolPolicy),
            acceptanceCriteria: Self.normalizedLines(newAcceptanceCriteria).map {
                $0.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            },
            desiredOutcome: newDoneMeans.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newDoneMeans.trimmingCharacters(in: .whitespacesAndNewlines),
            triageId: directionPreview?.triageId,
            triageTraceId: directionPreview?.traceId,
            recommendedRuntime: directionPreview?.recommendedRuntime,
            recommendedSurface: directionPreview?.recommendedSurface,
            runtimeReason: directionPreview?.runtimeReason,
            handoffSubject: directionPreview?.handoffSubject,
            handoffPacket: Self.handoffPacket(for: directionPreview),
            boardId: newBoardId,
            parentTicketId: nil,
            lessonsLearned: nil
        )

        do {
            let _: TicketDTO = try await api.post(path: "/api/v1/tickets", body: body)
            newTitle = ""
            newDescription = ""
            newAssigneeAgentId = ""
            newPriority = .normal
            newTicketType = "support"
            newTags = ""
            newComputeTag = "classify"
            newApprovalState = "not_required"
            newApprovalGate = ""
            newAutonomyLevel = "inspect_only"
            newWorkerLane = "mermaid"
            newToolPolicy = "bounded_workspace_edits_owner_review"
            newAcceptanceCriteria = ""
            newDoneMeans = ""
            newBoardId = Self.defaultBoardId(from: newBoardOptions, ticketType: newTicketType, tags: newTags)
            roughIntake = ""
            draftMessage = nil
            directionPreview = nil
            directionPreviewMessage = nil
            showCreateSheet = false
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't create ticket: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't create ticket. Try again."
        }
    }

    private static func apiPriority(_ priority: TicketPriority) -> String {
        priority == .normal ? "medium" : priority.rawValue
    }

    private static func defaultBoardId(from boards: [TicketBoardOption], ticketType: String, tags: String) -> String {
        let searchable = "\(ticketType) \(tags)".lowercased()
        let preferredSlug: String
        if searchable.contains("chat") {
            preferredSlug = "chat"
        } else if searchable.contains("memory") || searchable.contains("knowledge") {
            preferredSlug = "memory"
        } else if searchable.contains("compute") || searchable.contains("runtime") {
            preferredSlug = "compute"
        } else if searchable.contains("nats") || searchable.contains("nerve") {
            preferredSlug = "nerve"
        } else if searchable.contains("governance") || searchable.contains("dds") || searchable.contains("sop") {
            preferredSlug = "governance"
        } else if searchable.contains("pod") || searchable.contains("ui") {
            preferredSlug = "pod"
        } else if searchable.contains("orca") || searchable.contains("ticket") || searchable.contains("project") {
            preferredSlug = "orca"
        } else {
            preferredSlug = "pod"
        }
        return boards.first(where: { $0.slug == preferredSlug })?.id ?? boards.first?.id ?? ""
    }

    private static func parseTags(_ value: String) -> [String]? {
        let tags = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return tags.isEmpty ? nil : tags
    }

    private static func composedDescription(
        description: String,
        acceptanceCriteria: String,
        doneMeans: String
    ) -> String? {
        var sections: [String] = []
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            sections.append(trimmedDescription)
        }

        let criteria = normalizedLines(acceptanceCriteria)
        if !criteria.isEmpty {
            sections.append("## Acceptance Criteria\n\n" + criteria.joined(separator: "\n"))
        }

        let done = doneMeans.trimmingCharacters(in: .whitespacesAndNewlines)
        if !done.isEmpty {
            sections.append("## Done Means\n\n" + done)
        }

        let composed = sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return composed.isEmpty ? nil : composed
    }

    private static func normalizedLines(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return "- " + String(trimmed.dropFirst(2)) }
                return "- \(trimmed)"
            }
            .filter { $0.count > 2 }
    }

    private static func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func handoffPacket(for preview: TicketDirectionPreview?) -> [String: String] {
        [
            "surface": "pod_tickets",
            "triage_id": preview?.triageId ?? "",
            "triage_trace_id": preview?.traceId ?? "",
            "intent_type": preview?.intentType ?? "",
            "recommended_lane": preview?.recommendedLane ?? "",
            "owner_agent": preview?.suggestedOwner ?? "",
            "worker_lane": preview?.suggestedWorker ?? "",
            "recommended_runtime": preview?.recommendedRuntime ?? "unknown",
            "recommended_surface": preview?.recommendedSurface ?? "pod_tickets",
            "runtime_reason": preview?.runtimeReason ?? "",
            "handoff_subject": preview?.handoffSubject ?? "",
            "compute_route": preview?.suggestedComputeRoute ?? "auto",
            "next_action": preview?.nextAction ?? "",
        ].filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func toolPolicy(forWorkerLane workerLane: String) -> String {
        switch workerLane.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "protected-chief-review":
            return "read_only_until_chief_rooster_tony_approval"
        case "protected-rooster-review":
            return "read_only_until_rooster_tony_approval"
        case "mermaid":
            return "bounded_workspace_edits_owner_review"
        case "coral", "reef":
            return "runtime_support_dry_run_or_owner_review"
        default:
            return "owner_review_required"
        }
    }

    private static func defaultAcceptanceCriteria(from description: String) -> String {
        if description.localizedCaseInsensitiveContains("## Acceptance Criteria") {
            return ""
        }
        return """
        Owner confirms scope, priority, and routing.
        Evidence or test notes are attached before closure.
        Protected-domain approval is recorded before mutation when applicable.
        """
    }

    private static func defaultDoneMeans(from description: String) -> String {
        if description.localizedCaseInsensitiveContains("## Done Means") {
            return ""
        }
        return "Ticket is closed only after the requester can verify the outcome and ORCA has evidence or resolution notes."
    }

    private static func agentId(for suggested: String, agents: [AgentDTO]) -> String? {
        let normalized = suggested.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return agents.first { agent in
            (agent.domainRosterLane == .activeMain || agent.domainRosterLane == .supportRuntime)
                && (agent.name.lowercased() == normalized || agent.id.lowercased() == normalized)
        }?.id
    }

    private static func mergingTags(_ existing: String, _ incoming: [String]) -> String {
        var seen: Set<String> = []
        let merged = ((Self.parseTags(existing) ?? []) + incoming.map(normalizeTagForDisplay))
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
        return merged.joined(separator: ", ")
    }

    private static func normalizeTagForDisplay(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#,.;: \n\t"))
    }

    private static func appendMissingLine(_ line: String, to existing: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains(line) {
            return existing
        }
        if trimmed.isEmpty {
            return line
        }
        return trimmed + "\n" + line
    }

    // MARK: - Update Status

    @MainActor
    func updateStatus(ticketId: String, status: TicketStatus) async {
        do {
            let body = UpdateTicketBody(status: status.rawValue)
            let _: TicketDTO = try await api.patch(path: "/api/v1/tickets/\(ticketId)", body: body)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't update status: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't update status. Try again."
        }
    }

    // Tap-to-edit priority — optimistic local update, revert on failure.
    @MainActor
    func updatePriority(ticketId: String, priority: TicketPriority) async {
        guard let idx = tickets.firstIndex(where: { $0.id == ticketId }) else { return }
        let original = tickets[idx]
        guard original.priority != priority else { return }
        tickets[idx] = Self.replacingPriority(original, with: priority)
        do {
            let body = UpdateTicketBody(priority: Self.apiPriority(priority))
            let _: TicketDTO = try await api.patch(path: "/api/v1/tickets/\(ticketId)", body: body)
        } catch let apiError as APIError {
            if let restoreIdx = tickets.firstIndex(where: { $0.id == ticketId }) {
                tickets[restoreIdx] = original
            }
            errorMessage = "Couldn't update priority: \(Self.userFacingMessage(for: apiError))"
        } catch {
            if let restoreIdx = tickets.firstIndex(where: { $0.id == ticketId }) {
                tickets[restoreIdx] = original
            }
            errorMessage = "Couldn't update priority. Try again."
        }
    }

    private static func replacingPriority(_ ticket: Ticket, with newPriority: TicketPriority) -> Ticket {
        Ticket(
            id: ticket.id,
            title: ticket.title,
            description: ticket.description,
            status: ticket.status,
            priority: newPriority,
            assigneeAgentId: ticket.assigneeAgentId,
            assigneeAgentName: ticket.assigneeAgentName,
            ticketType: ticket.ticketType,
            tags: ticket.tags,
            source: ticket.source,
            sourceChatURL: ticket.sourceChatURL,
            sourceThreadURL: ticket.sourceThreadURL,
            computeTag: ticket.computeTag,
            approvalState: ticket.approvalState,
            approvalGate: ticket.approvalGate,
            autonomyLevel: ticket.autonomyLevel,
            workerLane: ticket.workerLane,
            toolPolicy: ticket.toolPolicy,
            acceptanceCriteria: ticket.acceptanceCriteria,
            desiredOutcome: ticket.desiredOutcome,
            triageId: ticket.triageId,
            triageTraceId: ticket.triageTraceId,
            chatThreadId: ticket.chatThreadId,
            parentTicketId: ticket.parentTicketId,
            lessonsLearned: ticket.lessonsLearned,
            createdAt: ticket.createdAt,
            updatedAt: Date(),
            claimedAt: ticket.claimedAt,
            startedAt: ticket.startedAt,
            resolvedAt: ticket.resolvedAt,
            resolutionNotes: ticket.resolutionNotes
        )
    }

    @MainActor
    func updateTicket(
        ticketId: String,
        title: String,
        description: String,
        priority: TicketPriority,
        acceptanceCriteria: [String]? = nil,
        desiredOutcome: String? = nil,
        approvalState: String? = nil,
        autonomyLevel: String? = nil,
        workerLane: String? = nil,
        toolPolicy: String? = nil
    ) async {
        do {
            let body = UpdateTicketBody(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                priority: Self.apiPriority(priority),
                approvalState: approvalState,
                autonomyLevel: autonomyLevel,
                workerLane: workerLane,
                toolPolicy: toolPolicy,
                acceptanceCriteria: acceptanceCriteria,
                desiredOutcome: desiredOutcome
            )
            let _: TicketDTO = try await api.patch(path: "/api/v1/tickets/\(ticketId)", body: body)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't save ticket: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't save ticket. Try again."
        }
    }

    // MARK: - Lifecycle Actions

    @MainActor
    func claimTicket(ticketId: String, agentId: String) async {
        do {
            let body = TicketAgentActionBody(agentId: agentId)
            let _: TicketDTO = try await api.post(path: "/api/v1/tickets/\(ticketId)/claim", body: body)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't claim ticket: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't claim ticket. Try again."
        }
    }

    @MainActor
    func startTicket(ticketId: String, agentId: String) async {
        do {
            let body = TicketAgentActionBody(agentId: agentId)
            let _: TicketDTO = try await api.post(path: "/api/v1/tickets/\(ticketId)/start", body: body)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't start ticket: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't start ticket. Try again."
        }
    }

    @MainActor
    func completeTicket(ticketId: String, agentId: String, resolutionNotes: String) async {
        do {
            let body = CompleteTicketBody(
                agentId: agentId,
                resolutionNotes: resolutionNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : resolutionNotes
            )
            let _: TicketDTO = try await api.post(path: "/api/v1/tickets/\(ticketId)/complete", body: body)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't close ticket: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't close ticket. Try again."
        }
    }

    @MainActor
    func cancelTicket(ticketId: String, reason: String) async {
        do {
            let body = UpdateTicketBody(
                status: TicketStatus.cancelled.rawValue,
                resolutionNotes: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cancelled from Pod" : reason
            )
            let _: TicketDTO = try await api.patch(path: "/api/v1/tickets/\(ticketId)", body: body)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't cancel ticket: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't cancel ticket. Try again."
        }
    }

    @MainActor
    func postTicketNote(ticketId: String, message: String) async -> Bool {
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return false }

        do {
            let comment = TicketCommentBody(
                message: note,
                traceId: Self.makeTraceId(prefix: "pod-note"),
                source: "pod.tickets.shared_note",
                lane: "shared_note"
            )
            let _: TicketCommentDTO = try await api.post(
                path: "/api/v1/tickets/\(ticketId)/comments",
                body: comment
            )
            await loadComments(ticketId: ticketId)
            await loadTicketSummaries(limit: limitForSummaries)
            return true
        } catch let apiError as APIError {
            errorMessage = "Couldn't add note: \(Self.userFacingMessage(for: apiError))"
            return false
        } catch {
            errorMessage = "Couldn't add note. Try again."
            return false
        }
    }

    @MainActor
    func loadApprovals(ticketId: String) async {
        loadingTicketApprovalIds.insert(ticketId)
        ticketApprovalErrorsByTicketId[ticketId] = nil
        defer { loadingTicketApprovalIds.remove(ticketId) }

        do {
            let dtos: [TicketApprovalDTO] = try await api.get(path: "/api/v1/tickets/\(ticketId)/approvals")
            ticketApprovalsByTicketId[ticketId] = dtos.map(\.toDomain)
        } catch let apiError as APIError {
            ticketApprovalErrorsByTicketId[ticketId] = "Approvals unavailable: \(Self.userFacingMessage(for: apiError))"
        } catch {
            ticketApprovalErrorsByTicketId[ticketId] = "Approvals unavailable."
        }
    }

    func approvals(for ticketId: String) -> [TicketApprovalRecord] {
        ticketApprovalsByTicketId[ticketId] ?? []
    }

    func approvalsError(for ticketId: String) -> String? {
        ticketApprovalErrorsByTicketId[ticketId]
    }

    func isLoadingApprovals(for ticketId: String) -> Bool {
        loadingTicketApprovalIds.contains(ticketId)
    }

    func approvalAuthoritySpec(for actionType: String) -> ApprovalRegistrySpec? {
        approvalRegistrySpecs[actionType.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    @MainActor
    func loadApprovalRegistry() async {
        if isLoadingApprovalRegistry { return }
        isLoadingApprovalRegistry = true
        approvalRegistryErrorMessage = nil
        defer { isLoadingApprovalRegistry = false }

        do {
            let response: ApprovalRegistryResponse = try await api.get(path: "/api/v1/approval-registry")
            approvalRegistrySpecs = response.actionTypes
        } catch let apiError as APIError {
            approvalRegistryErrorMessage = "Approval registry unavailable: \(Self.userFacingMessage(for: apiError))"
        } catch {
            approvalRegistryErrorMessage = "Approval registry unavailable."
        }
    }

    @MainActor
    func createOrcaTicketNote(
        ticketId: String,
        title: String,
        body: String,
        noteType: String = "note",
        tags: [String] = ["pod", "ticket-note"]
    ) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty else { return false }

        do {
            let request = TicketNoteCreateBody(
                targetType: "ticket",
                targetId: ticketId,
                noteType: noteType,
                title: trimmedTitle,
                body: trimmedBody,
                tags: tags,
                source: "pod.tickets.notes",
                traceId: Self.makeTraceId(prefix: "pod-orca-note")
            )
            let _: TicketNoteDTO = try await api.post(
                path: "/api/v1/notes/tickets/\(ticketId)",
                body: request
            )
            await loadNotes(ticketId: ticketId)
            return true
        } catch let apiError as APIError {
            errorMessage = "Couldn't add ORCA note: \(Self.userFacingMessage(for: apiError))"
            return false
        } catch {
            errorMessage = "Couldn't add ORCA note. Try again."
            return false
        }
    }

    @MainActor
    func approveTicket(_ ticket: Ticket) async {
        do {
            let request = TicketApprovalRequestBody(
                reason: """
                Approval review requested from Pod for ticket: \(ticket.title).

                Pod did not clear the approval gate. Formal protected-domain approval must be resolved through ORCA approval authority before mutation or protected execution.
                """,
                traceId: Self.makeTraceId(prefix: "pod-approval-request"),
                source: "pod.tickets.approval_request",
                lane: "human_approval_request"
            )
            let approval: TicketApprovalDTO = try await api.post(
                path: "/api/v1/tickets/\(ticket.id)/approval-requests",
                body: request
            )
            dispatchMessage = "Approval \(approval.approvalId) requested for \(ticket.id)."
            await loadApprovals(ticketId: ticket.id)
            await loadComments(ticketId: ticket.id)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't request approval review: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't request approval review. Try again."
        }
    }

    @MainActor
    func resolveApproval(
        ticketId: String,
        approvalId: String,
        approved: Bool,
        reason: String
    ) async {
        do {
            let request = TicketApprovalResolutionBody(
                status: approved ? "approved" : "rejected",
                reason: reason,
                traceId: Self.makeTraceId(prefix: approved ? "pod-approval-approved" : "pod-approval-rejected"),
                source: "pod.tickets.approval_resolution",
                lane: "human_approval_resolution"
            )
            let _: TicketApprovalDTO = try await api.patch(
                path: "/api/v1/tickets/\(ticketId)/approvals/\(approvalId)",
                body: request
            )
            dispatchMessage = approved
                ? "Approval \(approvalId) approved for \(ticketId)."
                : "Approval \(approvalId) rejected for \(ticketId)."
            await loadApprovals(ticketId: ticketId)
            await loadComments(ticketId: ticketId)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't resolve approval: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't resolve approval. Try again."
        }
    }

    // MARK: - Update Lessons Learned

    @MainActor
    func updateLessonsLearned(ticketId: String, lessonsLearned: String) async {
        do {
            let body = UpdateTicketLessonsBody(lessonsLearned: lessonsLearned)
            let _: TicketDTO = try await api.patch(path: "/api/v1/tickets/\(ticketId)", body: body)
            await load()
        } catch let apiError as APIError {
            errorMessage = "Couldn't save lessons: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't save lessons. Try again."
        }
    }

    // MARK: - Schoolhouse Dispatch

    @MainActor
    func dispatchTicketToSchoolhouse(_ ticket: Ticket) async {
        guard !isDispatching else { return }
        isDispatching = true
        dispatchMessage = nil
        defer { isDispatching = false }

        let traceId = Self.makeTraceId(prefix: "pod-dispatch")
        var createdRun: AgentRun?
        do {
            var backendDispatchError: Error?
            do {
                let backendDispatch = try await dispatchTicketThroughORCA(ticket)
                if let execution = try? await queueExecutionThroughORCA(dispatchRunId: backendDispatch.run.id) {
                    if execution.run.status == .waitingForHuman {
                        dispatchMessage = "Schoolhouse dispatch recorded; execution paused for human approval."
                    } else {
                        dispatchMessage = "Schoolhouse dispatch recorded; \(execution.run.workerLane ?? "worker") execution queued."
                    }
                } else {
                    dispatchMessage = backendDispatch.message
                }
                await loadComments(ticketId: ticket.id)
                await loadAgentRuns(ticketId: ticket.id)
                await load()
                return
            } catch {
                backendDispatchError = error
                dispatchMessage = "Backend dispatch unavailable; using Pod fallback evidence path."
            }

            createdRun = await createAgentRunIfAvailable(for: ticket, traceId: traceId)
            if let createdRun {
                await updateAgentRunIfAvailable(
                    runId: createdRun.id,
                    status: .running,
                    outcome: nil,
                    evidence: nil,
                    error: nil,
                    backend: nil,
                    model: nil,
                    latencyMs: nil
                )
            }
            let run = try await SchoolhouseTicketDispatchService.dispatch(ticket: ticket, traceId: traceId)
            let fallbackNote = backendDispatchError.map { "\n\nBackend dispatch fallback: \(Self.userFacingMessage(for: $0))" } ?? ""
            let comment = TicketCommentBody(
                message: run.commentBody + fallbackNote,
                traceId: traceId,
                source: backendDispatchError == nil ? "pod.tickets" : "pod.tickets.dispatch_fallback",
                lane: backendDispatchError == nil ? "agent_run" : "pod_dispatch_fallback"
            )
            let _: TicketCommentDTO = try await api.post(
                path: "/api/v1/tickets/\(ticket.id)/comments",
                body: comment
            )
            if let createdRun {
                await updateAgentRunIfAvailable(
                    runId: createdRun.id,
                    status: .succeeded,
                    outcome: run.outcome,
                    evidence: run.commentBody,
                    error: nil,
                    backend: run.backend,
                    model: run.model,
                    latencyMs: run.latencyMs
                )
                dispatchMessage = backendDispatchError == nil
                    ? "Schoolhouse run recorded in ORCA."
                    : "Backend dispatch unavailable; fallback evidence recorded in ORCA."
            } else {
                dispatchMessage = backendDispatchError == nil
                    ? "Schoolhouse evidence posted to ORCA."
                    : "Backend dispatch unavailable; fallback evidence posted to ORCA."
            }
            await loadComments(ticketId: ticket.id)
            await loadAgentRuns(ticketId: ticket.id)
            await load()
        } catch let apiError as APIError {
            if let createdRun {
                await updateAgentRunIfAvailable(
                    runId: createdRun.id,
                    status: .failed,
                    outcome: nil,
                    evidence: nil,
                    error: Self.userFacingMessage(for: apiError),
                    backend: "compute-router",
                    model: "compute",
                    latencyMs: nil
                )
                await loadAgentRuns(ticketId: ticket.id)
            }
            errorMessage = "Schoolhouse dispatch failed: \(Self.userFacingMessage(for: apiError))"
        } catch {
            if let createdRun {
                await updateAgentRunIfAvailable(
                    runId: createdRun.id,
                    status: .failed,
                    outcome: nil,
                    evidence: nil,
                    error: "Compute or ORCA dispatch failed.",
                    backend: "compute-router",
                    model: "compute",
                    latencyMs: nil
                )
                await loadAgentRuns(ticketId: ticket.id)
            }
            errorMessage = "Schoolhouse dispatch failed. Check compute and ticket comments."
        }
    }

    @MainActor
    func loadDispatchPreview(ticketId: String) async {
        do {
            let dto: AgentRunDispatchPreviewDTO = try await api.post(
                path: "/api/v1/agent-runs/tickets/\(ticketId)/dispatch-preview",
                body: EmptyRequestBody()
            )
            dispatchPreviewsByTicketId[ticketId] = dto.toDomain()
            dispatchPreviewErrorsByTicketId[ticketId] = nil
        } catch let apiError as APIError {
            dispatchPreviewErrorsByTicketId[ticketId] = Self.userFacingMessage(for: apiError)
        } catch {
            dispatchPreviewErrorsByTicketId[ticketId] = "Dispatch preview unavailable."
        }
    }

    func dispatchPreview(for ticketId: String) -> TicketDispatchPreview? {
        dispatchPreviewsByTicketId[ticketId]
    }

    func dispatchPreviewError(for ticketId: String) -> String? {
        dispatchPreviewErrorsByTicketId[ticketId]
    }

    @MainActor
    func retryAgentRun(_ run: AgentRun, ticket: Ticket) async {
        do {
            let body = AgentRunRetryBody(reason: "Retry requested from Pod after reviewing Mermaid evidence.")
            let dto: AgentRunDTO = try await api.post(path: "/api/v1/agent-runs/\(run.id)/retry", body: body)
            var runs = agentRunsByTicketId[ticket.id] ?? []
            runs.removeAll { $0.id == run.id }
            runs.insert(dto.toDomain(), at: 0)
            agentRunsByTicketId[ticket.id] = runs
            dispatchMessage = "Retry queued for \(run.workerLane ?? "worker") run."
            await loadAgentRuns(ticketId: ticket.id)
            await loadTicketSummaries()
        } catch let apiError as APIError {
            errorMessage = "Couldn't retry run: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't retry run. Try again."
        }
    }

    @MainActor
    func reviewAgentRun(_ run: AgentRun, ticket: Ticket, reviewStatus: String) async {
        do {
            let label = reviewStatus.replacingOccurrences(of: "_", with: " ")
            let body = AgentRunReviewBody(
                reviewStatus: reviewStatus,
                reviewedBy: "maui",
                reviewNote: "Owner review recorded from Pod: \(label)."
            )
            let dto: AgentRunDTO = try await api.post(path: "/api/v1/agent-runs/\(run.id)/review", body: body)
            var runs = agentRunsByTicketId[ticket.id] ?? []
            runs.removeAll { $0.id == run.id }
            runs.insert(dto.toDomain(), at: 0)
            agentRunsByTicketId[ticket.id] = runs
            dispatchMessage = "Mermaid run review recorded: \(label)."
            await loadAgentRuns(ticketId: ticket.id)
            await loadTicketSummaries()
        } catch let apiError as APIError {
            errorMessage = "Couldn't review run: \(Self.userFacingMessage(for: apiError))"
        } catch {
            errorMessage = "Couldn't review run. Try again."
        }
    }

    @MainActor
    private func dispatchTicketThroughORCA(_ ticket: Ticket) async throws -> AgentRunDispatch {
        let dto: AgentRunDispatchDTO = try await api.post(
            path: "/api/v1/agent-runs/tickets/\(ticket.id)/dispatch",
            body: EmptyRequestBody()
        )
        let dispatch = dto.toDomain()
        if dispatch.run.status == .failed {
            throw APIError(code: 0, message: dispatch.run.error ?? dispatch.message)
        }
        return dispatch
    }

    @MainActor
    private func queueExecutionThroughORCA(dispatchRunId: String) async throws -> AgentRunDispatch {
        let dto: AgentRunDispatchDTO = try await api.post(
            path: "/api/v1/agent-runs/\(dispatchRunId)/queue-execution",
            body: EmptyRequestBody()
        )
        return dto.toDomain()
    }

    private static func makeTraceId(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    private static func compactDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(max(0, Int(seconds)))s"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        }
        return "\(Int(seconds / 3600))h"
    }

    // MARK: - Comments / Evidence

    func comments(for ticketId: String) -> [TicketComment] {
        ticketCommentsByTicketId[ticketId] ?? []
    }

    func isLoadingComments(for ticketId: String) -> Bool {
        loadingCommentTicketIds.contains(ticketId)
    }

    func commentsError(for ticketId: String) -> String? {
        commentErrorsByTicketId[ticketId]
    }

    func notes(for ticketId: String) -> [TicketNoteRecord] {
        ticketNotesByTicketId[ticketId] ?? []
    }

    func isLoadingNotes(for ticketId: String) -> Bool {
        loadingTicketNoteIds.contains(ticketId)
    }

    func notesError(for ticketId: String) -> String? {
        ticketNoteErrorsByTicketId[ticketId]
    }

    func agentRuns(for ticketId: String) -> [AgentRun] {
        agentRunsByTicketId[ticketId] ?? []
    }

    func isLoadingAgentRuns(for ticketId: String) -> Bool {
        loadingAgentRunTicketIds.contains(ticketId)
    }

    func agentRunsError(for ticketId: String) -> String? {
        agentRunErrorsByTicketId[ticketId]
    }

    func traceLookup(for traceId: String) -> AgentRunTrace? {
        tracesById[traceId]
    }

    func traceError(for traceId: String) -> String? {
        traceErrorsById[traceId]
    }

    func isLoadingTrace(_ traceId: String) -> Bool {
        loadingTraceIds.contains(traceId)
    }

    func artifactSummaries(for runId: String) -> [AgentRunArtifactSummary]? {
        artifactSummariesByRunId[runId]
    }

    func artifactSummaryError(for runId: String) -> String? {
        artifactSummaryErrorsByRunId[runId]
    }

    func isLoadingArtifactSummary(for runId: String) -> Bool {
        loadingArtifactRunIds.contains(runId)
    }

    func computeRuns(for traceId: String) -> [ComputeRunRecord] {
        if let traceRuns = tracesById[traceId]?.computeRuns {
            return traceRuns
        }
        return computeRunsByTraceId[traceId] ?? []
    }

    @MainActor
    func loadComments(ticketId: String) async {
        guard !loadingCommentTicketIds.contains(ticketId) else { return }
        loadingCommentTicketIds.insert(ticketId)
        commentErrorsByTicketId[ticketId] = nil
        defer { loadingCommentTicketIds.remove(ticketId) }

        do {
            let dtos: [TicketCommentDTO] = try await api.get(path: "/api/v1/tickets/\(ticketId)/comments")
            ticketCommentsByTicketId[ticketId] = dtos
                .map { $0.toDomain() }
                .sorted { $0.createdAt < $1.createdAt }
        } catch let apiError as APIError {
            commentErrorsByTicketId[ticketId] = Self.userFacingMessage(for: apiError)
        } catch {
            commentErrorsByTicketId[ticketId] = "Couldn't load evidence comments."
        }
    }

    @MainActor
    func loadNotes(ticketId: String) async {
        guard !loadingTicketNoteIds.contains(ticketId) else { return }
        loadingTicketNoteIds.insert(ticketId)
        ticketNoteErrorsByTicketId[ticketId] = nil
        defer { loadingTicketNoteIds.remove(ticketId) }

        do {
            let dtos: [TicketNoteDTO] = try await api.get(path: "/api/v1/notes/tickets/\(ticketId)")
            ticketNotesByTicketId[ticketId] = dtos
                .map { $0.toDomain() }
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch let apiError as APIError {
            ticketNoteErrorsByTicketId[ticketId] = Self.userFacingMessage(for: apiError)
        } catch {
            ticketNoteErrorsByTicketId[ticketId] = "Couldn't load ORCA notes."
        }
    }

    @MainActor
    func loadAgentRuns(ticketId: String) async {
        guard !loadingAgentRunTicketIds.contains(ticketId) else { return }
        loadingAgentRunTicketIds.insert(ticketId)
        agentRunErrorsByTicketId[ticketId] = nil
        defer { loadingAgentRunTicketIds.remove(ticketId) }

        do {
            let dtos: [AgentRunDTO] = try await api.get(path: "/api/v1/tickets/\(ticketId)/agent-runs")
            agentRunsByTicketId[ticketId] = dtos
                .map { $0.toDomain() }
                .sorted { $0.createdAt < $1.createdAt }
        } catch let apiError as APIError {
            if apiError.code == 404 {
                agentRunsByTicketId[ticketId] = []
                agentRunErrorsByTicketId[ticketId] = "Agent Runs are not deployed on this ORCA yet."
            } else {
                agentRunErrorsByTicketId[ticketId] = Self.userFacingMessage(for: apiError)
            }
        } catch {
            agentRunErrorsByTicketId[ticketId] = "Couldn't load Agent Runs."
        }
    }

    @MainActor
    func loadTrace(traceId: String) async {
        let cleanTraceId = traceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTraceId.isEmpty, !loadingTraceIds.contains(cleanTraceId) else { return }
        loadingTraceIds.insert(cleanTraceId)
        traceErrorsById[cleanTraceId] = nil
        defer { loadingTraceIds.remove(cleanTraceId) }

        guard let encodedTraceId = cleanTraceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            traceErrorsById[cleanTraceId] = "Trace id could not be encoded."
            return
        }

        do {
            let dto: AgentRunTraceDTO = try await api.get(path: "/api/v1/agent-runs/traces/\(encodedTraceId)")
            tracesById[cleanTraceId] = dto.toDomain()
            if let computeDTOs = dto.computeRuns {
                computeRunsByTraceId[cleanTraceId] = computeDTOs.map { $0.toDomain() }.sorted { $0.createdAt < $1.createdAt }
            } else {
                let computeDTOs: [ComputeRunRecordDTO] = try await api.get(path: "/api/v1/compute/runs?trace_id=\(encodedTraceId)")
                computeRunsByTraceId[cleanTraceId] = computeDTOs.map { $0.toDomain() }.sorted { $0.createdAt < $1.createdAt }
            }
        } catch let apiError as APIError {
            traceErrorsById[cleanTraceId] = Self.userFacingMessage(for: apiError)
        } catch {
            traceErrorsById[cleanTraceId] = "Couldn't load trace evidence."
        }
    }

    @MainActor
    func loadArtifactSummary(runId: String) async {
        guard !loadingArtifactRunIds.contains(runId) else { return }
        loadingArtifactRunIds.insert(runId)
        artifactSummaryErrorsByRunId[runId] = nil
        defer { loadingArtifactRunIds.remove(runId) }

        do {
            let dtos: [AgentRunArtifactSummaryDTO] = try await api.get(path: "/api/v1/agent-runs/\(runId)/artifacts")
            artifactSummariesByRunId[runId] = dtos.map { $0.toDomain() }
        } catch let apiError as APIError {
            artifactSummaryErrorsByRunId[runId] = Self.userFacingMessage(for: apiError)
        } catch {
            artifactSummaryErrorsByRunId[runId] = "Couldn't load artifact summary."
        }
    }

    @MainActor
    private func createAgentRunIfAvailable(for ticket: Ticket, traceId: String) async -> AgentRun? {
        let body = AgentRunCreateBody(
            ticketId: ticket.id,
            agentId: ticket.assigneeAgentId,
            traceId: traceId,
            computeTag: SchoolhouseTicketDispatchService.normalizeComputeTag(ticket.computeTag),
            caller: "pod.schoolhouse-dispatch",
            source: "pod.tickets",
            lane: "agent_run",
            workerLane: SchoolhouseTicketDispatchService.workerLane(for: ticket),
            toolPolicy: SchoolhouseTicketDispatchService.toolPolicy(for: ticket),
            inputSummary: ticket.title,
            guardrails: [
                "surface": "pod",
                "mode": "planning-dispatch",
                "mutation": "forbidden-without-approval"
            ]
        )

        do {
            let dto: AgentRunDTO = try await api.post(path: "/api/v1/agent-runs", body: body)
            return dto.toDomain()
        } catch {
            return nil
        }
    }

    @MainActor
    private func updateAgentRunIfAvailable(
        runId: String,
        status: AgentRunStatus,
        outcome: String?,
        evidence: String?,
        error: String?,
        backend: String?,
        model: String?,
        latencyMs: Int?
    ) async {
        let body = AgentRunUpdateBody(
            status: status.rawValue,
            outcome: outcome,
            evidence: evidence,
            error: error,
            backend: backend,
            model: model,
            latencyMs: latencyMs
        )

        do {
            let _: AgentRunDTO = try await api.patch(path: "/api/v1/agent-runs/\(runId)", body: body)
        } catch {
            // Agent Runs are progressive. A failed metadata patch should not hide the ticket evidence.
        }
    }

    // MARK: - SSE live updates (b9bbe115 — REST + SSE + write)

    /// Start live subscription to /api/v1/tickets/stream. Reconnects with
    /// exponential backoff capped at 30s. Idempotent — calling twice is a no-op.
    @MainActor
    func startLiveUpdates() {
        guard sseListenTask == nil else { return }

        liveStatus = .reconnecting
        liveStatusDetail = "Connecting to live ticket updates..."
        lastLiveEventAt = nil
        startLiveStalenessWatchdog()

        sseListenTask = Task { @MainActor in
            guard let token = await api.currentToken(), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.liveStatus = .stopped
                self.liveStatusDetail = "Live tickets need an ORCA auth token."
                self.sseListenTask = nil
                return
            }

            var backoffNanos: UInt64 = 2_000_000_000  // 2s
            while !Task.isCancelled {
                let manager = SSEStreamManager()
                self.sseManager = manager
                do {
                    let baseURL = AppState.backendURL
                    let events = await manager.connectTickets(token: token, baseURL: baseURL)
                    for try await event in events {
                        if Task.isCancelled { return }
                        switch event {
                        case .connected:
                            self.markLiveEvent("Connected to live ticket updates.")
                            backoffNanos = 2_000_000_000  // reset on success
                        case .ticketLifecycle(let envelope):
                            self.markLiveEvent("Received a live ticket update.")
                            await self.refreshTicketFromLifecycleEvent(envelope)
                        case .keepalive:
                            self.markLiveEvent("Live ticket stream heartbeat received.")
                        case .error:
                            self.liveStatus = .stale
                            self.liveStatusDetail = "Live ticket stream reported an error; reconnecting..."
                        case .message:
                            break  // chat events not expected on this stream
                        }
                    }
                } catch {
                    // Stream ended — fall through to backoff + reconnect.
                    self.liveStatus = .reconnecting
                    self.liveStatusDetail = "Live ticket stream ended; reconnecting..."
                }
                if Task.isCancelled { break }
                self.liveStatus = .reconnecting
                self.liveStatusDetail = "Reconnecting live ticket updates..."
                await manager.markReconnecting()
                await TaskSafeSleep.sleep(nanoseconds: backoffNanos)
                backoffNanos = min(backoffNanos * 2, 30_000_000_000)  // cap 30s
            }
        }
    }

    @MainActor
    private func markLiveEvent(_ detail: String) {
        lastLiveEventAt = Date()
        liveStatus = .connected
        liveStatusDetail = detail
    }

    @MainActor
    private func startLiveStalenessWatchdog() {
        liveStalenessTask?.cancel()
        liveStalenessTask = Task { @MainActor in
            while !Task.isCancelled {
                await TaskSafeSleep.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                guard self.sseListenTask != nil else { continue }
                guard self.liveStatus == .connected else { continue }
                guard let lastLiveEventAt else { continue }
                let age = Date().timeIntervalSince(lastLiveEventAt)
                if age > 95 {
                    self.liveStatus = .stale
                    self.liveStatusDetail = "No live ticket heartbeat for \(Self.compactDuration(age)); reconnecting may be needed."
                } else {
                    self.liveStatusDetail = "Live ticket stream active; last update \(Self.compactDuration(age)) ago."
                }
            }
        }
    }

    /// Cancel the live subscription. Safe to call multiple times.
    @MainActor
    func stopLiveUpdates() {
        sseListenTask?.cancel()
        sseListenTask = nil
        liveStalenessTask?.cancel()
        liveStalenessTask = nil
        lastLiveEventAt = nil
        liveStatus = .stopped
        liveStatusDetail = "Ticket stream is stopped."
        Task { [manager = sseManager] in
            await manager?.disconnect()
        }
        sseManager = nil
    }
}

// MARK: - Compute Ticket Drafting

private struct ComputeTicketDraft: Sendable {
    let title: String
    let description: String
    let priority: TicketPriority
    let suggestedAgentId: String
    let ticketType: String
    let tags: [String]
    let computeTag: String
}

private struct ComputeRunContext: Encodable {
    let conversationId: String?
    let ticketId: String?
    let guardrails: [String]
    let traceId: String?
    let computeLane: String?

    init(
        conversationId: String?,
        ticketId: String?,
        guardrails: [String],
        traceId: String? = nil,
        computeLane: String? = nil
    ) {
        self.conversationId = conversationId
        self.ticketId = ticketId
        self.guardrails = guardrails
        self.traceId = traceId
        self.computeLane = computeLane
    }

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case ticketId = "ticket_id"
        case traceId = "trace_id"
        case computeLane = "compute_lane"
        case guardrails
    }
}

private struct ComputeRunRequest: Encodable {
    let surface: String
    let taskHint: String
    let route: String
    let agentId: String?
    let input: String
    let context: ComputeRunContext

    enum CodingKeys: String, CodingKey {
        case surface, route, input, context
        case taskHint = "task_hint"
        case agentId = "agent_id"
    }
}

private struct ComputeRunTicketDraftStructured: Decodable {
    let title: String?
    let description: String?
    let priority: String?
    let suggestedAgentId: String?
    let ticketType: String?
    let tags: [String]?
    let computeTag: String?

    enum CodingKeys: String, CodingKey {
        case title, description, priority, tags
        case suggestedAgentId = "suggested_agent_id"
        case ticketType = "ticket_type"
        case computeTag = "compute_tag"
    }
}

private struct ComputeRunUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

private struct ComputeRunResponse: Decodable {
    let id: String
    let route: String
    let model: String
    let status: String
    let output: String
    let structured: ComputeRunTicketDraftStructured?
    let usage: ComputeRunUsage?
    let evidenceCommentId: String?
    let fallbackUsed: Bool
    let backend: String?
    let latencyMs: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, route, model, status, output, structured, usage, backend, error
        case evidenceCommentId = "evidence_comment_id"
        case fallbackUsed = "fallback_used"
        case latencyMs = "latency_ms"
    }
}

private actor ComputeRouteClient {
    static let shared = ComputeRouteClient()

    func ticketDraft(from intake: String) async throws -> ComputeTicketDraft {
        let request = ComputeRunRequest(
            surface: "pod",
            taskHint: "ticket_draft",
            route: "auto",
            agentId: nil,
            input: intake,
            context: ComputeRunContext(
                conversationId: nil,
                ticketId: nil,
                guardrails: ["no_secret_exposure", "protected_domain_review"]
            )
        )
        let response: ComputeRunResponse = try await APIClient.shared.post(
            path: "/api/v1/compute/runs",
            body: request
        )
        guard response.status == "succeeded" else {
            throw APIError(code: 0, message: response.error ?? "ORCA compute route failed")
        }
        return Self.ticketDraft(from: response, fallbackIntake: intake)
    }

    private static func ticketDraft(
        from response: ComputeRunResponse,
        fallbackIntake: String
    ) -> ComputeTicketDraft {
        if let structured = response.structured {
            return ComputeTicketDraft(
                title: clean(structured.title) ?? makeTitle(from: fallbackIntake),
                description: clean(structured.description) ?? fallbackIntake,
                priority: TicketPriority(rawValue: normalizePriority(structured.priority)) ?? .medium,
                suggestedAgentId: normalizeAgent(structured.suggestedAgentId ?? ""),
                ticketType: normalizeTicketType(structured.ticketType ?? ""),
                tags: structured.tags?.map(normalizeTag).filter { !$0.isEmpty } ?? ["triage"],
                computeTag: normalizeComputeTag(structured.computeTag ?? "")
            )
        }
        return ComputeTicketDraftService.localDraft(from: fallbackIntake)
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizePriority(_ value: String?) -> String {
        switch value?.lowercased() {
        case "urgent": return "urgent"
        case "high": return "high"
        case "low": return "low"
        default: return "medium"
        }
    }

    private static func normalizeTicketType(_ value: String) -> String {
        switch value.lowercased() {
        case "bug", "bugfix", "defect": return "bug"
        case "feature", "feature_request", "enhancement": return "feature"
        case "incident", "outage": return "incident"
        default: return "support"
        }
    }

    private static func normalizeComputeTag(_ value: String) -> String {
        switch value.lowercased() {
        case "code", "security", "financial", "tony-facing", "classify", "reasoning": return value.lowercased()
        default: return "classify"
        }
    }

    private static func normalizeAgent(_ value: String) -> String {
        let allowed = ["aloha", "maui", "chief", "rooster", "coral", "reef"]
        let normalized = value.lowercased().replacingOccurrences(of: "_", with: "-")
        return allowed.contains(normalized) ? normalized : ""
    }

    private static func normalizeTag(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#,.;: \n\t"))
    }

    private static func makeTitle(from intake: String) -> String {
        let cleaned = intake
            .split(separator: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "New triage ticket"
        if cleaned.count <= 80 { return cleaned }
        return String(cleaned.prefix(77)) + "..."
    }
}

private enum ComputeTicketDraftService {
    static func draft(from intake: String) async throws -> ComputeTicketDraft {
        try await ComputeRouteClient.shared.ticketDraft(from: intake)
    }

    static func localDraft(from intake: String) -> ComputeTicketDraft {
        let lowered = intake.lowercased()
        let priority: TicketPriority = lowered.contains("urgent") || lowered.contains("broken") || lowered.contains("blocked")
            ? .high
            : .medium
        let agent = suggestedAgent(for: lowered)
        let ticketType = lowered.contains("bug") || lowered.contains("broken") || lowered.contains("doesn't work")
            ? "bug"
            : "support"
        let tag = agent == "rooster" ? "security" : agent == "chief" ? "financial" : agent == "coral" || agent == "reef" ? "reasoning" : "general"
        return ComputeTicketDraft(
            title: makeTitle(from: intake),
            description: structuredDescription(from: intake, suggestedAgent: agent),
            priority: priority,
            suggestedAgentId: agent,
            ticketType: ticketType,
            tags: ["pod", "triage"],
            computeTag: tag
        )
    }

    private static func extractContent(from data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    private static func parseDraft(_ content: String, fallbackIntake: String) throws -> ComputeTicketDraft {
        let json = strippedJSON(content)
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return localDraft(from: fallbackIntake)
        }

        let title = cleanString(object["title"]) ?? makeTitle(from: fallbackIntake)
        let description = cleanString(object["description"]) ?? fallbackIntake
        let priority = TicketPriority(rawValue: normalizePriority(cleanString(object["priority"]))) ?? .medium
        let agent = normalizeAgent(cleanString(object["suggested_agent_id"]) ?? "")
        let ticketType = normalizeTicketType(cleanString(object["ticket_type"]) ?? "")
        let tags = parseTags(object["tags"])
        let computeTag = normalizeComputeTag(cleanString(object["compute_tag"]) ?? "")

        return ComputeTicketDraft(
            title: title,
            description: description,
            priority: priority,
            suggestedAgentId: agent,
            ticketType: ticketType,
            tags: tags.isEmpty ? ["triage"] : tags,
            computeTag: computeTag
        )
    }

    private static func strippedJSON(_ content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    private static func cleanString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseTags(_ value: Any?) -> [String] {
        if let tags = value as? [String] {
            return tags.map(normalizeTag).filter { !$0.isEmpty }
        }
        if let string = value as? String {
            return string.split(separator: ",").map { normalizeTag(String($0)) }.filter { !$0.isEmpty }
        }
        return []
    }

    private static func normalizeTag(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#,.;: \n\t"))
    }

    private static func normalizePriority(_ value: String?) -> String {
        switch value?.lowercased() {
        case "urgent": return "urgent"
        case "high": return "high"
        case "low": return "low"
        default: return "medium"
        }
    }

    private static func normalizeTicketType(_ value: String) -> String {
        switch value.lowercased() {
        case "bug", "bugfix", "defect": return "bug"
        case "feature", "feature_request", "enhancement": return "feature"
        case "incident", "outage": return "incident"
        default: return "support"
        }
    }

    private static func normalizeComputeTag(_ value: String) -> String {
        switch value.lowercased() {
        case "code", "security", "financial", "tony-facing", "classify", "reasoning": return value.lowercased()
        default: return "general"
        }
    }

    private static func normalizeAgent(_ value: String) -> String {
        let allowed = ["aloha", "maui", "chief", "rooster", "coral", "reef"]
        let normalized = value.lowercased().replacingOccurrences(of: "_", with: "-")
        if allowed.contains(normalized) { return normalized }
        return ""
    }

    private static func suggestedAgent(for loweredIntake: String) -> String {
        if loweredIntake.contains("security") || loweredIntake.contains("token") || loweredIntake.contains("auth") {
            return "rooster"
        }
        if loweredIntake.contains("fund") || loweredIntake.contains("trading") || loweredIntake.contains("chief") {
            return "chief"
        }
        if loweredIntake.contains("reef") || loweredIntake.contains("chief mac") || loweredIntake.contains("mirror") {
            return "reef"
        }
        if loweredIntake.contains("coral") || loweredIntake.contains("watchdog") || loweredIntake.contains("daemon") || loweredIntake.contains("launchagent") || loweredIntake.contains("compute observability") {
            return "coral"
        }
        if loweredIntake.contains("pod") || loweredIntake.contains("swift") || loweredIntake.contains("backend") {
            return "maui"
        }
        return "aloha"
    }

    private static func makeTitle(from intake: String) -> String {
        let cleaned = intake
            .split(separator: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "New triage ticket"
        if cleaned.count <= 80 { return cleaned }
        return String(cleaned.prefix(77)) + "..."
    }

    private static func structuredDescription(from intake: String, suggestedAgent: String) -> String {
        """
        ## Request

        \(intake)

        ## Desired Outcome

        The request is converted into a clear ORCA control record with owner, priority, approvals, and verification path.

        ## Proposed Owner / Lane

        - Suggested agent: \(suggestedAgent.isEmpty ? "unassigned" : suggestedAgent)
        - Routing source: Pod local triage draft

        ## Approval / Guardrail Check

        \(approvalCheck(for: intake, suggestedAgent: suggestedAgent))

        ## Acceptance Criteria

        - Owner confirms or adjusts scope and priority.
        - Protected-domain work records approval before mutation.
        - Evidence, notes, or completion details are added as ORCA comments or lessons learned.

        ## Source

        - Created from Pod Tickets rough intake.
        - Requestor: Tony / Captain.
        """
    }

    private static func approvalCheck(for intake: String, suggestedAgent: String) -> String {
        let lowered = intake.lowercased()
        var gates: [String] = []
        if suggestedAgent == "chief" || lowered.contains("fund") || lowered.contains("trading") || lowered.contains("wallet") || lowered.contains("position") {
            gates.append("- Chief/Fund gate: Chief plus Tony/Rooster review before mutation.")
        }
        if suggestedAgent == "rooster" || lowered.contains("security") || lowered.contains("token") || lowered.contains("credential") || lowered.contains("auth") || lowered.contains("key") {
            gates.append("- Security gate: Rooster/Tony review before exposing, rotating, or changing access.")
        }
        if lowered.contains("archive") || lowered.contains("delete") || lowered.contains("identity") || lowered.contains("soul") || lowered.contains("memory") {
            gates.append("- Agent memory/identity gate: Tony/Aloha review before durable memory, identity, or archive changes.")
        }
        if gates.isEmpty {
            return "- No protected-domain approval detected from intake.\n- Owner should still confirm scope before execution."
        }
        return gates.joined(separator: "\n")
    }
}

// MARK: - Schoolhouse Ticket Dispatch

struct SchoolhouseRunResult {
    let commentBody: String
    let outcome: String
    let backend: String
    let model: String
    let latencyMs: Int
}

enum SchoolhouseTicketDispatchService {
    static func dispatch(ticket: Ticket, traceId: String) async throws -> SchoolhouseRunResult {
        let computeTag = normalizeComputeTag(ticket.computeTag)
        let workerLane = workerLane(for: ticket)
        let toolPolicy = toolPolicy(for: ticket)
        let prompt = """
        You are Schoolhouse runtime preparing a guarded execution brief for an ORCA ticket.
        Do not claim that work has been completed. Do not mutate external systems.
        Return a concise Markdown run note with these sections:
        ## Schoolhouse Run
        ## Ticket Read
        ## Owner / Worker Lane
        ## Approval Gates
        ## Next Action
        ## Evidence To Collect

        Ticket:
        - id: \(ticket.id)
        - title: \(ticket.title)
        - status: \(ticket.status.rawValue)
        - priority: \(ticket.priority.rawValue)
        - type: \(ticket.ticketType ?? "unknown")
        - compute_tag: \(computeTag)
        - assignee_agent_id: \(ticket.assigneeAgentId ?? "unassigned")
        - owner_agent: \(ticket.assigneeAgentName ?? ticket.assigneeAgentId ?? "unassigned")
        - worker_lane: \(workerLane)
        - tool_policy: \(toolPolicy)
        - tags: \(ticket.tags?.joined(separator: ", ") ?? "none")

        Description:
        \(ticket.description ?? "No description provided.")

        Guardrails:
        - ORCA remains truth for status, ownership, approvals, blockers, and evidence.
        - Chief/Fund, trading, security, credentials, identity, archive, and durable memory require approval before mutation.
        - The ticket owner remains accountable; worker_lane executes only bounded work under that owner.
        - This dispatch may prepare execution steps, but external mutation still requires the tool policy and approval gates above.
        """

        let compute = try await callCompute(prompt: prompt, computeTag: computeTag, traceId: traceId, ticketId: ticket.id)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return SchoolhouseRunResult(
            commentBody: """
            ## Schoolhouse Dispatch Evidence

            - Run surface: Pod Tickets
            - Ticket: \(ticket.id)
            - Trace: \(traceId)
            - Compute tag: \(computeTag)
            - Owner: \(ticket.assigneeAgentName ?? ticket.assigneeAgentId ?? "unassigned")
            - Worker lane: \(workerLane)
            - Tool policy: \(toolPolicy)
            - Backend: \(compute.backend)
            - Model: \(compute.model)
            - Latency: \(compute.latencyMs)ms
            - Fallback used: \(compute.fallbackUsed ? "yes" : "no")
            - Created at: \(timestamp)

            \(compute.content)
            """
            ,
            outcome: compute.content,
            backend: compute.backend,
            model: compute.model,
            latencyMs: compute.latencyMs
        )
    }

    private struct ComputeResult {
        let content: String
        let backend: String
        let model: String
        let latencyMs: Int
        let fallbackUsed: Bool
    }

    private static func callCompute(prompt: String, computeTag: String, traceId: String, ticketId: String) async throws -> ComputeResult {
        let request = ComputeRunRequest(
            surface: "pod.tickets",
            taskHint: "dispatch_plan",
            route: "auto",
            agentId: nil,
            input: prompt,
            context: ComputeRunContext(
                conversationId: nil,
                ticketId: ticketId,
                guardrails: ["no_secret_exposure", "protected_domain_review", "ticket_owner_review"],
                traceId: traceId,
                computeLane: "agent_run.dispatch"
            )
        )
        let response: ComputeRunResponse = try await APIClient.shared.post(
            path: "/api/v1/compute/runs",
            body: request
        )
        guard response.status == "succeeded" else {
            throw APIError(code: 0, message: response.error ?? "ORCA compute dispatch failed")
        }
        let content = response.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            throw APIError(code: 0, message: "ORCA compute returned an empty dispatch note")
        }
        return ComputeResult(
            content: content,
            backend: response.backend ?? "orca-compute-runs",
            model: response.model,
            latencyMs: response.latencyMs ?? 0,
            fallbackUsed: response.fallbackUsed
        )
    }

    private static func extractContent(from data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
                let text: String?
            }
            let choices: [Choice]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message?.content ?? response.choices.first?.text ?? ""
    }

    private static func extractModel(from data: Data) throws -> String? {
        struct Response: Decodable { let model: String? }
        return try JSONDecoder().decode(Response.self, from: data).model
    }

    static func normalizeComputeTag(_ value: String?) -> String {
        switch value?.lowercased() {
        case "code": return "code"
        case "security": return "security"
        case "financial": return "financial"
        case "tony-facing": return "tony-facing"
        case "reasoning": return "reasoning"
        case "classify": return "classify"
        default: return "classify"
        }
    }

    static func workerLane(for ticket: Ticket) -> String {
        let tag = normalizeComputeTag(ticket.computeTag)
        let haystack = "\(ticket.title) \(ticket.description ?? "")".lowercased()
        if tag == "financial" || haystack.contains("chief") || haystack.contains("fund") || haystack.contains("trading") {
            return "protected-chief-review"
        }
        if tag == "security" || haystack.contains("credential") || haystack.contains("token") || haystack.contains("secret") {
            return "protected-rooster-review"
        }
        if haystack.contains("reef") || haystack.contains("chief mac") || haystack.contains("chief-mac") || haystack.contains("mirror") {
            return "reef-support-runtime"
        }
        if haystack.contains("coral") || haystack.contains("watchdog") || haystack.contains("daemon") || haystack.contains("launchagent") || haystack.contains("runtime health") || haystack.contains("observability") || haystack.contains("openclaw") {
            return "coral-support-runtime"
        }
        return "mermaid"
    }

    static func toolPolicy(for ticket: Ticket) -> String {
        let lane = workerLane(for: ticket)
        switch lane {
        case "protected-chief-review":
            return "read_only_until_chief_tony_rooster_approval"
        case "protected-rooster-review":
            return "read_only_until_rooster_tony_approval"
        case "reef-support-runtime":
            return "read_only_runtime_inventory_until_chief_rooster_review"
        case "coral-support-runtime":
            return "bounded_runtime_triage_owner_review"
        default:
            return "bounded_workspace_edits_owner_review"
        }
    }
}

// MARK: - Request Bodies

private struct CreateTicketBody: Encodable {
    let title: String
    let description: String?
    let priority: String
    let assigneeAgentId: String?
    let status = "open"
    let source = "pod_app"
    let ticketType: String?
    let tags: [String]?
    let computeTag: String?
    let approvalState: String?
    let approvalGate: String?
    let autonomyLevel: String?
    let workerLane: String?
    let toolPolicy: String?
    let acceptanceCriteria: [String]?
    let desiredOutcome: String?
    let triageId: String?
    let triageTraceId: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let handoffPacket: [String: String]
    let boardId: String?
    let parentTicketId: String?   // POD-4: subtask hierarchy
    let lessonsLearned: String?  // POD-4: lessons-learned capture

    enum CodingKeys: String, CodingKey {
        case title, description, priority, status, source, tags
        case assigneeAgentId = "assignee_agent_id"
        case ticketType = "ticket_type"
        case computeTag = "compute_tag"
        case approvalState = "approval_state"
        case approvalGate = "approval_gate"
        case autonomyLevel = "autonomy_level"
        case workerLane = "worker_lane"
        case toolPolicy = "tool_policy"
        case acceptanceCriteria = "acceptance_criteria"
        case desiredOutcome = "desired_outcome"
        case triageId = "triage_id"
        case triageTraceId = "triage_trace_id"
        case recommendedRuntime = "recommended_runtime"
        case recommendedSurface = "recommended_surface"
        case runtimeReason = "runtime_reason"
        case handoffSubject = "handoff_subject"
        case handoffPacket = "handoff_packet"
        case boardId = "board_id"
        case parentTicketId  = "parent_ticket_id"
        case lessonsLearned  = "lessons_learned"
    }
}

struct TicketBoardOption: Identifiable, Sendable, Hashable {
    let id: String
    let slug: String
    let name: String
    let layer: String?
    let component: String?

    var icon: String { Self.iconMap[slug] ?? "square.grid.2x2" }
    var displayName: String { component?.isEmpty == false ? component! : name }
    var detail: String {
        [slug, layer]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    static let preferredSlugs = [
        "north-star", "pod", "surfaces", "orca", "memory", "compute", "nerve",
        "governance", "jarvis", "schoolhouse", "fund", "products", "tools"
    ]

    private static let iconMap: [String: String] = [
        "north-star": "star.fill", "pod": "iphone", "surfaces": "bubble.left.and.bubble.right",
        "orca": "server.rack",
        "memory": "brain", "compute": "cpu", "nerve": "bolt",
        "governance": "scalemass", "jarvis": "point.3.connected.trianglepath.dotted",
        "schoolhouse": "building.columns", "fund": "lock.shield",
        "products": "shippingbox", "tools": "wrench.and.screwdriver"
    ]
}

private struct TicketBoardListResponse: Decodable {
    let items: [TicketBoardDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [TicketBoardDTO] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(TicketBoardDTO.self))
            }
            items = values
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([TicketBoardDTO].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey { case items }
}

private struct TicketBoardDTO: Decodable {
    let id: String
    let slug: String
    let name: String
    let layer: String?
    let component: String?

    var option: TicketBoardOption {
        TicketBoardOption(id: id, slug: slug, name: name, layer: layer, component: component)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeTicketFlexibleString(forKey: .id)
        slug = try container.decodeTicketFlexibleStringIfPresent(forKey: .slug) ?? id
        name = try container.decodeTicketFlexibleStringIfPresent(forKey: .name) ?? slug
        layer = try container.decodeTicketFlexibleStringIfPresent(forKey: .layer)
        component = try container.decodeTicketFlexibleStringIfPresent(forKey: .component)
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, layer, component
    }
}

private extension KeyedDecodingContainer {
    func decodeTicketFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return "\(value)"
        }
        if let value = try? decode(UUID.self, forKey: key) {
            return value.uuidString
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected string-compatible value")
        )
    }

    func decodeTicketFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if !contains(key) || (try? decodeNil(forKey: key)) == true {
            return nil
        }
        return try decodeTicketFlexibleString(forKey: key)
    }
}

struct TicketDirectionPreview: Sendable, Hashable {
    let triageId: String
    let traceId: String
    let intentType: String
    let recommendedLane: String
    let riskLevel: String
    let needsTicket: Bool
    let needsApproval: Bool
    let suggestedOwner: String
    let suggestedWorker: String?
    let suggestedComputeRoute: String
    let nextAction: String
    let reason: String
    let approvalGate: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let tags: [String]

    init(response: MermanTicketDirectionResponse) {
        self.triageId = response.triageId
        self.traceId = response.traceId
        self.intentType = response.intentType
        self.recommendedLane = response.recommendedLane
        self.riskLevel = response.riskLevel
        self.needsTicket = response.needsTicket
        self.needsApproval = response.needsApproval
        self.suggestedOwner = response.suggestedOwner
        self.suggestedWorker = response.suggestedWorker
        self.suggestedComputeRoute = response.suggestedComputeRoute
        self.nextAction = response.nextAction
        self.reason = response.reason
        self.approvalGate = response.approvalGate
        self.recommendedRuntime = response.recommendedRuntime
        self.recommendedSurface = response.recommendedSurface
        self.runtimeReason = response.runtimeReason
        self.handoffSubject = response.handoffSubject
        self.tags = response.tags
    }

    var ownerDisplay: String {
        suggestedOwner.isEmpty ? recommendedLane : suggestedOwner
    }

    var nextActionDisplay: String {
        nextAction.replacingOccurrences(of: "_", with: " ")
    }
}

struct MermanTicketDirectionRequest: Encodable {
    let surface: String
    let target: String?
    let text: String
    let context: [String: String]
}

struct MermanTicketDirectionResponse: Decodable {
    let triageId: String
    let traceId: String
    let intentType: String
    let recommendedLane: String
    let riskLevel: String
    let needsTicket: Bool
    let needsApproval: Bool
    let suggestedOwner: String
    let suggestedWorker: String?
    let suggestedComputeRoute: String
    let nextAction: String
    let reason: String
    let approvalGate: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case triageId = "triage_id"
        case traceId = "trace_id"
        case intentType = "intent_type"
        case recommendedLane = "recommended_lane"
        case riskLevel = "risk_level"
        case needsTicket = "needs_ticket"
        case needsApproval = "needs_approval"
        case suggestedOwner = "suggested_owner"
        case suggestedWorker = "suggested_worker"
        case suggestedComputeRoute = "suggested_compute_route"
        case nextAction = "next_action"
        case reason
        case approvalGate = "approval_gate"
        case recommendedRuntime = "recommended_runtime"
        case recommendedSurface = "recommended_surface"
        case runtimeReason = "runtime_reason"
        case handoffSubject = "handoff_subject"
        case tags
    }
}

private struct UpdateTicketBody: Encodable {
    let title: String?
    let description: String?
    let status: String?
    let priority: String?
    let resolutionNotes: String?
    let approvalState: String?
    let autonomyLevel: String?
    let workerLane: String?
    let toolPolicy: String?
    let acceptanceCriteria: [String]?
    let desiredOutcome: String?

    init(
        title: String? = nil,
        description: String? = nil,
        status: String? = nil,
        priority: String? = nil,
        resolutionNotes: String? = nil,
        approvalState: String? = nil,
        autonomyLevel: String? = nil,
        workerLane: String? = nil,
        toolPolicy: String? = nil,
        acceptanceCriteria: [String]? = nil,
        desiredOutcome: String? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.resolutionNotes = resolutionNotes
        self.approvalState = approvalState
        self.autonomyLevel = autonomyLevel
        self.workerLane = workerLane
        self.toolPolicy = toolPolicy
        self.acceptanceCriteria = acceptanceCriteria
        self.desiredOutcome = desiredOutcome
    }

    enum CodingKeys: String, CodingKey {
        case title, description, status, priority
        case resolutionNotes = "resolution_notes"
        case approvalState = "approval_state"
        case autonomyLevel = "autonomy_level"
        case workerLane = "worker_lane"
        case toolPolicy = "tool_policy"
        case acceptanceCriteria = "acceptance_criteria"
        case desiredOutcome = "desired_outcome"
    }
}

private struct UpdateTicketLessonsBody: Encodable {
    let lessonsLearned: String

    enum CodingKeys: String, CodingKey {
        case lessonsLearned = "lessons_learned"
    }
}

private struct TicketCommentBody: Encodable {
    let message: String
    let traceId: String?
    let source: String?
    let lane: String?

    enum CodingKeys: String, CodingKey {
        case message, source, lane
        case traceId = "trace_id"
    }
}

private struct TicketApprovalRequestBody: Encodable {
    let reason: String
    let traceId: String?
    let source: String
    let lane: String

    enum CodingKeys: String, CodingKey {
        case reason, source, lane
        case traceId = "trace_id"
    }
}

private struct TicketApprovalResolutionBody: Encodable {
    let status: String
    let reason: String?
    let traceId: String?
    let source: String
    let lane: String

    enum CodingKeys: String, CodingKey {
        case status, reason, source, lane
        case traceId = "trace_id"
    }
}

private struct TicketApprovalDTO: Decodable {
    let approvalId: String
    let ticketId: String
    let boardId: String
    let actionType: String
    let status: String
    let confidence: Double
    let payload: [String: AgentRunJSONValue]?
    let createdAt: Date
    let resolvedAt: Date?
    let linkId: String
    let linkedAt: Date

    enum CodingKeys: String, CodingKey {
        case status, confidence
        case approvalId = "approval_id"
        case ticketId = "ticket_id"
        case boardId = "board_id"
        case actionType = "action_type"
        case payload
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
        case linkId = "link_id"
        case linkedAt = "linked_at"
    }

    var toDomain: TicketApprovalRecord {
        TicketApprovalRecord(
            id: approvalId,
            ticketId: ticketId,
            boardId: boardId,
            actionType: actionType,
            status: status,
            confidence: confidence,
            reason: payload?["reason"]?.displayValue,
            source: payload?["source"]?.displayValue,
            lane: payload?["lane"]?.displayValue,
            traceId: payload?["trace_id"]?.displayValue,
            createdAt: createdAt,
            resolvedAt: resolvedAt,
            linkedAt: linkedAt
        )
    }
}

private struct TicketNoteCreateBody: Encodable {
    let targetType: String
    let targetId: String
    let noteType: String
    let title: String
    let body: String
    let tags: [String]
    let source: String
    let traceId: String

    enum CodingKeys: String, CodingKey {
        case title, body, tags, source
        case targetType = "target_type"
        case targetId = "target_id"
        case noteType = "note_type"
        case traceId = "trace_id"
    }
}

private struct EmptyRequestBody: Encodable {}

private struct AgentRunCreateBody: Encodable {
    let ticketId: String
    let agentId: String?
    let status = "queued"
    let traceId: String
    let computeTag: String
    let caller: String
    let source: String
    let lane: String
    let workerLane: String
    let toolPolicy: String
    let inputSummary: String
    let guardrails: [String: String]

    enum CodingKeys: String, CodingKey {
        case status, caller, source, lane, guardrails
        case ticketId = "ticket_id"
        case agentId = "agent_id"
        case traceId = "trace_id"
        case computeTag = "compute_tag"
        case workerLane = "worker_lane"
        case toolPolicy = "tool_policy"
        case inputSummary = "input_summary"
    }
}

private struct AgentRunDispatch: Sendable, Hashable {
    let run: AgentRun
    let commentId: String?
    let message: String
}

private struct AgentRunDispatchDTO: Decodable {
    let run: AgentRunDTO
    let commentId: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case run, message
        case commentId = "comment_id"
    }

    func toDomain() -> AgentRunDispatch {
        AgentRunDispatch(
            run: run.toDomain(),
            commentId: commentId,
            message: message
        )
    }
}

private struct AgentRunDispatchPreviewDTO: Decodable {
    let ticketId: String
    let ownerAgentId: String?
    let workerLane: String
    let toolPolicy: String
    let computeTag: String
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let approvalRequired: Bool
    let protectedLane: Bool
    let nextState: String
    let blockers: [String]
    let preview: String

    enum CodingKeys: String, CodingKey {
        case blockers, preview
        case ticketId = "ticket_id"
        case ownerAgentId = "owner_agent_id"
        case workerLane = "worker_lane"
        case toolPolicy = "tool_policy"
        case computeTag = "compute_tag"
        case recommendedRuntime = "recommended_runtime"
        case recommendedSurface = "recommended_surface"
        case runtimeReason = "runtime_reason"
        case handoffSubject = "handoff_subject"
        case approvalRequired = "approval_required"
        case protectedLane = "protected_lane"
        case nextState = "next_state"
    }

    func toDomain() -> TicketDispatchPreview {
        TicketDispatchPreview(
            ticketId: ticketId,
            ownerAgentId: ownerAgentId,
            workerLane: workerLane,
            toolPolicy: toolPolicy,
            computeTag: computeTag,
            recommendedRuntime: recommendedRuntime,
            recommendedSurface: recommendedSurface,
            runtimeReason: runtimeReason,
            handoffSubject: handoffSubject,
            approvalRequired: approvalRequired,
            protectedLane: protectedLane,
            nextState: nextState,
            blockers: blockers,
            preview: preview
        )
    }
}

private struct AgentRunUpdateBody: Encodable {
    let status: String
    let outcome: String?
    let evidence: String?
    let error: String?
    let backend: String?
    let model: String?
    let latencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case status, outcome, evidence, error, backend, model
        case latencyMs = "latency_ms"
    }
}

private struct AgentRunRetryBody: Encodable {
    let reason: String
}

private struct AgentRunReviewBody: Encodable {
    let reviewStatus: String
    let reviewedBy: String
    let reviewNote: String?

    enum CodingKeys: String, CodingKey {
        case reviewStatus = "review_status"
        case reviewedBy = "reviewed_by"
        case reviewNote = "review_note"
    }
}

struct AgentRunDTO: Decodable {
    let id: String
    let ticketId: String
    let agentId: String?
    let status: String
    let runType: String?
    let traceId: String?
    let computeTag: String?
    let caller: String?
    let source: String?
    let lane: String?
    let workerLane: String?
    let toolPolicy: String?
    let backend: String?
    let model: String?
    let tier: String?
    let latencyMs: Int?
    let tokenCount: Int?
    let inputSummary: String?
    let outcome: String?
    let evidence: String?
    let error: String?
    let artifacts: [String: AgentRunJSONValue]?
    let guardrails: [String: AgentRunJSONValue]?
    let reviewStatus: String?
    let reviewedBy: String?
    let reviewedAt: Date?
    let reviewNote: String?
    let createdAt: Date
    let updatedAt: Date
    let startedAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, caller, source, lane, backend, model, tier, outcome, evidence, error, artifacts, guardrails
        case ticketId = "ticket_id"
        case agentId = "agent_id"
        case runType = "run_type"
        case traceId = "trace_id"
        case computeTag = "compute_tag"
        case workerLane = "worker_lane"
        case toolPolicy = "tool_policy"
        case latencyMs = "latency_ms"
        case tokenCount = "token_count"
        case inputSummary = "input_summary"
        case reviewStatus = "review_status"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case reviewNote = "review_note"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }

    func toDomain() -> AgentRun {
        AgentRun(
            id: id,
            ticketId: ticketId,
            agentId: agentId,
            status: AgentRunStatus(rawValue: status) ?? .queued,
            runType: runType ?? "execution",
            traceId: traceId,
            computeTag: computeTag,
            caller: caller,
            source: source,
            lane: lane,
            workerLane: workerLane,
            toolPolicy: toolPolicy,
            backend: backend,
            model: model,
            tier: tier,
            latencyMs: latencyMs,
            tokenCount: tokenCount,
            inputSummary: inputSummary,
            outcome: outcome,
            evidence: evidence,
            error: error,
            artifacts: artifacts,
            guardrails: guardrails,
            reviewStatus: reviewStatus,
            reviewedBy: reviewedBy,
            reviewedAt: reviewedAt,
            reviewNote: reviewNote,
            createdAt: createdAt,
            updatedAt: updatedAt,
            startedAt: startedAt,
            completedAt: completedAt
        )
    }
}

struct TicketListRunSummaryDTO: Decodable {
    let id: String
    let status: String
    let runType: String
    let workerLane: String?
    let backend: String?
    let model: String?
    let reviewStatus: String?
    let reviewedBy: String?
    let reviewedAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, backend, model
        case runType = "run_type"
        case workerLane = "worker_lane"
        case reviewStatus = "review_status"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> TicketListSummary.TicketListRunSummary {
        TicketListSummary.TicketListRunSummary(
            id: id,
            status: AgentRunStatus(rawValue: status) ?? .queued,
            runType: runType,
            workerLane: workerLane,
            backend: backend,
            model: model,
            reviewStatus: reviewStatus,
            reviewedBy: reviewedBy,
            reviewedAt: reviewedAt,
            updatedAt: updatedAt
        )
    }
}

struct TicketListSummaryDTO: Decodable {
    let ticketId: String
    let commentCount: Int
    let runCount: Int
    let failedRunCount: Int
    let approvalCount: Int
    let dispatchCount: Int
    let workerReviewRequiredCount: Int?
    let queuedRunCount: Int?
    let runningRunCount: Int?
    let waitingRunCount: Int?
    let retryingRunCount: Int?
    let latestRun: TicketListRunSummaryDTO?
    let latestActivity: String?
    let latestActivityAt: Date?
    let latestIntelligenceAt: Date?
    let latestRoutePacket: [String: AgentRunJSONValue]?
    let blockers: [String]?
    let nextAction: String?

    enum CodingKeys: String, CodingKey {
        case ticketId = "ticket_id"
        case commentCount = "comment_count"
        case runCount = "run_count"
        case failedRunCount = "failed_run_count"
        case approvalCount = "approval_count"
        case dispatchCount = "dispatch_count"
        case workerReviewRequiredCount = "worker_review_required_count"
        case queuedRunCount = "queued_run_count"
        case runningRunCount = "running_run_count"
        case waitingRunCount = "waiting_run_count"
        case retryingRunCount = "retrying_run_count"
        case latestRun = "latest_run"
        case latestActivity = "latest_activity"
        case latestActivityAt = "latest_activity_at"
        case latestIntelligenceAt = "latest_intelligence_at"
        case latestRoutePacket = "latest_route_packet"
        case blockers
        case nextAction = "next_action"
    }

    func toDomain() -> TicketListSummary {
        TicketListSummary(
            ticketId: ticketId,
            commentCount: commentCount,
            runCount: runCount,
            failedRunCount: failedRunCount,
            approvalCount: approvalCount,
            dispatchCount: dispatchCount,
            workerReviewRequiredCount: workerReviewRequiredCount ?? 0,
            queuedRunCount: queuedRunCount ?? 0,
            runningRunCount: runningRunCount ?? 0,
            waitingRunCount: waitingRunCount ?? 0,
            retryingRunCount: retryingRunCount ?? 0,
            latestRun: latestRun?.toDomain(),
            latestActivity: latestActivity,
            latestActivityAt: latestActivityAt,
            latestIntelligenceAt: latestIntelligenceAt,
            latestRoutePacket: latestRoutePacket,
            blockers: blockers ?? [],
            nextAction: nextAction
        )
    }
}

struct TicketCommentDTO: Decodable {
    let id: String
    let ticketId: String?
    let message: String?
    let agentId: String?
    let eventType: String?
    let traceId: String?
    let source: String?
    let lane: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, message, source, lane
        case ticketId = "ticket_id"
        case agentId = "agent_id"
        case eventType = "event_type"
        case traceId = "trace_id"
        case createdAt = "created_at"
    }

    func toDomain() -> TicketComment {
        TicketComment(
            id: id,
            ticketId: ticketId,
            message: message ?? "",
            agentId: agentId,
            eventType: eventType ?? "comment",
            traceId: traceId,
            source: source,
            lane: lane,
            createdAt: createdAt ?? Date.distantPast
        )
    }
}

struct TicketNoteDTO: Decodable {
    let id: String
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
        case targetType = "target_type"
        case targetId = "target_id"
        case noteType = "note_type"
        case createdBy = "created_by"
        case traceId = "trace_id"
        case signState = "sign_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> TicketNoteRecord {
        TicketNoteRecord(
            id: id,
            targetType: targetType,
            targetId: targetId,
            noteType: noteType,
            title: title,
            body: body,
            tags: tags ?? [],
            createdBy: createdBy,
            source: source,
            traceId: traceId,
            owner: owner,
            reviewer: reviewer,
            signState: signState,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct AgentRunTraceEventDTO: Decodable {
    let id: String
    let ticketId: String?
    let eventType: String?
    let message: String?
    let source: String?
    let lane: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, message, source, lane
        case ticketId = "ticket_id"
        case eventType = "event_type"
        case createdAt = "created_at"
    }

    func toDomain() -> AgentRunTraceEvent {
        AgentRunTraceEvent(
            id: id,
            ticketId: ticketId,
            eventType: eventType ?? "event",
            message: message ?? "",
            source: source,
            lane: lane,
            createdAt: createdAt ?? Date.distantPast
        )
    }
}

struct AgentRunTraceDTO: Decodable {
    let traceId: String
    let agentRuns: [AgentRunDTO]
    let events: [AgentRunTraceEventDTO]
    let computeRuns: [ComputeRunRecordDTO]?
    let chatMessages: [AgentRunTraceChatMessageDTO]?
    let notes: [TicketNoteDTO]?

    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case agentRuns = "agent_runs"
        case computeRuns = "compute_runs"
        case chatMessages = "chat_messages"
        case notes
        case events
    }

    func toDomain() -> AgentRunTrace {
        AgentRunTrace(
            traceId: traceId,
            agentRuns: agentRuns.map { $0.toDomain() }.sorted { $0.createdAt < $1.createdAt },
            events: events.map { $0.toDomain() }.sorted { $0.createdAt < $1.createdAt },
            computeRuns: (computeRuns ?? []).map { $0.toDomain() }.sorted { $0.createdAt < $1.createdAt },
            chatMessages: (chatMessages ?? []).map { $0.toDomain() }.sorted { $0.createdAt < $1.createdAt },
            notes: (notes ?? []).map { $0.toDomain() }.sorted { $0.updatedAt < $1.updatedAt }
        )
    }
}

struct AgentRunTraceChatMessageDTO: Decodable {
    let id: String
    let channelId: String
    let content: String
    let messageType: String
    let source: String?
    let lane: String?
    let deliveryMode: String?
    let provenance: String?
    let responseState: String?
    let triageId: String?
    let triageTraceId: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, content, source, lane, provenance
        case channelId = "channel_id"
        case messageType = "message_type"
        case deliveryMode = "delivery_mode"
        case responseState = "response_state"
        case triageId = "triage_id"
        case triageTraceId = "triage_trace_id"
        case createdAt = "created_at"
    }

    func toDomain() -> AgentRunTraceChatMessage {
        AgentRunTraceChatMessage(
            id: id,
            channelId: channelId,
            content: content,
            messageType: messageType,
            source: source,
            lane: lane,
            deliveryMode: deliveryMode,
            provenance: provenance,
            responseState: responseState,
            triageId: triageId,
            triageTraceId: triageTraceId,
            createdAt: createdAt ?? Date.distantPast
        )
    }
}

struct AgentRunArtifactSummaryDTO: Decodable {
    let key: String
    let value: String
    let kind: String
    let safeToPreview: Bool
    let exists: Bool?
    let sizeBytes: Int?
    let preview: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case key, value, kind, exists, preview, reason
        case safeToPreview = "safe_to_preview"
        case sizeBytes = "size_bytes"
    }

    func toDomain() -> AgentRunArtifactSummary {
        AgentRunArtifactSummary(
            key: key,
            value: value,
            kind: kind,
            safeToPreview: safeToPreview,
            exists: exists,
            sizeBytes: sizeBytes,
            preview: preview,
            reason: reason
        )
    }
}

struct ComputeRunRecordDTO: Decodable {
    let id: String
    let traceId: String?
    let surface: String
    let taskHint: String
    let route: String
    let requestedRoute: String?
    let actualTier: String?
    let actualBackend: String?
    let model: String?
    let backend: String?
    let status: String
    let fallbackUsed: Bool
    let latencyMs: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let outputPreview: String?
    let error: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, surface, route, model, backend, status, error
        case traceId = "trace_id"
        case taskHint = "task_hint"
        case requestedRoute = "requested_route"
        case actualTier = "actual_tier"
        case actualBackend = "actual_backend"
        case fallbackUsed = "fallback_used"
        case latencyMs = "latency_ms"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case outputPreview = "output_preview"
        case createdAt = "created_at"
    }

    func toDomain() -> ComputeRunRecord {
        ComputeRunRecord(
            id: id,
            traceId: traceId,
            surface: surface,
            taskHint: taskHint,
            route: route,
            requestedRoute: requestedRoute,
            actualTier: actualTier,
            actualBackend: actualBackend,
            model: model,
            backend: backend,
            status: status,
            fallbackUsed: fallbackUsed,
            latencyMs: latencyMs,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            outputPreview: outputPreview,
            error: error,
            createdAt: createdAt ?? Date.distantPast
        )
    }
}

private struct TicketAgentActionBody: Encodable {
    let agentId: String

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
    }
}

private struct CompleteTicketBody: Encodable {
    let agentId: String
    let resolutionNotes: String?

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case resolutionNotes = "resolution_notes"
    }
}
