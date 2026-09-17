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
            Set([.overview, .conversations, .work, .workbench, .fund, .crew, .knowledge, .lab, .runtime, .maker])
        )
        XCTAssertTrue(ConsoleSection.fund.isProtected)
        XCTAssertFalse(ConsoleSection.work.isProtected)
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

    func testWorkSnapshotProjectsValidatedRuntimeWorkControl() async throws {
        let service = OrcaConsoleService(
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
        XCTAssertEqual(Set(snapshot.records.map(\.title)), Set(["Prove Work Control", "Sign Standard", "Credential Rotation"]))
        let approvalRecord = snapshot.records.first { $0.group == "Decision Queue" }
        XCTAssertEqual(approvalRecord?.status, "pending")
        XCTAssertEqual(approvalRecord?.approval?.status, "pending")
        XCTAssertEqual(approvalRecord?.approval?.stale, false)
        XCTAssertTrue(approvalRecord?.fields.contains { $0.label == "Staleness" && $0.value == "Fresh" } ?? false)
        let attentionRecord = try XCTUnwrap(snapshot.records.first { $0.group == "Approval Attention" })
        let attentionApproval = try XCTUnwrap(attentionRecord.approval)
        XCTAssertEqual(attentionApproval.id, "approval-credential-rotation")
        XCTAssertEqual(attentionApproval.authority, "tony")
        XCTAssertEqual(attentionApproval.status, "pending")
        XCTAssertNil(attentionApproval.blockReason)
        XCTAssertTrue(attentionApproval.canResolve)
        XCTAssertEqual(attentionApproval.decisionEndpoint, "/api/v1/approvals/approval-credential-rotation")
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
            (Self.eligibleApproval(authority: "tony", viewerAuthorized: false), .authorityMismatch("tony")),
            (Self.eligibleApproval(resolutionEnabled: false), .resolutionHeld),
            (Self.eligibleApproval(selfApprovalProhibited: true), .selfApprovalProhibited),
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
            decisionEndpoint: "/api/v1/approvals/approval-other"
        )
        let scoped = Self.eligibleApproval(
            decisionEndpoint: "/api/v1/tickets/ticket-1/approvals/approval-other"
        )

        XCTAssertEqual(flat.blockReason, .endpointMismatch)
        XCTAssertEqual(scoped.blockReason, .endpointMismatch)
        XCTAssertFalse(flat.canResolve)
        XCTAssertFalse(scoped.canResolve)
    }

    func testEndpointWithExtraSegmentsOrQueryStringIsMismatch() {
        let extraSegments = Self.flatBundleApproval(
            decisionEndpoint: "/api/v1/approvals/approval-1/extra"
        )
        let queryString = Self.flatBundleApproval(
            decisionEndpoint: "/api/v1/approvals/approval-1?decide=approve"
        )
        let prefixed = Self.flatBundleApproval(
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
            resolutionEnabled: true,
            selfApprovalProhibited: false,
            stale: false,
            staleAfterHours: 72,
            status: .pending,
            targetRef: "ticket-runtime",
            targetType: "ticket",
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
}
