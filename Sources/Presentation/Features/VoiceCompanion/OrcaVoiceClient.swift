import Foundation
import OrcaRuntimeContracts

actor OrcaVoiceClient {
    private let baseURL: String
    private let tokenProvider: @Sendable () async -> String?
    private let session: URLSession

    init(baseURL: String = AppConfig.backendURL,
         tokenProvider: @escaping @Sendable () async -> String? = {
             await APIClient.shared.currentToken()
         }) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = OrcaSecureURLSession.make()
    }

    struct VoiceProvider: Decodable, Sendable {
        let provider: String
        let package: String
        let packageUrl: String
        let configured: Bool
        let livekitUrl: String?
        let notes: String

        enum CodingKeys: String, CodingKey {
            case provider
            case package
            case packageUrl = "package_url"
            case configured
            case livekitUrl = "livekit_url"
            case notes
        }
    }

    struct LiveKitSession: Decodable, Sendable {
        let provider: String
        let package: String
        let livekitUrl: String
        let roomName: String
        let token: String
        let participantIdentity: String
        let participantName: String
        let agentSlug: String
        let traceId: String
        let expiresAt: String
        let surfaceEventId: String?

        enum CodingKeys: String, CodingKey {
            case provider
            case package
            case livekitUrl = "livekit_url"
            case roomName = "room_name"
            case token
            case participantIdentity = "participant_identity"
            case participantName = "participant_name"
            case agentSlug = "agent_slug"
            case traceId = "trace_id"
            case expiresAt = "expires_at"
            case surfaceEventId = "surface_event_id"
        }
    }

    private struct LiveKitSessionRequest: Encodable {
        let agentSlug: String
        let participantName: String
        let ttlSeconds: Int

        enum CodingKeys: String, CodingKey {
            case agentSlug = "agent_slug"
            case participantName = "participant_name"
            case ttlSeconds = "ttl_seconds"
        }
    }

    func fetchVoiceProviders() async throws -> [VoiceProvider] {
        let authToken = try await bearerToken()
        let url = URL(string: "\(baseURL)/api/v1/voice/providers")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try OrcaDeviceIdentity.authorize(&request, token: authToken)

        let (data, response) = try await session.data(for: request)
        guard OrcaSecureURLSession.responseStayedOnOrigin(response, requestURL: url) else {
            throw URLError(.redirectToNonExistentLocation)
        }
        try validate(response: response, data: data)
        return try JSONDecoder().decode([VoiceProvider].self, from: data)
    }

    func createLiveKitSession(agentSlug: String, participantName: String = "Tony") async throws -> LiveKitSession {
        let authToken = try await bearerToken()
        let url = URL(string: "\(baseURL)/api/v1/voice/livekit/sessions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            LiveKitSessionRequest(agentSlug: agentSlug, participantName: participantName, ttlSeconds: 1800)
        )
        try OrcaDeviceIdentity.authorize(&request, token: authToken)

        let (data, response) = try await session.data(for: request)
        guard OrcaSecureURLSession.responseStayedOnOrigin(response, requestURL: url) else {
            throw URLError(.redirectToNonExistentLocation)
        }
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LiveKitSession.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OrcaVoiceClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid ORCA response"
            ])
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "ORCA request failed"
            throw NSError(domain: "OrcaVoiceClient", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: body
            ])
        }
    }

    private func bearerToken() async throws -> String {
        guard let token = await tokenProvider(), !token.isEmpty else {
            throw NSError(domain: "OrcaVoiceClient", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Sign in to ORCA before using voice."
            ])
        }
        return token
    }

}
