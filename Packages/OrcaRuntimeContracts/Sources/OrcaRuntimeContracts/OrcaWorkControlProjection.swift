import Foundation

public struct OrcaWorkControlProjection: Hashable, Sendable {
    public enum Group: String, CaseIterable, Hashable, Sendable {
        case readyNow = "Ready Now"
        case assigned = "Assigned"
        case waitingOnOthers = "Waiting On Others"
        case approvals = "Decision Queue"
        case approvalAttention = "Approval Attention"
        case protected = "Protected"
        case historical = "Historical"
        case decisionsOnTony = "Decisions On Tony"
        case ticketsOnTony = "Tickets On Tony"
        case delegationRequests = "Delegation Requests"
    }

    public struct Item: Identifiable, Hashable, Sendable {
        public let id: String
        public let kind: String
        public let title: String
        public let status: String
        public let priority: String
        public let approvalState: String
        public let reason: String
        public let blockedOn: String?
        public let waitingOn: String?
        public let executionEligible: Bool
        public let stale: Bool
        public let updatedAt: Date
        public let pendingApprovalIDs: [String]
        public var desiredOutcome: String? = nil
        public var needsScope: Bool = false

        public init(
            id: String,
            kind: String,
            title: String,
            status: String,
            priority: String,
            approvalState: String,
            reason: String,
            blockedOn: String?,
            waitingOn: String?,
            executionEligible: Bool,
            stale: Bool,
            updatedAt: Date,
            pendingApprovalIDs: [String]
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.status = status
            self.priority = priority
            self.approvalState = approvalState
            self.reason = reason
            self.blockedOn = blockedOn
            self.waitingOn = waitingOn
            self.executionEligible = executionEligible
            self.stale = stale
            self.updatedAt = updatedAt
            self.pendingApprovalIDs = pendingApprovalIDs
        }
    }

    public struct Approval: Identifiable, Hashable, Sendable {
        public let id: String
        public let actionType: String
        public let authority: String
        public let status: String
        public let reason: String
        public let targetType: String?
        public let targetReference: String?
        public let linkedTicketIDs: [String]
        public let linkedTaskIDs: [String]
        public let decisionEndpoint: String?
        public let viewerAuthorized: Bool
        public let resolutionEnabled: Bool
        public let selfApprovalProhibited: Bool
        public let stale: Bool
        public let createdAt: Date
        public let ticketTitle: String?
        public let ticketStatus: String?
        public let approvalGate: String?
        public let ticketReason: String?
        public let requestedBy: String?
        public var desiredOutcome: String? = nil
        public var needsScope: Bool = false

        public init(
            id: String,
            actionType: String,
            authority: String,
            status: String,
            reason: String,
            targetType: String?,
            targetReference: String?,
            linkedTicketIDs: [String],
            linkedTaskIDs: [String],
            decisionEndpoint: String?,
            viewerAuthorized: Bool,
            resolutionEnabled: Bool,
            selfApprovalProhibited: Bool,
            stale: Bool,
            createdAt: Date,
            ticketTitle: String?,
            ticketStatus: String?,
            approvalGate: String?,
            ticketReason: String?,
            requestedBy: String?
        ) {
            self.id = id
            self.actionType = actionType
            self.authority = authority
            self.status = status
            self.reason = reason
            self.targetType = targetType
            self.targetReference = targetReference
            self.linkedTicketIDs = linkedTicketIDs
            self.linkedTaskIDs = linkedTaskIDs
            self.decisionEndpoint = decisionEndpoint
            self.viewerAuthorized = viewerAuthorized
            self.resolutionEnabled = resolutionEnabled
            self.selfApprovalProhibited = selfApprovalProhibited
            self.stale = stale
            self.createdAt = createdAt
            self.ticketTitle = ticketTitle
            self.ticketStatus = ticketStatus
            self.approvalGate = approvalGate
            self.ticketReason = ticketReason
            self.requestedBy = requestedBy
        }
    }

    public struct Counts: Hashable, Sendable {
        public let assigned: Int
        public let readyNow: Int
        public let waitingOnOthers: Int
        public let approvals: Int
        public let approvalInventory: Int
        public let protected: Int
        public let historical: Int
        public let stale: Int
        public let plannerItems: Int
        public let projectTasks: Int
        public let activeWorkerRuns: Int
        public let workerReviewRuns: Int
        public let researchActiveRequests: Int
        public let researchAwaitingReview: Int
        public let fishProducing: Int
        public let fishBlocked: Int
        public let toolsDeclared: Int
    }

    public let agentID: String
    public let agentKey: String
    public let generatedAt: Date
    public let bundleSHA256: String
    public let configurationSHA256: String
    public let runtimeManifestRevision: String
    public let contractVersion: String
    public let sourceContract: String
    public let counts: Counts
    public let readyNow: [Item]
    public let assigned: [Item]
    public let waitingOnOthers: [Item]
    public let approvals: [Approval]
    public let approvalInventory: [Approval]
    public let approvalAttention: [Approval]
    public let protected: [Item]
    public let historical: [Item]
    public let resourceEndpoints: [String: String]

