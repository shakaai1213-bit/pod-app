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
            == "a3625bd57814ec97e7e3dcd1629e492f71c366df9e467cea9f67ba07f8d3d980"
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
