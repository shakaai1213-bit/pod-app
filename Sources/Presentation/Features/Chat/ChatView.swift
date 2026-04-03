import SwiftUI

struct ChatView: View {
    // Match ChatViewModel.mockUserId
    private static let currentUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @State private var viewModel = ChatViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if isIPad {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .task {
            await viewModel.loadChannels()
        }
        .task(id: viewModel.selectedChannel?.id) {
            if viewModel.selectedChannel != nil {
                viewModel.startPolling()
            } else {
                viewModel.stopPolling()
            }
        }
        .onDisappear { viewModel.stopPolling() }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar — channel list
                ChannelSidebarView(viewModel: viewModel)
                    .frame(width: 280)
                    .background(AppColors.backgroundSecondary)

                Divider()
                    .background(AppColors.border)

                // Main — message thread
                if let channel = viewModel.selectedChannel {
                    MessageThreadView(channel: channel, viewModel: viewModel)
                } else {
                    EmptyThreadPlaceholder()
                }
            }
        }
        .background(AppColors.backgroundPrimary)
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        NavigationStack {
            ChannelListView(viewModel: viewModel)
        }
        .background(AppColors.backgroundPrimary)
    }
}

// MARK: - Channel Sidebar (iPad)

struct ChannelSidebarView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Channels")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColors.backgroundTertiary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Pinned
                    if !viewModel.pinnedChannels.isEmpty {
                        Section {
                            ForEach(viewModel.pinnedChannels) { channel in
                                ChannelRowView(
                                    channel: channel,
                                    isSelected: viewModel.selectedChannel?.id == channel.id,
                                    onSelect: {
                                        viewModel.selectChannel(channel)
                                        Task { await viewModel.loadMessages(channelId: channel.id) }
                                    },
                                    onMute: { viewModel.toggleMute(channelId: channel.id) }
                                )
                            }
                        } header: {
                            sectionHeader("Pinned")
                        }
                    }

                    // Channels
                    if !viewModel.unpinnedChannels.isEmpty {
                        Section {
                            ForEach(viewModel.unpinnedChannels) { channel in
                                ChannelRowView(
                                    channel: channel,
                                    isSelected: viewModel.selectedChannel?.id == channel.id,
                                    onSelect: {
                                        viewModel.selectChannel(channel)
                                        Task { await viewModel.loadMessages(channelId: channel.id) }
                                    },
                                    onMute: { viewModel.toggleMute(channelId: channel.id) }
                                )
                            }
                        } header: {
                            sectionHeader("Channels")
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .refreshable {
                await viewModel.loadChannels()
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// MARK: - Channel List View (iPhone)

struct ChannelListView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.channels.isEmpty {
                loadingView
            } else {
                if !viewModel.pinnedChannels.isEmpty {
                    Section("Pinned") {
                        ForEach(viewModel.pinnedChannels) { channel in
                            NavigationLink(value: channel) {
                                ChannelListRowContent(channel: channel)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    viewModel.toggleMute(channelId: channel.id)
                                } label: {
                                    Label(
                                        channel.isMuted ? "Unmute" : "Mute",
                                        systemImage: channel.isMuted ? "speaker.wave.2" : "speaker.slash"
                                    )
                                }
                                .tint(AppColors.accentWarning)
                            }
                        }
                    }
                }

                if !viewModel.unpinnedChannels.isEmpty {
                    Section("Channels") {
                        ForEach(viewModel.unpinnedChannels) { channel in
                            NavigationLink(value: channel) {
                                ChannelListRowContent(channel: channel)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    viewModel.toggleMute(channelId: channel.id)
                                } label: {
                                    Label(
                                        channel.isMuted ? "Unmute" : "Mute",
                                        systemImage: channel.isMuted ? "speaker.wave.2" : "speaker.slash"
                                    )
                                }
                                .tint(AppColors.accentWarning)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary)
        .navigationDestination(for: Channel.self) { channel in
            MessageThreadView(channel: channel, viewModel: viewModel)
                .onAppear {
                    viewModel.selectChannel(channel)
                    Task { await viewModel.loadMessages(channelId: channel.id) }
                }
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
        .refreshable {
            await viewModel.loadChannels()
        }
    }

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .tint(AppColors.accentElectric)
            Spacer()
        }
        .listRowBackground(AppColors.backgroundPrimary)
    }
}

// MARK: - Channel Row Content

struct ChannelListRowContent: View {
    let channel: Channel

    var body: some View {
        HStack(spacing: 12) {
            channelIcon
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(channelColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)

                if let preview = channel.lastMessage {
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let ts = channel.lastMessageTimestamp {
                    Text(ts.relativeTimeString)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }

                if channel.unreadCount > 0 && !channel.isMuted {
                    Circle()
                        .fill(AppColors.accentElectric)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(AppColors.backgroundSecondary)
    }

    @ViewBuilder
    private var channelIcon: some View {
        switch channel.type {
        case .general:
            Text("#")
        case .projects:
            Image(systemName: "folder")
        case .agents:
            Image(systemName: "cpu")
        case .research:
            Image(systemName: "magnifyingglass")
        case .alerts:
            Image(systemName: "bell")
        }
    }

    private var channelColor: Color {
        switch channel.type {
        case .general:  return AppColors.textSecondary
        case .projects: return AppColors.accentElectric
        case .agents:   return AppColors.accentAgent
        case .research: return AppColors.accentSuccess
        case .alerts:   return AppColors.accentDanger
        }
    }
}

// MARK: - Channel Row (iPad sidebar swipe)

struct ChannelRowView: View {
    let channel: Channel
    let isSelected: Bool
    let onSelect: () -> Void
    let onMute: () -> Void

    @State private var offsetX: CGFloat = 0
    @State private var showMuteAction = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Swipe background
            HStack {
                Spacer()
                Button(action: onMute) {
                    Image(systemName: channel.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 44)
                }
                .background(AppColors.accentWarning)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Foreground row
            HStack(spacing: 12) {
                channelIcon
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(channelColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)

                    if let preview = channel.lastMessage {
                        Text(preview)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let ts = channel.lastMessageTimestamp {
                        Text(ts.relativeTimeString)
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }

                    HStack(spacing: 4) {
                        if channel.unreadCount > 0 && !channel.isMuted {
                            Text("\(channel.unreadCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AppColors.accentElectric)
                                .clipShape(Capsule())
                        }

                        if channel.isMuted {
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 8))
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.accentElectric.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppColors.accentElectric.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .offset(x: offsetX)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offsetX = max(value.translation.width, -80)
                        } else {
                            offsetX = min(max(0, value.translation.width - 80), 0)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if value.translation.width < -40 {
                                offsetX = -80
                            } else {
                                offsetX = 0
                            }
                        }
                    }
            )
            .onTapGesture {
                if offsetX != 0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offsetX = 0
                    }
                } else {
                    onSelect()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var channelIcon: some View {
        switch channel.type {
        case .general:
            Text("#")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(channelColor)
                .frame(width: 24)
        case .projects:
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(channelColor)
                .frame(width: 24)
        case .agents:
            Image(systemName: "cpu")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(channelColor)
                .frame(width: 24)
        case .research:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(channelColor)
                .frame(width: 24)
        case .alerts:
            Image(systemName: "bell")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(channelColor)
                .frame(width: 24)
        }
    }

    private var channelColor: Color {
        switch channel.type {
        case .general:  return AppColors.textSecondary
        case .projects: return AppColors.accentElectric
        case .agents:   return AppColors.accentAgent
        case .research: return AppColors.accentSuccess
        case .alerts:   return AppColors.accentDanger
        }
    }
}

// MARK: - Message Thread View

struct MessageThreadView: View {
    let channel: Channel
    @Bindable var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Thread header
            threadHeader

            Divider()
                .background(AppColors.border)

            // Messages
            if viewModel.isLoading && viewModel.messages.isEmpty {
                loadingView
            } else if viewModel.messages.isEmpty {
                emptyThreadView
            } else {
                messageListView
            }

            Divider()
                .background(AppColors.border)

            // Compose bar
            ComposeBarView(
                channelId: channel.id.uuidString,
                isSending: viewModel.isSending,
                typingUsers: viewModel.typingUsers,
                replyingTo: viewModel.replyingTo,
                onSend: { content, replyToId in
                    Task {
                        await viewModel.sendMessage(channelId: channel.id, content: content, replyToId: replyToId ?? viewModel.replyingTo?.id)
                        viewModel.replyingTo = nil
                    }
                },
                onCancelReply: {
                    viewModel.replyingTo = nil
                }
            )
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle(channel.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var threadHeader: some View {
        HStack(spacing: 8) {
            headerIcon
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(headerIconColor)

            Text("#\(channel.displayName)")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            // SSE connection indicator
            sseIndicator

            Spacer()

            if viewModel.highlightedAuthorId != nil {
                Button {
                    viewModel.clearHighlight()
                } label: {
                    HStack(spacing: 4) {
                        Text("Clear highlight")
                            .font(.caption)
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .foregroundColor(AppColors.accentAgent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.accentAgent.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.backgroundTertiary)
    }

    private var sseIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(viewModel.isSSEConnected ? AppColors.accentSuccess : AppColors.accentDanger)
                .frame(width: 6, height: 6)
                .overlay {
                    if viewModel.isSSEConnected {
                        Circle()
                            .stroke(AppColors.accentSuccess.opacity(0.4), lineWidth: 2)
                            .scaleEffect(1.8)
                    }
                }

            Text(viewModel.isSSEConnected ? "LIVE" : "OFFLINE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(viewModel.isSSEConnected ? AppColors.accentSuccess : AppColors.accentDanger)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            (viewModel.isSSEConnected ? AppColors.accentSuccess : AppColors.accentDanger)
                .opacity(0.12)
        )
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var headerIcon: some View {
        switch channel.type {
        case .general:
            Text("#")
        case .projects:
            Image(systemName: "folder")
        case .agents:
            Image(systemName: "cpu")
        case .research:
            Image(systemName: "magnifyingglass")
        case .alerts:
            Image(systemName: "bell")
        }
    }

    private var headerIconColor: Color {
        switch channel.type {
        case .general:  return AppColors.textSecondary
        case .projects: return AppColors.accentElectric
        case .agents:   return AppColors.accentAgent
        case .research: return AppColors.accentSuccess
        case .alerts:   return AppColors.accentDanger
        }
    }

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Pull to load more indicator
                    if !viewModel.messages.isEmpty {
                        pullToLoadHint
                    }

                    ForEach(viewModel.groupedMessages(viewModel.messages)) { group in
                        // Date separator
                        dateSeparator(for: group.date)

                        ForEach(Array(group.messages.enumerated()), id: \.element.id) { index, message in
                            let showAvatar = shouldShowAvatar(message, at: index, in: group.messages)

                            MessageBubbleView(
                                message: message,
                                showAvatar: showAvatar,
                                isCurrentUser: message.authorId == ChatViewModel.mockUserId,
                                onAgentTapped: {
                                    if message.authorRole == .agent {
                                        viewModel.highlightAgent(authorId: message.authorId)
                                    }
                                },
                                onAddReaction: { emoji in
                                    viewModel.addReaction(to: message.id, emoji: emoji)
                                },
                                onReply: { repliedTo in
                                    viewModel.replyingTo = repliedTo
                                }
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .refreshable {
                await viewModel.loadMessages(channelId: channel.id)
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: viewModel.messages.count) {
                // Auto-scroll to bottom on new messages
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var pullToLoadHint: some View {
        HStack {
            Spacer()
            Text("Pull to load more")
                .font(.caption)
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func dateSeparator(for date: Date) -> some View {
        HStack {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
            Text(date.groupDateString)
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 8)
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func shouldShowAvatar(_ message: Message, at index: Int, in messages: [Message]) -> Bool {
        // Always show avatar for system messages
        if message.authorRole == .system { return false }

        // Show avatar for first message in group
        if index == 0 { return true }

        // Show avatar if previous message is from different author
        let previous = messages[index - 1]
        return previous.authorId != message.authorId
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(AppColors.accentElectric)
            Spacer()
        }
    }

    private var emptyThreadView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)
            Text("No messages yet")
                .font(.headline)
                .foregroundColor(AppColors.textSecondary)
            Text("Be the first to say something in #\(channel.displayName)")
                .font(.subheadline)
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Empty Thread Placeholder (iPad when no channel selected)

struct EmptyThreadPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundColor(AppColors.textTertiary)
            Text("Select a channel")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textSecondary)
            Text("Choose a channel from the sidebar to start chatting")
                .font(.subheadline)
                .foregroundColor(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
    }
}

// MARK: - Preview

#Preview {
    ChatView()
        .preferredColorScheme(.dark)
}
