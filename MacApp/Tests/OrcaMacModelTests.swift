import XCTest
import OrcaAPI
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

    func loadCredential(for serverOrigin: String) -> RuntimeCredential? {
        credential?.serverOrigin == serverOrigin ? credential : nil
    }
    func storeCredential(_ credential: RuntimeCredential) { self.credential = credential }
    func deleteCredential(for serverOrigin: String) { credential = nil }
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

    func testConsoleJSONPreservesStructuredValues() throws {
        let value = try JSONDecoder().decode(
            ConsoleJSON.self,
            from: Data(#"{"ok":true,"count":7,"items":[{"title":"Coral"}]}"#.utf8)
        )

        XCTAssertEqual(value.objectValue?["ok"]?.displayValue, "Yes")
        XCTAssertEqual(value.objectValue?["count"]?.displayValue, "7")
        XCTAssertEqual(value.objectValue?["items"]?.displayValue, "1 items")
    }

    func testWorkSnapshotProjectsCanonicalBoardsProjectsApprovalsAndTickets() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer console-token")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Key"))
            XCTAssertFalse(request.value(forHTTPHeaderField: "X-ORCA-Device-ID")?.isEmpty ?? true)
            let payload: String
            switch request.url?.path {
            case "/api/v1/boards":
                payload = #"{"total":1,"items":[{"id":"board-pod","name":"Pod","status":"active"}]}"#
            case "/api/v1/projects", "/api/v1/projects/":
                payload = #"{"items":[{"id":"project-console","name":"ORCA Console","status":"active"}]}"#
            case "/api/v1/tickets":
                payload = #"[{"id":"ticket-runtime","title":"Promote Runtime API v1","flow_state":"ready"}]"#
            case "/api/v1/control-room/captain-inbox":
                payload = #"{"items":[{"id":"approval-release","kind":"approval","title":"Release review","status":"pending"}]}"#
            default:
                return (404, Data(#"{"detail":"not found"}"#.utf8))
            }
            return (200, Data(payload.utf8))
        }
        defer { TestURLProtocol.response = nil }

        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )
        let snapshot = try await service.snapshot(for: .work)

        XCTAssertEqual(snapshot.metrics.first(where: { $0.id == "boards" })?.value, "1")
        XCTAssertEqual(snapshot.metrics.first(where: { $0.id == "projects" })?.value, "1")
        XCTAssertEqual(snapshot.metrics.first(where: { $0.id == "approvals" })?.value, "1")
        XCTAssertEqual(Set(snapshot.records.map(\.group)), Set(["Boards", "Projects", "Approvals", "Tickets"]))
        XCTAssertEqual(
            Set(snapshot.records.map(\.title)),
            Set(["Pod", "ORCA Console", "Release review", "Promote Runtime API v1"])
        )
        XCTAssertEqual(
            Set(snapshot.sources),
            Set(["/api/v1/boards", "/api/v1/projects/", "/api/v1/tickets", "/api/v1/control-room/captain-inbox"])
        )
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

    func testWorkbenchServiceUsesTypedTicketBoundRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let operation = Self.workbenchOperationJSON
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer console-token")
            XCTAssertFalse(request.value(forHTTPHeaderField: "X-ORCA-Device-ID")?.isEmpty ?? true)
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/tickets"):
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

        let tickets = try await service.workbenchTickets()
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

    private static let workbenchHostJSON = #"{"host_id":"shaka-mac","capability_id":"engineering.workspace","state":"attested","ready":true,"reason":"fresh","observed_at":"2026-08-18T04:00:00Z","expires_at":null,"evidence_refs":["attestation-evidence://shaka-mac/canary"],"policy_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#

    private static let workbenchContractJSON = "{\"schema\":\"orca.engineering-workbench.v1\",\"enabled\":true,\"mode\":\"active\",\"host\":\(workbenchHostJSON),\"worker_lane\":\"engineering-host\",\"policy_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"roots\":[{\"id\":\"pod-client\",\"label\":\"Pod and Console\",\"description\":\"Native source\",\"access\":\"read_test\",\"source_mutation\":false}],\"actions\":[{\"id\":\"git.status\",\"label\":\"Git Status\",\"kind\":\"diff\",\"requires_approval\":false,\"mutates_source\":false,\"default_timeout_seconds\":30,\"allowed_root_ids\":[\"pod-client\"],\"available\":true,\"blocked_reasons\":[]}],\"lifecycle\":[\"request.persisted\"],\"guarantees\":[\"AgentRun first\"]}"

    private static let workbenchOperationJSON = #"{"id":"run-c9","ticket_id":"ticket-c9","parent_run_id":null,"trace_id":"engineering-test","status":"queued","action_id":"git.status","action_kind":"diff","root_id":"pod-client","relative_path":".","worker_lane":"engineering-host","agent_slug":"coral","requires_approval":false,"approval_id":null,"approval_status":null,"idempotency_key":"workbench-test-1","outcome":null,"evidence":"Queued","artifacts":{"engineering_request":{"root_id":"pod-client"}},"error":null,"created_at":"2026-08-18T04:00:00Z","updated_at":"2026-08-18T04:00:00Z","started_at":null,"completed_at":null}"#
}
