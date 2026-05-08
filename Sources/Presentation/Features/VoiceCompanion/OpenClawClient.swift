import Foundation

actor OpenClawClient {
    private let baseURL: String
    private let authToken: String

    init(baseURL: String = "http://shakas-mac-mini.tail82d30d.ts.net:8000",
         // SEC-007 remediation 2026-05-08: default sourced from OrcaSecrets.swift
         // (gitignored) instead of hardcoded literal.
         authToken: String = OrcaSecrets.bearerToken) {
        self.baseURL = baseURL
        self.authToken = authToken
    }

    struct MessagePayload: Encodable {
        let content: String
        let message_type: String = "text"
    }

    /// Post a message to the ORCA MC general channel
    func postMessage(content: String, channelId: String = "4a37b0e8-bd9f-419f-ad82-f133877facf9") async throws {
        let url = URL(string: "\(baseURL)/api/v1/chat/channels/\(channelId)/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

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
