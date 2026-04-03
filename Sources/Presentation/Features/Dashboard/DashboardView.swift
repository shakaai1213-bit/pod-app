import SwiftUI

// MARK: - Dashboard View

struct DashboardView: View {

    @Environment(\.appState) private var appState: AppState
    @State private var viewModel = DashboardViewModel()
    @State private var selectedAgent: Agent?
    @State private var showingSettings = false
    @State private var showingSearch = false
    @State private var showingScanSheet = false
    @AppStorage("orca_display_name") private var displayName: String = "Captain"

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    headerSection
                    metricsStrip
                    agentStatusStrip
                    thisMorningSection
                    needsAttentionSection
                    quickActionsSection
                }
                .padding(.horizontal, Theme.md)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .refreshable {
                await viewModel.loadDashboard()
            }
            .sheet(item: $selectedAgent) { agent in
                AgentDetailSheet(agent: agent)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingSearch) {
                SearchSheet()
            }
            .sheet(isPresented: $showingScanSheet) {
                ScanSheet()
            }
            .task {
                await viewModel.loadDashboard()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .podTextStyle(.title1, color: AppColors.textPrimary)

                Text(formattedDate)
                    .podTextStyle(.body, color: AppColors.textSecondary)
            }

            Spacer()

            // Live connection badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("LIVE")
                    .font(.caption2.bold())
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.15))
            .clipShape(Capsule())

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.top, Theme.md)
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.md)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    AppColors.backgroundSecondary.opacity(0.8),
                    AppColors.backgroundPrimary
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }

    // MARK: - Metrics Strip

    private var metricsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.sm) {
                MetricCard(
                    value: viewModel.activeProjectsCount,
                    label: "Active Projects",
                    color: AppColors.accentElectric
                )

                MetricCard(
                    value: viewModel.inProgressCount,
                    label: "In Progress",
                    color: AppColors.accentWarning
                )

                MetricCard(
                    value: viewModel.agentsOnlineCount,
                    label: "Agents Online",
                    color: AppColors.accentSuccess
                )

                MetricCard(
                    value: viewModel.needsReviewCount,
                    label: "Needs Review",
                    color: AppColors.accentDanger
                )
            }
        }
    }

    // MARK: - Agent Status Strip

    private var agentStatusStrip: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionHeader("Agent Status", count: viewModel.agents.count)

            if viewModel.isLoading {
                loadingAgentsView
            } else if viewModel.agents.isEmpty {
                emptyAgentsView
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.sm) {
                        ForEach(viewModel.agents) { agent in
                            AgentStatusCard(agent: agent) {
                                selectedAgent = agent
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - This Morning Section

    private var thisMorningSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionHeader("This Morning", count: viewModel.activities.count)

            VStack(spacing: 0) {
                if viewModel.activities.isEmpty {
                    emptyActivitiesView
                } else {
                    ForEach(viewModel.activities) { item in
                        ActivityItemView(item: item)
                        if item.id != viewModel.activities.last?.id {
                            Divider()
                                .background(AppColors.border)
                        }
                    }
                }
            }
            .podCard()
        }
    }

    // MARK: - Needs Attention Section

    private var needsAttentionSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                sectionHeader("Needs Attention", count: viewModel.attentionItems.count)

                if !viewModel.attentionItems.isEmpty {
                    Circle()
                        .fill(AppColors.accentDanger)
                        .frame(width: 8, height: 8)
                }

                Spacer(minLength: 0)
            }

            if viewModel.attentionItems.isEmpty {
                emptyAttentionView
            } else {
                VStack(spacing: Theme.xs) {
                    ForEach(viewModel.attentionItems) { item in
                        AttentionItemRow(item: item)
                    }
                }
                .podCard()
            }
        }
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionHeader("Quick Actions")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.sm) {
                QuickActionButton(
                    icon: "plus.circle.fill",
                    label: "New Task",
                    color: AppColors.accentSuccess
                ) {
                    appState.navigateTo(.projects)
                }

                QuickActionButton(
                    icon: "bubble.left.fill",
                    label: "New Message",
                    color: AppColors.accentElectric
                ) {
                    appState.navigateTo(.chat)
                }

                QuickActionButton(
                    icon: "magnifyingglass",
                    label: "Search",
                    color: AppColors.accentWarning
                ) {
                    showingSearch = true
                }

                QuickActionButton(
                    icon: "doc.text.viewfinder",
                    label: "Scan",
                    color: AppColors.accentAgent
                ) {
                    showingScanSheet = true
                }
            }
        }
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

    // MARK: - Empty States

    private var loadingAgentsView: some View {
        HStack(spacing: Theme.sm) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(AppColors.backgroundTertiary)
                    .frame(width: 200, height: 64)
                    .shimmer()
            }
        }
    }

    private var emptyAgentsView: some View {
        Text("No agents available")
            .podTextStyle(.body, color: AppColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Theme.lg)
            .podCard()
    }

    private var emptyActivitiesView: some View {
        Text("No recent activity")
            .podTextStyle(.body, color: AppColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Theme.lg)
    }

    private var emptyAttentionView: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(AppColors.accentSuccess)

            Text("All clear. Your team is humming.")
                .podTextStyle(.body, color: AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.accentSuccess.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = displayName.isEmpty ? "Captain" : displayName
        switch hour {
        case 5..<12:  return "Good morning, \(name)"
        case 12..<17: return "Good afternoon, \(name)"
        case 17..<21: return "Good evening, \(name)"
        default:       return "Good night, \(name)"
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
}

// MARK: - Attention Item Row

struct AttentionItemRow: View {
    let item: AttentionItem

    var body: some View {
        HStack(spacing: Theme.sm) {
            ZStack {
                Circle()
                    .fill(item.type.iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: item.type.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.type.iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .podTextStyle(.headline, color: AppColors.textPrimary)
                    .lineLimit(1)

                if !item.actor.isEmpty {
                    Text(item.actor)
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if item.severity == .critical {
                Circle()
                    .fill(AppColors.accentDanger)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: Theme.sm) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                }

                Text(label)
                    .podTextStyle(.caption, color: AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.md)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: Theme.sm) {
            Rectangle()
                .fill(color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(label)
                    .podTextStyle(.caption, color: AppColors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.sm)
        .frame(width: 140)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }
}
