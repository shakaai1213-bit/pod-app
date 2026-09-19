import CoreFoundation
import Foundation
import OrcaAPI
import OrcaRuntimeContracts

enum ConsoleWorkMode: String, CaseIterable, Identifiable {
    case portfolio
    case agentWork

    var id: String { rawValue }
    var title: String { self == .portfolio ? "Portfolio" : "Agent Work" }
}

struct ConsoleMetric: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    let status: String?
}

enum ConsoleWorkMetricFilter: String, CaseIterable, Identifiable, Sendable {
    case ready
    case assigned
    case waiting
    case approvals
    case protected
    case historical

    var id: String { rawValue }

    var groups: Set<String> {
        switch self {
        case .ready: [OrcaWorkControlProjection.Group.readyNow.rawValue]
        case .assigned: [OrcaWorkControlProjection.Group.assigned.rawValue]
        case .waiting: [OrcaWorkControlProjection.Group.waitingOnOthers.rawValue]
        case .approvals: [
                OrcaWorkControlProjection.Group.approvals.rawValue,
                OrcaWorkControlProjection.Group.approvalAttention.rawValue,
            ]
        case .protected: [OrcaWorkControlProjection.Group.protected.rawValue]
        case .historical: [OrcaWorkControlProjection.Group.historical.rawValue]
        }
    }

    var emptyTitle: String {
        switch self {
        case .ready: "No Ready Now records"
        case .assigned: "No assigned records"
        case .waiting: "No waiting records"
        case .approvals: "No approvals"
        case .protected: "No protected records"
        case .historical: "No historical records"
        }
    }

    static func filter(forMetricID id: String) -> ConsoleWorkMetricFilter? {
        ConsoleWorkMetricFilter(rawValue: id)
    }
}

struct ConsoleField: Identifiable, Equatable, Sendable {
    var id: String { label }
    let label: String
    let value: String
}

struct ConsoleRecord: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let status: String?
    let group: String
    let fields: [ConsoleField]
    let approval: ConsoleApprovalRecord?
    let ticket: ConsoleWaitingTicketRecord?

    init(
        id: String,
        title: String,
        subtitle: String?,
        status: String?,
        group: String,
        fields: [ConsoleField],
        approval: ConsoleApprovalRecord?,
        ticket: ConsoleWaitingTicketRecord? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.group = group
        self.fields = fields
        self.approval = approval
        self.ticket = ticket
    }
}

struct ConsoleWaitingTicketRecord: Equatable, Sendable {
    let id: String
    let endpoint: String
    let summary: String
    let agentSlug: String?
    let status: String?
    let blockedOn: String?
    let approvalState: String?
}

enum ConsoleApprovalBlockReason: Equatable, Sendable {
    case notPending
    case authorityMismatch(String)
    case resolutionHeld
    case selfApprovalProhibited
    case endpointMismatch
    case ticketUnresolved

    static var allCases: [ConsoleApprovalBlockReason] {
        [.notPending, .authorityMismatch(""), .resolutionHeld, .selfApprovalProhibited, .endpointMismatch, .ticketUnresolved]
    }

    var message: String {
        switch self {
        case .notPending:
            return "Not decidable: this approval is no longer pending."
        case let .authorityMismatch(authority):
            return "This approval is \(authority)'s to decide."
        case .resolutionHeld:
            return "Not decidable: resolution is held for this approval."
        case .selfApprovalProhibited:
            return "Not decidable here: self-approval is prohibited for this approval."
        case .endpointMismatch:
            return "Not decidable: the server-supplied decision endpoint does not match either expected approval path."
        case .ticketUnresolved:
            return "Not decidable: no single unambiguous linked ticket could be resolved."
        }
    }
}

struct ConsoleApprovalRecord: Equatable, Sendable {
    let id: String
    let authority: String
    let status: String
    let stale: Bool
    let decisionEndpoint: String?
    let viewerAuthorized: Bool
    let resolutionEnabled: Bool
    let selfApprovalProhibited: Bool
    let targetType: String?
    let targetReference: String?
    let linkedTicketIDs: [String]
    let ticketTitle: String?
    let ticketStatus: String?
    let approvalGate: String?
    let reason: String?
    let requestedBy: String?

    static let captainAuthority = "tony"

