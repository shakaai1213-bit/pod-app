import SwiftUI

// MARK: - Dashboard View

struct DashboardView: View {

    @EnvironmentObject private var appState: AppState
    @State private var viewModel = DashboardViewModel()
    @State private var selectedAgent: Agent?
    @State private var showingSettings = false
    @AppStorage("orca_display_name") private var displayName: String = "Captain"

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    headerSection
                    // Partial-load error banner — surfaces when any dashboard section fails
                    if let err = viewModel.error, !err.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.accentWarning)
                                .font(.caption)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                Task { await viewModel.loadDashboard() }
                            } label: {
                                Text("Retry")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(AppColors.accentElectric)
                            }
                        }
                        .padding(10)
                        .background(AppColors.accentWarning.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                .strokeBorder(AppColors.accentWarning.opacity(0.3), lineWidth: 0.5)
                        )
                    }
                    // Cockpit Tier 1 — sign queue. The "what needs your eyes" surface.
                    CockpitSignQueueSection()

                    flowReviewSection
                    metricsStrip
                    startupTruthSection
                    liveStateSection
                    chiefProtectionSection
                    agentStatusStrip
                    needsAttentionSection
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
            .task {
                await viewModel.loadDashboard()
            }
            .task {
                await viewModel.startFlowReviewPolling()
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

    private var flowReviewSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FLOW REVIEW")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                        .kerning(0.5)

                    if let review = viewModel.ticketFlowReview {
                        Text("\(review.counts.total) tickets · \(flowUpdatedText)")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                    } else {
                        Text(viewModel.ticketFlowErrorMessage ?? "Loading ticket flow...")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                Button {
                    openWorkFlowFilter(nil)
                } label: {
                    Label("Work", systemImage: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
            }

            if let review = viewModel.ticketFlowReview {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack(spacing: 8) {
                        flowMetricChip(label: "Dispatchable", value: review.counts.dispatchable, icon: "bolt.fill", color: AppColors.accentSuccess, key: "dispatchable")
                        flowMetricChip(label: "Noise", value: review.counts.noiseReview, icon: "exclamationmark.bubble.fill", color: AppColors.accentWarning, key: "noise_review")
                        flowMetricChip(label: "Protected", value: review.counts.protected, icon: "lock.shield.fill", color: AppColors.accentDanger, key: "protected")
                    }

                    flowBucketRow(title: "By flow state", buckets: review.counts.byFlowState)
                    flowBucketRow(title: "By owner", buckets: review.counts.byOwnerAgent)
                    flowBucketRow(title: "By support lane", buckets: review.counts.bySupportLane)
                }
            } else {
                HStack(spacing: Theme.sm) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Waiting for ORCA flow review.")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            openWorkFlowFilter(nil)
        }
    }

    private var flowUpdatedText: String {
        guard let updated = viewModel.ticketFlowLastUpdated else { return "fresh" }
        let seconds = max(0, Int(Date().timeIntervalSince(updated)))
        if seconds < 60 { return "just updated" }
        let minutes = seconds / 60
        return "updated \(minutes)m ago"
    }

    private func flowMetricChip(label: String, value: Int, icon: String, color: Color, key: String) -> some View {
        Button {
            openWorkFlowFilter(key)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(label) \(value)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func flowBucketRow(title: String, buckets: [String: Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)

            if buckets.isEmpty {
                Text("No buckets yet")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sortedFlowBuckets(buckets), id: \.0) { key, value in
                            Button {
                                openWorkFlowFilter(key)
                            } label: {
                                Text("\(displayFlowKey(key)) \(value)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppColors.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(AppColors.backgroundTertiary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func sortedFlowBuckets(_ buckets: [String: Int]) -> [(String, Int)] {
        buckets.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }
        .prefix(8)
        .map { ($0.key, $0.value) }
    }

    private func displayFlowKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func openWorkFlowFilter(_ key: String?) {
        if let key {
            UserDefaults.standard.set(key, forKey: "pod.pendingWorkFlowFilter")
        } else {
            UserDefaults.standard.removeObject(forKey: "pod.pendingWorkFlowFilter")
        }
        NotificationCenter.default.post(name: Notification.Name("pod.openWorkFlowFilter"), object: key)
    }

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
                    value: viewModel.openTicketsCount,
                    label: "Open Tickets",
                    color: AppColors.accentDanger
                )
            }
        }
    }

    // MARK: - Live State Section

    private var startupTruthSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                sectionHeader("Startup Truth", count: viewModel.startupStatus?.components.count)

                if let status = viewModel.startupStatus {
                    Text(status.ok ? "OK" : "\(viewModel.startupDebtCount) needs review")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(status.ok ? AppColors.accentSuccess : AppColors.accentWarning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((status.ok ? AppColors.accentSuccess : AppColors.accentWarning).opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)
            }

            if let status = viewModel.startupStatus {
                VStack(spacing: Theme.xs) {
                    ForEach(status.components) { component in
                        StartupTruthRow(component: component)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            } else {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)

                    Text("Startup truth unavailable.")
                        .podTextStyle(.body, color: AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.md)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private var liveStateSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                sectionHeader("Live State", count: viewModel.stateTags.count)

                if viewModel.staleStateTagCount > 0 {
                    Text("\(viewModel.staleStateTagCount) stale")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.accentWarning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColors.accentWarning.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                Button {
                    Task { await viewModel.exportStateRegistryReview() }
                } label: {
                    if viewModel.isExportingStateRegistryReview {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.accentElectric)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExportingStateRegistryReview)
                .accessibilityLabel("Export State Registry review packet")
            }

            if viewModel.stateTags.isEmpty {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)

                    Text("No live state tags available.")
                        .podTextStyle(.body, color: AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.md)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else {
                VStack(spacing: Theme.xs) {
                    ForEach(viewModel.stateTags.prefix(10)) { tag in
                        LiveStateRow(tag: tag)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            }

            if let message = viewModel.stateRegistryReviewExportMessage {
                Label(message, systemImage: viewModel.stateRegistryReviewExport == nil ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(viewModel.stateRegistryReviewExport == nil ? AppColors.accentWarning : AppColors.accentSuccess)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.sm)
            }

            if let path = viewModel.stateRegistryReviewExport?.path, !path.isEmpty {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppColors.textTertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.sm)
            }
        }
    }

    private var chiefProtectionSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                sectionHeader("Chief/Fund", count: ChiefFundContent.bots.count)

                Text("Read-Only")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.accentWarning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.accentWarning.opacity(0.12))
                    .clipShape(Capsule())

                Spacer(minLength: 0)
            }

            // Guardrail notice
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accentWarning)
                Text("Pod shows verified registry only. P&L, positions, orders, wallets, and bot changes stay Chief/Rooster/Tony gated.")
                    .podTextStyle(.caption, color: AppColors.textSecondary)
                    .lineLimit(2)
            }
            .padding(Theme.sm)
            .background(AppColors.accentWarning.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(AppColors.accentWarning.opacity(0.2), lineWidth: 0.5)
            )

            // Bot registry cards
            VStack(spacing: Theme.xs) {
                ForEach(ChiefFundContent.bots) { bot in
                    ChiefFundBotCard(bot: bot)
                }
            }

            // Live state tags (when backend publishes them)
            if !viewModel.chiefProtectionTags.isEmpty {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("LIVE STATE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .tracking(0.5)
                    ForEach(viewModel.chiefProtectionTags) { tag in
                        LiveStateRow(tag: tag)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Chief/Fund Bot Card

    private struct ChiefFundBotCard: View {
        let bot: ChiefFundBot
        @State private var expanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Text(bot.emoji)
                            .font(.system(size: 22))
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(bot.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)

                                modePill(bot.mode)
                            }
                            Text(bot.role)
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    Divider().background(AppColors.border)

                    VStack(alignment: .leading, spacing: 8) {
                        if let path = bot.launchPath {
                            botDetailRow(icon: "terminal", label: "Launch", value: path)
                        }
                        botDetailRow(icon: "power", label: "Kill Switch", value: bot.killSwitch)
                        botDetailRow(icon: "person.2.badge.gearshape", label: "Review Gate", value: bot.reviewGate.rawValue)
                        if let notes = bot.notes {
                            botDetailRow(icon: "info.circle", label: "Notes", value: notes)
                        }
                        botDetailRow(icon: "person.crop.circle", label: "Owner", value: bot.owner)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
        }

        private func modePill(_ mode: BotMode) -> some View {
            HStack(spacing: 3) {
                Image(systemName: mode.icon)
                    .font(.system(size: 8, weight: .bold))
                Text(mode.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.3)
            }
            .foregroundStyle(mode.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(mode.color.opacity(0.12))
            .clipShape(Capsule())
        }

        private func botDetailRow(icon: String, label: String, value: String) -> some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 72, alignment: .leading)

                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
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

    private var emptyAttentionView: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(AppColors.accentSuccess)

            Text("No high-priority open tickets.")
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

// MARK: - Startup Truth Row

struct StartupTruthRow: View {
    let component: DashboardStartupStatusComponentDTO

    var body: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.xs) {
                    Text(component.label)
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                        .lineLimit(1)

                    if let latency = component.latencyMs {
                        Text("\(latency)ms")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                Text(component.detail)
                    .podTextStyle(.body, color: AppColors.textPrimary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(component.status.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
    }

    private var icon: String {
        switch component.status.lowercased() {
        case "good": return "checkmark.circle.fill"
        case "degraded": return "exclamationmark.triangle.fill"
        case "unavailable": return "xmark.octagon.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch component.status.lowercased() {
        case "good": return AppColors.accentSuccess
        case "degraded", "unknown": return AppColors.accentWarning
        case "unavailable": return AppColors.accentDanger
        default: return AppColors.textTertiary
        }
    }
}

// MARK: - Live State Row

struct LiveStateRow: View {
    let tag: StateTagDTO

    var body: some View {
        HStack(spacing: Theme.sm) {
            Circle()
                .fill(statusColor.opacity(0.18))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .podTextStyle(.caption, color: AppColors.textTertiary)
                    .lineLimit(1)

                Text(tag.valueText)
                    .podTextStyle(.body, color: AppColors.textPrimary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(tag.quality?.uppercased() ?? "UNKNOWN")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
    }

    private var displayName: String {
        tag.tagId
            .replacingOccurrences(of: "agent.", with: "")
            .replacingOccurrences(of: "worker.", with: "")
            .replacingOccurrences(of: "ticket.", with: "")
            .replacingOccurrences(of: "work_control.", with: "work control ")
            .replacingOccurrences(of: ".count", with: "")
            .replacingOccurrences(of: ".counts", with: "")
            .replacingOccurrences(of: ".active_task", with: "")
            .replacingOccurrences(of: ".status", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var statusColor: Color {
        if tag.stale {
            return AppColors.accentWarning
        }
        switch tag.quality?.lowercased() {
        case "good": return AppColors.accentSuccess
        case "degraded", "unknown", "estimated": return AppColors.accentWarning
        case "error": return AppColors.accentDanger
        default: return AppColors.textTertiary
        }
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
