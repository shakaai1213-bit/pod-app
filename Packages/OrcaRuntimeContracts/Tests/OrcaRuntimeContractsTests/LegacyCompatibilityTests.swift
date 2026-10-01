import CryptoKit
import Foundation
import Testing
@testable import OrcaRuntimeContracts

private let legacyDigest = "33cd117fe92dca4544c835ffb838eb1f7ce34be381c1c897fee1d4c4f94fbc12"
private func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}
private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func exactCompatibilityIdentities() throws {
    #expect(OrcaRuntimeContract.legacySchemas == [legacyDigest: "release-a-fa74b098"])
    #expect(try OrcaRuntimeCompatibility(contractVersion: OrcaRuntimeContract.version, schemaSHA256: OrcaRuntimeContract.schemaSHA256).mode == .canonical)
    #expect(try OrcaRuntimeCompatibility(contractVersion: OrcaRuntimeContract.version, schemaSHA256: legacyDigest).mode == .legacy("release-a-fa74b098"))
    for digest in ["40a298668534e87d47abc42279d4777334e1e2c9ae92dc6e291818a8a76cfbeb", "0" + legacyDigest.dropFirst(), ""] {
        #expect(throws: OrcaRuntimeClientError.incompatibleSchema(expected: OrcaRuntimeContract.schemaSHA256, actual: digest)) {
            try OrcaRuntimeCompatibility(contractVersion: OrcaRuntimeContract.version, schemaSHA256: digest)
        }
    }
    #expect(throws: OrcaRuntimeClientError.incompatibleContract(expected: OrcaRuntimeContract.version, actual: "v2")) {
        try OrcaRuntimeCompatibility(contractVersion: "v2", schemaSHA256: legacyDigest)
    }
}

@Test func releaseAProvenance() throws {
    let data = try fixtureData("release-a-openapi")
    #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == "31245d97941fe3c1773c977867433159e606a6b040e5bc4215c13b61ae414652")
    let legacy = try object(data)
    #expect(legacy["x-orca-schema-sha256"] as? String == legacyDigest)
    let live = try object(fixtureData("live-schema-bundle"))
    #expect(live["schema_sha256"] as? String == legacyDigest)
}

@Test func releaseAExactStructuralDelta() throws {
    let legacyData = try ProcessInfo.processInfo.environment["ORCA_TEST_LEGACY_OPENAPI"].map { try Data(contentsOf: URL(fileURLWithPath: $0)) } ?? fixtureData("release-a-openapi")
    let legacy = try object(legacyData)
    let defaultSource = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/OrcaRuntimeContracts/openapi.json")
    let source = ProcessInfo.processInfo.environment["ORCA_TEST_CURRENT_OPENAPI"].map { URL(fileURLWithPath: $0) } ?? defaultSource
    var current = try object(Data(contentsOf: source))
    #expect(current["x-orca-schema-sha256"] as? String == OrcaRuntimeContract.schemaSHA256)
    var components = try #require(current["components"] as? [String: Any])
    var schemas = try #require(components["schemas"] as? [String: Any])
    let oldSchemas = try #require((legacy["components"] as? [String: Any])?["schemas"] as? [String: Any])
    #expect(Set(schemas.keys) == Set(oldSchemas.keys).union(["TurnRoute"]))
    let changes = ["ChatMessageRead": ["terminal_kind"], "ChatRuntimeTerminalOutcomeRead": ["terminal_kind"], "ChatRuntimeTurnSubmissionRead": ["terminal_kind", "turn_route"], "DirectAgentChatMetadata": ["terminal_kind"], "ChatRuntimeTurnRead": ["turn_route"]]
    let terminal: [String: Any] = ["enum": ["held", "held_for_explicit_escalation", "route_unavailable", "provider_failure"], "title": "Terminal Kind", "type": "string"]
    for (name, fields) in changes {
        _ = try #require(oldSchemas[name])
        var schema = try #require(schemas[name] as? [String: Any])
        var properties = try #require(schema["properties"] as? [String: Any])
        for field in fields {
            #expect(!(schema["required"] as? [String] ?? []).contains(field))
            let added = try #require(properties.removeValue(forKey: field) as? [String: Any])
            let expected: [String: Any] = field == "terminal_kind" ? terminal : ["$ref": "#/components/schemas/TurnRoute"]
            #expect(NSDictionary(dictionary: added).isEqual(to: expected))
        }
        schema["properties"] = properties
        schemas[name] = schema
    }
    let route = try #require(schemas.removeValue(forKey: "TurnRoute") as? [String: Any])
    #expect(NSDictionary(dictionary: route).isEqual(to: ["enum": ["kimi_required", "held_for_explicit_escalation", "held", "frontier_required"], "title": "TurnRoute", "type": "string"]))
    components["schemas"] = schemas
    current["components"] = components
    current["x-orca-schema-sha256"] = legacyDigest
    // Full document equality catches paths, operations, requests, required lists,
    // removals and all other changes; missing schemas never become empty objects.
    #expect(NSDictionary(dictionary: current).isEqual(to: legacy))
}

