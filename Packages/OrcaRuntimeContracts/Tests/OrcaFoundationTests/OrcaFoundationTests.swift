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
        XCTAssertEqual(OrcaSurfaceSection.allCases.count, 11)
        XCTAssertEqual(OrcaSurfaceSection.allCases.first, .waitingOnCaptain)
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

    func testBoardPlanCardDecodesCanonicalLifecycleFacets() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(
            OrcaBoardPlan.self,
            from: Data(#"{"computed_at":"2026-09-04T20:00:00Z","board_id":"00000000-0000-4000-8000-000000000001","board_name":"Pod","board_slug":"pod","selection_mode":"pins_plus_canonical","pins":[],"lanes":[{"key":"in_progress","title":"In Progress","cards":[{"id":"ticket:00000000-0000-4000-8000-000000000002","object_type":"ticket","object_id":"00000000-0000-4000-8000-000000000002","title":"Runtime delivery","subtitle":"runtime","column":"in_progress","canonical_state":"in_progress","priority":"high","owner_agent_id":null,"owner_name":"coral","wait_reason":null,"wait_kind":null,"pinned":true,"rank":12,"latest_evidence":null,"evidence_state":"missing","project_ids":[],"run_ids":["00000000-0000-4000-8000-000000000004"],"canonical_ref":"/api/v1/tickets/00000000-0000-4000-8000-000000000002","canonical_work_id":"ticket:00000000-0000-4000-8000-000000000002","facets":[{"id":"ticket:00000000-0000-4000-8000-000000000002","object_type":"ticket","object_id":"00000000-0000-4000-8000-000000000002","relationship":"canonical","title":"Runtime delivery","state":"in_progress","board_id":"00000000-0000-4000-8000-000000000001","canonical_ref":"/api/v1/tickets/00000000-0000-4000-8000-000000000002"},{"id":"task:00000000-0000-4000-8000-000000000003","object_type":"task","object_id":"00000000-0000-4000-8000-000000000003","relationship":"delivery","title":"Seven-agent canary","state":"in_progress","board_id":"00000000-0000-4000-8000-000000000001","canonical_ref":"/api/v1/boards/00000000-0000-4000-8000-000000000001/tasks/00000000-0000-4000-8000-000000000003"},{"id":"agent_run:00000000-0000-4000-8000-000000000004","object_type":"agent_run","object_id":"00000000-0000-4000-8000-000000000004","relationship":"execution","title":"Canary","state":"queued","board_id":null,"canonical_ref":"/api/v1/agent-runs/00000000-0000-4000-8000-000000000004/trace"}],"pin_ids":["00000000-0000-4000-8000-000000000005"],"integrity_warnings":[]}]}],"counts":{"in_progress":1},"source_refs":["/api/v1/tickets"]}"#.utf8)
        )

        let card = try XCTUnwrap(plan.lanes.first?.cards.first)
        XCTAssertEqual(card.resolvedCanonicalWorkId, card.id)
        XCTAssertEqual(card.resolvedFacets.map(\.objectType), ["ticket", "task", "agent_run"])
        XCTAssertEqual(card.resolvedPinIds.count, 1)
        XCTAssertTrue(card.resolvedIntegrityWarnings.isEmpty)
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

    func testWorkControlGroupRawValuesStayStableWithCaptainLensCases() {
        XCTAssertEqual(OrcaWorkControlProjection.Group.readyNow.rawValue, "Ready Now")
        XCTAssertEqual(OrcaWorkControlProjection.Group.assigned.rawValue, "Assigned")
        XCTAssertEqual(OrcaWorkControlProjection.Group.waitingOnOthers.rawValue, "Waiting On Others")
        XCTAssertEqual(OrcaWorkControlProjection.Group.approvals.rawValue, "Decision Queue")
        XCTAssertEqual(OrcaWorkControlProjection.Group.approvalAttention.rawValue, "Approval Attention")
        XCTAssertEqual(OrcaWorkControlProjection.Group.protected.rawValue, "Protected")
        XCTAssertEqual(OrcaWorkControlProjection.Group.historical.rawValue, "Historical")
        XCTAssertEqual(OrcaWorkControlProjection.Group.decisionsOnTony.rawValue, "Decisions On Tony")
        XCTAssertEqual(OrcaWorkControlProjection.Group.ticketsOnTony.rawValue, "Tickets On Tony")
        XCTAssertEqual(OrcaWorkControlProjection.Group.delegationRequests.rawValue, "Delegation Requests")
    }

    func testCaptainLensProjectionDecodesGroupedContract() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(
            OrcaWorkControlProjection.CaptainLensResponse.self,
            from: Data(#"""
            {
              "contract_version": "orca.captain-work-lens.v1",
              "generated_at": "2026-09-20T12:00:00Z",
              "groups": [
                {"name": "Decisions On Tony", "items": [
                  {"id": "approval:a-1", "kind": "approval", "title": "Approve release",
                   "summary": "Release approval pending.", "authority": "tony",
                   "agent_slug": "coral", "occurred_at": "2026-09-20T08:00:00Z",
                   "age_hours": 4.0, "stale_after_hours": 24, "is_stale": false,
                   "gate_severity": 2, "endpoint": "/api/v1/approvals/a-1",
                   "decision_endpoint": "/api/v1/tickets/t-2/approvals/a-1",
                   "approval_id": "a-1", "ticket_id": "t-2",
                   "ticket_title": "Ship release", "ticket_status": "in_review",
                   "desired_outcome": null, "needs_scope": false,
                   "approval_gate": "release", "reason": "Captain authority.",
                   "requested_by": "coral"}
                ]},
                {"name": "Tickets On Tony", "items": [
                  {"id": "ticket:t-1", "kind": "ticket", "title": "Pick window",
                   "summary": "Tony decides window.", "authority": "tony",
                   "agent_slug": "maui", "occurred_at": "2026-09-19T05:00:00Z",
                   "age_hours": 31.0, "stale_after_hours": null, "is_stale": true,
                   "gate_severity": 3, "endpoint": "/api/v1/tickets/t-1",
                   "decision_endpoint": null, "approval_id": null, "ticket_id": "t-1",
                   "ticket_title": "Pick window", "ticket_status": "blocked",
                   "desired_outcome": "Window chosen.", "needs_scope": true,
                   "approval_gate": null, "reason": "Captain input required.",
                   "requested_by": "maui"}
                ]},
                {"name": "Delegation Requests", "items": []}
              ],
              "counts": {"Decisions On Tony": 1, "Tickets On Tony": 1, "Delegation Requests": 0}
            }
            """#.utf8)
        )

        XCTAssertEqual(response.contractVersion, "orca.captain-work-lens.v1")
        XCTAssertEqual(response.groups.map(\.name), ["Decisions On Tony", "Tickets On Tony", "Delegation Requests"])
        XCTAssertEqual(response.counts["Tickets On Tony"], 1)

        let projection = OrcaWorkControlProjection(captainLens: response)
        XCTAssertEqual(projection.contractVersion, "orca.captain-work-lens.v1")
        XCTAssertEqual(projection.counts.approvals, 1)
        XCTAssertEqual(projection.counts.waitingOnOthers, 1)
        XCTAssertEqual(projection.counts.stale, 1)

        let decisions = projection.approvals
        XCTAssertEqual(decisions.map(\.id), ["a-1"])
        XCTAssertEqual(decisions.first?.authority, "tony")
        XCTAssertEqual(decisions.first?.linkedTicketIDs, ["t-2"])

        let tickets = projection.items(in: .ticketsOnTony)
        XCTAssertEqual(tickets.map(\.id), ["ticket:t-1"])
        XCTAssertTrue(tickets.first?.needsScope ?? false)
        XCTAssertEqual(tickets.first?.desiredOutcome, "Window chosen.")
        XCTAssertTrue(tickets.first?.stale ?? false)

        XCTAssertTrue(projection.items(in: .delegationRequests).isEmpty)
        XCTAssertTrue(projection.items(in: .decisionsOnTony).isEmpty)
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
