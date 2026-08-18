import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import OrcaRuntimeContracts

private func canonicalTurn() throws -> Components.Schemas.ChatRuntimeTurnRead {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "complete-turn",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
        Components.Schemas.ChatRuntimeTurnRead.self,
        from: Data(contentsOf: fixtureURL)
    )
}

private func canonicalAgentPack(
    _ agentKey: String
) -> Components.Schemas.ChatRuntimeAgentPackRead {
    .init(
        agentKey: agentKey,
        capabilityAttestationRequired: true,
        capabilityRef: "/api/v1/chat-runtime/v1/agents/\(agentKey)/capabilities",
        contractVersion: .orca_agentPack_v1,
        escalationRef: "orca://agent-packs/\(agentKey)/escalation",
        identityRef: "orca://agent-packs/\(agentKey)/identity",
        ingressSubject: "agents.\(agentKey).inbox",
        lifecycleOwner: .schoolhouse,
        lockerRef: "orca://agent-packs/\(agentKey)/locker",
        memoryContract: .orcaManaged,
        memoryRef: "orca://agent-packs/\(agentKey)/memory",
        payloadSha256: String(repeating: "a", count: 64),
        releaseSignatureRequired: true,
        rosterLane: .activeMain,
        routerOwner: .cascade,
        runtimeHost: .shakaMac,
        runtimePosture: "local-compute-first",
        sourceRefs: ["app/registries/agent-runtime-manifest.json"],
        supportedAdapterIds: ["local_compute"],
        terminalReplyOwner: .schoolhouseWake,
        title: agentKey.capitalized,
        voiceContract: .orca_namedAgentVoice_v1
    )
}

private func canonicalAgentPackBundle() -> Components.Schemas.ChatRuntimeAgentPackBundleRead {
    .init(
        bundleSha256: String(repeating: "b", count: 64),
        configurationOnly: true,
        contractVersion: .orca_agentPackBundle_v1,
        packs: ["aloha", "chief", "coral", "maui", "reef", "rooster", "shaka"]
            .map(canonicalAgentPack),
        runtimeAttestationRequired: true,
        runtimeManifestRevision: "2026-08-17.1"
    )
}

private func canonicalCapability(
    state: String = "missing",
    productionReady: Bool = false,
    wouldBlockIfEnforced: Bool = true,
    enforced: Bool = false,
    endpoint: String = "/api/v1/agent/tool-runs"
) -> Components.Schemas.ChatRuntimeCapabilityRead {
    let executionHost = "orca-mini"
    return .init(
        attestation: .init(
            attestedExecutionHost: state == "attested" ? executionHost : nil,
            configuredStatus: "available",
            effectiveStatus: "available",
            enforced: enforced,
            evidenceRefs: state == "attested" ? ["orca://evidence/capability-search"] : [],
            evidenceValid: true,
            executionHost: executionHost,
            missingChecks: wouldBlockIfEnforced ? ["bounded_canary_fresh"] : [],
            mode: "shadow",
            reason: state == "attested" ? "Live proof is fresh." : "Live proof is missing.",
            recordContractErrors: [],
            recordContractValid: true,
            recordHealth: state == "attested" ? "fresh" : "unknown",
            rejectedEvidenceCount: 0,
            requiredChecks: ["bounded_canary_fresh"],
            schema: .orca_runtimeCapabilityAttestation_v1,
            sourceTag: "capability.coral.search.orca",
            state: state,
            wouldBlockIfEnforced: wouldBlockIfEnforced
        ),
        blockedReasons: [],
        capabilityClass: "search",
        capabilityId: "search.orca",
        declaredStatus: "available",
        endpoints: .init(additionalProperties: ["run": endpoint]),
        evidenceTypes: ["tool_run"],
        executionAllowedByCurrentPolicy: true,
        executionHost: executionHost,
        label: "Search ORCA",
        mode: "governed",
        productionReady: productionReady,
        requiresApproval: false,
        resultSchema: "orca.agent-tool-run.v1",
        risk: "read_only",
        scopes: ["orca:read"],
        version: "1.0"
    )
}