    init(
        id: String,
        authority: String,
        status: String,
        stale: Bool,
        decisionEndpoint: String?,
        viewerAuthorized: Bool,
        resolutionEnabled: Bool,
        selfApprovalProhibited: Bool,
        targetType: String?,
        targetReference: String?,
        linkedTicketIDs: [String],
        ticketTitle: String? = nil,
        ticketStatus: String? = nil,
        approvalGate: String? = nil,
        reason: String? = nil,
        requestedBy: String? = nil
    ) {
        self.id = id
        self.authority = authority
        self.status = status
        self.stale = stale
        self.decisionEndpoint = decisionEndpoint
        self.viewerAuthorized = viewerAuthorized
        self.resolutionEnabled = resolutionEnabled
        self.selfApprovalProhibited = selfApprovalProhibited
        self.targetType = targetType
        self.targetReference = targetReference
        self.linkedTicketIDs = linkedTicketIDs
        self.ticketTitle = ticketTitle
        self.ticketStatus = ticketStatus
        self.approvalGate = approvalGate
        self.reason = reason
        self.requestedBy = requestedBy
    }

    var isCaptainAuthority: Bool {
        authority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == Self.captainAuthority
    }

    var captainDecisionEndpoint: String? {
        guard isCaptainAuthority, let ticketID = resolvedTicketID else { return nil }
        return "/api/v1/tickets/\(ticketID)/approvals/\(id)"
    }

    var showsDecisionControl: Bool {
        isCaptainAuthority && canResolve
    }

    var resolvedTicketID: String? {
        let linked = Set(linkedTicketIDs)
        if linked.count == 1, let ticketID = linked.first {
            return ticketID
        }
        if targetType?.lowercased() == "ticket",
           let reference = targetReference,
           !reference.isEmpty {
            if linked.isEmpty || linked.contains(reference) {
                return reference
            }
        }
        return nil
    }

    var blockReason: ConsoleApprovalBlockReason? {
        guard status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "pending" else {
            return .notPending
        }
        if isCaptainAuthority {
            guard resolutionEnabled else { return .resolutionHeld }
            guard captainDecisionEndpoint != nil else { return .ticketUnresolved }
            return nil
        }
        guard viewerAuthorized else { return .authorityMismatch(authority) }
        guard resolutionEnabled else { return .resolutionHeld }
        guard !selfApprovalProhibited else { return .selfApprovalProhibited }
        guard let decisionEndpoint else { return .authorityMismatch(authority) }
        let flatEndpoint = "/api/v1/approvals/\(id)"
        if decisionEndpoint == flatEndpoint { return nil }
        guard let ticketID = resolvedTicketID else { return .ticketUnresolved }
        let ticketEndpoint = "/api/v1/tickets/\(ticketID)/approvals/\(id)"
        guard decisionEndpoint == ticketEndpoint else { return .endpointMismatch }
        return nil
    }

    var isProtectedTicketContext: Bool {
        ticketTitle == nil
            && ticketStatus == nil
            && approvalGate == nil
            && reason == nil
            && requestedBy == nil
            && resolvedTicketID != nil
    }

    var canResolve: Bool { blockReason == nil }
}

struct WaitingOnCaptainCounts: Decodable, Equatable, Sendable {
    let approvals: Int
    let tickets: Int
    let delegationRequests: Int
    let stale: Int

    enum CodingKeys: String, CodingKey {
        case approvals, tickets, stale
        case delegationRequests = "delegation_requests"
    }

    var badgeCount: Int { approvals + tickets + delegationRequests }

    static let zero = WaitingOnCaptainCounts(
        approvals: 0,
        tickets: 0,
        delegationRequests: 0,
        stale: 0
    )
}

struct WaitingOnCaptainItem: Decodable, Equatable, Sendable {
    let id: String
    let kind: String
    let title: String
    let summary: String
    let authority: String
    let agentSlug: String?
    let occurredAt: Date
    let ageHours: Double
    let staleAfterHours: Int?
    let isStale: Bool
    let gateSeverity: Int
    let endpoint: String
    let decisionEndpoint: String?
    let approvalId: String?
    let ticketId: String?
    let ticketTitle: String?
    let ticketStatus: String?
    let approvalGate: String?
    let reason: String?
    let requestedBy: String?

