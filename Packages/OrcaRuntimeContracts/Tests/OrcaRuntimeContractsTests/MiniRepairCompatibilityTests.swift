import CryptoKit
import Foundation
import Testing
@testable import OrcaRuntimeContracts

private let repairDigest = "e2e4518bed018c52a3caf02f51f472fd6fcad37356311632ad173b437ddb82e7"
private func repairFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}
private func repairObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func miniRepairCompatibilityIsExactAndNamed() throws {
    #expect(try OrcaRuntimeCompatibility(contractVersion: OrcaRuntimeContract.version, schemaSHA256: repairDigest).mode == .legacy("mini-repair-a2f4d6eb"))
    for digest in ["0" + repairDigest.dropFirst(), String(repeating: "f", count: 64), ""] {
        #expect(throws: OrcaRuntimeClientError.incompatibleSchema(expected: OrcaRuntimeContract.schemaSHA256, actual: digest)) {
            try OrcaRuntimeCompatibility(contractVersion: OrcaRuntimeContract.version, schemaSHA256: digest)
        }
    }
    #expect(throws: OrcaRuntimeClientError.incompatibleContract(expected: OrcaRuntimeContract.version, actual: "v2")) {
        try OrcaRuntimeCompatibility(contractVersion: "v2", schemaSHA256: repairDigest)
    }
}

@Test func miniRepairExportProvenanceIsPinned() throws {
    let data = try repairFixture("mini-repair-a2f4d6eb-openapi")
    #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == "799c02629796f73e60b992c83719831a0224cc85a062b907343b436f52bc520f")
    #expect(try repairObject(data)["x-orca-schema-sha256"] as? String == repairDigest)
    let delta = try repairObject(repairFixture("mini-repair-a2f4d6eb-contract-delta"))
    #expect((delta["delta"] as? [[String: Any]])?.count == 6)
    #expect(delta["new_digest"] as? String == repairDigest)
}

@Test func miniRepairOnlyAddsOptionalMemoryPagination() throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/OrcaRuntimeContracts/openapi.json")
    let current = try repairObject(Data(contentsOf: source))
    var repair = try repairObject(repairFixture("mini-repair-a2f4d6eb-openapi"))
    var components = try #require(repair["components"] as? [String: Any])
    var schemas = try #require(components["schemas"] as? [String: Any])
    let cursor = try #require(schemas.removeValue(forKey: "ConversationMemoryPendingCursor") as? [String: Any])
    let expectedCursor: [String: Any] = [
        "properties": ["created_at": ["format": "date-time", "title": "Created At", "type": "string"], "id": ["format": "uuid", "title": "Id", "type": "string"]],
        "required": ["created_at", "id"], "title": "ConversationMemoryPendingCursor", "type": "object"
    ]
    #expect(NSDictionary(dictionary: cursor).isEqual(to: expectedCursor))
    var memory = try #require(schemas["ConversationMemoryRead"] as? [String: Any])
    var properties = try #require(memory["properties"] as? [String: Any])
    let expected: [String: [String: Any]] = [
        "pending_before": ["$ref": "#/components/schemas/ConversationMemoryPendingCursor"],
        "pending_proposals_total": ["title": "Pending Proposals Total", "type": "integer"],
        "pending_proposals_truncated": ["default": false, "title": "Pending Proposals Truncated", "type": "boolean"]
    ]
    for (name, value) in expected {
        #expect(!(memory["required"] as? [String] ?? []).contains(name))
        let actual = try #require(properties.removeValue(forKey: name) as? [String: Any])
        #expect(NSDictionary(dictionary: actual).isEqual(to: value))
    }
    memory["properties"] = properties
    schemas["ConversationMemoryRead"] = memory
    components["schemas"] = schemas
    repair["components"] = components
    var paths = try #require(repair["paths"] as? [String: Any])
    let path = "/api/v1/conversations/{conversation_id}/memory"
    var memoryPath = try #require(paths[path] as? [String: Any])
    var get = try #require(memoryPath["get"] as? [String: Any])
    var parameters = try #require(get["parameters"] as? [[String: Any]])
    let index = try #require(parameters.firstIndex { $0["name"] as? String == "pending_before" })
    let query = parameters.remove(at: index)
    #expect(NSDictionary(dictionary: query).isEqual(to: ["in": "query", "name": "pending_before", "required": false, "schema": ["maxLength": 200, "title": "Pending Before", "type": "string"]]))
    get["parameters"] = parameters
    memoryPath["get"] = get
    paths[path] = memoryPath
    repair["paths"] = paths
    repair["x-orca-schema-sha256"] = OrcaRuntimeContract.schemaSHA256
    // Full equality prevents hidden request, required-field, path, enum or authority drift.
    #expect(NSDictionary(dictionary: repair).isEqual(to: current))
}

@Test func miniRepairMemoryResponsePreservesKnownFields() throws {
    let value: [String: Any] = [
        "conversation_id": "11111111-1111-4111-8111-111111111111",
        "organization_id": "22222222-2222-4222-8222-222222222222",
        "revision": 7, "memory": ["active_summary": "existing summary"],
        "content_sha256": String(repeating: "a", count: 64), "pending_proposals": [],
        "pending_before": ["created_at": "2026-10-03T00:00:00Z", "id": "33333333-3333-4333-8333-333333333333"],
        "pending_proposals_total": 100, "pending_proposals_truncated": true
    ]
    let decoded = try JSONDecoder().decode(Components.Schemas.ConversationMemoryRead.self, from: JSONSerialization.data(withJSONObject: value))
    #expect(decoded.revision == 7)
    #expect(decoded.memory.activeSummary == "existing summary")
    #expect(decoded.pendingProposals?.isEmpty == true)
    #expect(decoded.contentSha256 == String(repeating: "a", count: 64))
}
