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

                // Routing toggles
                routingTogglesView

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

    private var voiceButtonView: some View {
        ZStack {
            // Pulse animation when recording
            if viewModel.isRecording {
                Circle()
                    .fill(recordingColor.opacity(0.3))
                    .frame(width: 140, height: 140)
                    .scaleEffect(viewModel.isRecording ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: viewModel.isRecording
                    )
            }

            // Main button
            Circle()
                .fill(viewModel.isRecording ? recordingColor : accentColor)
                .frame(width: 120, height: 120)
                .shadow(color: (viewModel.isRecording ? recordingColor : accentColor).opacity(0.5), radius: 20)

            // Icon
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundColor(.white)

            // Processing overlay
            if viewModel.isProcessing {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 120, height: 120)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !viewModel.isRecording && !viewModel.isProcessing {
                        Task { await viewModel.startRecording() }
                    }
                }
                .onEnded { _ in
                    if viewModel.isRecording {
                        Task { await viewModel.stopRecordingAndProcess() }
                    }
                }
        )
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
            Text(viewModel.realtimeSessionText ?? viewModel.realtimePackageText)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if viewModel.isRealtimeConnected && viewModel.realtimeRemoteParticipantCount == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundColor(.orange)
                    Text("You are in the room. Aloha is offline until the voice worker is started.")
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
            .disabled(!viewModel.routeToRealtimePackage || viewModel.isPreparingRealtimeSession)
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
