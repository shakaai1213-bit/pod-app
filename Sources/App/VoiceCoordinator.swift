import Combine
import Foundation

@MainActor
final class VoiceCoordinator: ObservableObject {
    @Published private(set) var viewModel: VoiceCompanionViewModel
    @Published var isConnected: Bool = false
    @Published var isActive: Bool = false
    @Published var activeAgentSlug: String
    @Published var statusText: String = "Tap the mic to join LiveKit realtime voice."

    private var viewModelCancellable: AnyCancellable?

    init(initialAgentSlug: String = AgentRosterPolicy.activeDisplayOrder.first ?? "maui") {
        self.activeAgentSlug = initialAgentSlug
        self.viewModel = VoiceCompanionViewModel(agentSlug: initialAgentSlug)
        bindViewModel()
        syncFromViewModel()
    }

    func connect(agentSlug: String) async {
        let requestedAgentSlug = agentSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedAgentSlug.isEmpty else {
            statusText = "Choose an agent before joining voice."
            return
        }

        if isActive && activeAgentSlug != requestedAgentSlug {
            await disconnect()
        }

        if viewModel.agentSlug != requestedAgentSlug {
            await viewModel.teardownRealtimeVoice()
            activeAgentSlug = requestedAgentSlug
            viewModel = VoiceCompanionViewModel(agentSlug: requestedAgentSlug)
            bindViewModel()
        } else {
            activeAgentSlug = requestedAgentSlug
        }

        await viewModel.joinRealtimeVoice()
        syncFromViewModel()
    }

    func disconnect() async {
        await viewModel.teardownRealtimeVoice()
        syncFromViewModel()
    }

    var realtimeProviderStatus: RealtimeProviderStatus {
        viewModel.realtimeProviderStatus
    }

    var realtimePackageText: String {
        viewModel.realtimePackageText
    }

    var realtimeSessionText: String? {
        viewModel.realtimeSessionText
    }

    var realtimeTranscriptText: String {
        viewModel.realtimeTranscriptText
    }

    var isPreparingRealtimeSession: Bool {
        viewModel.isPreparingRealtimeSession
    }

    var isRealtimeConnected: Bool {
        viewModel.isRealtimeConnected
    }

    var isMicEnabled: Bool {
        viewModel.isMicEnabled
    }

    var realtimeRemoteParticipantCount: Int {
        viewModel.realtimeRemoteParticipantCount
    }

    var activeAgentDisplayName: String {
        displayName(for: activeAgentSlug)
    }

    private func bindViewModel() {
        viewModelCancellable = viewModel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncFromViewModel()
                self?.objectWillChange.send()
            }
        }
    }

    private func syncFromViewModel() {
        isConnected = viewModel.isRealtimeConnected
        isActive = viewModel.isRealtimeConnected
        statusText = viewModel.statusText
    }

    private func displayName(for agentSlug: String) -> String {
        if let agent = AgentInfo.find(agentSlug) {
            return agent.name
        }
        return agentSlug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
