import Foundation
import Combine

@MainActor
final class VoiceCompanionViewModel: ObservableObject {
    // MARK: - Published State
    @Published var messages: [VoiceMessage] = []
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var partialTranscript: String = ""
    @Published var statusText: String = "Tap and hold to speak"
    @Published var errorMessage: String?

    // Routing toggles
    @Published var routeToClaude: Bool = true
    @Published var routeToOpenClaw: Bool = true

    // MARK: - Dependencies
    private let speechRecorder: SpeechRecorder
    private let claudeClient: ClaudeClient?
    private let openClawClient: OpenClawClient

    // MARK: - System Prompt
    private let systemPrompt = """
    You are Aurora, Mission Control for the ORCA team. \
    You coordinate engineering, research, and operations across both machines. \
    Keep responses concise and practical. \
    The user is Tony, the Captain.
    """

    // MARK: - Initialization
    init() {
        self.speechRecorder = SpeechRecorder()

        // Initialize clients (API key from Secrets.plist or environment)
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? ""

        if apiKey.isEmpty {
            self.claudeClient = nil
            print("[VoiceCompanion] Warning: No Anthropic API key configured")
        } else {
            self.claudeClient = ClaudeClient(apiKey: apiKey)
        }

        self.openClawClient = OpenClawClient()
    }

    // MARK: - Recording Control
    func startRecording() async {
        // Request authorization
        let authorized = await speechRecorder.requestAuthorization()
        guard authorized else {
            errorMessage = "Speech recognition not authorized. Enable in Settings."
            return
        }

        do {
            try speechRecorder.startRecording()
            isRecording = true
            statusText = "Listening…"

            // Observe partial transcript changes
            for await transcript in speechRecorder.$partialTranscript.values {
                self.partialTranscript = transcript
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndProcess() async {
        let transcript = speechRecorder.stopRecording()
        isRecording = false
        partialTranscript = ""

        guard !transcript.isEmpty else {
            statusText = "No speech detected. Tap and hold to speak."
            return
        }

        // Add user message to conversation
        let userMessage = VoiceMessage(
            id: UUID(),
            role: .user,
            content: transcript,
            timestamp: Date()
        )
        messages.append(userMessage)

        // Process through AI
        await processMessage(userMessage)
    }

    func cancelRecording() {
        speechRecorder.cancel()
        isRecording = false
        partialTranscript = ""
        statusText = "Tap and hold to speak"
    }

    // MARK: - Message Processing
    private func processMessage(_ userMessage: VoiceMessage) async {
        isProcessing = true
        statusText = "Processing…"

        // Route to OpenClaw if enabled
        if routeToOpenClaw {
            Task {
                await openClawClient.postVoiceExchange(
                    userMessage: userMessage.content,
                    aiResponse: "[processing]"
                )
            }
        }

        // Get AI response from Claude
        if routeToClaude, let client = claudeClient {
            do {
                let responseText = try await client.send(
                    prompt: userMessage.content,
                    systemPrompt: systemPrompt
                )

                // Add AI response to conversation
                let aiMessage = VoiceMessage(
                    id: UUID(),
                    role: .assistant,
                    content: responseText,
                    timestamp: Date()
                )
                messages.append(aiMessage)

                // Update OpenClaw with actual response
                if routeToOpenClaw {
                    await openClawClient.postVoiceExchange(
                        userMessage: userMessage.content,
                        aiResponse: responseText
                    )
                }

                statusText = "Tap and hold to speak"
            } catch {
                errorMessage = "AI response failed: \(error.localizedDescription)"
                statusText = "Error getting response"
            }
        } else {
            statusText = "Claude API not configured"
        }

        isProcessing = false
    }

    // MARK: - Utilities
    func clearConversation() {
        messages.removeAll()
        statusText = "Tap and hold to speak"
    }

    func dismissError() {
        errorMessage = nil
    }
}

// MARK: - Supporting Types

struct VoiceMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    enum MessageRole {
        case user
        case assistant
    }
}

// Publisher wrapper for observing Combine publishers
extension Publisher where Failure == Never {
    var terminalValues: AsyncStream<Output> {
        AsyncStream { continuation in
            let cancellable = sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                _ = cancellable
            }
        }
    }
}
