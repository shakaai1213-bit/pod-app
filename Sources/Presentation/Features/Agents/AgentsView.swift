import SwiftUI

// MARK: - Agents View

struct AgentsView: View {

    @State private var viewModel = AgentsViewModel()
    @State private var searchText: String = ""
    @State private var selectedAgent: Agent?
    @State private var showingLogStream: Agent?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    onlineAgentsSection
                    allAgentsSection
                }
                .padding(.horizontal, Theme.md)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Agents")
            .toolbar {
                toolbarContent
            }
            .searchable(text: $searchText, prompt: "Search agents…")
            .refreshable {
                await viewModel.loadAgents()
            }
            .sheet(item: $selectedAgent) { agent in
                AgentDetailSheet(
                    agent: agent,
                    onViewLogs: { showingLogStream = agent },
                    onStatusChanged: { newStatus in
                        Task {
                            await viewModel.updateAgentState(agent.id, newStatus)
                        }
                    },
                    onPause: {
                        Task { await viewModel.pauseAgent(agent.id) }
                    },
                    onRestart: {
                        Task { await viewModel.restartAgent(agent.id) }
                    }
                )
            }
            .fullScreenCover(item: $showingLogStream) { agent in
                LogStreamView(agent: agent)
            }
            .task {
                await viewModel.loadAgents()
                viewModel.subscribeToAgentState()
            }
            .onDisappear {
                viewModel.disconnectSSE()
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if viewModel.isLoading {
                ProgressView()
                    .tint(AppColors.accentElectric)
            } else {
                onlineCountBadge
            }
        }
    }

    private var onlineCountBadge: some View {
        HStack(spacing: Theme.xxs) {
            Circle()
                .fill(AppColors.accentSuccess)
                .frame(width: 8, height: 8)

            Text("\(viewModel.onlineCount)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.accentSuccess)
        }
        .padding(.horizontal, Theme.sm)
        .padding(.vertical, Theme.xxs)
        .background(AppColors.accentSuccess.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Online Agents Section

    private var onlineAgentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionHeader("Online", count: viewModel.onlineCount)

            if viewModel.isLoading {
                loadingCardRow
            } else if viewModel.onlineAgents.isEmpty {
                emptyOnlineView
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.sm) {
                        ForEach(viewModel.onlineAgents) { agent in
                            CompactAgentCard(agent: agent) {
                                selectedAgent = agent
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, Theme.md)
    }

    private var loadingCardRow: some View {
        HStack(spacing: Theme.sm) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(AppColors.backgroundTertiary)
                    .frame(width: 160, height: 100)
                    .shimmer()
            }
        }
    }

    private var emptyOnlineView: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 20))
                .foregroundStyle(AppColors.textTertiary)

            Text("No agents currently online")
                .podTextStyle(.body, color: AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.lg)
        .podCard()
    }

    // MARK: - All Agents Section

    private var allAgentsSection: some View {
        let filtered = viewModel.agents(matching: searchText)
        let grouped = Dictionary(grouping: filtered) { $0.status }

        return VStack(alignment: .leading, spacing: Theme.md) {
            sectionHeader("All Agents", count: filtered.count)

            if viewModel.isLoading && viewModel.agents.isEmpty {
                loadingListView
            } else if filtered.isEmpty {
                emptySearchView
            } else {
                ForEach(AgentState.displayOrder, id: \.self) { status in
                    if let agents = grouped[status], !agents.isEmpty {
                        statusSection(status: status, agents: agents)
                    }
                }
            }
        }
    }

    private func statusSection(status: AgentState, agents: [Agent]) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            statusHeader(status)

            VStack(spacing: 0) {
                ForEach(agents) { agent in
                    AgentRow(agent: agent) {
                        selectedAgent = agent
                    }

                    if agent.id != agents.last?.id {
                        Divider()
                            .background(AppColors.border)
                    }
                }
            }
            .podCard()
        }
    }

    private func statusHeader(_ status: AgentState) -> some View {
        HStack(spacing: Theme.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            Text(status.displayName.uppercased())
                .podTextStyle(.label, color: AppColors.textTertiary)

            Text("\(agentsForStatus(status).count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.backgroundTertiary)
                .clipShape(Capsule())
        }
    }

    private func agentsForStatus(_ status: AgentState) -> [Agent] {
        viewModel.agents.filter { $0.status == status }
    }

    private var loadingListView: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: Theme.sm) {
                    Circle()
                        .fill(AppColors.backgroundTertiary)
                        .frame(width: 44, height: 44)
                        .shimmer()

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.backgroundTertiary)
                            .frame(width: 100, height: 14)
                            .shimmer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.backgroundTertiary)
                            .frame(width: 60, height: 10)
                            .shimmer()
                    }

                    Spacer()
                }
                .padding(Theme.md)

                Divider()
                    .background(AppColors.border)
            }
        }
        .podCard()
    }

    private var emptySearchView: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(AppColors.textTertiary)

            Text("No agents match \"\(searchText)\"")
                .podTextStyle(.body, color: AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.lg)
        .podCard()
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: Theme.xs) {
            Text(title.uppercased())
                .podTextStyle(.label, color: AppColors.textTertiary)

            if let count = count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Agent Status Extension

extension AgentState {
    var color: Color {
        switch self {
        case .online: return AppColors.accentSuccess
        case .busy:   return AppColors.accentWarning
        case .idle:   return AppColors.textTertiary
        case .offline: return AppColors.textMuted
        case .error:  return AppColors.accentDanger
        }
    }

    /// Display order for section grouping
    static var displayOrder: [AgentState] {
        [.online, .busy, .idle, .error, .offline]
    }
}

// MARK: - Compact Agent Card

struct CompactAgentCard: View {
    let agent: Agent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap, label: compactLabel)
            .buttonStyle(.plain)
    }

    private func compactLabel() -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            HStack(spacing: Theme.xs) {
                AgentAvatar(agent: agent, size: 40)
                Spacer()
                statusDot
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .podTextStyle(.headline, color: AppColors.textPrimary)
                    .lineLimit(1)

                Text(agent.role)
                    .podTextStyle(.caption, color: AppColors.textSecondary)
                    .lineLimit(1)
            }

            if let task = agent.currentTask {
                Text(task)
                    .podTextStyle(.caption, color: AppColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.sm)
        .frame(width: 160)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private var statusDot: some View {
        Circle()
            .fill(agent.status.color)
            .frame(width: 10, height: 10)
    }
}

