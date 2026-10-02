import Foundation
import OrcaDomain
import XCTest

final class OrcaTicketTimelineTests: XCTestCase {
    private let ticketID = "00000000-0000-4000-8000-000000000001"
    private func page(typedCursor: Int? = nil, legacyCursor: Bool = false) throws -> OrcaTicketTimelinePage {
        let fixture: [String: Any] = [
            "items": [["id": "00000000-0000-4000-8000-000000000002", "ticket_id": ticketID,
                "kind": "comment", "actor_type": "service", "author": "Captain", "credential_class": "fleet_bearer",
                "message": "ENTRY: review | by: rooster | model: verified", "model": "unverified", "model_verified": false,
                "approval_authority": false, "generation": 1, "created_at": "2026-10-02T20:00:00Z", "details": [:]]],
            "legacy_items": [], "approval_records": [],
            "ownership": ["ticket_id": ticketID, "generation": 1, "awaiting_acknowledgement": false, "overdue": false],
            "permissions": ["can_claim": false, "can_comment": true, "can_review": true, "can_handoff": false,
                "can_change_status": false, "can_acknowledge": false],
            "next_before_generation": typedCursor as Any? ?? NSNull(),
            "next_legacy_before_at": legacyCursor ? "2026-10-02T19:00:00+00:00" : NSNull(),
            "next_legacy_before_id": legacyCursor ? "00000000-0000-4000-8000-000000000003" : NSNull()]
        return try JSONDecoder().decode(OrcaTicketTimelinePage.self, from: JSONSerialization.data(withJSONObject: fixture))
    }
    func testFleetBodyCannotClaimReviewerOrModelIdentity() throws {
        let row = try page().items[0]
        XCTAssertEqual(row.authorLabel, "Fleet service")
        XCTAssertEqual(row.modelLabel, "Model unverified")
        XCTAssertFalse(row.approvalAuthority)
    }
    func testResponseMustBelongToSelectedTicket() throws {
        XCTAssertTrue(try page().belongs(to: ticketID))
        XCTAssertFalse(try page().belongs(to: "00000000-0000-4000-8000-000000000099"))
        XCTAssertNil(OrcaTicketTimelineCursor.path(ticketID: "../../agents"))
    }
    func testIndependentHistoryStreamsDoNotRestartWhenOneIsExhausted() throws {
        let legacyOnly = OrcaTicketTimelineCursor(page: try page(legacyCursor: true))
        let path = try XCTUnwrap(OrcaTicketTimelineCursor.path(ticketID: ticketID, cursor: legacyOnly))
        let parts = try XCTUnwrap(URLComponents(string: path))
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["include_typed"], "false")
        XCTAssertEqual(query["include_legacy"], "true")
        XCTAssertEqual(query["legacy_before_at"], "2026-10-02T19:00:00+00:00")
        XCTAssertNil(query["before_generation"])
        XCTAssertFalse(OrcaTicketTimelineCursor(page: try page()).hasMore)
    }
    func testWriteContainsNoCallerSelectedActorOrApprovalAuthority() throws {
        let key = UUID()
        var input = OrcaTicketEntryInput(kind: "comment", message: "Update", idempotencyKey: key, expectedGeneration: 7)
        input.onBehalfOf = "Tony"
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        XCTAssertEqual(object["expected_generation"] as? Int, 7)
        XCTAssertEqual((object["idempotency_key"] as? String)?.lowercased(), key.uuidString.lowercased())
        for field in ["actor_agent_id", "actor_type", "model_verified", "approved_by", "approval_authority"] { XCTAssertNil(object[field]) }
    }
}
