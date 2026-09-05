import Foundation
import Combine
import AVFoundation

@MainActor
final class VoiceCompanionViewModel: ObservableObject {
    private static let realtimePrompt = "Tap the mic to join LiveKit realtime voice."
    private static let realtimeTranscriptionWaitingText = "Realtime transcripts will appear when ORCA/LiveKit emits transcription segments."

    // MARK: - Published State
    @Published var messages: [VoiceMessage] = []
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var partialTranscript: String = ""
    @Published var statusText: String = VoiceCompanionViewModel.realtimePrompt
    @Published var errorMessage: String?
    @Published var realtimePackageText: String = "LiveKit package selected; checking ORCA..."
    @Published var realtimeSessionText: String?
    @Published var realtimeTranscriptText: String = VoiceCompanionViewModel.realtimeTranscriptionWaitingText
    @Published var isPreparingRealtimeSession: Bool = false
    @Published var isRealtimeConnected: Bool = false
    /// Live mic state mirrored from LiveKitVoiceConnection — drives the
    /// mute/unmute room control (always-on-mic model, Tony 2026-06-16).
    @Published var isMicEnabled: Bool = false
    @Published var realtimeRemoteParticipantCount: Int = 0
    @Published var realtimeProviderStatus: RealtimeProviderStatus = .checking

    @Published var routeToRealtimePackage: Bool = true

    // MARK: - Dependencies
    private let speechRecorder: SpeechRecorder
    private let agentChatService: AgentChatService?
    private let orcaVoiceClient: OrcaVoiceClient
    private let liveKitConnection: LiveKitVoiceConnection
    private var realtimeParticipantPollTask: Task<Void, Never>?
    private var realtimeStateCancellable: AnyCancellable?
    private var micStateCancellable: AnyCancellable?
    private var partialTranscriptTask: Task<Void, Never>?
    private var realtimeTranscriptMessageIDs: [String: UUID] = [:]
    private var orcaConversationID: String?

    // MARK: - Agent Identity
    let agentSlug: String
    let agentDisplayName: String

