import Foundation
import Testing
@testable import OrcaRuntimeContracts

@Test func contractMetadataIsPinned() {
    #expect(OrcaRuntimeContract.version == "orca.chat-runtime.v1")
    #expect(OrcaRuntimeContract.schemaSHA256.count == 64)
}

@Test func generatedClientSupportsBothNativeSurfaces() {
    let client = OrcaRuntimeContract.makeClient(
        serverURL: URL(string: "https://orca.invalid")!
    )
    _ = client
}

@Test func generatedTypesDecodeCanonicalCompleteTurn() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "complete-turn",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let turn = try decoder.decode(
        Components.Schemas.ChatRuntimeTurnRead.self,
        from: Data(contentsOf: fixtureURL)
    )

    #expect(turn.state == .completed)
    #expect(turn.adapter?.providerId == "conformance-provider")
    #expect(turn.adapter?.hostId == "conformance-host")
    #expect(turn.runtimeSessionId == "50000000-0000-4000-8000-000000000001")
    #expect(turn.events?.map(\.sequence) == [0, 1, 2, 3, 4])
    #expect(turn.latestCursor == turn.events?.last?.cursor)
    #expect(turn.terminalOutcome?.state == .completed)
    #expect(turn.terminalOutcome?.errorCode == nil)
}
