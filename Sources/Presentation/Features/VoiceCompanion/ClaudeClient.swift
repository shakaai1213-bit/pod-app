import Foundation

actor ClaudeClient {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "claude-opus-4-5") {
        self.apiKey = apiKey
        self.model = model
    }

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct Request: Codable {
        let model: String
        let max_tokens: Int
        let messages: [Message]
        let stream: Bool
    }

    func stream(prompt: String, systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let url = URL(string: "https://api.anthropic.com/v1/messages")!

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "anthropic-version")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "x-api-key")
                request.setValue(model, forHTTPHeaderField: "anthropic-dangerous-direct-browser-access")

                let body: [String: Any] = [
                    "model": model,
                    "max_tokens": 1024,
                    "messages": [
                        ["role": "user", "content": prompt]
                    ],
                    "stream": true
                ]

                // Inject system prompt if provided
                var fullMessages: [[String: Any]] = []
                if !systemPrompt.isEmpty {
                    fullMessages.append(["role": "system", "content": systemPrompt])
                }
                fullMessages.append(["role": "user", "content": prompt])

                var bodyWithSystem = body
                bodyWithSystem["messages"] = fullMessages

                request.httpBody = try? JSONSerialization.data(withJSONObject: bodyWithSystem)

                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.finish(throwing: error)
                        return
                    }

                    guard let data = data, let text = String(data: data, encoding: .utf8) else {
                        continuation.finish(throwing: NSError(domain: "ClaudeClient", code: -1))
                        return
                    }

                    // Parse SSE stream
                    let lines = text.components(separatedBy: "\n")
                    for line in lines {
                        if line.hasPrefix("data: ") {
                            let json = String(line.dropFirst(6))
                            if let content = Self.parseSSEvent(json) {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                }

                // Use streaming session
                let session = URLSession(configuration: .default)
                let streamTask = session.dataTask(with: request)
                streamTask.resume()
            }
        }
    }

    private static func parseSSEvent(_ json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }

        struct Event: Decodable {
            let type: String?
            let delta: Delta?
            struct Delta: Decodable {
                let text: String?
            }
        }

        guard let event = try? JSONDecoder().decode(Event.self, from: data),
              event.type == "content_block_delta",
              let text = event.delta?.text else {
            return nil
        }

        return text
    }
}

// Simple streaming using URLSession dataTask (non-streaming fallback)
extension ClaudeClient {
    nonisolated func send(prompt: String, systemPrompt: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "x-api-key")

        var messages: [[String: Any]] = []
        if !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": messages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Decodable {
            let content: [ContentBlock]
            struct ContentBlock: Decodable {
                let text: String?
            }
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.content.first?.text ?? ""
    }
}