// MARK: - Agent Row

struct AgentRow: View {
    let agent: Agent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap, label: rowContent)
            .buttonStyle(.plain)
    }

    private func rowContent() -> some View {
        HStack(spacing: Theme.sm) {
            AgentAvatar(agent: agent, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .podTextStyle(.headline, color: AppColors.textPrimary)
                    .lineLimit(1)

                Text(agent.role)
                    .podTextStyle(.caption, color: AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if let task = agent.currentTask {
                Text(task)
                    .podTextStyle(.caption, color: AppColors.textTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Circle()
                    .fill(agent.status.color)
                    .frame(width: 8, height: 8)

                Text((agent.lastActivity ?? Date()).relativeFormatted)
                    .podTextStyle(.caption, color: AppColors.textTertiary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textMuted)
        }
        .padding(Theme.md)
    }
}

// MARK: - Avatar View

private struct AgentAvatar: View {
    let agent: Agent
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hexString: agent.avatarColor ?? "#6B46C1").opacity(0.2))
                .frame(width: size, height: size)

            Circle()
                .fill(Color(hexString: agent.avatarColor ?? "#6B46C1"))
                .frame(width: size, height: size)

            Text(agent.name.prefix(1).uppercased())
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Date Relative Formatting

extension Date {
    var relativeFormatted: String {
        let seconds = Int(-timeIntervalSinceNow)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let mins = seconds / 60
            return "\(mins)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            return "\(days)d ago"
        }
    }
}
