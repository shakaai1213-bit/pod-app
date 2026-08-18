import Foundation
import OrcaRuntimeContracts

enum RuntimeContractReachability: Equatable, Sendable {
    case available
    case upgradeRequired
    case unavailable(String)
}

protocol OrcaRuntimeServing: Sendable {
    func verifyCompatibility() async throws -> OrcaRuntimeCompatibility
    func agentPacks() async throws -> Components.Schemas.ChatRuntimeAgentPackBundleRead
    func capabilities(agentKey: String) async throws -> Components.Schemas.ChatRuntimeCapabilityBundleRead
    func workControl(agentKey: String) async throws -> Components.Schemas.ChatRuntimeWorkControlBundleRead
    func send(_ request: OrcaRuntimeDirectTurnRequest) async throws -> OrcaRuntimeDirectTurnResponse
    func messages(conversationID: String, offset: Int, limit: Int) async throws -> [OrcaRuntimeConversationMessage]
}

actor OrcaRuntimeService: OrcaRuntimeServing {
    private let client: OrcaRuntimeClient

    init(serverURL: URL, authService: OrcaNativeAuthService) {
        client = OrcaRuntimeClient(
            serverURL: serverURL,
            tokenProvider: { try? await authService.validAccessToken() },
            deviceIDProvider: { await authService.boundDeviceID() },
            requestProofProvider: { method, target, body, token in
                try await authService.requestProofHeaders(
                    method: method,
                    target: target,
                    body: body,
                    token: token
                )
            }
        )
    }

    static func probeContract(at serverURL: URL, session: URLSession? = nil) async -> RuntimeContractReachability {
        guard let url = URL(
            string: "/api/v1/chat-runtime/v1/contract",
            relativeTo: serverURL
        )?.absoluteURL else {
            return .unavailable("Invalid ORCA server address.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (_, response) = try await (session ?? OrcaSecureURLSession.make()).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unavailable("ORCA returned an unreadable response.")
            }
            guard OrcaSecureURLSession.responseStayedOnOrigin(response, requestURL: url) else {
                return .unavailable("ORCA redirected outside its approved origin.")
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

    func agentPacks() async throws -> Components.Schemas.ChatRuntimeAgentPackBundleRead {
        try await client.agentPacks()
    }

    func capabilities(
        agentKey: String
    ) async throws -> Components.Schemas.ChatRuntimeCapabilityBundleRead {
        try await client.capabilities(agentKey: agentKey)
    }

    func workControl(
        agentKey: String
    ) async throws -> Components.Schemas.ChatRuntimeWorkControlBundleRead {
        try await client.workControl(agentKey: agentKey)
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