private func canonicalCapabilityBundle(
    enforced: Bool = false,
    configurationSHA256: String = String(repeating: "a", count: 64),
    capability: Components.Schemas.ChatRuntimeCapabilityRead = canonicalCapability()
) -> Components.Schemas.ChatRuntimeCapabilityBundleRead {
    .init(
        agentId: "40000000-0000-4000-8000-000000000001",
        agentKey: "coral",
        attestationEnforced: enforced,
        authority: .orca,
        bundleSha256: String(repeating: "c", count: 64),
        capabilities: [capability],
        capabilityTruthReply: "Current ORCA capability truth.",
        configurationSha256: configurationSHA256,
        contractVersion: .orca_capabilityBundle_v1,
        gaps: [],
        generatedAt: Date(timeIntervalSince1970: 1_787_000_000),
        runtimeManifestRevision: "2026-08-17.1",
        sourceContract: .orca_agentTools_v1
    )
}

private func canonicalWorkItem(
    id: String = "70000000-0000-4000-8000-000000000001",
    bucket: Components.Schemas.ChatRuntimeWorkItemRead.WorkBucketPayload = .current,
    executionEligible: Bool = true,
    stale: Bool = false,
    pendingApprovalIDs: [String] = [],
    blockedOn: String? = nil
) -> Components.Schemas.ChatRuntimeWorkItemRead {
    .init(
        approvalState: pendingApprovalIDs.isEmpty ? "not_required" : "pending",
        blockedOn: blockedOn,
        bucketReason: "Current bounded work.",
        executionEligible: executionEligible,
        pendingApprovalIds: pendingApprovalIDs,
        priority: "high",
        safeTitle: "Prove Work Control",
        sourceRefs: .init(),
        stale: stale,
        status: "open",
        updatedAt: Date(timeIntervalSince1970: 1_787_000_000),
        workBucket: bucket,
        workId: id,
        workKind: .ticket
    )
}

private func canonicalWorkApproval(
    id: String = "80000000-0000-4000-8000-000000000001",
    viewerAuthorized: Bool = true,
    resolutionEnabled: Bool = true,
    selfApprovalProhibited: Bool = false
) -> Components.Schemas.ChatRuntimeWorkApprovalRead {
    let mayDecide = viewerAuthorized && resolutionEnabled && !selfApprovalProhibited
    return .init(
        actionType: "sign_standard",
        approvalId: id,
        authority: "aloha",
        authorizationReason: mayDecide ? "Aloha is the registered authority." : "Waiting on Aloha.",
        createdAt: Date(timeIntervalSince1970: 1_787_000_000),
        decisionEndpoint: mayDecide ? "/api/v1/approvals/\(id)" : nil,
        linkedTaskIds: [],
        linkedTicketIds: [],
        noCascade: false,
        resolutionEnabled: resolutionEnabled,
        selfApprovalProhibited: selfApprovalProhibited,
        stale: false,
        staleAfterHours: 72,
        status: .pending,
        targetRef: "70000000-0000-4000-8000-000000000001",
        targetType: "ticket",
        viewerAuthorized: viewerAuthorized
    )
}

