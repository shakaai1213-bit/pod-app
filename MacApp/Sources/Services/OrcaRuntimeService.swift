import Foundation
import OrcaRuntimeContracts

protocol OrcaRuntimeServing: Sendable {
    func verifyCompatibility() async throws -> OrcaRuntimeCompatibility
    func send(_ request: OrcaRuntimeDirectTurnRequest) async throws -> OrcaRuntimeDirectTurnResponse
    func messages(conversationID: String, offset: Int, limit: Int) async throws -> [OrcaRuntimeConversationMessage]
}

actor OrcaRuntimeService: OrcaRuntimeServing {
    private let client: OrcaRuntimeClient

    init(serverURL: URL, tokenStore: any RuntimeTokenStoring) {
        client = OrcaRuntimeClient(
            serverURL: serverURL,
            tokenProvider: { try? await tokenStore.loadToken() }
        )
    }

    func verifyCompatibility() async throws -> OrcaRuntimeCompatibility {
        try await client.verifyCompatibility()
    }

    func send(_ request: OrcaRuntimeDirectTurnRequest) async throws -> OrcaRuntimeDirectTurnResponse {
        try await client.send(request)
    }

    func messages(
        conversationID: String,
        offset: Int,
        limit: Int
    ) async throws -> [OrcaRuntimeConversationMessage] {
        try await client.messages(conversationID: conversationID, offset: offset, limit: limit)
    }
}
