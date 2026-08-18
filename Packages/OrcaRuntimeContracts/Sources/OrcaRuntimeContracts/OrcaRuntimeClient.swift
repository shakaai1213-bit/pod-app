import Foundation
import HTTPTypes
import OpenAPIRuntime

public typealias OrcaRuntimeRequestProofProvider = @Sendable (
    _ method: String,
    _ target: String,
    _ body: Data,
    _ token: String
) async throws -> [String: String]

public enum OrcaRuntimeClientError: Error, Equatable, LocalizedError {
    case incompatibleContract(expected: String, actual: String)
    case incompatibleSchema(expected: String, actual: String)
    case missingContractIdentity
    case httpStatus(Int)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case let .incompatibleContract(expected, actual):
            return "ORCA runtime contract mismatch: expected \(expected), received \(actual)."
        case let .incompatibleSchema(expected, actual):
            return "ORCA runtime schema mismatch: expected \(expected), received \(actual)."
        case .missingContractIdentity:
            return "ORCA runtime did not provide a contract identity."
        case let .httpStatus(status):
            return "ORCA runtime returned HTTP \(status)."
        case let .invalidResponse(reason):
            return "ORCA runtime returned an invalid response: \(reason)."
        }
    }
}

public struct OrcaRuntimeCompatibility: Equatable, Sendable {
    public let contractVersion: String
    public let schemaSHA256: String

    public init(contractVersion: String, schemaSHA256: String) throws {
        guard contractVersion == OrcaRuntimeContract.version else {
            throw OrcaRuntimeClientError.incompatibleContract(
                expected: OrcaRuntimeContract.version,
                actual: contractVersion
            )
        }
        guard schemaSHA256 == OrcaRuntimeContract.schemaSHA256 else {
            throw OrcaRuntimeClientError.incompatibleSchema(
                expected: OrcaRuntimeContract.schemaSHA256,
                actual: schemaSHA256
            )
        }
        self.contractVersion = contractVersion
        self.schemaSHA256 = schemaSHA256
    }
}

public struct OrcaRuntimeAuthorizationMiddleware: ClientMiddleware {
    private let tokenProvider: @Sendable () async -> String?
    private let deviceIDProvider: @Sendable () async -> String?
    private let requestProofProvider: OrcaRuntimeRequestProofProvider?

    public init(
        tokenProvider: @escaping @Sendable () async -> String?,
        deviceIDProvider: @escaping @Sendable () async -> String? = { nil },
        requestProofProvider: OrcaRuntimeRequestProofProvider? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.deviceIDProvider = deviceIDProvider
        self.requestProofProvider = requestProofProvider
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        var bufferedBody = body
        if let token = await tokenProvider(), !token.isEmpty {
            request.headerFields[.authorization] = "Bearer \(token)"
            if let requestProofProvider, token.split(separator: ".", omittingEmptySubsequences: false).count == 3 {
                let bytes: Data
                if let body {
                    bytes = try await Data(collecting: body, upTo: 8 * 1024 * 1024)
                } else {
                    bytes = Data()
                }
                bufferedBody = bytes.isEmpty ? nil : HTTPBody(bytes)
                let proof = try await requestProofProvider(
                    request.method.rawValue,
                    request.path ?? "/",
                    bytes,
                    token
                )
                for (name, value) in proof {
                    guard let fieldName = HTTPField.Name(name) else { continue }
                    request.headerFields[fieldName] = value
                }
            }
        }
        if let deviceID = await deviceIDProvider(), !deviceID.isEmpty {
            request.headerFields[HTTPField.Name("X-ORCA-Device-ID")!] = deviceID
        }
        return try await next(request, bufferedBody, baseURL)
    }
}

public struct OrcaRuntimeHistoryMessage: Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct OrcaRuntimeDirectTurnRequest: Equatable, Sendable {
    public let agentSlug: String
    public let content: String
    public let history: [OrcaRuntimeHistoryMessage]
    public let deliveryMode: String
    public let asyncResponse: Bool
    public let idempotencyKey: String
    public let traceID: String
    public let triageID: String?
    public let triageTraceID: String?
    public let activeTicketID: String?
    public let conversationID: String?

