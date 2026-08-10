import SwiftUI

struct ConversationView: View {
    @Environment(OrcaMacModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            conversationHeader
            Divider()
            transcript
            Divider()
            composer
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var conversationHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(model.selectedAgent.accent.color.opacity(0.16))
                Image(systemName: model.selectedAgent.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.selectedAgent.accent.color)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedAgent.name)
                    .font(.headline)
                Text(model.selectedAgent.role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if model.isSending {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await model.refreshSelectedConversation() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh conversation")

            Button {
                openSettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Runtime settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.selectedMessages.isEmpty {
                        ContentUnavailableView(
                            model.connectionState == .credentialsRequired
                                ? "ORCA Sign-In Required"
                                : "No Messages",
                            systemImage: model.connectionState == .credentialsRequired
                                ? "key"
                                : "bubble.left.and.bubble.right"
                        )
                        .frame(maxWidth: .infinity, minHeight: 360)
                    } else {
                        ForEach(model.selectedMessages) { message in
                            TranscriptRow(
                                message: message,
                                agent: model.selectedAgent,
                                retry: { Task { await model.retryFailedMessage(message) } }
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .onChange(of: model.selectedMessages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        @Bindable var model = model
        return HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "Message \(model.selectedAgent.name)",
                text: $model.draft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .disabled(!model.connectionState.isReady)
            .onSubmit {
                guard model.canSend else { return }
                Task { await model.sendDraft() }
            }

            Button {
                Task { await model.sendDraft() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.selectedAgent.accent.color)
            .controlSize(.large)
            .disabled(!model.canSend)
            .help("Send message")
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TranscriptRow: View {
    let message: TranscriptMessage
    let agent: AgentProfile
    let retry: () -> Void

    var body: some View {
        if message.role == .system {
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if message.role == .user { Spacer(minLength: 90) }
                if message.role == .agent {
                    Image(systemName: agent.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(agent.accent.color)
                        .frame(width: 24, height: 24)
                        .background(agent.accent.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 7))

                    HStack(spacing: 5) {
                        Text(message.createdAt, style: .time)
                        deliveryIndicator
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if message.role == .agent { Spacer(minLength: 90) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bubbleBackground: Color {
        message.role == .user
            ? Color(red: 0.12, green: 0.43, blue: 0.50)
            : Color(nsColor: .controlBackgroundColor)
    }

    @ViewBuilder
    private var deliveryIndicator: some View {
        switch message.deliveryState {
        case .persisted:
            EmptyView()
        case .pending:
            Image(systemName: "clock")
        case .failed:
            Button(action: retry) {
                Image(systemName: "arrow.clockwise.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.orcaCoral)
            .help("Retry")
        }
    }
}
