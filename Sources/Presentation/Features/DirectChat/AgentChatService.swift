import Foundation

/// Streams messages to/from an agent's OpenClaw gateway via SSE.
actor AgentChatService {

    enum AgentChatError: Error, LocalizedError {
        case invalidURL
        case httpError(Int)
        case noResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid agent endpoint URL"
            case .httpError(let code): return "Agent returned HTTP \(code)"
            case .noResponse: return "No response from agent"
            }
        }
    }

    private let agent: AgentInfo

    init(agent: AgentInfo) {
        self.agent = agent
    }

    // MARK: - Send message via OpenClaw gateway OpenAI-compatible endpoint

    /// Sends a message to the agent via the gateway's /v1/chat/completions endpoint.
    /// Returns an AsyncThrowingStream of response tokens as they arrive via SSE.
    func send(message: String, history: [(role: String, content: String)] = []) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Build messages array with conversation history
                    var messages: [[String: Any]] = []
                    
                    // System prompt for agent context
                    messages.append([
                        "role": "system",
                        "content": "You are \(agent.name), \(agent.role) on the ORCA platform. You are having a 1:1 conversation with Tony (The Captain). Be concise, direct, and helpful. Tony values brevity and execution over narration."
                    ])
                    
                    // Add conversation history (last 20 messages)
                    for msg in history.suffix(20) {
                        messages.append(["role": msg.role, "content": msg.content])
                    }
                    
                    // Add the new user message
                    messages.append(["role": "user", "content": message])

                    // POST to OpenClaw gateway's OpenAI-compatible endpoint
                    let url = URL(string: "\(agent.endpoint.baseURL)/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(agent.endpoint.authToken)", forHTTPHeaderField: "Authorization")
                    request.timeoutInterval = 120

                    let body: [String: Any] = [
                        "model": "openclaw/\(agent.id)",
                        "messages": messages,
                        "stream": true
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        continuation.finish(throwing: AgentChatError.httpError(http.statusCode))
                        return
                    }

                    // Parse SSE stream
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let json = String(line.dropFirst(6))
                            if json == "[DONE]" { break }
                            if let content = Self.parseContentDelta(json) {
                                continuation.yield(content)
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

    // MARK: - Direct Claude API streaming (for agents with API keys)

    /// Streams a response directly from Claude API with agent-specific system prompt.
    /// Used when we want real-time streaming responses (not async OpenClaw injection).
    func streamDirect(
        message: String,
        history: [(role: String, content: String)] = [],
        apiKey: String,
        model: String = "claude-sonnet-4-6"
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let systemPrompt = """
                    You are \(agent.name), \(agent.role) on the ORCA platform.
                    You are having a 1:1 conversation with Tony (The Captain).
                    Be concise, direct, and helpful. Tony values brevity and execution over narration.
                    """

                    var messages: [[String: Any]] = []
                    // Include conversation history
                    for msg in history.suffix(20) {
                        messages.append(["role": msg.role, "content": msg.content])
                    }
                    messages.append(["role": "user", "content": message])

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 4096,
                        "system": systemPrompt,
                        "messages": messages,
                        "stream": true
                    ]

                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.timeoutInterval = 120
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        continuation.finish(throwing: AgentChatError.httpError(http.statusCode))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let json = String(line.dropFirst(6))
                            if json == "[DONE]" { break }
                            if let text = Self.parseContentDelta(json) {
                                continuation.yield(text)
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

    // MARK: - SSE Parser

    private static func parseContentDelta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }
        struct Event: Decodable {
            let type: String?
            let delta: Delta?
            struct Delta: Decodable { let text: String? }
        }
        guard let event = try? JSONDecoder().decode(Event.self, from: data),
              event.type == "content_block_delta",
              let text = event.delta?.text else {
            return nil
        }
        return text
    }
}
