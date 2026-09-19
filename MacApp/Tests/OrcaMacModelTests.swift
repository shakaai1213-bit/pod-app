import CryptoKit
import XCTest
import OrcaAPI
import OrcaRuntimeContracts
@testable import ORCA

private actor TestRuntimeTokenStore: RuntimeTokenStoring {
    private var credential: RuntimeCredential?

    init(token: String?) {
        credential = token.map {
            RuntimeCredential(
                accessToken: $0,
                refreshToken: "test-refresh-token",
                expiresAt: Date().addingTimeInterval(3_600),
                clientID: OrcaNativeAuthService.clientID,
                deviceID: "test-device-id-0123456789",
                serverOrigin: "http://127.0.0.1:8000",
                organizationID: "test-organization"
            )
        }
    }

    init(credential: RuntimeCredential?) {
        self.credential = credential
    }

    func loadCredential(for serverOrigin: String) -> RuntimeCredential? {
        credential?.serverOrigin == serverOrigin ? credential : nil
    }
    func storeCredential(_ credential: RuntimeCredential) { self.credential = credential }
    func deleteCredential(for serverOrigin: String) { credential = nil }

    func setCredential(_ credential: RuntimeCredential?) { self.credential = credential }
}

private final class TestURLProtocol: URLProtocol {
    static var response: ((URLRequest) throws -> (Int, Data))?

