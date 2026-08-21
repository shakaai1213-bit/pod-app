import Foundation

public struct OrcaWorkControlProjection: Hashable, Sendable {
    public enum Group: String, CaseIterable, Hashable, Sendable {
        case readyNow = "Ready Now"
        case assigned = "Assigned"
        case waitingOnOthers = "Waiting On Others"
        case approvals = "Approvals"
        case protected = "Protected"
        case historical = "Historical"
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
    }

    public struct Approval: Identifiable, Hashable, Sendable {
        public let id: String
        public let actionType: String
        public let authority: String
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
        protected = (bundle.protectedWork ?? []).map(Item.init)
        historical = (bundle.historicalWork ?? []).map(Item.init)
        resourceEndpoints = bundle.resources.endpoints?.additionalProperties ?? [:]
    }

    public func items(in group: Group) -> [Item] {
        switch group {
        case .readyNow: readyNow
        case .assigned: assigned
        case .waitingOnOthers: waitingOnOthers
        case .approvals: []
        case .protected: protected
        case .historical: historical
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

private extension OrcaWorkControlProjection.Approval {
    init(_ approval: Components.Schemas.ChatRuntimeWorkApprovalRead) {
        id = approval.approvalId
        actionType = approval.actionType
        authority = approval.authority
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
