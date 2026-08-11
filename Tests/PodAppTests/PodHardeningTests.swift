import Foundation
import XCTest
@testable import pod

final class PodHardeningTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "orca_auth_token")
        UserDefaults.standard.removeObject(forKey: "orca_agent_token")
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testAPIClientUsesKeychainProviderInsteadOfPlaintextDefaults() async throws {
        UserDefaults.standard.set("plaintext-token", forKey: "orca_auth_token")
        let client = makeClient(keychainToken: "keychain-token")

        let request = try await client.buildRequest(path: "/api/v1/agents")

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer keychain-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Key"))
        XCTAssertFalse(request.value(forHTTPHeaderField: "X-ORCA-Device-ID")?.isEmpty ?? true)
        XCTAssertFalse(request.allHTTPHeaderFields?.values.contains("plaintext-token") ?? false)
    }

    func testPhysicalPodUsesCanonicalORCAMiniBackend() {
        XCTAssertEqual(AppConfig.canonicalBackendURL, "http://100.104.72.62:8000")
        XCTAssertNotEqual(AppConfig.canonicalBackendURL, "http://100.76.196.40:8000")
    }

    func testPodChatHasOneUserFacingEntryInsideWork() throws {
        XCTAssertEqual(AppTab.chat.title, "Pod Chat")

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let appState = try String(
            contentsOf: sourceRoot.appendingPathComponent("App/AppState.swift"),
            encoding: .utf8
        )
        let contentView = try String(
            contentsOf: sourceRoot.appendingPathComponent("App/ContentView.swift"),
            encoding: .utf8
        )
        let dashboard = try String(
            contentsOf: sourceRoot.appendingPathComponent("Presentation/Features/Dashboard/DashboardView.swift"),
            encoding: .utf8
        )
        let chatPanel = try String(
            contentsOf: sourceRoot.appendingPathComponent("Presentation/Features/Dashboard/PodChatPanel.swift"),
            encoding: .utf8
        )
        let retiredShells = [
            "Presentation/Features/Sonar/SonarView.swift",
            "Presentation/Features/DirectChat/DirectChatView.swift",
            "Presentation/Features/Chat/ChatView.swift",
            "Presentation/Features/Chat/ChatViewModel.swift",
            "Presentation/Features/Chat/ComposeBar.swift",
            "Presentation/Features/Chat/MessageBubbleView.swift",
            "Presentation/Features/Chat/SpeechRecognizer.swift",
        ]

        XCTAssertTrue(appState.contains("case .chat: selectedTab = .work"))
        XCTAssertTrue(appState.contains("pendingDirectChatChannelId = channelId.uuidString"))
        XCTAssertTrue(contentView.contains("appState.selectedTab == .chat || appState.selectedTab == .work"))
        XCTAssertFalse(contentView.contains("SonarView(viewModel:"))
        XCTAssertTrue(contentView.contains("directChatViewModel.agent(forChannelId: channelId)"))
        XCTAssertTrue(dashboard.contains("appState.navigateTo(.work)"))
        XCTAssertTrue(chatPanel.contains("Text(\"POD CHAT\")"))
        XCTAssertTrue(chatPanel.contains("Label(\"Open Chat\""))
        XCTAssertFalse(chatPanel.contains("Open Playground"))
        for relativePath in retiredShells {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: sourceRoot.appendingPathComponent(relativePath).path
            ))
        }
    }

    func testUserFacingBackendClientsUseAppConfigInsteadOfLegacyShakaProxy() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let clientPaths = [
            "Core/Auth/AuthManager.swift",
            "Presentation/Features/Agents/AgentsViewModel.swift",
            "Presentation/Features/Agents/LogStreamView.swift",
            "Presentation/Shared/Components/SettingsView.swift",
        ]

        for clientPath in clientPaths {
            let source = try String(
                contentsOf: sourceRoot.appendingPathComponent(clientPath),
                encoding: .utf8
            )
            XCTAssertTrue(source.contains("AppConfig.backendURL"), clientPath)
            XCTAssertFalse(source.contains("http://100.76.196.40:8000"), clientPath)
        }
    }

    func testAPIClientPreservesStructuredServerErrorBody() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 422,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"detail":"Milestone dependency missing"}"#.utf8))
        }
        let client = makeClient(keychainToken: "keychain-token")

        do {
            let _: EmptyResponse = try await client.get(path: "/failure")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.code, 422)
            XCTAssertEqual(error.message, "Milestone dependency missing")
        }
    }

    func testStrictAgentRequestUsesKeychainAgentTokenOnly() async throws {
        UserDefaults.standard.set("plaintext-agent-token", forKey: "orca_agent_token")
        let client = makeClient(
            keychainToken: "keychain-bearer-token",
            keychainAgentToken: "keychain-agent-token"
        )

        let request = try await client.buildRequest(
            path: "/api/v1/agent/workbench",
            includeAgentToken: true
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Agent-Token"), "keychain-agent-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Key"))
        XCTAssertFalse(request.allHTTPHeaderFields?.values.contains("plaintext-agent-token") ?? false)
    }

    func testWorkbenchWritesAlwaysEncodeStableIdempotencyKeys() throws {
        let action = WorkbenchAgentActionRequest(action: "ticket_comment", ticketId: "ticket-1")
        let actionKey = try encodedString(action, key: "idempotency_key")
        XCTAssertTrue(actionKey.hasPrefix("pod-workbench-action-"))
        XCTAssertEqual(try encodedString(action, key: "idempotency_key"), actionKey)
        XCTAssertNotEqual(
            WorkbenchAgentActionRequest(action: "ticket_comment", ticketId: "ticket-1").idempotencyKey,
            action.idempotencyKey
        )

        let tool = WorkbenchToolRunRequest(toolId: "workbench.summarize_queue")
        let toolKey = try encodedString(tool, key: "idempotency_key")
        XCTAssertTrue(toolKey.hasPrefix("pod-workbench-tool-"))
        XCTAssertEqual(try encodedString(tool, key: "idempotency_key"), toolKey)
    }

    func testBoundedConcurrentMapNeverExceedsLimit() async {
        let probe = ConcurrencyProbe()
        let values = await boundedConcurrentMap(Array(0..<12), limit: 4) { value in
            await probe.begin()
            try? await Task.sleep(nanoseconds: 20_000_000)
            await probe.end()
            return value
        }

        XCTAssertEqual(Set(values), Set(0..<12))
        let peak = await probe.peak()
        XCTAssertEqual(peak, 4)
    }

    func testLoopAtlasDecodesLiveORCAPayloadShape() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"""
            {
              "computed_at":"2026-07-13T23:09:56.183641",
              "gauge":[{
                "key":"sense","title":"Sense","status":"green","value":832.0,
                "unit":"wake receipts/day","freshness_at":"2026-07-13T23:09:56.099562Z",
                "cause":"Wake and intake freshness","source_ref":"/api/v1/lab/velocity#wake_receipts_per_day",
                "drill_ref":"/api/v1/management/agents"
              }],
              "lanes":[{
                "key":"intake","title":"Intake","status":"green","count":75,
                "freshness_at":"2026-07-13T23:09:56.183641","cause":"Open canonical intake",
                "drill_refs":["/api/v1/tickets"]
              }],
              "captain_queue":[],
              "source_refs":["/api/v1/lab/velocity","/api/v1/tickets"]
            }
            """#
            return (response, Data(body.utf8))
        }
        let client = makeClient(keychainToken: "keychain-token")

        let atlas: LoopAtlasResponseDTO = try await client.get(path: "/api/v1/management/loop-atlas")

        XCTAssertEqual(atlas.gauge.map(\.key), ["sense"])
        XCTAssertEqual(atlas.lanes.map(\.key), ["intake"])
        XCTAssertTrue(atlas.captainQueue.isEmpty)
    }

    func testCaptainsDeskProtectedPointerDecodesWithoutFullTicketFields() throws {
        let payload = #"""
        {
          "id":"71a5f76b-87f4-4020-baa5-065e3107ad7e",
          "title":"CURRENT TOPICS",
          "type":"ticket",
          "protected":true,
          "pointer":"/api/v1/tickets/71a5f76b-87f4-4020-baa5-065e3107ad7e"
        }
        """#

        let dto = try JSONDecoder().decode(
            CaptainsDeskTicketPayload.self,
            from: Data(payload.utf8)
        )
        let ticket = CaptainsDeskTicket(dto)

        XCTAssertTrue(ticket.isProtected)
        XCTAssertNil(ticket.updatedAt)
        XCTAssertEqual(
            ticket.description,
            "Protected focus pointer. The current detail remains governed in ORCA."
        )
    }

    @MainActor
    func testLoopAtlasRetriesOneTransientServerFailure() async {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(#"{"detail":"Restarting"}"#.utf8))
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"""
            {
              "computed_at":"2026-07-27T01:44:39.890242",
              "gauge":[],
              "lanes":[],
              "captain_queue":[],
              "source_refs":["/api/v1/lab/velocity"]
            }
            """#
            return (response, Data(body.utf8))
        }

        let model = LoopAtlasViewModel(
            apiClient: makeClient(keychainToken: "keychain-token"),
            retryDelayNanoseconds: 0
        )
        await model.load(force: true)

        XCTAssertEqual(requestCount, 2)
        XCTAssertNotNil(model.response)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testLoopAtlasDoesNotShowUnavailableBeforeFirstLoad() {
        let model = LoopAtlasViewModel(
            apiClient: makeClient(keychainToken: "keychain-token"),
            retryDelayNanoseconds: 0
        )

        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.response)
        XCTAssertNil(model.errorMessage)
    }

    func testCentralAgentHealthDecodesRuntimeEvidence() throws {
        let payload = #"""
        {
          "generated_at":"2026-07-14T00:28:55.115402",
          "status":"needs_attention",
          "checks":{
            "controller_runtime":{"status":"ok","state":"active","active_lease_count":1,"agents":["coral"]},
            "codex_worker":{"status":"warning","state":"no_completed_run_evidence","completed_count":0,"stuck_count":0},
            "durable_arrival":{"status":"ok","state":"traffic_observed","messages_observed":4,"missing_count":0}
          }
        }
        """#

        let health = try JSONDecoder().decode(CentralAgentHealth.self, from: Data(payload.utf8))

        XCTAssertTrue(health.controllerIsLive)
        XCTAssertFalse(health.hasCompletedCodexProof)
        XCTAssertFalse(health.needsAttention)
        XCTAssertEqual(health.compactSummary, "Controller live · Codex awaiting proof · 4 arrivals")
    }

    func testAllNamedAgentChatsShareCanonicalLiveInboxRoute() {
        let expectedAgents = Set(["aloha", "maui", "shaka", "chief", "rooster", "coral", "reef"])

        XCTAssertEqual(Set(AgentInfo.team.map(\.id)), expectedAgents)
        for agent in AgentInfo.team {
            XCTAssertTrue(agent.isReachable, "\(agent.id) should be reachable from Pod")
            XCTAssertEqual(agent.defaultDeliveryMode, .liveInbox, "\(agent.id) should enter the shared lifecycle")
        }
    }

    func testPodChatUsesProviderNeutralRuntimeAndResumableDelivery() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let service = try String(
            contentsOf: sourceRoot.appendingPathComponent(
                "Presentation/Features/DirectChat/AgentChatService.swift"
            ),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: sourceRoot.appendingPathComponent(
                "Presentation/Features/DirectChat/DirectChatViewModel.swift"
            ),
            encoding: .utf8
        )
        let sse = try String(
            contentsOf: sourceRoot.appendingPathComponent("Data/Remote/SSEClient.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(service.contains("import OrcaRuntimeContracts"))
        XCTAssertTrue(service.contains("verifyCompatibility()"))
        XCTAssertTrue(service.contains("idempotencyKey: \"pod-chat-turn:"))
        XCTAssertTrue(service.contains("case .httpStatus(404), .httpStatus(405):"))
        XCTAssertFalse(service.contains("api.anthropic.com"))
        XCTAssertFalse(service.contains("systemPrompt"))
        XCTAssertTrue(viewModel.contains("sendMessage(reusingTraceID: message.traceId)"))
        XCTAssertTrue(viewModel.contains("afterEventID: lastLiveEventIDByChannel[channelId]"))
        XCTAssertTrue(sse.contains("forHTTPHeaderField: \"Last-Event-ID\""))
    }

    func testChatPresentationKeepsLifecyclePrimaryAndExceptionsVisible() {
        let completeSteps = [
            DirectChatProgressStep(id: "reply", title: "Reply", icon: "checkmark", state: .done)
        ]
        let activeSteps = [
            DirectChatProgressStep(id: "work", title: "Work", icon: "hammer", state: .current)
        ]

        XCTAssertFalse(DirectChatPresentationPolicy.showsRouteProgress(completeSteps))
        XCTAssertTrue(DirectChatPresentationPolicy.showsRouteProgress(activeSteps))
        XCTAssertFalse(
            DirectChatPresentationPolicy.showsAssistantStatus(
                deliveryState: "response_received",
                provenance: "live_inbox",
                isStreaming: false
            )
        )
        XCTAssertTrue(
            DirectChatPresentationPolicy.showsAssistantStatus(
                deliveryState: "waiting_for_live_agent",
                provenance: "live_inbox",
                isStreaming: false
            )
        )
        XCTAssertTrue(
            DirectChatPresentationPolicy.showsAssistantStatus(
                deliveryState: "response_received",
                provenance: "protected",
                isStreaming: false
            )
        )
        XCTAssertFalse(DirectChatPresentationPolicy.showsUserDeliveryChip("sent"))
        XCTAssertTrue(DirectChatPresentationPolicy.showsUserDeliveryChip("transport_failed"))
        XCTAssertFalse(DirectChatPresentationPolicy.showsLiveStatusBar("Live stream connected."))
        XCTAssertTrue(DirectChatPresentationPolicy.showsLiveStatusBar("Live stream unavailable; using refresh."))
    }

    func testNamedAgentProvenanceWinsOverSparkSubstrate() throws {
        let payload = #"""
        {
          "id":"message-1",
          "sender_agent_id":"coral-agent",
          "sender_name":"coral",
          "sender_type":"agent",
          "content":"POD_AUTHORITY_LIVE_OK",
          "message_type":"text",
          "delivery_mode":"agent_inbox",
          "provenance":"live_inbox",
          "provider":"spark",
          "model":"Qwen/Qwen3-8B",
          "response_state":"response_received",
          "created_at":"2026-07-14T00:48:32Z"
        }
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dto = try decoder.decode(DirectChatORCAMessageDTO.self, from: Data(payload.utf8))
        let roomMessage = SonarRoomMessage(dto: dto)

        XCTAssertEqual(dto.normalizedProvenance, DMResponseProvenance.liveInbox.rawValue)
        XCTAssertEqual(roomMessage.provenance, DMResponseProvenance.liveInbox.rawValue)
        XCTAssertEqual(roomMessage.statusLabel, "Coral replied")
        XCTAssertEqual(
            DMBubble.resolvedProvenance(
                explicit: dto.normalizedProvenance,
                deliveryMode: dto.deliveryMode,
                source: dto.source,
                lane: dto.lane,
                model: dto.attributionLabel
            ),
            .liveInbox
        )
    }

    func testShakaRuntimeIsActiveWhileLegacyShakaAgentRemainsArchived() {
        XCTAssertTrue(AgentRosterPolicy.isActiveOrSupport("shaka"))
        XCTAssertFalse(AgentRosterPolicy.isDormantOrArchived("shaka"))
        XCTAssertEqual(AgentRosterPolicy.defaultLane(for: "shaka"), .activeMain)

        XCTAssertFalse(AgentRosterPolicy.isActiveOrSupport("shaka-agent"))
        XCTAssertTrue(AgentRosterPolicy.isDormantOrArchived("shaka-agent"))
        XCTAssertEqual(AgentRosterPolicy.defaultLane(for: "shaka-agent"), .dormantArchive)
    }

    private func makeClient(
        keychainToken: String,
        keychainAgentToken: String? = nil
    ) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(
            baseURL: "https://pod-tests.invalid",
            session: URLSession(configuration: configuration),
            keychainTokenProvider: { keychainToken },
            keychainAgentTokenProvider: { keychainAgentToken }
        )
    }

    private func encodedString<T: Encodable>(_ value: T, key: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object[key] as? String)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor ConcurrencyProbe {
    private var active = 0
    private var maximum = 0

    func begin() {
        active += 1
        maximum = max(maximum, active)
    }

    func end() {
        active -= 1
    }

    func peak() -> Int { maximum }
}