    static func bodyData(for request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            throw URLError(.cannotDecodeRawData)
        }
        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                body.append(buffer, count: count)
            } else if count == 0 {
                return body
            } else {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let response = Self.response else {
                throw URLError(.badServerResponse)
            }
            let (status, data) = try response(request)
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class OrcaMacModelTests: XCTestCase {
    func testRosterHasSevenUniqueNamedAgents() {
        XCTAssertEqual(AgentProfile.fallbackRoster.count, 7)
        XCTAssertEqual(Set(AgentProfile.fallbackRoster.map(\.id)).count, 7)
        XCTAssertEqual(
            Set(AgentProfile.fallbackRoster.map(\.id)),
            Set(["aloha", "maui", "shaka", "chief", "rooster", "coral", "reef"])
        )
    }

    func testConsoleExposesReviewedConversationMemory() {
        _ = OrcaMacModel.applyLatestMemoryProposal
    }

    func testConversationRefreshUsesBoundedRecentWindows() {
        XCTAssertEqual(
            OrcaMacModel.conversationRefreshLimit(hasCanonicalMessages: false),
            200
        )
        XCTAssertEqual(
            OrcaMacModel.conversationRefreshLimit(hasCanonicalMessages: true),
            50
        )
    }

    func testCanonicalMergeDeduplicatesAndPreservesPending() {
        let start = Date(timeIntervalSince1970: 1_000)
        var state = ConversationState()
        state.mergeCanonical([
            TranscriptMessage(
                id: "m1",
                role: .user,
                content: "Hello",
                createdAt: start,
                deliveryState: .persisted,
                retryIdentity: nil
            ),
        ])
        state.appendPending(id: "pending", content: "Next", at: start.addingTimeInterval(2))
        state.mergeCanonical([
            TranscriptMessage(
                id: "m1",
                role: .user,
                content: "Hello",
                createdAt: start,
                deliveryState: .persisted,
                retryIdentity: nil
            ),
            TranscriptMessage(
                id: "m2",
                role: .agent,
                content: "Hi",
                createdAt: start.addingTimeInterval(1),
                deliveryState: .persisted,
                retryIdentity: nil
            ),
        ])

        XCTAssertEqual(state.messages.map(\.id), ["m1", "m2", "pending"])
    }

    func testPendingResolutionUsesCanonicalIdentifiers() {
        let start = Date(timeIntervalSince1970: 2_000)
        var state = ConversationState()
        state.appendPending(id: "local", content: "Status?", at: start)
        state.resolvePending(
            id: "local",
            with: [
                TranscriptMessage(
                    id: "orca-user",
                    role: .user,
                    content: "Status?",
                    createdAt: start,
                    deliveryState: .persisted,
                    retryIdentity: nil
                ),
                TranscriptMessage(
                    id: "orca-agent",
                    role: .agent,
                    content: "Working",
                    createdAt: start.addingTimeInterval(1),
                    deliveryState: .persisted,
                    retryIdentity: nil
                ),
            ]
        )

        XCTAssertEqual(state.messages.map(\.id), ["orca-user", "orca-agent"])
        XCTAssertFalse(state.messages.contains(where: { $0.id == "local" }))
    }

    func testEndpointNormalizationAcceptsTailscaleAndRejectsNonHTTP() {
        XCTAssertEqual(
            OrcaMacModel.normalizedEndpoint("100.104.72.62:8000/")?.absoluteString,
            "http://100.104.72.62:8000"
        )
        XCTAssertNil(OrcaMacModel.normalizedEndpoint("file:///tmp/orca"))
        XCTAssertNil(OrcaMacModel.normalizedEndpoint("http://untrusted.example:8000"))
        XCTAssertNil(OrcaMacModel.normalizedEndpoint("https://orca.example"))
        XCTAssertNil(OrcaMacModel.normalizedEndpoint(""))
    }

    func testFailedTurnRetainsRetryIdentity() {
        var state = ConversationState()
        let identity = TurnRetryIdentity(traceID: "trace-1", idempotencyKey: "turn-1")
        state.appendPending(id: "pending", content: "Retry me", at: Date(), retryIdentity: identity)
        state.failPending(id: "pending", reason: "offline")

        XCTAssertEqual(state.messages.first?.retryIdentity, identity)
    }

    func testConsoleInventoryMatchesPodOperatingAreas() {
        XCTAssertEqual(
            Set(ConsoleSection.allCases),
            Set([.waitingOnCaptain, .overview, .conversations, .work, .workbench, .fund, .crew, .knowledge, .lab, .runtime, .maker])
        )
        XCTAssertEqual(ConsoleSection.allCases.first, .waitingOnCaptain)
        XCTAssertTrue(ConsoleSection.fund.isProtected)
        XCTAssertFalse(ConsoleSection.work.isProtected)
    }

    func testWaitingOnCaptainFixtureDecodesAndMapsWithoutResorting() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(
            WaitingOnCaptainResponse.self,
            from: Data(Self.waitingOnCaptainFixtureJSON.utf8)
        )

        XCTAssertEqual(response.source, "orca.waiting-on-captain.v1")
        XCTAssertEqual(response.counts, WaitingOnCaptainCounts(
            approvals: 1,
            tickets: 1,
            delegationRequests: 0,
            stale: 1
        ))
        XCTAssertEqual(response.items.map(\.id), ["ticket:ticket-1", "approval:approval-1"])

        let snapshot = ConsoleSectionSnapshot.waitingOnCaptain(response)
        XCTAssertEqual(snapshot.badgeCount, 2)
        XCTAssertEqual(snapshot.records.map(\.id), ["ticket:ticket-1", "approval:approval-1"])
        XCTAssertNil(snapshot.emptyStateTitle)
        XCTAssertEqual(snapshot.delegationEmptyStateTitle, "No delegation requests")

        let ticket = try XCTUnwrap(snapshot.records.first?.ticket)
        XCTAssertEqual(ticket.id, "ticket-1")
        XCTAssertEqual(ticket.endpoint, "/api/v1/tickets/ticket-1")

        let approval = try XCTUnwrap(snapshot.records.last?.approval)
        XCTAssertTrue(approval.isCaptainAuthority)
        XCTAssertEqual(
            approval.decisionEndpoint,
            "/api/v1/tickets/ticket-2/approvals/approval-1"
        )
        XCTAssertTrue(approval.showsDecisionControl)
    }

    func testWaitingOnCaptainZeroState() {
        let snapshot = ConsoleSectionSnapshot.waitingOnCaptain(
            .zero(at: Date(timeIntervalSince1970: 1_789_000_000))
        )

        XCTAssertEqual(snapshot.badgeCount, 0)
        XCTAssertTrue(snapshot.records.isEmpty)
        XCTAssertEqual(snapshot.emptyStateTitle, "Nothing is waiting on you.")
        XCTAssertEqual(snapshot.delegationEmptyStateTitle, "No delegation requests")
        XCTAssertEqual(
            snapshot.metrics.map(\.value),
            ["0", "0", "0", "0"]
        )
    }

    func testWaitingOnCaptain404ReturnsCleanZeroState() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/control-room/waiting-on-captain")
            return (404, Data(#"{"detail":"not found"}"#.utf8))
        }
        defer { TestURLProtocol.response = nil }
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        let snapshot = try await service.snapshot(
            for: .waitingOnCaptain,
            workControl: nil
        )

        XCTAssertEqual(snapshot.emptyStateTitle, "Nothing is waiting on you.")
        XCTAssertEqual(snapshot.badgeCount, 0)
    }

    func testConsoleWorkSeparatesPortfolioFromAgentQueue() {
        XCTAssertEqual(ConsoleWorkMode.allCases.map(\.rawValue), ["portfolio", "agentWork"])
        XCTAssertEqual(ConsoleWorkMode.portfolio.title, "Portfolio")
        XCTAssertEqual(ConsoleWorkMode.agentWork.title, "Agent Work")
    }

    func testWorkbenchPaneBarFitsTheMinimumContentColumn() {
        let panes = WorkbenchPane.allCases

        XCTAssertEqual(
            panes.map(\.rawValue),
            ["workspace", "files", "diff", "tests", "terminal", "workers", "evidence", "approvals"]
        )
        XCTAssertEqual(Set(panes.map(\.title)).count, panes.count)
        XCTAssertLessThanOrEqual(
            CGFloat(panes.count) * WorkbenchPane.minimumControlWidth,
            WorkbenchPane.minimumBarWidth
        )
    }

    func testConsoleJSONPreservesStructuredValues() throws {
        let value = try JSONDecoder().decode(
            ConsoleJSON.self,
            from: Data(#"{"ok":true,"count":7,"items":[{"title":"Coral"}]}"#.utf8)
        )

        XCTAssertEqual(value.objectValue?["ok"]?.displayValue, "Yes")
        XCTAssertEqual(value.objectValue?["count"]?.displayValue, "7")
        XCTAssertEqual(value.objectValue?["items"]?.displayValue, "1 items")
    }

    func testApprovalDecodesTicketContextFieldsWhenPresent() throws {
        let json = """
        {
          "action_type": "credential_rotation",
          "approval_id": "approval-ctx-1",
          "authority": "tony",
          "authorization_reason": "Signed-in human owns credential rotation.",
          "created_at": "2026-09-17T04:00:00Z",
          "decision_endpoint": "/api/v1/approvals/approval-ctx-1",
          "linked_task_ids": [],
          "linked_ticket_ids": ["ticket-a"],
          "no_cascade": false,
          "reason": "Ticket 824 rotates the macOS deploy key.",
          "requested_by": "maui",
          "resolution_enabled": true,
          "self_approval_prohibited": false,
          "stale": false,
          "stale_after_hours": 72,
          "status": "pending",
          "target_ref": "ticket-a",
          "target_type": "ticket",
          "ticket_status": "in_review",
          "ticket_title": "Rotate macOS Deploy Key",
          "approval_gate": "pre_merge",
          "viewer_authorized": true
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let approval = try decoder.decode(
            Components.Schemas.ChatRuntimeWorkApprovalRead.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(approval.ticketTitle, "Rotate macOS Deploy Key")
        XCTAssertEqual(approval.ticketStatus, "in_review")
        XCTAssertEqual(approval.approvalGate, "pre_merge")
        XCTAssertEqual(approval.reason, "Ticket 824 rotates the macOS deploy key.")
        XCTAssertEqual(approval.requestedBy, "maui")

        let projection = OrcaWorkControlProjection.Approval(approval)
        XCTAssertEqual(projection.ticketTitle, "Rotate macOS Deploy Key")
        XCTAssertEqual(projection.ticketStatus, "in_review")
        XCTAssertEqual(projection.approvalGate, "pre_merge")
        XCTAssertEqual(projection.ticketReason, "Ticket 824 rotates the macOS deploy key.")
        XCTAssertEqual(projection.requestedBy, "maui")
    }

    func testApprovalDecodesWithoutTicketContextFields() throws {
        let json = """
        {
          "action_type": "credential_rotation",
          "approval_id": "approval-ctx-2",
          "authority": "tony",
          "authorization_reason": "Signed-in human owns credential rotation.",
          "created_at": "2026-09-17T04:00:00Z",
          "decision_endpoint": "/api/v1/approvals/approval-ctx-2",
          "linked_task_ids": [],
          "linked_ticket_ids": ["ticket-b"],
          "no_cascade": false,
          "resolution_enabled": true,
          "self_approval_prohibited": false,
          "stale": false,
          "stale_after_hours": 72,
          "status": "pending",
          "target_ref": "ticket-b",
          "target_type": "ticket",
          "viewer_authorized": true
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let approval = try decoder.decode(
            Components.Schemas.ChatRuntimeWorkApprovalRead.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(approval.ticketTitle)
        XCTAssertNil(approval.ticketStatus)
        XCTAssertNil(approval.approvalGate)
        XCTAssertNil(approval.reason)
        XCTAssertNil(approval.requestedBy)

        let projection = OrcaWorkControlProjection.Approval(approval)
        XCTAssertNil(projection.ticketTitle)
        XCTAssertNil(projection.ticketReason)
    }

    func testTicketTitleTakesPrecedenceOverActionTypeTitle() async throws {
        let snapshot = try await workSnapshot()
        let attentionRecord = try XCTUnwrap(snapshot.records.first { $0.group == "Approval Attention" })
        let queueRecord = try XCTUnwrap(snapshot.records.first { $0.group == "Decision Queue" })

        XCTAssertEqual(attentionRecord.title, "Rotate Deploy Signing Key")
        XCTAssertEqual(queueRecord.title, "Sign Standard")
        XCTAssertNotEqual(attentionRecord.title, queueRecord.title)
        XCTAssertNotEqual(attentionRecord.id, queueRecord.id)
    }

    func testProtectedApprovalContextIsDetected() {
        let protectedApproval = Self.eligibleApproval()
        XCTAssertNil(protectedApproval.ticketTitle)
        XCTAssertNil(protectedApproval.ticketStatus)
        XCTAssertNil(protectedApproval.approvalGate)
        XCTAssertNil(protectedApproval.reason)
        XCTAssertNil(protectedApproval.requestedBy)
        XCTAssertNotNil(protectedApproval.resolvedTicketID)
        XCTAssertTrue(protectedApproval.isProtectedTicketContext)

        let withContext = ConsoleApprovalRecord(
            id: "approval-ctx-3",
            authority: "tony",
            status: "pending",
            stale: false,
            decisionEndpoint: "/api/v1/approvals/approval-ctx-3",
            viewerAuthorized: true,
            resolutionEnabled: true,
            selfApprovalProhibited: false,
            targetType: "ticket",
            targetReference: "ticket-1",
            linkedTicketIDs: ["ticket-1"],
            ticketTitle: "Rotate macOS Deploy Key",
            reason: "Key expires next week."
        )
        XCTAssertFalse(withContext.isProtectedTicketContext)

        let noTicket = ConsoleApprovalRecord(
            id: "approval-ctx-4",
            authority: "tony",
            status: "pending",
            stale: false,
            decisionEndpoint: nil,
            viewerAuthorized: true,
            resolutionEnabled: true,
            selfApprovalProhibited: false,
            targetType: nil,
            targetReference: nil,
            linkedTicketIDs: []
        )
        XCTAssertFalse(noTicket.isProtectedTicketContext)
    }

    func testWorkSnapshotProjectsValidatedRuntimeWorkControl() async throws {        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789"
        )
        let snapshot = try await service.snapshot(
            for: .work,
            workControl: Self.workControlBundle
        )

        XCTAssertEqual(snapshot.metrics.first(where: { $0.id == "ready" })?.value, "1")
        XCTAssertEqual(snapshot.metrics.first(where: { $0.id == "assigned" })?.value, "1")
        XCTAssertEqual(snapshot.metrics.first(where: { $0.id == "approvals" })?.value, "1")
        XCTAssertEqual(
            Set(snapshot.records.map(\.group)),
            Set(["Ready Now", "Assigned", "Decision Queue", "Approval Attention"])
        )
        XCTAssertEqual(Set(snapshot.records.map(\.title)), Set(["Prove Work Control", "Sign Standard", "Rotate Deploy Signing Key"]))
        let approvalRecord = snapshot.records.first { $0.group == "Decision Queue" }
        XCTAssertEqual(approvalRecord?.status, "pending")
        XCTAssertEqual(approvalRecord?.approval?.status, "pending")
        XCTAssertEqual(approvalRecord?.approval?.stale, false)
        XCTAssertTrue(approvalRecord?.fields.contains { $0.label == "Staleness" && $0.value == "Fresh" } ?? false)
        XCTAssertNil(approvalRecord?.approval?.ticketTitle)
        XCTAssertNil(approvalRecord?.approval?.ticketStatus)
        XCTAssertNil(approvalRecord?.approval?.approvalGate)
        XCTAssertNil(approvalRecord?.approval?.reason)
        XCTAssertNil(approvalRecord?.approval?.requestedBy)
        XCTAssertEqual(approvalRecord?.title, "Sign Standard")
        XCTAssertEqual(approvalRecord?.subtitle, "Sign Standard · authority: aloha")
        XCTAssertEqual(approvalRecord?.approval?.isProtectedTicketContext, true)
        let attentionRecord = try XCTUnwrap(snapshot.records.first { $0.group == "Approval Attention" })
        let attentionApproval = try XCTUnwrap(attentionRecord.approval)
        XCTAssertEqual(attentionApproval.id, "approval-credential-rotation")
        XCTAssertEqual(attentionApproval.authority, "tony")
        XCTAssertEqual(attentionApproval.status, "pending")
        XCTAssertNil(attentionApproval.blockReason)
        XCTAssertTrue(attentionApproval.canResolve)
        XCTAssertEqual(attentionApproval.decisionEndpoint, "/api/v1/approvals/approval-credential-rotation")
        XCTAssertEqual(attentionRecord.title, "Rotate Deploy Signing Key")
        XCTAssertEqual(attentionRecord.subtitle, "Credential Rotation · authority: tony")
        XCTAssertEqual(attentionRecord.status, "in_review")
        XCTAssertEqual(attentionApproval.ticketTitle, "Rotate Deploy Signing Key")
        XCTAssertEqual(attentionApproval.ticketStatus, "in_review")
        XCTAssertEqual(attentionApproval.reason, "Rotate the deploy signing key before expiry.")
        XCTAssertEqual(attentionApproval.requestedBy, "maui")
        XCTAssertNil(attentionApproval.approvalGate)
        XCTAssertFalse(attentionApproval.isProtectedTicketContext)
        XCTAssertEqual(Set(snapshot.records.map(\.id)).count, snapshot.records.count)
        XCTAssertEqual(
            Set(snapshot.sources),
            Set([
                "/api/v1/chat-runtime/v1/agents/coral/work-control",
                "orca.agent-workbench.v1",
                "bundle:\(String(repeating: "d", count: 64))",
            ])
        )
    }

    func testStalePendingApprovalFromBundleIsDecidable() async throws {
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789"
        )
        let snapshot = try await service.snapshot(
            for: .work,
            workControl: Self.staleWorkControlBundle
        )

        let record = try XCTUnwrap(snapshot.records.first { $0.group == "Decision Queue" })
        let approval = try XCTUnwrap(record.approval)
        XCTAssertEqual(approval.status, "pending")
        XCTAssertTrue(approval.stale)
        XCTAssertNil(approval.blockReason)
        XCTAssertTrue(approval.canResolve)
        XCTAssertTrue(record.fields.contains { $0.label == "Staleness" && $0.value == "Stale" })
    }

    func testMetricCardFilterNarrowsRecordsToMatchingBucket() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)

        model.toggleWorkMetricFilter("ready")

        XCTAssertEqual(model.workMetricFilter, .ready)
        XCTAssertEqual(model.displayedWorkRecords.map(\.group), ["Ready Now"])
        XCTAssertEqual(model.displayedWorkRecords.map(\.title), ["Prove Work Control"])
        XCTAssertGreaterThan(model.selectedSnapshot.records.count, model.displayedWorkRecords.count)
    }

    func testTappingActiveMetricCardClearsFilter() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)

        model.toggleWorkMetricFilter("approvals")
        XCTAssertEqual(model.workMetricFilter, .approvals)
        model.toggleWorkMetricFilter("approvals")

        XCTAssertNil(model.workMetricFilter)
        XCTAssertEqual(model.displayedWorkRecords, snapshot.records)
    }

    func testOnlyOneMetricFilterIsActiveAtATime() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)

        model.toggleWorkMetricFilter("ready")
        model.toggleWorkMetricFilter("assigned")

        XCTAssertEqual(model.workMetricFilter, .assigned)
        XCTAssertEqual(model.displayedWorkRecords.map(\.group), ["Assigned"])
    }

    func testApprovalsFilterIncludesDecisionQueueAndApprovalAttention() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)

        model.toggleWorkMetricFilter("approvals")

        XCTAssertEqual(
            Set(model.displayedWorkRecords.map(\.group)),
            Set(["Decision Queue", "Approval Attention"])
        )
        XCTAssertEqual(
            Set(model.displayedWorkRecords.map(\.title)),
            Set(["Sign Standard", "Rotate Deploy Signing Key"])
        )
    }

    func testFilterWithNoMatchingRecordsYieldsExplicitEmptyState() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)

        model.toggleWorkMetricFilter("waiting")

        XCTAssertTrue(model.displayedWorkRecords.isEmpty)
        XCTAssertEqual(model.workMetricFilter?.emptyTitle, "No waiting records")
        XCTAssertEqual(ConsoleWorkMetricFilter.approvals.emptyTitle, "No approvals")
    }

    func testMetricCardCountsAreUnchangedByActiveFilter() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)
        let before = model.selectedSnapshot.metrics

        model.toggleWorkMetricFilter("approvals")

        XCTAssertEqual(model.selectedSnapshot.metrics, before)
        XCTAssertEqual(model.selectedSnapshot.records, snapshot.records)
        XCTAssertEqual(model.selectedSnapshot.metrics.first(where: { $0.id == "approvals" })?.value, "1")
    }

    func testFilterSurvivesSnapshotRefreshOfSameView() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)
        model.toggleWorkMetricFilter("approvals")

        model.sectionSnapshots[.work] = try await workSnapshot()

        XCTAssertEqual(model.workMetricFilter, .approvals)
        XCTAssertEqual(
            Set(model.displayedWorkRecords.map(\.group)),
            Set(["Decision Queue", "Approval Attention"])
        )
    }

    func testChangingSelectedAgentResetsFilter() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)
        model.toggleWorkMetricFilter("approvals")

        model.selectWorkControlAgent("maui")

        XCTAssertNil(model.workMetricFilter)
    }

    func testChangingSectionResetsFilter() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)
        model.toggleWorkMetricFilter("approvals")

        model.selectSection(.overview, refresh: false)

        XCTAssertNil(model.workMetricFilter)
    }

    func testFilterExcludingSelectedRecordClearsInspectorSelection() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)
        let readyRecord = try XCTUnwrap(snapshot.records.first { $0.group == "Ready Now" })
        model.selectRecord(readyRecord.id)

        model.toggleWorkMetricFilter("approvals")

        XCTAssertNil(model.selectedRecordID)
        XCTAssertNil(model.selectedRecord)
    }

    func testFilterIncludingSelectedRecordKeepsInspectorSelection() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)
        let approvalRecord = try XCTUnwrap(snapshot.records.first { $0.group == "Approval Attention" })
        model.selectRecord(approvalRecord.id)

        model.toggleWorkMetricFilter("approvals")

        XCTAssertEqual(model.selectedRecordID, approvalRecord.id)
        XCTAssertEqual(model.selectedRecord, approvalRecord)
    }

    func testEveryWorkMetricCardHasAFilter() async throws {
        let snapshot = try await workSnapshot()
        let readyRecords = snapshot.records(matching: .ready)
        XCTAssertEqual(readyRecords, snapshot.records.filter { $0.group == "Ready Now" })

        for metric in snapshot.metrics {
            XCTAssertNotNil(
                ConsoleWorkMetricFilter.filter(forMetricID: metric.id),
                "Metric card \(metric.id) must be filterable"
            )
        }
        XCTAssertNil(ConsoleWorkMetricFilter.filter(forMetricID: "unknown-metric"))
    }

    func testConversationPersistenceChangesWithOrganizationAndClearsLegacyKey() {
        let suiteName = "OrcaMacModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let origin = "http://100.104.72.62:8000"
        let agentID = "coral"
        let orgAKey = OrcaMacModel.conversationDefaultsKey(
            origin: origin,
            organizationID: "organization-a",
            agentID: agentID
        )
        let orgBKey = OrcaMacModel.conversationDefaultsKey(
            origin: origin,
            organizationID: "organization-b",
            agentID: agentID
        )
        defaults.set("legacy-conversation", forKey: "orca.mac.conversation.coral")
        defaults.set("organization-a-conversation", forKey: orgAKey)
        defaults.set("organization-b-conversation", forKey: orgBKey)

        let model = OrcaMacModel(
            tokenStore: TestRuntimeTokenStore(token: nil),
            defaults: defaults
        )
        model.activateConversationScope(origin: origin, organizationID: "organization-a")
        XCTAssertEqual(model.selectedConversation.conversationID, "organization-a-conversation")
        XCTAssertNil(defaults.string(forKey: "orca.mac.conversation.coral"))

        model.conversations[agentID] = ConversationState(conversationID: "in-memory-organization-a")
        model.activateConversationScope(origin: origin, organizationID: "organization-b")
        XCTAssertEqual(model.selectedConversation.conversationID, "organization-b-conversation")
        XCTAssertNotEqual(orgAKey, orgBKey)
    }

    func testCanonicalChannelHydrationReplacesStaleLocalPointer() {
        let suiteName = "OrcaMacModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let origin = "http://100.104.72.62:8000"
        let key = OrcaMacModel.conversationDefaultsKey(
            origin: origin,
            organizationID: "canonical-organization",
            agentID: "coral"
        )
        defaults.set("stale-local-channel", forKey: key)
        let model = OrcaMacModel(
            tokenStore: TestRuntimeTokenStore(token: nil),
            defaults: defaults
        )
        model.activateConversationScope(
            origin: origin,
            organizationID: "canonical-organization"
        )
        model.conversations["coral"] = ConversationState(
            conversationID: "stale-local-channel"
        )

        model.hydrateCanonicalConversationIDs(["coral": "orca-canonical-channel"])

        XCTAssertEqual(model.conversations["coral"]?.conversationID, "orca-canonical-channel")
        XCTAssertEqual(defaults.string(forKey: key), "orca-canonical-channel")
    }

    func testConsoleDiscoversOnlyCanonicalNamedAgentChannels() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/chat/channels")
            return (200, Data(#"""
            [
              {"id":"00000000-0000-4000-8000-000000000001","name":"direct:coral","type":"direct","channel_purpose":"direct_agent"},
              {"id":"00000000-0000-4000-8000-000000000002","name":"direct:maui","type":"direct","channel_purpose":"direct_agent"},
              {"id":"00000000-0000-4000-8000-000000000003","name":"team","type":"general","channel_purpose":"general"},
              {"id":"00000000-0000-4000-8000-000000000004","name":"direct:unknown","type":"direct","channel_purpose":"direct_agent"}
            ]
            """#.utf8))
        }
        defer { TestURLProtocol.response = nil }
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        let channels = try await service.directAgentChannelIDs(
            allowedAgentIDs: ["coral", "maui"]
        )

        XCTAssertEqual(channels, [
            "coral": "00000000-0000-4000-8000-000000000001",
            "maui": "00000000-0000-4000-8000-000000000002",
        ])
    }

    func testConsoleRejectsDuplicateCanonicalAgentChannels() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TestURLProtocol.response = { _ in
            (200, Data(#"""
            [
              {"id":"00000000-0000-4000-8000-000000000001","name":"direct:coral","type":"direct","channel_purpose":"direct_agent"},
              {"id":"00000000-0000-4000-8000-000000000002","name":"direct:coral","type":"direct","channel_purpose":"direct_agent"}
            ]
            """#.utf8))
        }
        defer { TestURLProtocol.response = nil }
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        do {
            _ = try await service.directAgentChannelIDs(allowedAgentIDs: ["coral"])
            XCTFail("Duplicate canonical channels must fail closed")
        } catch let error as OrcaConsoleServiceError {
            guard case .invalidResponse = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRuntimeContractProbeSeparatesUpgradeFromCredentialGate() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TestURLProtocol.response = { request in
            (request.url?.host == "old.orca.test" ? 404 : 401, Data())
        }
        defer { TestURLProtocol.response = nil }

        let oldRuntime = await OrcaRuntimeService.probeContract(
            at: URL(string: "http://old.orca.test:8000")!,
            session: session
        )
        let currentRuntime = await OrcaRuntimeService.probeContract(
            at: URL(string: "http://current.orca.test:8000")!,
            session: session
        )

        XCTAssertEqual(oldRuntime, .upgradeRequired)
        XCTAssertEqual(currentRuntime, .available)
    }

    func testNativeAuthCoalescesConcurrentRefreshes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let lock = NSLock()
        var challengeCount = 0
        var refreshCount = 0
        TestURLProtocol.response = { request in
            switch request.url?.path {
            case "/api/v1/auth/native/challenge":
                lock.withLock { challengeCount += 1 }
                return (200, Data(#"{"nonce":"single-flight-nonce"}"#.utf8))
            case "/api/v1/auth/refresh":
                lock.withLock { refreshCount += 1 }
                Thread.sleep(forTimeInterval: 0.05)
                return (200, Data(#"{"access_token":"fresh-access","refresh_token":"fresh-refresh","expires_in":3600,"organization_id":"test-organization"}"#.utf8))
            default:
                return (404, Data(#"{"detail":"not found"}"#.utf8))
            }
        }
        defer { TestURLProtocol.response = nil }

        let store = TestRuntimeTokenStore(credential: nil)
        let auth = try OrcaNativeAuthService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: store,
            session: session,
            signingKey: Curve25519.Signing.PrivateKey()
        )
        let deviceID = await auth.boundDeviceID()
        await store.setCredential(RuntimeCredential(
            accessToken: "expired-access",
            refreshToken: "rotating-refresh",
            expiresAt: Date().addingTimeInterval(-60),
            clientID: OrcaNativeAuthService.clientID,
            deviceID: deviceID,
            serverOrigin: "http://127.0.0.1:8000",
            organizationID: "test-organization"
        ))

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 {
                group.addTask { try await auth.validAccessToken() }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(Set(tokens), ["fresh-access"])
        XCTAssertEqual(lock.withLock { challengeCount }, 1)
        XCTAssertEqual(lock.withLock { refreshCount }, 1)
    }

    func testWorkbenchServiceUsesTypedTicketBoundRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let operation = Self.workbenchOperationJSON
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer console-token")
            XCTAssertFalse(request.value(forHTTPHeaderField: "X-ORCA-Device-ID")?.isEmpty ?? true)
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/engineering-workbench/tickets"):
                XCTAssertEqual(request.url?.query, "agent_slug=coral")
                return (200, Data(#"[{"id":"ticket-c9","title":"Desktop Workbench","status":"open","flow_state":"in_progress","priority":"P1"}]"#.utf8))
            case ("GET", "/api/v1/engineering-workbench/contract"):
                XCTAssertEqual(request.url?.query, "agent_slug=coral")
                return (200, Data(Self.workbenchContractJSON.utf8))
            case ("GET", "/api/v1/engineering-workbench/tickets/ticket-c9"):
                XCTAssertEqual(request.url?.query, "agent_slug=coral")
                let payload = "{\"schema\":\"orca.engineering-workbench-session.v1\",\"ticket_id\":\"ticket-c9\",\"ticket_title\":\"Desktop Workbench\",\"ticket_status\":\"open\",\"contract\":\(Self.workbenchContractJSON),\"operations\":[\(operation)],\"counts\":{\"total\":1,\"queued\":1},\"sources\":[\"/api/v1/tickets/ticket-c9\"]}"
                return (200, Data(payload.utf8))
            case ("POST", "/api/v1/engineering-workbench/tickets/ticket-c9/operations"):
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                let body = try TestURLProtocol.bodyData(for: request)
                let object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                XCTAssertEqual(object["agent_slug"] as? String, "coral")
                XCTAssertEqual(object["action_id"] as? String, "git.status")
                XCTAssertEqual(object["root_id"] as? String, "pod-client")
                XCTAssertNil(object["host_path"])
                XCTAssertNil(object["shell"])
                let payload = "{\"created\":true,\"operation\":\(operation),\"host\":\(Self.workbenchHostJSON),\"message\":\"Queued\"}"
                return (201, Data(payload.utf8))
            case ("POST", "/api/v1/engineering-workbench/operations/run-c9/approval"):
                let body = try TestURLProtocol.bodyData(for: request)
                let object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: Any]
                )
                XCTAssertEqual(object["decision"] as? String, "approved")
                XCTAssertNotNil(object["note"])
                return (200, Data(operation.utf8))
            default:
                return (404, Data(#"{"detail":"not found"}"#.utf8))
            }
        }
        defer { TestURLProtocol.response = nil }

        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        let tickets = try await service.workbenchTickets(agentSlug: "coral")
        let contract = try await service.workbenchContract(agentSlug: "coral")
        let workbench = try await service.workbenchSession(
            ticketID: "ticket-c9",
            agentSlug: "coral"
        )
        let created = try await service.createWorkbenchOperation(
            ticketID: "ticket-c9",
            payload: OrcaEngineeringOperationCreate(
                agentSlug: "coral",
                actionID: "git.status",
                rootID: "pod-client",
                idempotencyKey: "workbench-test-1"
            )
        )
        let approved = try await service.decideWorkbenchApproval(
            runID: "run-c9",
            decision: OrcaEngineeringApprovalDecision(
                decision: "approved",
                note: "Approve exact test run."
            )
        )

        XCTAssertEqual(tickets.map(\.id), ["ticket-c9"])
        XCTAssertEqual(contract.policySHA256, String(repeating: "a", count: 64))
        XCTAssertEqual(workbench.operations.map(\.id), ["run-c9"])
        XCTAssertTrue(created.created)
        XCTAssertEqual(approved.id, "run-c9")
    }

    func testEligibleApprovalIsDecidable() {
        let approval = Self.eligibleApproval()

        XCTAssertNil(approval.blockReason)
        XCTAssertTrue(approval.canResolve)
        XCTAssertEqual(approval.resolvedTicketID, "ticket-1")
    }

    func testEachGuardConditionBlocksWithSpecificReason() {
        let cases: [(ConsoleApprovalRecord, ConsoleApprovalBlockReason)] = [
            (Self.eligibleApproval(status: "approved"), .notPending),
            (Self.eligibleApproval(authority: "coral", viewerAuthorized: false), .authorityMismatch("coral")),
            (Self.eligibleApproval(authority: "maui", viewerAuthorized: false), .authorityMismatch("maui")),
            (Self.eligibleApproval(resolutionEnabled: false), .resolutionHeld),
            (Self.eligibleApproval(authority: "maui", selfApprovalProhibited: true), .selfApprovalProhibited),
            (Self.eligibleApproval(targetReference: nil, linkedTicketIDs: []), .ticketUnresolved),
            (Self.eligibleApproval(targetReference: nil, linkedTicketIDs: ["ticket-1", "ticket-2"]), .ticketUnresolved),
        ]
        for (approval, expected) in cases {
            XCTAssertEqual(approval.blockReason, expected)
            XCTAssertFalse(approval.canResolve)
            XCTAssertEqual(approval.blockReason?.message, expected.message)
        }
        XCTAssertEqual(
            Set(ConsoleApprovalBlockReason.allCases.map(\.message)).count,
            ConsoleApprovalBlockReason.allCases.count
        )
    }

    func testAuthorizedAuthorityIsDecidableRegardlessOfRegistryName() {
        for authority in ["tony", "maui"] {
            let approval = Self.eligibleApproval(authority: authority, viewerAuthorized: true)
            XCTAssertNil(approval.blockReason)
            XCTAssertTrue(approval.canResolve)
        }
    }

    func testEndpointMismatchIsNotDecidable() {
        let approval = Self.eligibleApproval(
            authority: "maui",
            decisionEndpoint: "/api/v1/approvals/other-approval"
        )

        XCTAssertEqual(approval.blockReason, .endpointMismatch)
        XCTAssertFalse(approval.canResolve)
    }

    func testTicketIDResolvesFromTargetReferenceWhenLinkedIDsAbsent() {
        let approval = Self.eligibleApproval(linkedTicketIDs: [])

        XCTAssertEqual(approval.resolvedTicketID, "ticket-1")
        XCTAssertTrue(approval.canResolve)
    }

    func testConflictingTargetReferenceIsAmbiguous() {
        let approval = Self.eligibleApproval(
            targetReference: "ticket-9",
            linkedTicketIDs: ["ticket-1", "ticket-2"]
        )

        XCTAssertNil(approval.resolvedTicketID)
        XCTAssertEqual(approval.blockReason, .ticketUnresolved)
    }

    func testRejectWithEmptyReasonIsRefusedBeforeNetwork() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requestCount = 0
        TestURLProtocol.response = { _ in
            requestCount += 1
            return (500, Data())
        }
        defer { TestURLProtocol.response = nil }
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        do {
            _ = try await service.decideTicketApproval(
                approvalID: "approval-1",
                decisionEndpoint: "/api/v1/approvals/approval-1",
                decision: .rejected,
                reason: "   "
            )
            XCTFail("Empty rejection reason must be refused")
        } catch let error as ConsoleTicketApprovalError {
            XCTAssertEqual(error, .emptyRejectionReason)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(requestCount, 0)
    }

    func testSuccessfulApproveIssuesSinglePatchWithConsoleAttribution() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let lock = NSLock()
        var patchCount = 0
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/tickets/ticket-1/approvals/approval-1")
            lock.withLock { patchCount += 1 }
            let body = try TestURLProtocol.bodyData(for: request)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(object["status"] as? String, "approved")
            XCTAssertEqual(object["reason"] as? String, "Looks correct.")
            XCTAssertEqual(object["source"] as? String, "console.tickets.approval_resolution")
            XCTAssertEqual(object["lane"] as? String, "human_approval_resolution")
            let trace = try XCTUnwrap(object["trace_id"] as? String)
            XCTAssertTrue(trace.hasPrefix("console-approval-approved-"))
            XCTAssertFalse(trace.hasPrefix("pod-"))
            return (200, Data(#"{"approval_id":"approval-1","ticket_id":"ticket-1","status":"approved"}"#.utf8))
        }
        defer { TestURLProtocol.response = nil }
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        let result = try await service.decideTicketApproval(
            approvalID: "approval-1",
            decisionEndpoint: "/api/v1/tickets/ticket-1/approvals/approval-1",
            decision: .approved,
            reason: "Looks correct."
        )

        XCTAssertEqual(lock.withLock { patchCount }, 1)
        XCTAssertEqual(result.status, "approved")
    }

    func testDecisionFailureSurfacesAPIErrorMessage() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TestURLProtocol.response = { _ in
            (403, Data(#"{"detail":"Only the approval authority may decide this approval."}"#.utf8))
        }
        defer { TestURLProtocol.response = nil }
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        do {
            _ = try await service.decideTicketApproval(
                approvalID: "approval-1",
                decisionEndpoint: "/api/v1/tickets/ticket-1/approvals/approval-1",
                decision: .approved,
                reason: "Looks correct."
            )
            XCTFail("403 must throw")
        } catch let error as OrcaConsoleServiceError {
            guard case let .httpStatus(code, detail) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(code, 403)
            XCTAssertEqual(detail, "Only the approval authority may decide this approval.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFlatDecisionEndpointIsDecidable() {
        let approval = Self.flatBundleApproval()

        XCTAssertNil(approval.blockReason)
        XCTAssertTrue(approval.canResolve)
    }

    func testTicketScopedDecisionEndpointIsStillDecidable() {
        let approval = Self.eligibleApproval()

        XCTAssertNil(approval.blockReason)
        XCTAssertTrue(approval.canResolve)
    }

    func testEndpointWithDifferentApprovalIDIsMismatch() {
        let flat = Self.flatBundleApproval(
            authority: "maui",
            decisionEndpoint: "/api/v1/approvals/approval-other"
        )
        let scoped = Self.eligibleApproval(
            authority: "maui",
            decisionEndpoint: "/api/v1/tickets/ticket-1/approvals/approval-other"
        )

        XCTAssertEqual(flat.blockReason, .endpointMismatch)
        XCTAssertEqual(scoped.blockReason, .endpointMismatch)
        XCTAssertFalse(flat.canResolve)
        XCTAssertFalse(scoped.canResolve)
    }

    func testEndpointWithExtraSegmentsOrQueryStringIsMismatch() {
        let extraSegments = Self.flatBundleApproval(
            authority: "maui",
            decisionEndpoint: "/api/v1/approvals/approval-1/extra"
        )
        let queryString = Self.flatBundleApproval(
            authority: "maui",
            decisionEndpoint: "/api/v1/approvals/approval-1?decide=approve"
        )
        let prefixed = Self.flatBundleApproval(
            authority: "maui",
            decisionEndpoint: "https://other.example.com/api/v1/approvals/approval-1"
        )

        for approval in [extraSegments, queryString, prefixed] {
            XCTAssertEqual(approval.blockReason, .endpointMismatch)
            XCTAssertFalse(approval.canResolve)
        }
    }

    func testStalePendingApprovalIsDecidable() {
        let flat = Self.flatBundleApproval(stale: true)
        let scoped = Self.eligibleApproval(stale: true)

        XCTAssertNil(flat.blockReason)
        XCTAssertNil(scoped.blockReason)
        XCTAssertTrue(flat.canResolve)
        XCTAssertTrue(scoped.canResolve)
        XCTAssertTrue(flat.stale)
        XCTAssertTrue(scoped.stale)
    }

    func testFreshPendingApprovalIsDecidable() {
        let approval = Self.flatBundleApproval(stale: false)

        XCTAssertNil(approval.blockReason)
        XCTAssertTrue(approval.canResolve)
        XCTAssertFalse(approval.stale)
    }

    func testDecidedApprovalIsNotPendingWhetherStaleOrFresh() {
        for status in ["approved", "rejected"] {
            for stale in [false, true] {
                let approval = Self.flatBundleApproval(status: status, stale: stale)
                XCTAssertEqual(approval.blockReason, .notPending)
                XCTAssertFalse(approval.canResolve)
                XCTAssertEqual(approval.stale, stale)
            }
        }
    }

    func testNilDecisionEndpointReportsAuthorityMismatch() {
        let flat = Self.flatBundleApproval(authority: "maui", decisionEndpoint: nil)
        let scoped = Self.eligibleApproval(authority: "maui", decisionEndpoint: nil)

        XCTAssertEqual(flat.blockReason, .authorityMismatch("maui"))
        XCTAssertEqual(scoped.blockReason, .authorityMismatch("maui"))
        XCTAssertNotEqual(flat.blockReason, .endpointMismatch)
        XCTAssertTrue(flat.blockReason?.message.contains("maui") ?? false)
        XCTAssertFalse(flat.canResolve)
        XCTAssertFalse(scoped.canResolve)
    }

    func testAgentAuthorityApprovalShowsNoDecisionControl() {
        let approval = Self.flatBundleApproval(authority: "maui", viewerAuthorized: false)

        XCTAssertFalse(approval.showsDecisionControl)
        XCTAssertNil(approval.captainDecisionEndpoint)
        XCTAssertEqual(approval.blockReason, .authorityMismatch("maui"))
        XCTAssertEqual(approval.blockReason?.message, "This approval is maui's to decide.")
    }

    func testAgentAuthorityApprovalNeverRoutsToCaptainPath() {
        let approval = Self.flatBundleApproval(
            authority: "maui",
            decisionEndpoint: "/api/v1/approvals/approval-1",
            viewerAuthorized: true
        )

        XCTAssertNil(approval.captainDecisionEndpoint)
        XCTAssertFalse(approval.showsDecisionControl)
        XCTAssertFalse(approval.isCaptainAuthority)
    }

    func testCaptainApprovalIgnoresAgentComputedViewerFlags() {
        let approval = Self.flatBundleApproval(
            id: "f8ec2e96",
            authority: "tony",
            decisionEndpoint: "/api/v1/approvals/f8ec2e96",
            viewerAuthorized: false,
            selfApprovalProhibited: true,
            targetReference: "ticket-f8",
            linkedTicketIDs: ["ticket-f8"]
        )

        XCTAssertTrue(approval.isCaptainAuthority)
        XCTAssertNil(approval.blockReason)
        XCTAssertTrue(approval.canResolve)
        XCTAssertTrue(approval.showsDecisionControl)
        XCTAssertEqual(
            approval.captainDecisionEndpoint,
            "/api/v1/tickets/ticket-f8/approvals/f8ec2e96"
        )
    }

    func testCaptainPathIsComputedLocallyIgnoringBundleEndpoint() {
        let approval = Self.eligibleApproval(
            id: "approval-captain",
            authority: "tony",
            decisionEndpoint: "https://other.example.com/api/v1/approvals/approval-captain",
            viewerAuthorized: false,
            selfApprovalProhibited: true
        )

        XCTAssertEqual(
            approval.captainDecisionEndpoint,
            "/api/v1/tickets/ticket-1/approvals/approval-captain"
        )
        XCTAssertTrue(approval.showsDecisionControl)
    }

    func testCaptainApprovalWithoutResolvableTicketIsUnresolved() {
        let approval = Self.eligibleApproval(
            authority: "tony",
            viewerAuthorized: false,
            selfApprovalProhibited: true,
            targetType: nil,
            targetReference: nil,
            linkedTicketIDs: []
        )

        XCTAssertEqual(approval.blockReason, .ticketUnresolved)
        XCTAssertFalse(approval.canResolve)
        XCTAssertFalse(approval.showsDecisionControl)
        XCTAssertNil(approval.captainDecisionEndpoint)
    }

    func testCaptainApprovalNotPendingShowsNoControl() {
        let approval = Self.eligibleApproval(
            authority: "tony",
            status: "approved",
            viewerAuthorized: false,
            selfApprovalProhibited: true
        )

        XCTAssertEqual(approval.blockReason, .notPending)
        XCTAssertFalse(approval.showsDecisionControl)
    }

    func testCaptainApprovalHeldResolutionShowsNoControl() {
        let approval = Self.eligibleApproval(
            authority: "tony",
            viewerAuthorized: false,
            resolutionEnabled: false,
            selfApprovalProhibited: true
        )

        XCTAssertEqual(approval.blockReason, .resolutionHeld)
        XCTAssertFalse(approval.showsDecisionControl)
    }

    func testSelectingDifferentRecordClearsApprovalError() {
        let model = makeModel()
        model.approvalError = "ORCA returned HTTP 401."

        model.selectRecord("record-b")

        XCTAssertNil(model.approvalError)
    }

    func testTogglingMetricFilterClearsApprovalError() async throws {
        let snapshot = try await workSnapshot()
        let model = makeModel()
        model.sectionSnapshots[.work] = snapshot
        model.selectSection(.work, refresh: false)
        model.selectWorkMode(.agentWork)
        model.approvalError = "ORCA returned HTTP 401."

        model.toggleWorkMetricFilter("approvals")
        XCTAssertNil(model.approvalError)

        model.approvalError = "ORCA returned HTTP 401."
        model.toggleWorkMetricFilter("approvals")

        XCTAssertNil(model.approvalError)
    }

    func testApprovingFlatFormRecordPatchesFlatEndpoint() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let lock = NSLock()
        var patchCount = 0
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/approvals/approval-1")
            XCTAssertNil(request.url?.query)
            lock.withLock { patchCount += 1 }
            let body = try TestURLProtocol.bodyData(for: request)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(object["status"] as? String, "approved")
            XCTAssertEqual(object["source"] as? String, "console.tickets.approval_resolution")
            XCTAssertEqual(object["lane"] as? String, "human_approval_resolution")
            let trace = try XCTUnwrap(object["trace_id"] as? String)
            XCTAssertTrue(trace.hasPrefix("console-approval-approved-"))
            XCTAssertFalse(trace.hasPrefix("pod-"))
            return (200, Data(#"{"approval_id":"approval-1","status":"approved"}"#.utf8))
        }
        defer { TestURLProtocol.response = nil }
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        let result = try await service.decideTicketApproval(
            approvalID: "approval-1",
            decisionEndpoint: "/api/v1/approvals/approval-1",
            decision: .approved,
            reason: "Looks correct."
        )

        XCTAssertEqual(lock.withLock { patchCount }, 1)
        XCTAssertEqual(result.status, "approved")
    }

    func testApprovingTicketScopedRecordPatchesTicketEndpoint() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let lock = NSLock()
        var patchCount = 0
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/tickets/ticket-1/approvals/approval-1")
            lock.withLock { patchCount += 1 }
            return (200, Data(#"{"approval_id":"approval-1","ticket_id":"ticket-1","status":"approved"}"#.utf8))
        }
        defer { TestURLProtocol.response = nil }
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        let result = try await service.decideTicketApproval(
            approvalID: "approval-1",
            decisionEndpoint: "/api/v1/tickets/ticket-1/approvals/approval-1",
            decision: .approved,
            reason: "Looks correct."
        )

        XCTAssertEqual(lock.withLock { patchCount }, 1)
        XCTAssertEqual(result.status, "approved")
    }

    private func makeModel() -> OrcaMacModel {
        OrcaMacModel(
            tokenStore: TestRuntimeTokenStore(token: nil),
            defaults: UserDefaults(suiteName: "OrcaMacModelTests.\(UUID().uuidString)")!
        )
    }

    private func workSnapshot() async throws -> ConsoleSectionSnapshot {
        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789"
        )
        return try await service.snapshot(for: .work, workControl: Self.workControlBundle)
    }

    private static func eligibleApproval(
        id: String = "approval-1",
        authority: String = "tony",
        status: String = "pending",
        stale: Bool = false,
        decisionEndpoint: String? = "/api/v1/tickets/ticket-1/approvals/approval-1",
        viewerAuthorized: Bool = true,
        resolutionEnabled: Bool = true,
        selfApprovalProhibited: Bool = false,
        targetType: String? = "ticket",
        targetReference: String? = "ticket-1",
        linkedTicketIDs: [String] = ["ticket-1"]
    ) -> ConsoleApprovalRecord {
        ConsoleApprovalRecord(
            id: id,
            authority: authority,
            status: status,
            stale: stale,
            decisionEndpoint: decisionEndpoint,
            viewerAuthorized: viewerAuthorized,
            resolutionEnabled: resolutionEnabled,
            selfApprovalProhibited: selfApprovalProhibited,
            targetType: targetType,
            targetReference: targetReference,
            linkedTicketIDs: linkedTicketIDs
        )
    }

    private static func flatBundleApproval(
        id: String = "approval-1",
        authority: String = "tony",
        status: String = "pending",
        stale: Bool = false,
        decisionEndpoint: String? = "/api/v1/approvals/approval-1",
        viewerAuthorized: Bool = true,
        resolutionEnabled: Bool = true,
        selfApprovalProhibited: Bool = false,
        targetType: String? = "ticket",
        targetReference: String? = "ticket-1",
        linkedTicketIDs: [String] = ["ticket-1"]
    ) -> ConsoleApprovalRecord {
        ConsoleApprovalRecord(
            id: id,
            authority: authority,
            status: status,
            stale: stale,
            decisionEndpoint: decisionEndpoint,
            viewerAuthorized: viewerAuthorized,
            resolutionEnabled: resolutionEnabled,
            selfApprovalProhibited: selfApprovalProhibited,
            targetType: targetType,
            targetReference: targetReference,
            linkedTicketIDs: linkedTicketIDs
        )
    }

    private static let workbenchHostJSON = #"{"host_id":"shaka-mac","capability_id":"engineering.workspace","state":"attested","ready":true,"reason":"fresh","observed_at":"2026-08-18T04:00:00Z","expires_at":null,"evidence_refs":["attestation-evidence://shaka-mac/canary"],"policy_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#

    // Fixture mirrors SPEC-WAITING-ON-TONY's WaitingOnCaptainResponse and
    // WaitingOnCaptainItem shape exactly, including null card-context fields.
    private static let waitingOnCaptainFixtureJSON = #"""
    {
      "generated_at": "2026-09-19T12:00:00Z",
      "source": "orca.waiting-on-captain.v1",
      "counts": {
        "approvals": 1,
        "tickets": 1,
        "delegation_requests": 0,
        "stale": 1
      },
      "items": [
        {
          "id": "ticket:ticket-1",
          "kind": "ticket",
          "title": "Choose the release window",
          "summary": "Tony to decide the release window.",
          "authority": "tony",
          "agent_slug": "maui",
          "occurred_at": "2026-09-18T05:00:00Z",
          "age_hours": 31.0,
          "stale_after_hours": null,
          "is_stale": true,
          "gate_severity": 3,
          "endpoint": "/api/v1/tickets/ticket-1",
          "decision_endpoint": null,
          "approval_id": null,
          "ticket_id": "ticket-1",
          "ticket_title": "Choose the release window",
          "ticket_status": "blocked",
          "approval_gate": null,
          "reason": "Captain input is required.",
          "requested_by": "maui"
        },
        {
          "id": "approval:approval-1",
          "kind": "approval",
          "title": "Approve governed release",
          "summary": "Release approval is ready for Captain review.",
          "authority": "tony",
          "agent_slug": "coral",
          "occurred_at": "2026-09-19T08:00:00Z",
          "age_hours": 4.0,
          "stale_after_hours": 24,
          "is_stale": false,
          "gate_severity": 2,
          "endpoint": "/api/v1/approvals/approval-1",
          "decision_endpoint": "/api/v1/tickets/ticket-2/approvals/approval-1",
          "approval_id": "approval-1",
          "ticket_id": "ticket-2",
          "ticket_title": "Ship Console release",
          "ticket_status": "in_review",
          "approval_gate": "release",
          "reason": "Governed release requires Captain authority.",
          "requested_by": "coral"
        }
      ]
    }
    """#

    private static let workbenchContractJSON = "{\"schema\":\"orca.engineering-workbench.v1\",\"enabled\":true,\"mode\":\"active\",\"host\":\(workbenchHostJSON),\"worker_lane\":\"engineering-host\",\"policy_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"roots\":[{\"id\":\"pod-client\",\"label\":\"Pod and Console\",\"description\":\"Native source\",\"access\":\"read_test\",\"source_mutation\":false}],\"actions\":[{\"id\":\"git.status\",\"label\":\"Git Status\",\"kind\":\"diff\",\"requires_approval\":false,\"mutates_source\":false,\"default_timeout_seconds\":30,\"allowed_root_ids\":[\"pod-client\"],\"available\":true,\"blocked_reasons\":[]}],\"lifecycle\":[\"request.persisted\"],\"guarantees\":[\"AgentRun first\"]}"

    private static let workbenchOperationJSON = #"{"id":"run-c9","ticket_id":"ticket-c9","parent_run_id":null,"trace_id":"engineering-test","status":"queued","action_id":"git.status","action_kind":"diff","root_id":"pod-client","relative_path":".","worker_lane":"engineering-host","agent_slug":"coral","requires_approval":false,"approval_id":null,"approval_status":null,"idempotency_key":"workbench-test-1","outcome":null,"evidence":"Queued","artifacts":{"engineering_request":{"root_id":"pod-client"}},"error":null,"created_at":"2026-08-18T04:00:00Z","updated_at":"2026-08-18T04:00:00Z","started_at":null,"completed_at":null}"#

    private static let staleWorkControlBundle: Components.Schemas.ChatRuntimeWorkControlBundleRead = {
        var bundle = workControlBundle
        let staleApproval = Components.Schemas.ChatRuntimeWorkApprovalRead(
            actionType: "sign_standard",
            approvalId: "approval-release",
            authority: "tony",
            authorizationReason: "Aloha is the registered authority.",
            createdAt: Date(timeIntervalSince1970: 1_786_000_000),
            decisionEndpoint: "/api/v1/approvals/approval-release",
            linkedTaskIds: [],
            linkedTicketIds: ["ticket-runtime"],
            noCascade: false,
            resolutionEnabled: true,
            selfApprovalProhibited: false,
            stale: true,
            staleAfterHours: 24,
            status: .pending,
            targetRef: "ticket-runtime",
            targetType: "ticket",
            viewerAuthorized: true
        )
        bundle.approvalQueue = [staleApproval]
        bundle.approvalInventory = [staleApproval]
        return bundle
    }()

    private static let workControlBundle: Components.Schemas.ChatRuntimeWorkControlBundleRead = {
        let item = Components.Schemas.ChatRuntimeWorkItemRead(
            approvalState: "not_required",
            bucketReason: "Current bounded work.",
            executionEligible: true,
            priority: "high",
            safeTitle: "Prove Work Control",
            sourceRefs: .init(),
            stale: false,
            status: "open",
            updatedAt: Date(timeIntervalSince1970: 1_787_000_000),
            workBucket: .current,
            workId: "ticket-runtime",
            workKind: .ticket
        )
        let approval = Components.Schemas.ChatRuntimeWorkApprovalRead(
            actionType: "sign_standard",
            approvalId: "approval-release",
            authority: "aloha",
            authorizationReason: "Aloha is the registered authority.",
            createdAt: Date(timeIntervalSince1970: 1_787_000_000),
            decisionEndpoint: "/api/v1/approvals/approval-release",
            linkedTaskIds: [],
            linkedTicketIds: ["ticket-runtime"],
            noCascade: false,
            resolutionEnabled: true,
            selfApprovalProhibited: false,
            stale: false,
            staleAfterHours: 72,
            status: .pending,
            targetRef: "ticket-runtime",
            targetType: "ticket",
            viewerAuthorized: true
        )
        let attentionApproval = Components.Schemas.ChatRuntimeWorkApprovalRead(
            actionType: "credential_rotation",
            approvalId: "approval-credential-rotation",
            authority: "tony",
            authorizationReason: "Credential rotation belongs to the signed-in human.",
            createdAt: Date(timeIntervalSince1970: 1_787_000_100),
            decisionEndpoint: "/api/v1/approvals/approval-credential-rotation",
            linkedTaskIds: [],
            linkedTicketIds: ["ticket-runtime"],
            noCascade: false,
            reason: "Rotate the deploy signing key before expiry.",
            requestedBy: "maui",
            resolutionEnabled: true,
            selfApprovalProhibited: false,
            stale: false,
            staleAfterHours: 72,
            status: .pending,
            targetRef: "ticket-runtime",
            targetType: "ticket",
            ticketStatus: "in_review",
            ticketTitle: "Rotate Deploy Signing Key",
            viewerAuthorized: true
        )
        let counts = Components.Schemas.ChatRuntimeWorkControlCountsRead(
            activeWorkerRuns: 0,
            approvalInventory: 1,
            approvalQueue: 1,
            assignedWork: 1,
            blockingOthers: 1,
            fishBlocked: 0,
            fishProducing: 0,
            historicalWork: 0,
            plannerItems: 0,
            projectTasks: 0,
            protectedWork: 0,
            readyNow: 1,
            researchActiveRequests: 0,
            researchAwaitingReview: 0,
            staleWork: 0,
            toolsDeclared: 1,
            waitingOnMe: 1,
            waitingOnOthers: 0,
            workerReviewRuns: 0
        )
        return .init(
            agentId: "agent-coral",
            agentKey: "coral",
            approvalInventory: [approval, attentionApproval],
            approvalQueue: [approval],
            assignedWork: [item],
            authority: .orca,
            bundleSha256: String(repeating: "d", count: 64),
            configurationSha256: String(repeating: "a", count: 64),
            contractVersion: .orca_workControlBundle_v1,
            generatedAt: Date(timeIntervalSince1970: 1_787_000_000),
            historicalWork: [],
            mode: .readOnly,
            protectedWork: [],
            readyNow: [item],
            resources: .init(counts: counts),
            runtimeManifestRevision: "2026-08-21.1",
            sourceContract: .orca_agentWorkbench_v1,
            waitingOnOthers: []
        )
    }()

    // MARK: - SPEC-TICKET-SCOPED-CHAT AC13

    func testTicketConversationKeysByTicketAndKeepsGlobalState() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/tickets/ticket-7/chat-thread")
            return (200, Data(#"""
                {"ticket_id":"ticket-7","channel_id":"channel-ticket-7","owner_agent_slug":"maui","created":true,"messages_endpoint":"/api/v1/chat/channels/channel-ticket-7/messages"}
                """#.utf8))
        }
        defer { TestURLProtocol.response = nil }
        let consoleService = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        let model = makeModel()
        model.injectServicesForTesting(runtime: nil, console: consoleService)
        model.connectionState = .ready
        model.selectedAgentID = "maui"
        model.conversations["maui"] = ConversationState(
            conversationID: "direct-channel-maui",
            messages: [TranscriptMessage(
                id: "m1", role: .user, content: "global",
                createdAt: Date(), deliveryState: .persisted, retryIdentity: nil
            )]
        )

        await model.openTicketChat(ticketID: "ticket-7", ownerSlug: "maui", title: "Rotate keys")

        let context = try XCTUnwrap(model.activeTicketChat)
        XCTAssertEqual(context.conversationKey, "ticket:ticket-7")
        XCTAssertEqual(context.ownerSlug, "maui")
        XCTAssertEqual(context.channelID, "channel-ticket-7")
        XCTAssertEqual(model.selectedSection, .conversations)
        XCTAssertEqual(
            model.conversations["ticket:ticket-7"]?.conversationID,
            "channel-ticket-7"
        )
        XCTAssertEqual(
            model.conversations["maui"]?.conversationID,
            "direct-channel-maui",
            "global direct conversation must be untouched"
        )
        XCTAssertEqual(model.selectedConversation.conversationID, "channel-ticket-7")

        model.closeTicketChat()
        XCTAssertNil(model.activeTicketChat)
        XCTAssertEqual(model.selectedConversation.conversationID, "direct-channel-maui")
    }

    func testTicketChatWithoutOwnerMapsToAssignOwnerMessage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TestURLProtocol.response = { _ in
            (409, Data(#"{"detail":"ticket_has_no_owner"}"#.utf8))
        }
        defer { TestURLProtocol.response = nil }
        let consoleService = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        let model = makeModel()
        model.injectServicesForTesting(runtime: nil, console: consoleService)
        model.connectionState = .ready

        await model.openTicketChat(ticketID: "ticket-8", ownerSlug: nil, title: "Unowned")

        XCTAssertNil(model.activeTicketChat)
        XCTAssertEqual(model.presentedError, "Assign an owner first")
        XCTAssertFalse(model.conversations.keys.contains("ticket:ticket-8"))
    }

    func testTicketScopedTurnPayloadCarriesScopeTicketAndChannel() async throws {
        let stub = StubRuntimeService()
        let model = makeModel()
        model.injectServicesForTesting(runtime: stub, console: nil)
        model.connectionState = .ready
        let context = OrcaMacModel.TicketChatContext(
            ticketID: "ticket-9",
            ownerSlug: "coral",
            title: "Deploy",
            channelID: "channel-ticket-9",
            returnSection: .work,
            returnRecordID: nil,
            returnWorkbenchTicketID: nil
        )
        model.activeTicketChat = context
        model.conversations["ticket:ticket-9"] = ConversationState(conversationID: "channel-ticket-9")
        model.draft = "Ship it"

        await model.sendDraft()

        let sent = await stub.lastRequest
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(request.agentSlug, "coral")
        XCTAssertEqual(request.threadScope, "ticket")
        XCTAssertEqual(request.activeTicketID, "ticket-9")
        XCTAssertEqual(request.conversationID, "channel-ticket-9")
        XCTAssertEqual(
            model.conversations["ticket:ticket-9"]?.messages.last?.deliveryState,
            .persisted
        )
        XCTAssertNil(model.conversations["coral"], "no global conversation state created")
    }

    func testDirectTurnDefaultsToDirectScopeAndStoredConversation() async throws {
        let stub = StubRuntimeService()
        let model = makeModel()
        model.injectServicesForTesting(runtime: stub, console: nil)
        model.connectionState = .ready
        model.activateConversationScope(origin: "http://127.0.0.1:8000", organizationID: "test-organization")
        model.selectedAgentID = "coral"
        model.conversations["coral"] = ConversationState(conversationID: "direct-channel-coral")
        model.draft = "Hello"

        await model.sendDraft()

        let sent = await stub.lastRequest
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(request.threadScope, "direct")
        XCTAssertNil(request.activeTicketID)
        XCTAssertEqual(request.conversationID, "direct-channel-coral")
        XCTAssertEqual(model.conversations["coral"]?.conversationID, "direct-channel-coral")
        XCTAssertFalse(model.conversations.keys.contains { $0.hasPrefix("ticket:") })
    }
}

private actor StubRuntimeService: OrcaRuntimeServing {
    var lastRequest: OrcaRuntimeDirectTurnRequest?

    func verifyCompatibility() async throws -> OrcaRuntimeCompatibility {
        try OrcaRuntimeCompatibility(contractVersion: "v1", schemaSHA256: String(repeating: "a", count: 64))
    }
    func agentPacks() async throws -> Components.Schemas.ChatRuntimeAgentPackBundleRead {
        throw OrcaRuntimeClientError.invalidResponse("unused")
    }
    func capabilities(agentKey: String) async throws -> Components.Schemas.ChatRuntimeCapabilityBundleRead {
        throw OrcaRuntimeClientError.invalidResponse("unused")
    }
    func workControl(agentKey: String) async throws -> Components.Schemas.ChatRuntimeWorkControlBundleRead {
        throw OrcaRuntimeClientError.invalidResponse("unused")
    }
    func providerControl() async throws -> Components.Schemas.ChatRuntimeProviderControlBundleRead {
        throw OrcaRuntimeClientError.invalidResponse("unused")
    }
    func runtimeTurn(turnID: String) async throws -> Components.Schemas.ChatRuntimeTurnRead {
        throw OrcaRuntimeClientError.httpStatus(404)
    }
    func conversationMemory(conversationID: String) async throws -> Components.Schemas.ConversationMemoryRead {
        throw OrcaRuntimeClientError.invalidResponse("unused")
    }
    func proposeConversationMemory(
        conversationID: String,
        proposal: Components.Schemas.ConversationMemoryProposalCreate
    ) async throws -> Components.Schemas.ConversationMemoryProposalRead {
        throw OrcaRuntimeClientError.invalidResponse("unused")
    }
    func applyConversationMemoryProposal(
        conversationID: String,
        proposalID: String,
        reason: String?
    ) async throws -> Components.Schemas.ConversationMemoryRead {
        throw OrcaRuntimeClientError.invalidResponse("unused")
    }
    func send(_ request: OrcaRuntimeDirectTurnRequest) async throws -> OrcaRuntimeDirectTurnResponse {
        lastRequest = request
        return OrcaRuntimeDirectTurnResponse(
            conversationID: request.conversationID ?? "resolved-channel",
            userMessageID: "msg-user-1",
            assistantMessageID: "msg-assistant-1",
            content: "",
            agentSlug: request.agentSlug,
            traceID: request.traceID,
            source: "console",
            lane: "agent_inbox",
            deliveryMode: nil,
            provenance: nil,
            responseState: nil,
            provider: nil,
            model: nil,
            tier: nil,
            tokenCount: nil,
            triageID: nil,
            computeRunID: nil
        )
    }
    func messages(conversationID: String, offset: Int, limit: Int) async throws -> [OrcaRuntimeConversationMessage] {
        []
    }
}
