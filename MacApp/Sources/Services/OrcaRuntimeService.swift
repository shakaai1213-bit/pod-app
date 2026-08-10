import Foundation
import OrcaRuntimeContracts

enum RuntimeContractReachability: Equatable, Sendable {
    case available
    case upgradeRequired
    case unavailable(String)
}

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

    static func probeContract(at serverURL: URL, session: URLSession = .shared) async -> RuntimeContractReachability {
        guard let url = URL(
            string: "/api/v1/chat-runtime/v1/contract",
            relativeTo: serverURL
        )?.absoluteURL else {
            return .unavailable("Invalid ORCA server address.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unavailable("ORCA returned an unreadable response.")
            }
            switch http.statusCode {
            case 200, 401, 403:
                return .available
            case 404:
                return .upgradeRequired
            default:
                return .unavailable("ORCA returned HTTP \(http.statusCode).")
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
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
