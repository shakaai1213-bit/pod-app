import SwiftUI
import SwiftData

struct DirectChatView: View {
    @Bindable var viewModel: DirectChatViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            agentListSidebar
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
    }

    // MARK: - Agent List Sidebar

    private var agentListSidebar: some View {
        List(AgentInfo.team) { agent in
            NavigationLink(value: agent) {
                AgentRowView(agent: agent, viewModel: viewModel)
            }
            .listRowBackground(
                viewModel.selectedAgent?.id == agent.id
                ? AppColors.accentElectric.opacity(0.15)
                : Color.clear
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: AgentInfo.self) { agent in
            ConversationView(viewModel: viewModel, agent: agent)
                .onAppear { viewModel.selectAgent(agent) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)
            Text("Select an agent to start chatting")
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
    }
}

// MARK: - Agent Row

struct AgentRowView: View {
    let agent: AgentInfo
    let viewModel: DirectChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Agent avatar
            ZStack {
                Circle()
                    .fill(Color(hexString: agent.color).opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: agent.icon)
                    .font(.system(size: 18))
                    .foregroundColor(Color(hexString: agent.color))
            }

            // Name + last message
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(agent.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    if let date = viewModel.lastMessagePreview(for: agent).date {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                HStack {
                    Text(agent.role)
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    let unread = viewModel.unreadCount(for: agent)
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.accentElectric)
                            .clipShape(Capsule())
                    }
                }

                Text(viewModel.lastMessagePreview(for: agent).text)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Conversation View

struct ConversationView: View {
    let viewModel: DirectChatViewModel
    let agent: AgentInfo

    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var isTextFieldFocused: Bool
    // Padding to keep compose bar above the floating tab bar on iPhone.
    // Cleared when keyboard appears (tab bar also hides at that point).
    @State private var tabBarPadding: CGFloat = 83

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.currentMessages, id: \.id) { message in
                            DMBubble(message: message, agent: agent)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.currentMessages.count) { _, _ in
                    if let last = viewModel.currentMessages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    if let last = viewModel.currentMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(AppColors.backgroundPrimary)

            // Error bar
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.accentDanger)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppColors.accentDanger)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.accentDanger.opacity(0.1))
            }

            // Compose bar
            composeBar
        }
        .padding(.bottom, sizeClass == .compact ? tabBarPadding : 0)
        .background(AppColors.backgroundPrimary)
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { tabBarPadding = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { tabBarPadding = 83 }
        }
        .toolbarBackground(AppColors.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: agent.icon)
                        .foregroundColor(Color(hexString: agent.color))
                    Text(agent.name)
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                    Text(agent.role)
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: 10) {
            TextField("Message \(agent.name)...", text: Binding(
                get: { viewModel.composedMessage },
                set: { viewModel.composedMessage = $0 }
            ), axis: .vertical)
                .focused($isTextFieldFocused)
                .textFieldStyle(.plain)
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppColors.backgroundTertiary)
                .cornerRadius(20)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit {
                    viewModel.sendMessage()
                }

            Button {
                viewModel.sendMessage()
            } label: {
                Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(
                        viewModel.composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming
                        ? AppColors.textTertiary
                        : AppColors.accentElectric
                    )
            }
            .disabled(viewModel.composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

// MARK: - Message Bubble

struct DMBubble: View {
    let message: DMMessage
    let agent: AgentInfo

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                // Agent avatar
                ZStack {
                    Circle()
                        .fill(Color(hexString: agent.color).opacity(0.2))
                        .frame(width: 30, height: 30)
                    Image(systemName: agent.icon)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hexString: agent.color))
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.content.isEmpty && message.isStreaming ? "Thinking..." : message.content)
                    .font(.body)
                    .foregroundColor(isUser ? .white : AppColors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isUser
                        ? AppColors.accentElectric
                        : AppColors.backgroundTertiary
                    )
                    .cornerRadius(18)
                    .opacity(message.isStreaming && message.content.isEmpty ? 0.6 : 1)

                // Streaming indicator
                if message.isStreaming && !message.content.isEmpty {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Streaming...")
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                // Metadata (latency)
                if let ms = message.latencyMs, !message.isStreaming {
                    Text("\(ms)ms")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Preview

#Preview {
    DirectChatView(viewModel: DirectChatViewModel())
        .modelContainer(for: [DMConversation.self, DMMessage.self], inMemory: true)
}
