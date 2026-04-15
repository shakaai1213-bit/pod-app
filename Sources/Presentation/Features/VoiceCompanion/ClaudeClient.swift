import Foundation

actor ClaudeClient {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    // Default: Claude API. Swap baseURL + model for Kimi or any OpenAI-compatible endpoint.
    init(
        apiKey: String,
        model: String = "claude-opus-4-5",
        baseURL: String = "https://api.anthropic.com/v1/messages"
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    // MARK: - Streaming response

    func stream(prompt: String, systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var messages: [[String: Any]] = []
                    if !systemPrompt.isEmpty {
                        messages.append(["role": "system", "content": systemPrompt])
                    }
                    messages.append(["role": "user", "content": prompt])

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 1024,
                        "messages": messages,
                        "stream": true
                    ]

                    var request = URLRequest(url: URL(string: baseURL)!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        continuation.finish(throwing: NSError(
                            domain: "ClaudeClient",
                            code: http.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let json = String(line.dropFirst(6))
                            if json == "[DONE]" { break }
                            if let chunk = Self.parseSSEvent(json) {
                                continuation.yield(chunk)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Non-streaming (fallback / Kimi compatible)

    nonisolated func send(prompt: String, systemPrompt: String) async throws -> String {
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

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Decodable {
            let content: [ContentBlock]
            struct ContentBlock: Decodable {
                let text: String?
            }
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    // MARK: - SSE parser

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

// MARK: - Kimi (Moonshot) factory

extension ClaudeClient {
    /// Creates a ClaudeClient pointed at Kimi's OpenAI-compatible endpoint.
    /// Kimi uses OpenAI format so the response shape is different — use send() not stream() until we add OpenAI SSE parsing.
    static func kimi(apiKey: String, model: String = "moonshot-v1-8k") -> ClaudeClient {
        ClaudeClient(
            apiKey: apiKey,
            model: model,
            baseURL: "https://api.moonshot.cn/v1/chat/completions"
        )
    }
}