    // Forward-compatible ticket context. Part 1 may add these pointer-safe fields;
    // the v1 shape remains decodable when they are absent.
    let blockedOn: String?
    let approvalState: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, summary, authority, endpoint, reason
        case agentSlug = "agent_slug"
        case occurredAt = "occurred_at"
        case ageHours = "age_hours"
        case staleAfterHours = "stale_after_hours"
        case isStale = "is_stale"
        case gateSeverity = "gate_severity"
        case decisionEndpoint = "decision_endpoint"
        case approvalId = "approval_id"
        case ticketId = "ticket_id"
        case ticketTitle = "ticket_title"
        case ticketStatus = "ticket_status"
        case approvalGate = "approval_gate"
        case requestedBy = "requested_by"
        case blockedOn = "blocked_on"
        case approvalState = "approval_state"
    }
}

struct WaitingOnCaptainResponse: Decodable, Equatable, Sendable {
    let generatedAt: Date
    let source: String
    let counts: WaitingOnCaptainCounts
    let items: [WaitingOnCaptainItem]

    enum CodingKeys: String, CodingKey {
        case source, counts, items
        case generatedAt = "generated_at"
    }

    static func zero(at date: Date = Date()) -> WaitingOnCaptainResponse {
        WaitingOnCaptainResponse(
            generatedAt: date,
            source: "orca.waiting-on-captain.v1",
            counts: .zero,
            items: []
        )
    }
}

struct ConsoleSectionSnapshot: Equatable, Sendable {
    static let waitingOnCaptainEmptyTitle = "Nothing is waiting on you."
    static let delegationEmptyTitle = "No delegation requests"

    let section: ConsoleSection
    let metrics: [ConsoleMetric]
    let records: [ConsoleRecord]
    let sources: [String]
    let updatedAt: Date

    static func empty(_ section: ConsoleSection) -> ConsoleSectionSnapshot {
        ConsoleSectionSnapshot(
            section: section,
            metrics: [],
            records: [],
            sources: [],
            updatedAt: .distantPast
        )
    }

    func records(matching filter: ConsoleWorkMetricFilter) -> [ConsoleRecord] {
        records.filter { filter.groups.contains($0.group) }
    }

    var badgeCount: Int {
        guard section == .waitingOnCaptain else { return 0 }
        let badgeMetricIDs = Set(["approvals", "tickets", "delegations"])
        return metrics
            .filter { badgeMetricIDs.contains($0.id) }
            .compactMap { Int($0.value) }
            .reduce(0, +)
    }

    var emptyStateTitle: String? {
        section == .waitingOnCaptain && records.isEmpty
            ? Self.waitingOnCaptainEmptyTitle
            : nil
    }

    var delegationEmptyStateTitle: String? {
        guard section == .waitingOnCaptain,
              !records.contains(where: { $0.group == "Delegation Requests" }) else { return nil }
        return Self.delegationEmptyTitle
    }

    static func waitingOnCaptain(_ response: WaitingOnCaptainResponse) -> ConsoleSectionSnapshot {
        ConsoleSectionSnapshot(
            section: .waitingOnCaptain,
            metrics: [
                ConsoleMetric(id: "approvals", label: "Approvals", value: "\(response.counts.approvals)", status: response.counts.approvals > 0 ? "pending" : "ok"),
                ConsoleMetric(id: "tickets", label: "Tickets", value: "\(response.counts.tickets)", status: response.counts.tickets > 0 ? "attention" : "ok"),
                ConsoleMetric(id: "delegations", label: "Delegations", value: "\(response.counts.delegationRequests)", status: response.counts.delegationRequests > 0 ? "attention" : "ok"),
                ConsoleMetric(id: "stale", label: "Stale", value: "\(response.counts.stale)", status: response.counts.stale > 0 ? "attention" : "ok"),
            ],
            records: response.items.map(waitingOnCaptainRecord),
            sources: ["/api/v1/control-room/waiting-on-captain", response.source],
            updatedAt: response.generatedAt
        )
    }