    public init(_ bundle: Components.Schemas.ChatRuntimeWorkControlBundleRead) {
        agentID = bundle.agentId
        agentKey = bundle.agentKey
        generatedAt = bundle.generatedAt
        bundleSHA256 = bundle.bundleSha256
        configurationSHA256 = bundle.configurationSha256
        runtimeManifestRevision = bundle.runtimeManifestRevision
        contractVersion = bundle.contractVersion?.rawValue ?? "unknown"
        sourceContract = bundle.sourceContract?.rawValue ?? "unknown"
        counts = Counts(bundle.resources.counts)
        readyNow = (bundle.readyNow ?? []).map(Item.init)
        assigned = (bundle.assignedWork ?? []).map(Item.init)
        waitingOnOthers = (bundle.waitingOnOthers ?? []).map(Item.init)
        approvals = (bundle.approvalQueue ?? []).map(Approval.init)
        approvalInventory = (bundle.approvalInventory ?? []).map(Approval.init)
        let decisionIDs = Set(approvals.map(\.id))
        approvalAttention = approvalInventory.filter { !decisionIDs.contains($0.id) }
        protected = (bundle.protectedWork ?? []).map(Item.init)
        historical = (bundle.historicalWork ?? []).map(Item.init)
        resourceEndpoints = bundle.resources.endpoints?.additionalProperties ?? [:]
    }

    public struct CaptainLensItem: Decodable, Hashable, Sendable {
        public let id: String
        public let kind: String
        public let title: String
        public let summary: String
        public let authority: String
        public let agentSlug: String?
        public let occurredAt: Date
        public let ageHours: Double
        public let staleAfterHours: Int?
        public let isStale: Bool
        public let gateSeverity: Int
        public let endpoint: String
        public let decisionEndpoint: String?
        public let approvalId: String?
        public let ticketId: String?
        public let ticketTitle: String?
        public let ticketStatus: String?
        public let desiredOutcome: String?
        public let needsScope: Bool
        public let approvalGate: String?
        public let reason: String?
        public let requestedBy: String?

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
            case desiredOutcome = "desired_outcome"
            case needsScope = "needs_scope"
            case approvalGate = "approval_gate"
            case requestedBy = "requested_by"
        }
    }

    public struct CaptainLensGroup: Decodable, Hashable, Sendable {
        public let name: String
        public let items: [CaptainLensItem]
    }

    public struct CaptainLensResponse: Decodable, Hashable, Sendable {
        public let contractVersion: String
        public let generatedAt: Date
        public let groups: [CaptainLensGroup]
        public let counts: [String: Int]

        enum CodingKeys: String, CodingKey {
            case groups, counts
            case contractVersion = "contract_version"
            case generatedAt = "generated_at"
        }
    }

    public init(captainLens response: CaptainLensResponse) {
        agentID = "org"
        agentKey = "org"
        generatedAt = response.generatedAt
        bundleSHA256 = ""
        configurationSHA256 = ""
        runtimeManifestRevision = ""
        contractVersion = response.contractVersion
        sourceContract = response.contractVersion
        var groupedItems: [Group: [Item]] = [:]
        for group in response.groups {
            guard let key = Group(rawValue: group.name) else { continue }
            groupedItems[key] = group.items.map { lensItem in
                var item = Item(
                    id: lensItem.id,
                    kind: lensItem.kind,
                    title: lensItem.title,
                    status: lensItem.ticketStatus ?? (lensItem.isStale ? "stale" : "waiting"),
                    priority: "severity \(lensItem.gateSeverity)",
                    approvalState: "pending",
                    reason: lensItem.summary,
                    blockedOn: nil,
                    waitingOn: lensItem.agentSlug,
                    executionEligible: false,
                    stale: lensItem.isStale,
                    updatedAt: lensItem.occurredAt,
                    pendingApprovalIDs: lensItem.approvalId.map { [$0] } ?? []
                )
                item.desiredOutcome = lensItem.desiredOutcome
                item.needsScope = lensItem.needsScope
                return item
            }
        }
        let decisions = groupedItems[.decisionsOnTony] ?? []
        let tickets = groupedItems[.ticketsOnTony] ?? []
        let delegations = groupedItems[.delegationRequests] ?? []
        let totalStale = [decisions, tickets, delegations].flatMap { $0 }.filter(\.stale).count
        counts = Counts(
            assigned: 0,
            readyNow: 0,
            waitingOnOthers: tickets.count,
            approvals: decisions.count,
            approvalInventory: decisions.count,
            protected: 0,
            historical: 0,
            stale: totalStale,
            plannerItems: 0,
            projectTasks: 0,
            activeWorkerRuns: 0,
            workerReviewRuns: 0,
            researchActiveRequests: 0,
            researchAwaitingReview: 0,
            fishProducing: 0,
            fishBlocked: 0,
            toolsDeclared: 0
        )
        readyNow = []
        assigned = []
        waitingOnOthers = tickets
        let decisionByID = Dictionary(
            uniqueKeysWithValues: response.groups
                .first(where: { $0.name == Group.decisionsOnTony.rawValue })?.items
                .map { ($0.id, $0) } ?? []
        )
        approvals = decisions.compactMap { item -> Approval? in
            guard let approvalID = item.pendingApprovalIDs.first else { return nil }
            let lens = decisionByID[item.id]
            let ticketRef = lens?.ticketId
            var approval = Approval(
                id: approvalID,
                actionType: item.kind,
                authority: lens?.authority ?? "tony",
                status: "pending",
                reason: lens?.reason ?? item.reason,
                targetType: ticketRef == nil ? nil : "ticket",
                targetReference: ticketRef,
                linkedTicketIDs: ticketRef.map { [$0] } ?? [],
                linkedTaskIDs: [],
                decisionEndpoint: lens?.decisionEndpoint,
                viewerAuthorized: false,
                resolutionEnabled: lens?.decisionEndpoint != nil,
                selfApprovalProhibited: true,
                stale: item.stale,
                createdAt: item.updatedAt,
                ticketTitle: lens?.ticketTitle ?? item.title,
                ticketStatus: lens?.ticketStatus ?? item.status,
                approvalGate: lens?.approvalGate,
                ticketReason: lens?.reason ?? item.reason,
                requestedBy: lens?.requestedBy
            )
            approval.desiredOutcome = item.desiredOutcome
            approval.needsScope = item.needsScope
            return approval
        }
        approvalInventory = []
        approvalAttention = []
        protected = []
        historical = delegations
        resourceEndpoints = [:]
    }

    public func items(in group: Group) -> [Item] {
        switch group {
        case .readyNow: readyNow
        case .assigned: assigned
        case .waitingOnOthers: waitingOnOthers
        case .approvals, .approvalAttention, .decisionsOnTony: []
        case .protected: protected
        case .historical, .delegationRequests: historical
        case .ticketsOnTony: waitingOnOthers
        }
    }
}

