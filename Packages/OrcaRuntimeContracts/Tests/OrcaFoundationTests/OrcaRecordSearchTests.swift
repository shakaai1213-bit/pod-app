import Foundation
import OrcaDomain
import XCTest

final class OrcaRecordSearchTests: XCTestCase {
    func testShortIDsAndTitlesMatchWithoutSearchingMissingBodies() {
        XCTAssertTrue(OrcaRecordSearch.matches(" #4A9E889D ", values: ["approval:4a9e889d-1111-4000-8000-000000000001"]))
        XCTAssertTrue(OrcaRecordSearch.matches("mini stability", values: [nil, "Mini Stability Release"]))
        XCTAssertFalse(OrcaRecordSearch.matches("private body", values: ["4a9e889d", "Protected ticket"]))
        XCTAssertTrue(OrcaRecordSearch.matches("", values: []))
    }
    func testDelegatedApprovalDiscoveryKeepsRealAuthorityAndDeduplicates() throws {
        let item: [String: Any] = ["id": "approval:4a9e889d", "kind": "approval", "title": "Review standard",
            "authority": "aloha", "approval_id": "4a9e889d", "linked_ticket_ids": ["32ca9026"], "status": "pending"]
        var closed = item; closed["id"] = "approval:closed"; closed["approval_id"] = "closed"; closed["status"] = "approved"
        let fixture: [String: Any] = ["groups": [["name": "Decision Queue", "items": [item]],
            ["name": "Approval Attention", "items": [item, closed]]]]
        let result = try JSONDecoder().decode(OrcaApprovalDiscovery.self, from: JSONSerialization.data(withJSONObject: fixture))
        XCTAssertEqual(result.pendingApprovals.count, 1)
        XCTAssertEqual(result.pendingApprovals[0].authority, "aloha")
        XCTAssertEqual(result.pendingApprovals[0].linkedTicketIDs, ["32ca9026"])
        XCTAssertTrue(OrcaRecordSearch.matches("32ca9026", values: result.pendingApprovals[0].linkedTicketIDs))
    }
}