    private static func waitingOnCaptainRecord(_ item: WaitingOnCaptainItem) -> ConsoleRecord {
        let group: String
        switch item.kind {
        case "approval": group = "Approvals"
        case "ticket": group = "Tickets"
        case "delegation_request": group = "Delegation Requests"
        default: group = item.kind.replacingOccurrences(of: "_", with: " ").capitalized
        }

        let agent = item.agentSlug ?? "Unassigned"
        let gate = item.approvalGate ?? "severity \(item.gateSeverity)"
        let waiting = "waiting \(max(0, Int(item.ageHours.rounded(.down))))h"
        var fields = [
            ConsoleField(label: "ID", value: item.id),
            ConsoleField(label: "Kind", value: item.kind.replacingOccurrences(of: "_", with: " ").capitalized),
            ConsoleField(label: "Summary", value: item.summary),
            ConsoleField(label: "Agent", value: agent),
            ConsoleField(label: "Age", value: waiting),
            ConsoleField(label: "Gate", value: gate),
            ConsoleField(label: "Endpoint", value: item.endpoint),
        ]
        if let staleAfterHours = item.staleAfterHours {
            fields.append(ConsoleField(label: "Stale After", value: "\(staleAfterHours)h"))
        }
        if let ticketStatus = item.ticketStatus {
            fields.append(ConsoleField(label: "Ticket Status", value: ticketStatus))
        }
        if let blockedOn = item.blockedOn {
            fields.append(ConsoleField(label: "Blocked On", value: blockedOn))
        }
        if let approvalState = item.approvalState {
            fields.append(ConsoleField(label: "Approval State", value: approvalState))
        }

        let approval: ConsoleApprovalRecord?
        if item.kind == "approval", let approvalID = item.approvalId {
            let linkedTicketIDs = item.ticketId.map { [$0] } ?? []
            approval = ConsoleApprovalRecord(
                id: approvalID,
                authority: item.authority,
                status: "pending",
                stale: item.isStale,
                decisionEndpoint: item.decisionEndpoint,
                viewerAuthorized: false,
                resolutionEnabled: item.decisionEndpoint != nil,
                selfApprovalProhibited: true,
                targetType: item.ticketId == nil ? nil : "ticket",
                targetReference: item.ticketId,
                linkedTicketIDs: linkedTicketIDs,
                ticketTitle: item.ticketTitle,
                ticketStatus: item.ticketStatus,
                approvalGate: item.approvalGate,
                reason: item.reason,
                requestedBy: item.requestedBy
            )
        } else {
            approval = nil
        }

        let ticket: ConsoleWaitingTicketRecord?
        if item.kind == "ticket", let ticketID = item.ticketId {
            ticket = ConsoleWaitingTicketRecord(
                id: ticketID,
                endpoint: item.endpoint,
                summary: item.summary,
                agentSlug: item.agentSlug,
                status: item.ticketStatus,
                blockedOn: item.blockedOn,
                approvalState: item.approvalState
            )
        } else {
            ticket = nil
        }

        return ConsoleRecord(
            id: item.id,
            title: item.title,
            subtitle: "\(agent) · \(waiting) · gate: \(gate)",
            status: item.isStale ? "stale" : (item.ticketStatus ?? "waiting"),
            group: group,
            fields: fields,
            approval: approval,
            ticket: ticket
        )
    }

    static func workControl(_ projection: OrcaWorkControlProjection) -> ConsoleSectionSnapshot {
        let counts = projection.counts
        let metrics = [
            ConsoleMetric(id: "ready", label: "Ready Now", value: "\(counts.readyNow)", status: counts.readyNow > 0 ? "ready" : "ok"),
            ConsoleMetric(id: "assigned", label: "Assigned", value: "\(counts.assigned)", status: nil),
            ConsoleMetric(id: "waiting", label: "Waiting", value: "\(counts.waitingOnOthers)", status: counts.waitingOnOthers > 0 ? "attention" : "ok"),
            ConsoleMetric(id: "approvals", label: "Approvals", value: "\(counts.approvals)", status: counts.approvals > 0 ? "pending" : "ok"),
            ConsoleMetric(id: "protected", label: "Protected", value: "\(counts.protected)", status: counts.protected > 0 ? "protected" : nil),
            ConsoleMetric(id: "historical", label: "Historical", value: "\(counts.historical)", status: nil),
        ]
        var records: [ConsoleRecord] = []
        for group in OrcaWorkControlProjection.Group.allCases
        where group != .approvals && group != .approvalAttention {
            records += projection.items(in: group).map { workRecord($0, group: group) }
        }
        records += projection.approvals.map { approvalRecord($0, group: .approvals) }
        records += projection.approvalAttention.map { approvalRecord($0, group: .approvalAttention) }
        return ConsoleSectionSnapshot(
            section: .work,
            metrics: metrics,
            records: records,
            sources: [
                "/api/v1/chat-runtime/v1/agents/\(projection.agentKey)/work-control",
                projection.sourceContract,
                "bundle:\(projection.bundleSHA256)",
            ],
            updatedAt: projection.generatedAt
        )
    }

