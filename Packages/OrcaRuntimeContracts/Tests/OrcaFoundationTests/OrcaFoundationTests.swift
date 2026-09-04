import OrcaAPI
import OrcaDomain
import OrcaRuntime
import OrcaRuntimeContracts
import XCTest

final class OrcaFoundationTests: XCTestCase {
    func testFallbackRosterHasExactlySevenStableAgents() {
        XCTAssertEqual(OrcaAgentProfile.fallbackRoster.count, 7)
        XCTAssertEqual(
            OrcaAgentProfile.ids,
            Set(["aloha", "maui", "shaka", "chief", "rooster", "coral", "reef"])
        )
        XCTAssertEqual(OrcaAgentProfile.known("CHIEF")?.lane, .protected)
    }

    func testSurfaceInventoryIsSharedAndFundIsProtected() {
        XCTAssertEqual(OrcaSurfaceSection.allCases.count, 10)
        XCTAssertTrue(OrcaSurfaceSection.allCases.contains(.workbench))
        XCTAssertTrue(OrcaSurfaceSection.fund.isProtected)
        XCTAssertFalse(OrcaSurfaceSection.work.isProtected)
    }

    func testBoardDirectoryAndPlanPreserveCanonicalIdentifiers() throws {
        let directory = try JSONDecoder().decode(
            OrcaBoardDirectory.self,
            from: Data(#"{"items":[{"id":"00000000-0000-4000-8000-000000000001","slug":"pod","name":"Pod","component":"Pod","description":"[product] Native clients","project_count":3,"active_count":2,"ticket_count":5}]}"#.utf8)
        )
        XCTAssertEqual(directory.items.map(\.slug), ["pod"])
        XCTAssertEqual(directory.items.first?.projectCount, 3)
        XCTAssertTrue(directory.items.first?.isProduct == true)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(
            OrcaBoardPlan.self,
            from: Data(#"{"computed_at":"2026-08-27T03:00:00Z","board_id":"00000000-0000-4000-8000-000000000001","board_name":"Pod","board_slug":"pod","selection_mode":"canonical","pins":[],"lanes":[{"key":"in_progress","title":"In Progress","cards":[]}],"counts":{"in_progress":0},"source_refs":["/api/v1/tickets"]}"#.utf8)
        )
        XCTAssertEqual(plan.boardId, directory.items.first?.id)
        XCTAssertEqual(plan.lanes.map(\.key), ["in_progress"])
        XCTAssertEqual(plan.sourceRefs, ["/api/v1/tickets"])
    }

    func testEndpointPolicyApprovesOnlyCanonicalOrExplicitLoopback() {
        XCTAssertNotNil(OrcaEndpointPolicy.normalizedEndpoint("100.104.72.62:8000/"))
        XCTAssertNil(OrcaEndpointPolicy.normalizedEndpoint(
            "http://127.0.0.1:8000",
            allowLoopback: false
        ))
        XCTAssertNotNil(OrcaEndpointPolicy.normalizedEndpoint(
            "http://127.0.0.1:8000",
            allowLoopback: true
        ))
        XCTAssertNil(OrcaEndpointPolicy.normalizedEndpoint("https://untrusted.example"))
        XCTAssertNil(OrcaEndpointPolicy.normalizedEndpoint("file:///tmp/orca"))
    }

    func testConversationMergeDeduplicatesCanonicalMessagesAndPreservesPending() {
        let start = Date(timeIntervalSince1970: 1_000)
        var state = OrcaConversationState()
        state.mergeCanonical([message("m1", .user, start)])
        state.appendPending(id: "pending", content: "Next", at: start.addingTimeInterval(2))
        state.mergeCanonical([
            message("m1", .user, start),
            message("m2", .agent, start.addingTimeInterval(1)),
        ])
        XCTAssertEqual(state.messages.map(\.id), ["m1", "m2", "pending"])
    }

    func testRuntimeProjectionRejectsIncompleteAgentPacks() {
        let bundle = Components.Schemas.ChatRuntimeAgentPackBundleRead(
            bundleSha256: String(repeating: "a", count: 64),
            packs: [],
            runtimeManifestRevision: "test",
            sourceSha256: .init(additionalProperties: [:])
        )
        XCTAssertThrowsError(try OrcaRuntimeProjection.profiles(from: bundle))
    }

    func testEngineeringWorkbenchContractDecodesExactPolicyAndAliases() throws {
        let payload = Data(
            #"{"schema":"orca.engineering-workbench.v1","enabled":true,"mode":"active","host":{"host_id":"shaka-mac","capability_id":"engineering.workspace","state":"attested","ready":true,"reason":"fresh","observed_at":"2026-08-18T04:00:00Z","expires_at":null,"evidence_refs":["attestation-evidence://shaka-mac/canary"],"policy_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"worker_lane":"engineering-host","policy_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","roots":[{"id":"pod-client","label":"Pod and Console","description":"Native source","access":"read_test","source_mutation":false}],"actions":[{"id":"git.status","label":"Git Status","kind":"diff","requires_approval":false,"mutates_source":false,"default_timeout_seconds":30,"allowed_root_ids":["pod-client"],"available":true,"blocked_reasons":[]}],"lifecycle":["request.persisted"],"guarantees":["AgentRun first"]}"#.utf8
        )

        let contract = try JSONDecoder().decode(
            OrcaEngineeringWorkbenchContract.self,
            from: payload
        )

        XCTAssertEqual(contract.host.hostID, "shaka-mac")
        XCTAssertEqual(contract.workerLane, "engineering-host")
        XCTAssertEqual(contract.roots.map(\.id), ["pod-client"])
        XCTAssertEqual(contract.actions.first?.allowedRootIDs, ["pod-client"])
        XCTAssertTrue(contract.host.ready)
    }

    private func message(
        _ id: String,
        _ role: OrcaTranscriptRole,
        _ date: Date
    ) -> OrcaTranscriptMessage {
        OrcaTranscriptMessage(
            id: id,
            role: role,
            content: id,
            createdAt: date,
            deliveryState: .persisted,
            retryIdentity: nil
        )
    }
}
