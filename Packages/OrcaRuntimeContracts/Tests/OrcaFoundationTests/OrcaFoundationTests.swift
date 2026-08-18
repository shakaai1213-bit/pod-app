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
            runtimeManifestRevision: "test"
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