    // MARK: - Initialization
    init(agentSlug: String) {
        self.agentSlug = agentSlug
        self.agentDisplayName = Self.displayName(for: agentSlug)
        self.speechRecorder = SpeechRecorder()
        self.agentChatService = AgentInfo.find(agentSlug).map(AgentChatService.init)
        self.orcaVoiceClient = OrcaVoiceClient()
        self.liveKitConnection = LiveKitVoiceConnection()
        self.liveKitConnection.onTranscript = { [weak self] segment in
            Task { @MainActor [weak self] in
                self?.appendRealtimeTranscript(segment)
            }
        }
        self.realtimeStateCancellable = liveKitConnection.$state
            .sink { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.applyRealtimeVoiceState(state)
                }
            }
        self.micStateCancellable = liveKitConnection.$isMicEnabled
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in
                    self?.isMicEnabled = enabled
                }
            }

        Task { await refreshRealtimeProviderStatus() }
    }

    deinit {
        realtimeStateCancellable?.cancel()
        micStateCancellable?.cancel()
        realtimeParticipantPollTask?.cancel()
        partialTranscriptTask?.cancel()
        Task { @MainActor [liveKitConnection] in
            liveKitConnection.onTranscript = nil
            await liveKitConnection.disconnect()
        }
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
            startPartialTranscriptObservation()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndProcess() async {
        stopPartialTranscriptObservation()
        let transcript = speechRecorder.stopRecording()
        isRecording = false
        partialTranscript = ""

        guard !transcript.isEmpty else {
            statusText = "No speech detected. \(Self.realtimePrompt)"
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
        stopPartialTranscriptObservation()
        speechRecorder.cancel()
        isRecording = false
        partialTranscript = ""
        statusText = Self.realtimePrompt
    }

    // MARK: - Realtime Package
    func refreshRealtimeProviderStatus() async {
        realtimeProviderStatus = .checking
        do {
            let providers = try await orcaVoiceClient.fetchVoiceProviders()
            if let liveKit = providers.first(where: { $0.provider == "livekit" }) {
                if liveKit.configured {
                    realtimeProviderStatus = .configured
                    realtimePackageText = "LiveKit package ready: \(liveKit.livekitUrl ?? "configured")"
                } else {
                    realtimeProviderStatus = .needsConfiguration
                    realtimePackageText = "LiveKit package selected; ORCA needs LIVEKIT_URL/API credentials"
                }
            } else {
                realtimeProviderStatus = .unavailable
                realtimePackageText = "No realtime voice package registered in ORCA"
            }
        } catch {
            realtimeProviderStatus = .failed
            realtimePackageText = "Could not read ORCA voice package status"
        }
    }

    func prepareRealtimeSession() async {
        guard routeToRealtimePackage else { return }
        isPreparingRealtimeSession = true
        defer { isPreparingRealtimeSession = false }
        do {
            let session = try await orcaVoiceClient.createLiveKitSession(agentSlug: agentSlug, participantName: "Tony")
            realtimeSessionText = "LiveKit room ready: \(session.roomName)"
            statusText = "Realtime room prepared. Ready to join."
        } catch {
            realtimeSessionText = nil
            errorMessage = "LiveKit session not ready: \(error.localizedDescription)"
            await refreshRealtimeProviderStatus()
        }
    }

    func joinRealtimeVoice() async {
        guard routeToRealtimePackage else { return }
        guard !isPreparingRealtimeSession else { return }
        if liveKitConnection.isConnected {
            applyRealtimeVoiceState(liveKitConnection.state)
            return
        }

        stopRealtimeParticipantStatusPolling()
        isPreparingRealtimeSession = true
        statusText = "Requesting LiveKit voice session..."
        defer { isPreparingRealtimeSession = false }

        do {
            guard await requestRealtimeMicrophoneAccess() else {
                statusText = "Microphone access is required to join LiveKit voice"
                errorMessage = "Microphone access is required to join LiveKit voice. Enable microphone access in Settings."
                return
            }

            try configureRealtimeAudioSession()
            let session = try await orcaVoiceClient.createLiveKitSession(agentSlug: agentSlug, participantName: "Tony")
            realtimeSessionText = "LiveKit room ready: \(session.roomName)"
            realtimeTranscriptText = Self.realtimeTranscriptionWaitingText
            try await liveKitConnection.connect(session: session)
            applyRealtimeVoiceState(liveKitConnection.state)
            startRealtimeParticipantStatusPolling()
        } catch {
            applyRealtimeVoiceState(liveKitConnection.state)
            errorMessage = "LiveKit voice could not join: \(error.localizedDescription)"
            await refreshRealtimeProviderStatus()
        }
    }

    private func requestRealtimeMicrophoneAccess() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted {
            return true
        }
        return await AVAudioApplication.requestRecordPermission()
    }

    private func configureRealtimeAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try audioSession.setActive(true)
    }

    func leaveRealtimeVoice() async {
        stopRealtimeParticipantStatusPolling()
        statusText = "Leaving LiveKit voice..."
        await liveKitConnection.disconnect()
        applyRealtimeVoiceState(liveKitConnection.state)
        statusText = "Realtime voice left"
    }

    func toggleRealtimeVoiceFromPrimaryButton() async {
        if liveKitConnection.isConnected {
            await leaveRealtimeVoice()
        } else {
            await joinRealtimeVoice()
        }
    }

    /// Mute/unmute the live mic while connected (phone-call model). No-op when
    /// not connected — the primary button joins in that state instead.
    func toggleMicMute() async {
        guard liveKitConnection.isConnected else { return }
        await liveKitConnection.setMicrophone(enabled: !isMicEnabled)
    }

    func teardownRealtimeVoice() async {
        stopPartialTranscriptObservation()
        stopRealtimeParticipantStatusPolling()
        if isRecording {
            speechRecorder.cancel()
            isRecording = false
            partialTranscript = ""
        }
        await liveKitConnection.disconnect()
        applyRealtimeVoiceState(liveKitConnection.state)
    }

    private func startRealtimeParticipantStatusPolling() {
        stopRealtimeParticipantStatusPolling()
        realtimeParticipantPollTask = Task { [weak self] in
            while self?.liveKitConnection.isConnected == true {
                guard let self else { return }
                self.realtimeRemoteParticipantCount = self.liveKitConnection.remoteParticipantCount
                let displayText = self.realtimeDisplayText(for: self.liveKitConnection.state)
                self.statusText = displayText
                self.realtimeSessionText = displayText
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopRealtimeParticipantStatusPolling() {
        realtimeParticipantPollTask?.cancel()
        realtimeParticipantPollTask = nil
    }

    private func applyRealtimeVoiceState(_ state: RealtimeVoiceState) {
        let wasConnected = isRealtimeConnected
        let displayText = realtimeDisplayText(for: state)

        isRealtimeConnected = liveKitConnection.isConnected
        realtimeRemoteParticipantCount = liveKitConnection.remoteParticipantCount

        switch state {
        case .disconnected:
            if wasConnected || realtimeSessionText != nil {
                realtimeSessionText = displayText
                statusText = displayText
            }
        case .connecting, .connected, .failed:
            realtimeSessionText = displayText
            statusText = displayText
        }
    }

    private func realtimeDisplayText(for state: RealtimeVoiceState) -> String {
        switch state {
        case .connected(let roomName, let remoteParticipantCount) where remoteParticipantCount == 0:
            return "Connected to \(roomName). Waiting for \(agentDisplayName) worker."
        default:
            return state.displayText
        }
    }

    private func appendRealtimeTranscript(_ segment: RealtimeTranscriptSegment) {
        let content = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        realtimeTranscriptText = segment.isFinal
            ? "Realtime transcript received."
            : "Receiving realtime transcript..."

        let role: VoiceMessage.MessageRole = segment.isAgent ? .assistant : .user
        let messageID = realtimeTranscriptMessageIDs[segment.segmentID] ?? UUID()
        realtimeTranscriptMessageIDs[segment.segmentID] = messageID

        let message = VoiceMessage(
            id: messageID,
            role: role,
            content: content,
            timestamp: segment.timestamp
        )

        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    private func startPartialTranscriptObservation() {
        stopPartialTranscriptObservation()
        partialTranscriptTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await transcript in speechRecorder.$partialTranscript.values {
                if Task.isCancelled { return }
                partialTranscript = transcript
            }
        }
    }

    private func stopPartialTranscriptObservation() {
        partialTranscriptTask?.cancel()
        partialTranscriptTask = nil
    }

    // MARK: - Message Processing
    private func processMessage(_ userMessage: VoiceMessage) async {
        isProcessing = true
        statusText = "Starting \(agentDisplayName) through ORCA…"
        defer { isProcessing = false }

        guard let agentChatService else {
            errorMessage = "\(agentDisplayName) is not registered in the ORCA agent roster."
            statusText = "ORCA agent unavailable"
            return
        }

        let history = messages.dropLast().map { message in
            (
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            )
        }
        let traceID = "pod-voice-\(UUID().uuidString.lowercased())"

        do {
            let stream = await agentChatService.send(
                message: userMessage.content,
                history: history,
                deliveryMode: .auto,
                chatThreadId: orcaConversationID,
                traceId: traceID
            )
            var responseText = ""
            var responseMetadata: AgentChatService.ResponseMetadata?
            for try await chunk in stream {
                responseText += chunk.content
                responseMetadata = chunk.metadata ?? responseMetadata
            }

            let normalizedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedResponse.isEmpty else {
                throw AgentChatService.AgentChatError.noResponse
            }

            if let channelID = responseMetadata?.channelId, !channelID.isEmpty {
                orcaConversationID = channelID
            }
            messages.append(
                VoiceMessage(
                    id: UUID(),
                    role: .assistant,
                    content: normalizedResponse,
                    timestamp: Date()
                )
            )
            statusText = Self.realtimePrompt
        } catch {
            errorMessage = "ORCA voice response failed: \(error.localizedDescription)"
            statusText = "ORCA voice response failed"
        }
    }

    // MARK: - Utilities
    func clearConversation() {
        messages.removeAll()
        orcaConversationID = nil
        statusText = Self.realtimePrompt
    }

    func dismissError() {
        errorMessage = nil
    }

    private static func displayName(for agentSlug: String) -> String {
        if let agent = AgentInfo.find(agentSlug) {
            return agent.name
        }
        return agentSlug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Supporting Types

enum RealtimeProviderStatus: Equatable {
    case checking
    case configured
    case needsConfiguration
    case unavailable
    case failed
}

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