    public init(
        agentSlug: String,
        content: String,
        history: [OrcaRuntimeHistoryMessage] = [],
        deliveryMode: String,
        asyncResponse: Bool,
        traceID: String,
        idempotencyKey: String? = nil,
        triageID: String? = nil,
        triageTraceID: String? = nil,
        activeTicketID: String? = nil,
        conversationID: String? = nil
    ) {
        self.agentSlug = agentSlug
        self.content = content
        self.history = history
        self.deliveryMode = deliveryMode
        self.asyncResponse = asyncResponse
        self.idempotencyKey = idempotencyKey ?? "orca-runtime-turn:\(traceID)"
        self.traceID = traceID
        self.triageID = triageID
        self.triageTraceID = triageTraceID
        self.activeTicketID = activeTicketID
        self.conversationID = conversationID
    }
}

public struct OrcaRuntimeDirectTurnResponse: Equatable, Sendable {
    public let conversationID: String
    public let userMessageID: String
    public let assistantMessageID: String
    public let content: String
    public let agentSlug: String
    public let traceID: String
    public let source: String
    public let lane: String
    public let deliveryMode: String?
    public let provenance: String?
    public let responseState: String?
    public let provider: String?
    public let model: String?
    public let tier: String?
    public let tokenCount: Int?
    public let triageID: String?
    public let computeRunID: String?
}

