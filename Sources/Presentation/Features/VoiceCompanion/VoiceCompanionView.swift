import SwiftUI

struct VoiceCompanionView: View {
    @ObservedObject var viewModel: VoiceCompanionViewModel

    // Colors from app theme
    private let backgroundColor = Color(hex: "0A0A0F")
    private let userBubbleColor = Color(hex: "1E293B")
    private let assistantBubbleColor = Color(hex: "1D4ED8")
    private let accentColor = Color(hex: "3B82F6")
    private let recordingColor = Color.red

    var body: some View {
        ZStack {
            // Background
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                // Messages
                messageListView

                // Partial transcript (while recording)
                if viewModel.isRecording && !viewModel.partialTranscript.isEmpty {
                    partialTranscriptView
                }

                // Status text
                statusView

                Spacer()

                // Voice button
                voiceButtonView

                realtimePackageView
            }
            .padding(.bottom, 20)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Text("Voice")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()

            Button {
                viewModel.clearConversation()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var partialTranscriptView: some View {
        Text(viewModel.partialTranscript)
            .font(.subheadline)
            .italic()
            .foregroundColor(.gray)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    private var statusView: some View {
        Text(viewModel.statusText)
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.vertical, 8)
    }

    // Always-on-mic + mute-toggle room control (Tony 2026-06-16; push-to-talk
    // retired). Disconnected: primary button joins. Connected: primary button
    // mutes/unmutes the live mic; a separate End button leaves the call.
    private var voiceButtonView: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    if viewModel.isRealtimeConnected {
                        await viewModel.toggleMicMute()
                    } else {
                        await viewModel.toggleRealtimeVoiceFromPrimaryButton()
                    }
                }
            } label: {
                ZStack {
                    if viewModel.isRealtimeConnected && viewModel.isMicEnabled {
                        Circle()
                            .fill(recordingColor.opacity(0.3))
                            .frame(width: 140, height: 140)
                            .scaleEffect(1.1)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: viewModel.isMicEnabled
                            )
                    }

                    Circle()
                        .fill(micButtonColor)
                        .frame(width: 120, height: 120)
                        .shadow(color: micButtonColor.opacity(0.5), radius: 20)

                    Image(systemName: micButtonIcon)
                        .font(.system(size: 40))
                        .foregroundColor(.white)

                    if viewModel.isPreparingRealtimeSession || viewModel.isProcessing {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 120, height: 120)

                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPreparingRealtimeSession || viewModel.isProcessing)
            .accessibilityLabel(micButtonAccessibilityLabel)

            if viewModel.isRealtimeConnected {
                Button {
                    Task { await viewModel.leaveRealtimeVoice() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.down.fill")
                        Text("End")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End voice call")
            }
        }
    }

    private var micButtonColor: Color {
        guard viewModel.isRealtimeConnected else { return accentColor }
        return viewModel.isMicEnabled ? recordingColor : Color.gray
    }

    private var micButtonIcon: String {
        guard viewModel.isRealtimeConnected else { return "mic.fill" }
        return viewModel.isMicEnabled ? "mic.fill" : "mic.slash.fill"
    }

    private var micButtonAccessibilityLabel: String {
        guard viewModel.isRealtimeConnected else { return "Join voice call" }
        return viewModel.isMicEnabled ? "Mute microphone" : "Unmute microphone"
    }

    private var routingTogglesView: some View {
        HStack(spacing: 16) {
            // Claude toggle
            Button {
                viewModel.routeToClaude.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.routeToClaude ? accentColor : Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("Claude")
                        .font(.caption)
                        .foregroundColor(viewModel.routeToClaude ? .white : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(viewModel.routeToClaude ? accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                )
            }

            // OpenClaw toggle
            Button {
                viewModel.routeToOpenClaw.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.routeToOpenClaw ? accentColor : Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("OpenClaw")
                        .font(.caption)
                        .foregroundColor(viewModel.routeToOpenClaw ? .white : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(viewModel.routeToOpenClaw ? accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                )
            }

            Button {
                viewModel.routeToRealtimePackage.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.routeToRealtimePackage ? accentColor : Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("LiveKit")
                        .font(.caption)
                        .foregroundColor(viewModel.routeToRealtimePackage ? .white : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(viewModel.routeToRealtimePackage ? accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                )
            }
        }
        .padding(.top, 20)
    }

    private var realtimePackageView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wave.3.right.circle")
                    .foregroundColor(accentColor)
                Text("LiveKit realtime room")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.82))
            }
            .accessibilityElement(children: .combine)

            Text(viewModel.realtimeSessionText ?? viewModel.realtimePackageText)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if viewModel.isRealtimeConnected {
                Text(viewModel.realtimeTranscriptText)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            if viewModel.isRealtimeConnected && viewModel.realtimeRemoteParticipantCount == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundColor(.orange)
                    Text("You are in the room. \(viewModel.agentDisplayName) is offline until the voice worker is started.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.orange.opacity(0.12))
                )
                .padding(.horizontal, 20)
            }

            Button {
                Task {
                    if viewModel.isRealtimeConnected {
                        await viewModel.leaveRealtimeVoice()
                    } else {
                        await viewModel.joinRealtimeVoice()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isPreparingRealtimeSession {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: viewModel.isRealtimeConnected ? "phone.down.circle" : "wave.3.right.circle")
                    }
                    Text(viewModel.isRealtimeConnected ? "Leave Voice Room" : "Join Voice Room")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accentColor.opacity(viewModel.routeToRealtimePackage ? 0.35 : 0.12))
                )
            }
            .disabled(viewModel.isPreparingRealtimeSession)
        }
        .padding(.top, 12)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: VoiceMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            Text(message.content)
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(message.role == .user
                            ? Color(hex: "1E293B")
                            : Color(hex: "1D4ED8"))
                )

            if message.role == .assistant { Spacer() }
        }
    }
}
