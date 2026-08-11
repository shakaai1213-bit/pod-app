import Foundation

actor OpenClawClient {
    private let baseURL: String
    private let tokenProvider: @Sendable () async -> String?

    init(baseURL: String = AppConfig.backendURL,
         tokenProvider: @escaping @Sendable () async -> String? = {
             await APIClient.shared.currentToken()
         }) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    struct MessagePayload: Encodable {
        let content: String
        let message_type: String = "text"
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

    /// Post a message to the ORCA MC general channel
    func postMessage(content: String, channelId: String = "4a37b0e8-bd9f-419f-ad82-f133877facf9") async throws {
        let authToken = try await bearerToken()
        let url = URL(string: "\(baseURL)/api/v1/chat/channels/\(channelId)/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(OrcaDeviceIdentity.current(), forHTTPHeaderField: "X-ORCA-Device-ID")

        let payload = MessagePayload(content: content)
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "OpenClawClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to post message to ORCA MC"
            ])
        }
    }

    func fetchVoiceProviders() async throws -> [VoiceProvider] {
        let authToken = try await bearerToken()
        let url = URL(string: "\(baseURL)/api/v1/voice/providers")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(OrcaDeviceIdentity.current(), forHTTPHeaderField: "X-ORCA-Device-ID")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([VoiceProvider].self, from: data)
    }

    func createLiveKitSession(agentSlug: String, participantName: String = "Tony") async throws -> LiveKitSession {
        let authToken = try await bearerToken()
        let url = URL(string: "\(baseURL)/api/v1/voice/livekit/sessions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(OrcaDeviceIdentity.current(), forHTTPHeaderField: "X-ORCA-Device-ID")
        request.httpBody = try JSONEncoder().encode(
            LiveKitSessionRequest(agentSlug: agentSlug, participantName: participantName, ttlSeconds: 1800)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LiveKitSession.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenClawClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid ORCA response"
            ])
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "ORCA request failed"
            throw NSError(domain: "OpenClawClient", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: body
            ])
        }
    }

    private func bearerToken() async throws -> String {
        guard let token = await tokenProvider(), !token.isEmpty else {
            throw NSError(domain: "OpenClawClient", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Sign in to ORCA before using voice."
            ])
        }
        return token
    }

    /// Post a voice transcript and AI response to ORCA MC
    func postVoiceExchange(userMessage: String, aiResponse: String, channelId: String = "4a37b0e8-bd9f-419f-ad82-f133877facf9") async {
        // Post user message
        try? await postMessage(content: "🎤 \(userMessage)", channelId: channelId)

        // Brief pause
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Post AI response
        try? await postMessage(content: "🤖 \(aiResponse)", channelId: channelId)
    }
}