@Test func releaseAResponsesDecodeWithoutOptionalFields() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let turn = try decoder.decode(Components.Schemas.ChatRuntimeTurnRead.self, from: fixtureData("ChatRuntimeTurnRead-release-a"))
    #expect(turn.turnRoute == nil)
    let submission = try decoder.decode(Components.Schemas.ChatRuntimeTurnSubmissionRead.self, from: fixtureData("ChatRuntimeTurnSubmissionRead-release-a"))
    #expect(submission.turnRoute == nil && submission.terminalKind == nil)
    let outcome = try decoder.decode(Components.Schemas.ChatRuntimeTerminalOutcomeRead.self, from: fixtureData("ChatRuntimeTerminalOutcomeRead-release-a"))
    #expect(outcome.terminalKind == nil)
    let message = try decoder.decode(Components.Schemas.ChatMessageRead.self, from: fixtureData("ChatMessageRead-release-a"))
    #expect(message.terminalKind == nil)
    let metadata = try decoder.decode(Components.Schemas.DirectAgentChatMetadata.self, from: fixtureData("DirectAgentChatMetadata-release-a"))
    #expect(metadata.terminalKind == nil)
}

@Test func currentResponsesRetainTerminalAndKimiRoute() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    func current(_ name: String, route: Bool = false, terminal: Bool = false) throws -> Data {
        var value = try object(fixtureData(name + "-release-a"))
        if route { value["turn_route"] = "kimi_required" }
        if terminal { value["terminal_kind"] = "held" }
        return try JSONSerialization.data(withJSONObject: value)
    }
    #expect(try decoder.decode(Components.Schemas.ChatRuntimeTurnRead.self, from: current("ChatRuntimeTurnRead", route: true)).turnRoute?.rawValue == "kimi_required")
    let submission = try decoder.decode(Components.Schemas.ChatRuntimeTurnSubmissionRead.self, from: current("ChatRuntimeTurnSubmissionRead", route: true, terminal: true))
    #expect(submission.turnRoute?.rawValue == "kimi_required" && submission.terminalKind == .held)
    #expect(try decoder.decode(Components.Schemas.ChatRuntimeTerminalOutcomeRead.self, from: current("ChatRuntimeTerminalOutcomeRead", terminal: true)).terminalKind == .held)
    #expect(try decoder.decode(Components.Schemas.ChatMessageRead.self, from: current("ChatMessageRead", terminal: true)).terminalKind == .held)
    #expect(try decoder.decode(Components.Schemas.DirectAgentChatMetadata.self, from: current("DirectAgentChatMetadata", terminal: true)).terminalKind == .held)
}

private final class MissingIdentityProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = request.url?.path.hasSuffix("contract") == true
            ? Data(#"{"transports":[],"resources":[],"adapter":{},"turn":{"progress_states":[],"terminal_states":[]},"invariants":[],"compatibility_routes":[],"contract_version":"orca.chat-runtime.v1"}"#.utf8)
            : Data(#"{"schema_sha256":"33cd117fe92dca4544c835ffb838eb1f7ce34be381c1c897fee1d4c4f94fbc12","schemas":{}}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func missingRuntimeIdentityStillFailsClosed() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MissingIdentityProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = OrcaRuntimeClient(serverURL: URL(string: "http://orca.invalid")!, tokenProvider: { nil }, session: session)
    do {
        _ = try await client.verifyCompatibility()
        Issue.record("Missing identity was accepted")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .missingContractIdentity)
    }
}

@Test func missingTerminalKindDoesNotInferAHoldFromLane() {
    let response = OrcaRuntimeDirectTurnResponse(
        conversationID: "conversation", userMessageID: "user", assistantMessageID: "reply",
        content: "reply", agentSlug: "coral", traceID: "trace", source: "runtime", lane: "held",
        deliveryMode: nil, provenance: nil, responseState: nil, provider: nil, model: nil,
        tier: nil, tokenCount: nil, triageID: nil, computeRunID: nil
    )
    #expect(response.terminalKind == nil)
    #expect(response.turnRoute == nil)
}