private extension OrcaWorkControlProjection.Item {
    init(_ item: Components.Schemas.ChatRuntimeWorkItemRead) {
        id = item.workId
        kind = item.workKind.rawValue
        title = item.safeTitle
        status = item.status
        priority = item.priority
        approvalState = item.approvalState
        reason = item.bucketReason
        blockedOn = item.blockedOn
        waitingOn = item.waitingOn
        executionEligible = item.executionEligible
        stale = item.stale
        updatedAt = item.updatedAt
        pendingApprovalIDs = item.pendingApprovalIds ?? []
    }
}

extension OrcaWorkControlProjection.Approval {
    public init(_ approval: Components.Schemas.ChatRuntimeWorkApprovalRead) {
        id = approval.approvalId
        actionType = approval.actionType
        authority = approval.authority
        status = approval.status?.rawValue ?? "pending"
        reason = approval.authorizationReason
        targetType = approval.targetType
        targetReference = approval.targetRef
        linkedTicketIDs = approval.linkedTicketIds ?? []
        linkedTaskIDs = approval.linkedTaskIds ?? []
        decisionEndpoint = approval.decisionEndpoint
        viewerAuthorized = approval.viewerAuthorized
        resolutionEnabled = approval.resolutionEnabled
        selfApprovalProhibited = approval.selfApprovalProhibited
        stale = approval.stale
        createdAt = approval.createdAt
        ticketTitle = approval.ticketTitle
        ticketStatus = approval.ticketStatus
        approvalGate = approval.approvalGate
        ticketReason = approval.reason
        requestedBy = approval.requestedBy
    }
}

private extension OrcaWorkControlProjection.Counts {
    init(_ counts: Components.Schemas.ChatRuntimeWorkControlCountsRead) {
        assigned = counts.assignedWork
        readyNow = counts.readyNow
        waitingOnOthers = counts.waitingOnOthers
        approvals = counts.approvalQueue
        approvalInventory = counts.approvalInventory
        protected = counts.protectedWork
        historical = counts.historicalWork
        stale = counts.staleWork
        plannerItems = counts.plannerItems
        projectTasks = counts.projectTasks
        activeWorkerRuns = counts.activeWorkerRuns
        workerReviewRuns = counts.workerReviewRuns
        researchActiveRequests = counts.researchActiveRequests
        researchAwaitingReview = counts.researchAwaitingReview
        fishProducing = counts.fishProducing
        fishBlocked = counts.fishBlocked
        toolsDeclared = counts.toolsDeclared
    }
}
