import Foundation
import HTTPTypes
import OpenAPIRuntime

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

    public init(tokenProvider: @escaping @Sendable () async -> String?) {
        self.tokenProvider = tokenProvider
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = await tokenProvider(), !token.isEmpty {
            request.headerFields[.authorization] = "Bearer \(token)"
            request.headerFields[HTTPField.Name("X-Api-Key")!] = token
        }
        return try await next(request, body, baseURL)
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
    private let client: Client
    private var verifiedCompatibility: OrcaRuntimeCompatibility?

    public init(
        serverURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?
    ) {
        client = OrcaRuntimeContract.makeClient(
            serverURL: serverURL,
            middlewares: [OrcaRuntimeAuthorizationMiddleware(tokenProvider: tokenProvider)]
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