private func canonicalWorkControlBundle(
    assignedWork suppliedAssignedWork: [Components.Schemas.ChatRuntimeWorkItemRead]? = nil,
    readyNow suppliedReadyNow: [Components.Schemas.ChatRuntimeWorkItemRead]? = nil,
    approvalInventory: [Components.Schemas.ChatRuntimeWorkApprovalRead] = [],
    approvalQueue: [Components.Schemas.ChatRuntimeWorkApprovalRead] = []
) -> Components.Schemas.ChatRuntimeWorkControlBundleRead {
    let assignedWork = suppliedAssignedWork ?? [canonicalWorkItem()]
    let readyNow = suppliedReadyNow ?? assignedWork.filter {
        $0.executionEligible && !$0.stale && $0.workBucket == .current
    }
    let waitingOnOthers = assignedWork.filter {
        $0.workBucket != .historical
            && (!($0.pendingApprovalIds ?? []).isEmpty
                || $0.blockedOn != nil
                || $0.workBucket == .protected)
    }
    let protectedWork = assignedWork.filter { $0.workBucket == .protected }
    let historicalWork = assignedWork.filter { $0.workBucket == .historical }
    let counts = Components.Schemas.ChatRuntimeWorkControlCountsRead(
        activeWorkerRuns: 0,
        approvalInventory: approvalInventory.count,
        approvalQueue: approvalQueue.count,
        assignedWork: assignedWork.count,
        blockingOthers: approvalQueue.count,
        fishBlocked: 0,
        fishProducing: 1,
        historicalWork: historicalWork.count,
        plannerItems: 1,
        projectTasks: 1,
        protectedWork: protectedWork.count,
        readyNow: readyNow.count,
        researchActiveRequests: 1,
        researchAwaitingReview: 0,
        staleWork: assignedWork.filter(\.stale).count,
        toolsDeclared: 3,
        waitingOnMe: approvalQueue.count,
        waitingOnOthers: waitingOnOthers.count,
        workerReviewRuns: 0
    )
    return .init(
        agentId: "40000000-0000-4000-8000-000000000001",
        agentKey: "coral",
        approvalInventory: approvalInventory,
        approvalQueue: approvalQueue,
        assignedWork: assignedWork,
        authority: .orca,
        bundleSha256: String(repeating: "d", count: 64),
        configurationSha256: String(repeating: "a", count: 64),
        contractVersion: .orca_workControlBundle_v1,
        generatedAt: Date(timeIntervalSince1970: 1_787_000_000),
        historicalWork: historicalWork,
        mode: .readOnly,
        protectedWork: protectedWork,
        readyNow: readyNow,
        resources: .init(
            counts: counts,
            endpoints: .init(additionalProperties: [
                "approvals": "/api/v1/approvals",
                "research": "/api/v1/research",
                "tool_runs": "/api/v1/agent/tool-runs",
                "workbench": "/api/v1/agent/workbench",
            ])
        ),
        runtimeManifestRevision: "2026-08-17.1",
        sourceContract: .orca_agentWorkbench_v1,
        waitingOnOthers: waitingOnOthers
    )
}

@Test(arguments: [301, 302, 303, 307, 308])
func credentialRedirectsAreNeverFollowed(status: Int) throws {
    let source = try #require(URL(string: "https://orca.test/api/v1/agents"))
    let destination = try #require(URL(string: "https://attacker.test/capture"))
    let response = try #require(HTTPURLResponse(
        url: source,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Location": destination.absoluteString]
    ))
    #expect(OrcaRedirectPolicy.followedRequest(
        for: response,
        proposed: URLRequest(url: destination)
    ) == nil)
}

@Test func opaqueServiceTokensDoNotInvokeNativeDeviceProof() async throws {
    actor Counter {
        var value = 0
        func increment() { value += 1 }
    }
    let counter = Counter()
    let middleware = OrcaRuntimeAuthorizationMiddleware(
        tokenProvider: { "opaque-local-control-token" },
        deviceIDProvider: { "local-device" },
        requestProofProvider: { _, _, _, _ in
            await counter.increment()
            return ["X-ORCA-Proof-Signature": "should-not-be-added"]
        }
    )
    let request = HTTPRequest(method: .get, scheme: "https", authority: "orca.test", path: "/api/v1/agents")

    let (response, _) = try await middleware.intercept(
        request,
        body: nil,
        baseURL: URL(string: "https://orca.test")!,
        operationID: "opaque-token-test"
    ) { forwarded, body, _ in
        #expect(forwarded.headerFields[.authorization] == "Bearer opaque-local-control-token")
        #expect(forwarded.headerFields[HTTPField.Name("X-ORCA-Proof-Signature")!] == nil)
        return (HTTPResponse(status: .ok), body)
    }

    #expect(response.status == .ok)
    #expect(await counter.value == 0)
}

@Test func contractMetadataIsPinned() {
    #expect(OrcaRuntimeContract.version == "orca.chat-runtime.v1")
    #expect(
        OrcaRuntimeContract.schemaSHA256
            == "ba6769ea8bb0a708912bc0b9a942cebd9875f129ca5b463d74763ef67315d6f1"
    )
}

@Test func exactSevenAgentPackBundlePassesClientGate() throws {
    try OrcaRuntimeClient.validateAgentPacks(canonicalAgentPackBundle())
}