    private static func workRecord(
        _ item: OrcaWorkControlProjection.Item,
        group: OrcaWorkControlProjection.Group
    ) -> ConsoleRecord {
        var fields = [
            ConsoleField(label: "ID", value: item.id),
            ConsoleField(label: "Kind", value: item.kind.capitalized),
            ConsoleField(label: "Priority", value: item.priority),
            ConsoleField(label: "Approval", value: item.approvalState),
            ConsoleField(label: "Execution", value: item.executionEligible ? "Eligible" : "Held"),
        ]
        if let waitingOn = item.waitingOn {
            fields.append(ConsoleField(label: "Waiting On", value: waitingOn))
        }
        if let blockedOn = item.blockedOn {
            fields.append(ConsoleField(label: "Blocked On", value: blockedOn))
        }
        return ConsoleRecord(
            id: "\(group.rawValue):\(item.id)",
            title: item.title,
            subtitle: item.reason,
            status: item.stale ? "stale" : item.status,
            group: group.rawValue,
            fields: fields,
            approval: nil
        )
    }

    private static func approvalRecord(
        _ approval: OrcaWorkControlProjection.Approval,
        group: OrcaWorkControlProjection.Group
    ) -> ConsoleRecord {
        let decision = ConsoleApprovalRecord(
            id: approval.id,
            authority: approval.authority,
            status: approval.status,
            stale: approval.stale,
            decisionEndpoint: approval.decisionEndpoint,
            viewerAuthorized: approval.viewerAuthorized,
            resolutionEnabled: approval.resolutionEnabled,
            selfApprovalProhibited: approval.selfApprovalProhibited,
            targetType: approval.targetType,
            targetReference: approval.targetReference,
            linkedTicketIDs: approval.linkedTicketIDs,
            ticketTitle: approval.ticketTitle,
            ticketStatus: approval.ticketStatus,
            approvalGate: approval.approvalGate,
            reason: approval.ticketReason,
            requestedBy: approval.requestedBy
        )
        var fields = [
            ConsoleField(label: "ID", value: approval.id),
            ConsoleField(label: "Authority", value: approval.authority),
            ConsoleField(label: "Status", value: approval.status),
            ConsoleField(label: "Staleness", value: approval.stale ? "Stale" : "Fresh"),
            ConsoleField(label: "Resolution", value: approval.resolutionEnabled ? "Enabled" : "Held"),
        ]
        if let ticketID = decision.resolvedTicketID {
            fields.append(ConsoleField(label: "Ticket", value: ticketID))
        }
        if decision.showsDecisionControl {
            if let endpoint = decision.captainDecisionEndpoint {
                fields.append(ConsoleField(label: "Decision Path", value: endpoint))
            }
        } else if let reason = decision.blockReason {
            fields.append(ConsoleField(label: "Decision", value: reason.message))
        }
        let actionTitle = approval.actionType.replacingOccurrences(of: "_", with: " ").capitalized
        return ConsoleRecord(
            id: "\(group.rawValue):\(approval.id)",
            title: approval.ticketTitle ?? actionTitle,
            subtitle: "\(actionTitle) · authority: \(approval.authority)",
            status: approval.stale ? "stale" : (approval.ticketStatus ?? "pending"),
            group: group.rawValue,
            fields: fields,
            approval: decision
        )
    }
}

enum ConsoleJSON: Decodable, Equatable, Sendable {
    case object([String: ConsoleJSON])
    case array([ConsoleJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(foundationValue value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let object as [String: Any]:
            self = .object(try object.mapValues(ConsoleJSON.init(foundationValue:)))
        case let array as [Any]:
            self = .array(try array.map(ConsoleJSON.init(foundationValue:)))
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        default:
            throw DecodingError.typeMismatch(
                ConsoleJSON.self,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unsupported ORCA JSON value"
                )
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: ConsoleJSON].self) {
            self = .object(value)
        } else if let value = try? container.decode([ConsoleJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            throw DecodingError.typeMismatch(
                ConsoleJSON.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported ORCA JSON value"
                )
            )
        }
    }

    var objectValue: [String: ConsoleJSON]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [ConsoleJSON]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var displayValue: String? {
        switch self {
        case let .string(value): return value
        case let .number(value):
            return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        case let .bool(value): return value ? "Yes" : "No"
        case .null: return nil
        case let .array(value): return "\(value.count) items"
        case let .object(value):
            for key in ["label", "title", "name", "summary", "status", "state"] {
                if let text = value[key]?.displayValue, !text.isEmpty { return text }
            }
            return "\(value.count) fields"
        }
    }
}
