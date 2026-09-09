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

    func testBoardDirectoryUsesOneTaxonomyAndSearchContract() throws {
        let directory = try JSONDecoder().decode(
            OrcaBoardDirectory.self,
            from: Data(#"{"items":[{"id":"00000000-0000-4000-8000-000000000001","slug":"pod","name":"Pod","component":"Pod","description":"[product] Native clients"},{"id":"00000000-0000-4000-8000-000000000002","slug":"guardian","name":"Guardian","description":"Safety product"},{"id":"00000000-0000-4000-8000-000000000003","slug":"schoolhouse","name":"Schoolhouse","description":"Agent lifecycle"},{"id":"00000000-0000-4000-8000-000000000004","slug":"operations","name":"Operations","description":"Lab operations"},{"id":"00000000-0000-4000-8000-000000000005","slug":"fund","name":"Fund","description":"Protected domain"},{"id":"00000000-0000-4000-8000-000000000006","slug":"north-star","name":"North Star","description":"Strategy"}]}"#.utf8)
        )

        XCTAssertEqual(directory.items.map(\.architectureGroup), [
            .surfaces, .products, .platform, .infrastructure, .fund, .strategy,
        ])
        XCTAssertEqual(
            directory.filtered(searchQuery: "native").map(\.slug),
            ["pod"]
        )
        XCTAssertEqual(
            directory.grouped().map(\.group),
            [.products, .surfaces, .platform, .infrastructure, .fund, .strategy]
        )
        XCTAssertEqual(
            directory.filtered(group: .platform).map(\.slug),
            ["schoolhouse"]
        )
        XCTAssertTrue(directory.filtered(searchQuery: "protected domain").isEmpty)
        XCTAssertEqual(directory.filtered(searchQuery: "fund").map(\.slug), ["fund"])
    }

    func testBoardArchitectureDirectoryPreservesSignedTruthAndProtectedPointers() throws {
        let directory = try boardArchitectureDecoder().decode(
            OrcaBoardArchitectureDirectory.self,
            from: Self.boardArchitectureDirectoryJSON
        )

        XCTAssertEqual(directory.profiles.map { $0.header.slug }, ["guardian", "fund"])
        XCTAssertEqual(directory.directoryItems.map { $0.id }, directory.profiles.map { $0.id })
        XCTAssertEqual(directory.directoryItems.map { $0.projectCount }, [3, 0])
        XCTAssertEqual(directory.directoryItems.map { $0.ticketCount }, [5, 0])
        XCTAssertEqual(directory.directoryItems.map { $0.isProtected }, [false, true])
        XCTAssertEqual(directory.directoryItems.map { $0.classification }, [.product, .protectedDomain])
        XCTAssertTrue(directory.directoryItems[0].isProduct)
        XCTAssertTrue(OrcaBoardDirectoryItem(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000099")!,
            slug: "future-product",
            name: "Future Product",
            layer: "products",
            component: nil,
            boardDescription: "No legacy product marker.",
            classification: .product,
            projectCount: 0,
            activeCount: 0,
            ticketCount: 0,
            protection: false
        ).isProduct)

        let guardian = try XCTUnwrap(directory.profiles.first?.fullProfile)
        XCTAssertEqual(guardian.header.healthState, OrcaBoardHealthState.healthy)
        XCTAssertEqual(guardian.health.freshness, OrcaBoardFreshnessState.fresh)
        XCTAssertEqual(guardian.currentRelease?.revision, "guardian-r4")
        XCTAssertEqual(guardian.currentRelease?.releaseManifestSHA256, String(repeating: "c", count: 64))
        XCTAssertEqual(guardian.sourceRefs.map { $0.sourceType }, ["signed_operational_snapshot"])

        XCTAssertNil(directory.profiles.last?.fullProfile)
        XCTAssertEqual(directory.profiles.last?.header.classification, .protectedDomain)
        XCTAssertFalse(directory.profiles.last?.header.detailAvailable ?? true)
    }

    func testBoardArchitectureProfilesFailClosedOnContractDrift() throws {
        let protectedFull = Self.boardArchitectureFullJSON
            .replacingOccurrences(of: #""protected":false"#, with: #""protected":true"#)
        XCTAssertThrowsError(
            try boardArchitectureDecoder().decode(
                OrcaBoardArchitectureProfile.self,
                from: Data(protectedFull.utf8)
            )
        )

        let conflictingHealth = Self.boardArchitectureFullJSON
            .replacingOccurrences(of: #""health_state":"healthy""#, with: #""health_state":"blocked""#)
        XCTAssertThrowsError(
            try boardArchitectureDecoder().decode(
                OrcaBoardArchitectureProfile.self,
                from: Data(conflictingHealth.utf8)
            )
        )

        let unknownVisibility = Self.boardArchitectureFullJSON
            .replacingOccurrences(of: #""visibility":"full""#, with: #""visibility":"summary""#)
        XCTAssertThrowsError(
            try boardArchitectureDecoder().decode(
                OrcaBoardArchitectureProfile.self,
                from: Data(unknownVisibility.utf8)
            )
        )

        let leakedProtectedDetail = Self.boardArchitectureProtectedJSON
            .replacingOccurrences(
                of: #""visibility":"protected_pointer""#,
                with: #""purpose":"secret","visibility":"protected_pointer""#
            )
        XCTAssertThrowsError(
            try boardArchitectureDecoder().decode(
                OrcaBoardArchitectureProfile.self,
                from: Data(leakedProtectedDetail.utf8)
            )
        )

        let prefix = #"{"schema_version":"orca.board-architecture-directory.v1","config_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generated_at":"2026-09-09T20:00:00Z","profiles":["#
        let duplicateDirectory = Data(
            (prefix + Self.boardArchitectureFullJSON + "," + Self.boardArchitectureFullJSON + "]}").utf8
        )
        XCTAssertThrowsError(
            try boardArchitectureDecoder().decode(
                OrcaBoardArchitectureDirectory.self,
                from: duplicateDirectory
            )
        )
    }

    func testBoardDetailModelsDecodeCollectionsAndFailClosedForProtectedTickets() throws {
        let projectPage = try JSONDecoder().decode(
            OrcaBoardCollectionPage<OrcaBoardProjectSummary>.self,
            from: Data(#"[{"id":"10000000-0000-4000-8000-000000000001","board_id":"00000000-0000-4000-8000-000000000001","board_ids":["00000000-0000-4000-8000-000000000002"],"name":"Runtime","status":"in_progress","stage":"build","priority":1}]"#.utf8)
        )
        let primaryBoardID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let linkedBoardID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        XCTAssertTrue(projectPage.items[0].belongs(to: primaryBoardID))
        XCTAssertTrue(projectPage.items[0].belongs(to: linkedBoardID))

        let ticketPage = try JSONDecoder().decode(
            OrcaBoardCollectionPage<OrcaBoardTicketSummary>.self,
            from: Data(#"{"items":[{"id":"30000000-0000-4000-8000-000000000001","title":"Visible","status":"open","priority":"high","protected":false,"compute_tag":"code","autonomy_level":"draft_only"},{"id":"30000000-0000-4000-8000-000000000002","title":"Pointer only","status":"open","priority":"high","protected":true,"compute_tag":"code","autonomy_level":"draft_only"}]}"#.utf8)
        )
        XCTAssertTrue(ticketPage.items[0].isSafeForGenericSurface)
        XCTAssertFalse(ticketPage.items[1].isSafeForGenericSurface)
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
        XCTAssertEqual(OrcaBoardArchitectureEndpoint.directory, "/api/v1/board-architecture")
        XCTAssertEqual(
            OrcaBoardArchitectureEndpoint.profile(
                boardID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
            ),
            "/api/v1/board-architecture/00000000-0000-4000-8000-000000000001"
        )
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

    private func boardArchitectureDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let boardArchitectureFullJSON = #"{"schema_version":"orca.board-architecture-profile.v1","config_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generated_at":"2026-09-09T20:00:00Z","board_id":"00000000-0000-4000-8000-000000000010","slug":"guardian","name":"Guardian","group_id":null,"group_slug":"products","classification":"product","lifecycle_state":"active","protected":false,"public_summary":"Safety and health product.","health_state":"healthy","counts":{"project_count":3,"active_project_count":2,"task_count":7,"active_task_count":4,"ticket_count":5,"in_progress_count":6,"blocked_count":0,"review_count":1,"approval_count":0,"run_count":2,"stale_count":0},"detail_available":true,"visibility":"full","purpose":"Safety and health product.","primary_agent":"aloha","health":{"state":"healthy","reason":"All signed checks pass.","observed_at":"2026-09-09T19:59:00Z","freshness":"fresh","source_checks":["guardian.api"]},"current_release":{"revision":"guardian-r4","artifact_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","release_manifest_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","deployed_at":"2026-09-09T19:55:00Z","freshness":"fresh","evidence_refs":["orca://release/guardian-r4"]},"current_project_id":"10000000-0000-4000-8000-000000000010","current_project_name":"Guardian hardening","next_gate":"Run product canary","highest_impact_blocker":null,"source_refs":[{"source_type":"signed_operational_snapshot","ref":"/api/v1/state-registry/board.guardian.operational","revision":"guardian-r4","observed_at":"2026-09-09T19:59:00Z","freshness":"fresh"}]}"#

    private static let boardArchitectureProtectedJSON = #"{"schema_version":"orca.board-architecture-profile.v1","config_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generated_at":"2026-09-09T20:00:00Z","board_id":"00000000-0000-4000-8000-000000000020","slug":"fund","name":"Fund","group_id":null,"group_slug":"fund","classification":"protected_domain","lifecycle_state":"active","protected":true,"public_summary":null,"health_state":"unknown","counts":{},"detail_available":false,"visibility":"protected_pointer"}"#

    private static var boardArchitectureDirectoryJSON: Data {
        let prefix = #"{"schema_version":"orca.board-architecture-directory.v1","config_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generated_at":"2026-09-09T20:00:00Z","profiles":["#
        let payload = prefix + boardArchitectureFullJSON + "," + boardArchitectureProtectedJSON + "]}"
        return Data(payload.utf8)
    }
}