@Test func agentPackBundleCannotMasqueradeAsAttestedRuntime() throws {
    var bundle = canonicalAgentPackBundle()
    bundle.runtimeAttestationRequired = false
    do {
        try OrcaRuntimeClient.validateAgentPacks(bundle)
        Issue.record("A configuration-only bundle bypassed runtime attestation")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("agent pack bundle failed closed"))
    }
}

@Test func agentPackBundleRejectsMissingNamedAgent() throws {
    var bundle = canonicalAgentPackBundle()
    bundle.packs.removeLast()
    do {
        try OrcaRuntimeClient.validateAgentPacks(bundle)
        Issue.record("A six-agent bundle passed the native client gate")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("agent pack bundle failed closed"))
    }
}

@Test func agentPackBundleRejectsCapabilityRouteDrift() throws {
    var bundle = canonicalAgentPackBundle()
    bundle.packs[0].capabilityRef = "orca://legacy-capability-pointer"
    do {
        try OrcaRuntimeClient.validateAgentPacks(bundle)
        Issue.record("A legacy capability pointer passed the native client gate")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("agent pack failed closed for aloha"))
    }
}

@Test func shadowCapabilityIsUsableButCannotClaimProductionProof() throws {
    let bundle = canonicalCapabilityBundle()
    try OrcaRuntimeClient.validateCapabilities(
        bundle,
        expectedAgentKey: "coral",
        expectedConfigurationSHA256: String(repeating: "a", count: 64)
    )

    var falseClaim = bundle
    falseClaim.capabilities?[0].productionReady = true
    do {
        try OrcaRuntimeClient.validateCapabilities(
            falseClaim,
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("An unattested capability claimed production readiness")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("capability failed closed for search.orca"))
    }
}

@Test func enforcedRuntimeRejectsExecutableUnattestedCapability() throws {
    let capability = canonicalCapability(enforced: true)
    do {
        try OrcaRuntimeClient.validateCapabilities(
            canonicalCapabilityBundle(enforced: true, capability: capability),
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("An enforced runtime accepted executable capability without proof")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("capability failed closed for search.orca"))
    }
}

@Test func capabilityBundleRejectsEnforcementFlagDrift() throws {
    let capability = canonicalCapability(
        state: "attested",
        productionReady: true,
        wouldBlockIfEnforced: false
    )
    do {
        try OrcaRuntimeClient.validateCapabilities(
            canonicalCapabilityBundle(enforced: true, capability: capability),
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("A capability disagreed with its bundle enforcement state")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("capability failed closed for search.orca"))
    }
}

@Test func capabilityBundleRejectsAgentPackConfigurationDrift() throws {
    do {
        try OrcaRuntimeClient.validateCapabilities(
            canonicalCapabilityBundle(configurationSHA256: String(repeating: "d", count: 64)),
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("A capability bundle detached from its Agent Pack was accepted")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("capability bundle failed closed"))
    }
}

@Test func capabilityBundleRejectsExternalExecutionEndpoint() throws {
    let capability = canonicalCapability(
        state: "attested",
        productionReady: true,
        wouldBlockIfEnforced: false,
        endpoint: "https://outside.invalid/run"
    )
    do {
        try OrcaRuntimeClient.validateCapabilities(
            canonicalCapabilityBundle(capability: capability),
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("A capability endpoint outside ORCA was accepted")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("capability failed closed for search.orca"))
    }
}

@Test func workControlBundlePassesNativeClientGate() throws {
    try OrcaRuntimeClient.validateWorkControl(
        canonicalWorkControlBundle(),
        expectedAgentKey: "coral",
        expectedConfigurationSHA256: String(repeating: "a", count: 64)
    )
}

@Test func workControlRejectsProtectedOrStaleReadyWork() throws {
    var protectedBundle = canonicalWorkControlBundle()
    protectedBundle.readyNow?[0].workBucket = .protected
    do {
        try OrcaRuntimeClient.validateWorkControl(
            protectedBundle,
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("Protected work appeared in the executable queue")
    } catch let error as OrcaRuntimeClientError {
        #expect(
            error == .invalidResponse(
                "work-control projection contains contradictory work truth"
            )
        )
    }

    var staleBundle = canonicalWorkControlBundle()
    staleBundle.readyNow?[0].stale = true
    do {
        try OrcaRuntimeClient.validateWorkControl(
            staleBundle,
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("Stale work appeared in the executable queue")
    } catch let error as OrcaRuntimeClientError {
        #expect(
            error == .invalidResponse(
                "work-control projection contains contradictory work truth"
            )
        )
    }
}