public struct OrcaRuntimeConversationMessage: Equatable, Sendable {
    public let id: String
    public let conversationID: String
    public let content: String
    public let messageType: String
    public let senderAgentID: String?
    public let traceID: String?
    public let source: String?
    public let lane: String?
    public let responseState: String?
    public let deliveryState: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public actor OrcaRuntimeClient {
    private static let namedAgentKeys: Set<String> = [
        "aloha", "chief", "coral", "maui", "reef", "rooster", "shaka",
    ]

    private let client: Client
    private var verifiedCompatibility: OrcaRuntimeCompatibility?

    public init(
        serverURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
        deviceIDProvider: @escaping @Sendable () async -> String? = { nil },
        requestProofProvider: OrcaRuntimeRequestProofProvider? = nil,
        session: URLSession = OrcaSecureURLSession.make()
    ) {
        client = OrcaRuntimeContract.makeClient(
            serverURL: serverURL,
            middlewares: [
                OrcaRuntimeAuthorizationMiddleware(
                    tokenProvider: tokenProvider,
                    deviceIDProvider: deviceIDProvider,
                    requestProofProvider: requestProofProvider
                )
            ],
            session: session
        )
    }

    public func verifyCompatibility() async throws -> OrcaRuntimeCompatibility {
        if let verifiedCompatibility {
            return verifiedCompatibility
        }
        let contractOutput = try await client.getRuntimeContract()
        let contract: Components.Schemas.ChatRuntimeContractRead
        switch contractOutput {
        case let .ok(response):
            contract = try response.body.json
        case let .undocumented(statusCode, _):
            throw OrcaRuntimeClientError.httpStatus(statusCode)
        }

        let schemaOutput = try await client.getRuntimeSchemaBundle()
        let schema: Components.Schemas.ChatRuntimeSchemaBundleRead
        switch schemaOutput {
        case let .ok(response):
            schema = try response.body.json
        case let .undocumented(statusCode, _):
            throw OrcaRuntimeClientError.httpStatus(statusCode)
        }

        guard let contractVersion = contract.contractVersion?.rawValue,
              let schemaVersion = schema.contractVersion?.rawValue,
              contractVersion == schemaVersion else {
            throw OrcaRuntimeClientError.missingContractIdentity
        }
        let compatibility = try OrcaRuntimeCompatibility(
            contractVersion: contractVersion,
            schemaSHA256: schema.schemaSha256
        )
        verifiedCompatibility = compatibility
        return compatibility
    }

    public func agentPacks() async throws -> Components.Schemas.ChatRuntimeAgentPackBundleRead {
        _ = try await verifyCompatibility()
        let output = try await client.getRuntimeAgentPacks()
        let bundle: Components.Schemas.ChatRuntimeAgentPackBundleRead
        switch output {
        case let .ok(response):
            bundle = try response.body.json
        case let .undocumented(statusCode, _):
            throw OrcaRuntimeClientError.httpStatus(statusCode)
        }
        try Self.validateAgentPacks(bundle)
        return bundle
    }

    public func capabilities(
        agentKey: String
    ) async throws -> Components.Schemas.ChatRuntimeCapabilityBundleRead {
        _ = try await verifyCompatibility()
        let normalizedAgentKey = agentKey.lowercased()
        guard Self.namedAgentKeys.contains(normalizedAgentKey) else {
            throw OrcaRuntimeClientError.invalidResponse("capability agent is not in roster")
        }
        let packs = try await agentPacks()
        guard let pack = packs.packs.first(where: { $0.agentKey == normalizedAgentKey }) else {
            throw OrcaRuntimeClientError.invalidResponse("capability agent pack is missing")
        }
        let output = try await client.getRuntimeAgentCapabilities(
            .init(path: .init(agentKey: normalizedAgentKey))
        )
        let bundle: Components.Schemas.ChatRuntimeCapabilityBundleRead
        switch output {
        case let .ok(response):
            bundle = try response.body.json
        case .unprocessableContent:
            throw OrcaRuntimeClientError.httpStatus(422)
        case let .undocumented(statusCode, _):
            throw OrcaRuntimeClientError.httpStatus(statusCode)
        }
        try Self.validateCapabilities(
            bundle,
            expectedAgentKey: normalizedAgentKey,
            expectedConfigurationSHA256: pack.payloadSha256
        )
        return bundle
    }

    public func workControl(
        agentKey: String
    ) async throws -> Components.Schemas.ChatRuntimeWorkControlBundleRead {
        _ = try await verifyCompatibility()
        let normalizedAgentKey = agentKey.lowercased()
        guard Self.namedAgentKeys.contains(normalizedAgentKey) else {
            throw OrcaRuntimeClientError.invalidResponse("work-control agent is not in roster")
        }
        let packs = try await agentPacks()
        guard let pack = packs.packs.first(where: { $0.agentKey == normalizedAgentKey }) else {
            throw OrcaRuntimeClientError.invalidResponse("work-control agent pack is missing")
        }
        let output = try await client.getRuntimeAgentWorkControl(
            .init(path: .init(agentKey: normalizedAgentKey))
        )
        let bundle: Components.Schemas.ChatRuntimeWorkControlBundleRead
        switch output {
        case let .ok(response):
            bundle = try response.body.json
        case .unprocessableContent:
            throw OrcaRuntimeClientError.httpStatus(422)
        case let .undocumented(statusCode, _):
            throw OrcaRuntimeClientError.httpStatus(statusCode)
        }
        try Self.validateWorkControl(
            bundle,
            expectedAgentKey: normalizedAgentKey,
            expectedConfigurationSHA256: pack.payloadSha256
        )
        return bundle
    }

    static func validateAgentPacks(
        _ bundle: Components.Schemas.ChatRuntimeAgentPackBundleRead
    ) throws {
        guard bundle.contractVersion?.rawValue == "orca.agent-pack-bundle.v1",
              bundle.configurationOnly == true,
              bundle.runtimeAttestationRequired == true,
              bundle.bundleSha256.count == 64,
              bundle.packs.count == namedAgentKeys.count,
              Set(bundle.packs.map(\.agentKey)) == namedAgentKeys else {
            throw OrcaRuntimeClientError.invalidResponse("agent pack bundle failed closed")
        }
        for pack in bundle.packs {
            guard pack.contractVersion?.rawValue == "orca.agent-pack.v1",
                  pack.ingressSubject == "agents.\(pack.agentKey).inbox",
                  pack.lifecycleOwner?.rawValue == "schoolhouse",
                  pack.routerOwner?.rawValue == "cascade",
                  pack.terminalReplyOwner?.rawValue == "schoolhouse_wake",
                  pack.voiceContract?.rawValue == "orca.named-agent-voice.v1",
                  pack.memoryContract?.rawValue == "orca_managed",
                  pack.capabilityRef
                    == "/api/v1/chat-runtime/v1/agents/\(pack.agentKey)/capabilities",
                  pack.capabilityAttestationRequired == true,
                  pack.releaseSignatureRequired == true,
                  pack.payloadSha256.count == 64,
                  !pack.supportedAdapterIds.isEmpty else {
                throw OrcaRuntimeClientError.invalidResponse(
                    "agent pack failed closed for \(pack.agentKey)"
                )
            }
        }
    }

    static func validateCapabilities(
        _ bundle: Components.Schemas.ChatRuntimeCapabilityBundleRead,
        expectedAgentKey: String,
        expectedConfigurationSHA256: String
    ) throws {
        guard namedAgentKeys.contains(expectedAgentKey),
              bundle.contractVersion?.rawValue == "orca.capability-bundle.v1",
              bundle.sourceContract?.rawValue == "orca.agent-tools.v1",
              bundle.authority?.rawValue == "orca",
              bundle.agentKey == expectedAgentKey,
              bundle.runtimeManifestRevision.isEmpty == false,
              bundle.configurationSha256 == expectedConfigurationSHA256,
              bundle.configurationSha256.count == 64,
              bundle.bundleSha256.count == 64,
              bundle.capabilityTruthReply.isEmpty == false,
              let capabilities = bundle.capabilities,
              capabilities.isEmpty == false,
              Set(capabilities.map(\.capabilityId)).count == capabilities.count else {
            throw OrcaRuntimeClientError.invalidResponse("capability bundle failed closed")
        }

        for capability in capabilities {
            let declaredAvailable = capability.declaredStatus == "available"
            let attested = capability.attestation.state == "attested"
            let expectedProductionReady = declaredAvailable && attested
            let endpointValues = capability.endpoints.map {
                Array($0.additionalProperties.values)
            } ?? []
            let attestationFreshAtGeneration = capability.attestation.expiresAt.map {
                $0 > bundle.generatedAt
            } ?? true
            guard capability.capabilityId.isEmpty == false,
                  capability.label.isEmpty == false,
                  capability.executionAllowedByCurrentPolicy == declaredAvailable,
                  capability.productionReady == expectedProductionReady,
                  capability.attestation.schema.rawValue
                    == "orca.runtime-capability-attestation.v1",
                  capability.attestation.enforced == bundle.attestationEnforced,
                  capability.attestation.configuredStatus == capability.declaredStatus,
                  capability.attestation.effectiveStatus == capability.declaredStatus,
                  capability.attestation.executionHost == capability.executionHost,
                  capability.attestation.mode.isEmpty == false,
                  capability.attestation.reason.isEmpty == false,
                  capability.attestation.sourceTag.isEmpty == false,
                  capability.attestation.recordContractValid,
                  capability.attestation.evidenceValid,
                  capability.attestation.rejectedEvidenceCount == 0,
                  endpointValues.allSatisfy({ $0.hasPrefix("/api/v1/") }),
                  !(capability.productionReady
                    && capability.attestation.wouldBlockIfEnforced),
                  !(capability.productionReady
                    && !(capability.attestation.missingChecks ?? []).isEmpty),
                  !(capability.productionReady
                    && !(capability.attestation.recordContractErrors ?? []).isEmpty),
                  !(capability.productionReady
                    && capability.attestation.expectedRoute != nil
                    && capability.attestation.expectedRoute
                        != capability.attestation.actualRoute),
                  !capability.productionReady || attestationFreshAtGeneration,
                  !(bundle.attestationEnforced
                    && capability.executionAllowedByCurrentPolicy
                    && !capability.productionReady) else {
                throw OrcaRuntimeClientError.invalidResponse(
                    "capability failed closed for \(capability.capabilityId)"
                )
            }
        }
    }

    static func validateWorkControl(
        _ bundle: Components.Schemas.ChatRuntimeWorkControlBundleRead,
        expectedAgentKey: String,
        expectedConfigurationSHA256: String
    ) throws {
        guard namedAgentKeys.contains(expectedAgentKey),
              bundle.contractVersion?.rawValue == "orca.work-control-bundle.v1",
              bundle.sourceContract?.rawValue == "orca.agent-workbench.v1",
              bundle.authority?.rawValue == "orca",
              bundle.mode?.rawValue == "read_only",
              bundle.agentKey == expectedAgentKey,
              bundle.agentId.isEmpty == false,
              bundle.runtimeManifestRevision.isEmpty == false,
              bundle.configurationSha256 == expectedConfigurationSHA256,
              bundle.configurationSha256.count == 64,
              bundle.bundleSha256.count == 64,
              let assignedWork = bundle.assignedWork,
              let readyNow = bundle.readyNow,
              let waitingOnOthers = bundle.waitingOnOthers,
              let protectedWork = bundle.protectedWork,
              let historicalWork = bundle.historicalWork,
              let approvalQueue = bundle.approvalQueue,
              let approvalInventory = bundle.approvalInventory else {
            throw OrcaRuntimeClientError.invalidResponse("work-control bundle failed closed")
        }

        func identity(_ item: Components.Schemas.ChatRuntimeWorkItemRead) -> String {
            "\(item.workKind.rawValue):\(item.workId)"
        }

        let assignedIdentities = assignedWork.map(identity)
        let assignedSet = Set(assignedIdentities)
        guard assignedSet.count == assignedIdentities.count else {
            throw OrcaRuntimeClientError.invalidResponse(
                "work-control assigned work contains duplicates"
            )
        }

        for item in assignedWork {
            let pendingApprovalIDs = item.pendingApprovalIds ?? []
            let eligibleTruth = item.workBucket == .current
                && pendingApprovalIDs.isEmpty
                && item.blockedOn == nil
            guard item.workId.isEmpty == false,
                  item.safeTitle.isEmpty == false,
                  item.status.isEmpty == false,
                  item.priority.isEmpty == false,
                  item.bucketReason.isEmpty == false,
                  Set(pendingApprovalIDs).count == pendingApprovalIDs.count,
                  !item.executionEligible || eligibleTruth else {
                throw OrcaRuntimeClientError.invalidResponse(
                    "work-control item failed closed for \(item.workId)"
                )
            }
        }

        let projections: [(String, [Components.Schemas.ChatRuntimeWorkItemRead])] = [
            ("ready_now", readyNow),
            ("waiting_on_others", waitingOnOthers),
            ("protected_work", protectedWork),
            ("historical_work", historicalWork),
        ]
        for (label, items) in projections {
            let identities = items.map(identity)
            guard Set(identities).count == identities.count,
                  Set(identities).isSubset(of: assignedSet) else {
                throw OrcaRuntimeClientError.invalidResponse(
                    "work-control projection failed closed for \(label)"
                )
            }
        }
        guard readyNow.allSatisfy({
            $0.workBucket == .current
                && $0.executionEligible
                && ($0.pendingApprovalIds ?? []).isEmpty
                && $0.blockedOn == nil
                && !$0.stale
        }), protectedWork.allSatisfy({ $0.workBucket == .protected }),
        historicalWork.allSatisfy({ $0.workBucket == .historical }),
        waitingOnOthers.allSatisfy({
            $0.workBucket != .historical
                && (!($0.pendingApprovalIds ?? []).isEmpty
                    || $0.blockedOn != nil
                    || $0.workBucket == .protected)
        }) else {
            throw OrcaRuntimeClientError.invalidResponse(
                "work-control projection contains contradictory work truth"
            )
        }

        func decisionAllowed(
            _ approval: Components.Schemas.ChatRuntimeWorkApprovalRead
        ) -> Bool {
            approval.viewerAuthorized
                && approval.resolutionEnabled
                && !approval.selfApprovalProhibited
        }

        for approval in approvalInventory {
            let hasDecisionEndpoint = approval.decisionEndpoint?.isEmpty == false
            guard approval.approvalId.isEmpty == false,
                  approval.actionType.isEmpty == false,
                  approval.authority.isEmpty == false,
                  approval.authorizationReason.isEmpty == false,
                  approval.status == .pending,
                  approval.staleAfterHours > 0,
                  approval.linkedTicketIds != nil,
                  approval.linkedTaskIds != nil,
                  decisionAllowed(approval) == hasDecisionEndpoint,
                  approval.decisionEndpoint.map({
                      $0.hasPrefix("/api/v1/approvals/")
                  }) ?? true else {
                throw OrcaRuntimeClientError.invalidResponse(
                    "work-control approval failed closed for \(approval.approvalId)"
                )
            }
        }
        let inventoryIDs = approvalInventory.map(\.approvalId)
        let inventorySet = Set(inventoryIDs)
        let queueIDs = approvalQueue.map(\.approvalId)
        guard inventorySet.count == inventoryIDs.count,
              Set(queueIDs).count == queueIDs.count,
              Set(queueIDs).isSubset(of: inventorySet),
              approvalQueue.allSatisfy({
                  decisionAllowed($0)
                      && $0.decisionEndpoint?.hasPrefix("/api/v1/approvals/") == true
              }) else {
            throw OrcaRuntimeClientError.invalidResponse(
                "work-control approval queue failed closed"
            )
        }

        let counts = bundle.resources.counts
        let countValues = [
            counts.activeWorkerRuns,
            counts.approvalInventory,
            counts.approvalQueue,
            counts.assignedWork,
            counts.blockingOthers,
            counts.fishBlocked,
            counts.fishProducing,
            counts.historicalWork,
            counts.plannerItems,
            counts.projectTasks,
            counts.protectedWork,
            counts.readyNow,
            counts.researchActiveRequests,
            counts.researchAwaitingReview,
            counts.staleWork,
            counts.toolsDeclared,
            counts.waitingOnMe,
            counts.waitingOnOthers,
            counts.workerReviewRuns,
        ]
        guard countValues.allSatisfy({ $0 >= 0 }),
              counts.assignedWork == assignedWork.count,
              counts.readyNow == readyNow.count,
              counts.waitingOnOthers == waitingOnOthers.count,
              counts.protectedWork == protectedWork.count,
              counts.historicalWork == historicalWork.count,
              counts.approvalQueue == approvalQueue.count,
              counts.approvalInventory == approvalInventory.count else {
            throw OrcaRuntimeClientError.invalidResponse(
                "work-control counts failed closed"
            )
        }

        guard let endpoints = bundle.resources.endpoints?.additionalProperties,
              endpoints["workbench"] == "/api/v1/agent/workbench",
              endpoints["approvals"] == "/api/v1/approvals",
              endpoints["tool_runs"] == "/api/v1/agent/tool-runs",
              endpoints.values.allSatisfy({ $0.hasPrefix("/api/v1/") }) else {
            throw OrcaRuntimeClientError.invalidResponse(
                "work-control endpoints failed closed"
            )
        }
    }

    public func send(_ request: OrcaRuntimeDirectTurnRequest) async throws -> OrcaRuntimeDirectTurnResponse {
        let body = Components.Schemas.DirectAgentChatRequest(
            activeTicketId: request.activeTicketID,
            asyncResponse: request.asyncResponse,
            channelOfOrigin: "pod-chat",
            chatThreadId: request.conversationID,
            content: request.content,
            deliveryMode: request.deliveryMode,
            history: request.history.suffix(20).map {
                Components.Schemas.DirectAgentChatMessage(content: $0.content, role: $0.role)
            },
            idempotencyKey: request.idempotencyKey,
            traceId: request.traceID,
            triageId: request.triageID,
            triageTraceId: request.triageTraceID
        )
        let output = try await client.sendDirectAgentTurn(
            .init(path: .init(agentSlug: request.agentSlug), body: .json(body))
        )
        let response: Components.Schemas.DirectAgentChatResponse
        switch output {
        case let .ok(value):
            response = try value.body.json
        case .unprocessableContent:
            throw OrcaRuntimeClientError.httpStatus(422)
        case let .undocumented(statusCode, _):
            throw OrcaRuntimeClientError.httpStatus(statusCode)
        }
        let metadata = response.metadata
        return OrcaRuntimeDirectTurnResponse(
            conversationID: response.channelId,
            userMessageID: response.userMessageId,
            assistantMessageID: response.assistantMessageId,
            content: response.content,
            agentSlug: response.agentSlug,
            traceID: metadata.traceId,
            source: metadata.source,
            lane: metadata.lane,
            deliveryMode: metadata.deliveryMode,
            provenance: metadata.provenance,
            responseState: metadata.responseState,
            provider: metadata.backend,
            model: metadata.model,
            tier: metadata.tier,
            tokenCount: metadata.tokenCount,
            triageID: metadata.triageId,
            computeRunID: metadata.computeRunId
        )
    }

    public func messages(
        conversationID: String,
        offset: Int = 0,
        limit: Int = 200
    ) async throws -> [OrcaRuntimeConversationMessage] {
        let output = try await client.listConversationMessages(
            .init(
                path: .init(channelId: conversationID),
                query: .init(limit: limit, offset: offset)
            )
        )
        let messages: [Components.Schemas.ChatMessageRead]
        switch output {
        case let .ok(response):
            messages = try response.body.json
        case .unprocessableContent:
            throw OrcaRuntimeClientError.httpStatus(422)
        case let .undocumented(statusCode, _):
            throw OrcaRuntimeClientError.httpStatus(statusCode)
        }
        return messages.map {
            OrcaRuntimeConversationMessage(
                id: $0.id,
                conversationID: $0.channelId,
                content: $0.content,
                messageType: $0.messageType,
                senderAgentID: $0.senderAgentId,
                traceID: $0.traceId,
                source: $0.source,
                lane: $0.lane,
                responseState: $0.responseState,
                deliveryState: $0.deliveryState,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
    }
}
