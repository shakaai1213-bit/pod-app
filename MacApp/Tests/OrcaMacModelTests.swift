import XCTest
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
            Set([.overview, .conversations, .work, .fund, .crew, .knowledge, .lab, .runtime, .maker])
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

    func testAgentRosterLoadsFromCanonicalManagementProjection() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TestURLProtocol.response = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/management/agents")
            return (200, Data(#"{"agents":[{"agent_name":"coral","display_name":"Coral","title":"Operations and surfaces"},{"agent_name":"reef","display_name":"Reef","title":"Runtime support"}]}"#.utf8))
        }
        defer { TestURLProtocol.response = nil }

        let service = OrcaConsoleService(
            serverURL: URL(string: "http://127.0.0.1:8000")!,
            tokenStore: TestRuntimeTokenStore(token: "console-token"),
            deviceID: "test-device-id-0123456789",
            session: session
        )

        let profiles = try await service.agentProfiles()
        XCTAssertEqual(profiles.map(\.id), ["coral", "reef"])
        XCTAssertEqual(profiles.first?.role, "Operations and surfaces")
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
}
