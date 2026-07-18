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
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "keychain-token")
        XCTAssertFalse(request.allHTTPHeaderFields?.values.contains("plaintext-token") ?? false)
    }

    func testPhysicalPodUsesCanonicalORCAMiniBackend() {
        XCTAssertEqual(AppConfig.canonicalBackendURL, "http://100.104.72.62:8000")
        XCTAssertNotEqual(AppConfig.canonicalBackendURL, "http://100.76.196.40:8000")
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
        XCTAssertTrue(health.needsAttention)
        XCTAssertEqual(health.compactSummary, "Controller live · Codex awaiting proof · 4 arrivals")
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