@Test func workControlRejectsUnauthorizedApprovalQueue() throws {
    let approval = canonicalWorkApproval(viewerAuthorized: false)
    do {
        try OrcaRuntimeClient.validateWorkControl(
            canonicalWorkControlBundle(
                approvalInventory: [approval],
                approvalQueue: [approval]
            ),
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("An unauthorized approval appeared in the decision queue")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("work-control approval queue failed closed"))
    }
}

@Test func workControlRejectsApprovalQueueOutsideInventory() throws {
    let inventoryApproval = canonicalWorkApproval()
    let queueApproval = canonicalWorkApproval(
        id: "80000000-0000-4000-8000-000000000002"
    )
    do {
        try OrcaRuntimeClient.validateWorkControl(
            canonicalWorkControlBundle(
                approvalInventory: [inventoryApproval],
                approvalQueue: [queueApproval]
            ),
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("A detached approval appeared in the decision queue")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("work-control approval queue failed closed"))
    }
}

@Test func workControlRejectsExternalResourceEndpoint() throws {
    var bundle = canonicalWorkControlBundle()
    bundle.resources.endpoints?.additionalProperties["research"] =
        "https://outside.invalid/research"
    do {
        try OrcaRuntimeClient.validateWorkControl(
            bundle,
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("A Work Control resource escaped ORCA")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("work-control endpoints failed closed"))
    }
}

@Test func workControlRejectsAgentPackConfigurationDrift() throws {
    var bundle = canonicalWorkControlBundle()
    bundle.configurationSha256 = String(repeating: "e", count: 64)
    do {
        try OrcaRuntimeClient.validateWorkControl(
            bundle,
            expectedAgentKey: "coral",
            expectedConfigurationSHA256: String(repeating: "a", count: 64)
        )
        Issue.record("Work Control detached from its Agent Pack")
    } catch let error as OrcaRuntimeClientError {
        #expect(error == .invalidResponse("work-control bundle failed closed"))
    }
}

@Test func generatedClientSupportsBothNativeSurfaces() {
    let client = OrcaRuntimeContract.makeClient(
        serverURL: URL(string: "https://orca.invalid")!
    )
    _ = client
}

@Test func directTurnDerivesStableMutationIdentityFromTrace() {
    let request = OrcaRuntimeDirectTurnRequest(
        agentSlug: "coral",
        content: "One turn",
        deliveryMode: "agent_inbox",
        asyncResponse: true,
        traceID: "pod-chat-trace-1"
    )

    #expect(request.idempotencyKey == "orca-runtime-turn:pod-chat-trace-1")
}

@Test func generatedTypesDecodeCanonicalCompleteTurn() throws {
    let turn = try canonicalTurn()

    #expect(turn.state == .completed)
    #expect(turn.adapter?.providerId == "conformance-provider")
    #expect(turn.adapter?.hostId == "conformance-host")
    #expect(turn.runtimeSessionId == "50000000-0000-4000-8000-000000000001")
    #expect(turn.events?.map(\.sequence) == [0, 1, 2, 3, 4])
    #expect(turn.latestCursor == turn.events?.last?.cursor)
    #expect(turn.terminalOutcome?.state == .completed)
    #expect(turn.terminalOutcome?.errorCode == nil)
}

