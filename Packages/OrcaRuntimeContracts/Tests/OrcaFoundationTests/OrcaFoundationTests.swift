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
        XCTAssertEqual(OrcaSurfaceSection.allCases.count, 9)
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