@Test func incompatibleRuntimePairFailsClosed() throws {
    do {
        _ = try OrcaRuntimeCompatibility(
            contractVersion: "orca.chat-runtime.v2",
            schemaSHA256: OrcaRuntimeContract.schemaSHA256
        )
        Issue.record("A mismatched major contract was accepted")
    } catch let error as OrcaRuntimeClientError {
        #expect(
            error == .incompatibleContract(
                expected: OrcaRuntimeContract.version,
                actual: "orca.chat-runtime.v2"
            )
        )
    }

    do {
        _ = try OrcaRuntimeCompatibility(
            contractVersion: OrcaRuntimeContract.version,
            schemaSHA256: String(repeating: "0", count: 64)
        )
        Issue.record("A mismatched schema digest was accepted")
    } catch let error as OrcaRuntimeClientError {
        #expect(
            error == .incompatibleSchema(
                expected: OrcaRuntimeContract.schemaSHA256,
                actual: String(repeating: "0", count: 64)
            )
        )
    }
}

@Test func timelineReconnectIgnoresOverlapAndCompletesOnce() throws {
    let turn = try canonicalTurn()
    let generatedEvents = try #require(turn.events)
    var initial = OrcaRuntimeTimelineReducer()
    for event in generatedEvents.prefix(3) {
        #expect(try initial.apply(OrcaRuntimeTimelineEvent(generated: event)) == .applied)
    }

    var resumed = OrcaRuntimeTimelineReducer(resumePoint: initial.resumePoint)
    var reconnectTurn = turn
    reconnectTurn.events = Array(generatedEvents.suffix(from: 2))
    let results = try resumed.apply(reconnectTurn)

    #expect(results == [.duplicate, .applied, .applied])
    #expect(resumed.resumePoint.cursor == turn.latestCursor)
    #expect(resumed.terminal?.state == "completed")
    #expect(resumed.events.count == 2)
    #expect(
        try resumed.apply(OrcaRuntimeTimelineEvent(generated: generatedEvents.last!))
            == .duplicate
    )
}

@Test func timelineRejectsGapAndConflictingDuplicate() throws {
    let turn = try canonicalTurn()
    let generatedEvents = try #require(turn.events)
    var gapReducer = OrcaRuntimeTimelineReducer()
    do {
        _ = try gapReducer.apply(OrcaRuntimeTimelineEvent(generated: generatedEvents[1]))
        Issue.record("A sequence gap was accepted")
    } catch let error as OrcaRuntimeTimelineError {
        #expect(error == .sequenceGap(expected: 0, actual: 1))
    }

    var duplicateReducer = OrcaRuntimeTimelineReducer()
    let first = OrcaRuntimeTimelineEvent(generated: generatedEvents[0])
    _ = try duplicateReducer.apply(first)
    let conflicting = OrcaRuntimeTimelineEvent(
        eventID: first.eventID,
        sequence: first.sequence,
        cursor: "different-cursor",
        turnID: first.turnID,
        eventType: first.eventType,
        state: first.state
    )
    do {
        _ = try duplicateReducer.apply(conflicting)
        Issue.record("A conflicting duplicate was accepted")
    } catch let error as OrcaRuntimeTimelineError {
        #expect(error == .conflictingEvent(first.eventID))
    }
}

@Test func providerLossIsOneHonestFailedTerminal() throws {
    let fixture = try canonicalTurn()
    let failedEvent = Components.Schemas.ChatRuntimeTimelineEventRead(
        actorId: "provider-adapter",
        actorType: .adapter,
        agentId: fixture.agentId,
        conversationId: fixture.conversationId,
        cursor: "provider-loss:0",
        eventId: "70000000-0000-4000-8000-000000000001",
        eventType: .turn_failed,
        messageId: fixture.messageId,
        occurredAt: Date(),
        provenance: .init(
            sourceRef: "orca://runtime/provider-loss",
            traceId: "provider-loss-trace"
        ),
        sequence: 0,
        state: .failed,
        turnId: fixture.turnId
    )
    var failedTurn = fixture
    failedTurn.events = [failedEvent]
    failedTurn.latestCursor = failedEvent.cursor
    failedTurn.state = .failed
    failedTurn.terminalOutcome = .init(
        completedAt: Date(),
        errorCode: "provider_unavailable",
        state: .failed,
        summary: "The selected provider became unavailable."
    )

    var reducer = OrcaRuntimeTimelineReducer()
    #expect(try reducer.apply(failedTurn) == [.applied])
    #expect(reducer.terminal?.state == "failed")
    #expect(reducer.terminal?.errorCode == "provider_unavailable")
    #expect(reducer.events.count == 1)
}
