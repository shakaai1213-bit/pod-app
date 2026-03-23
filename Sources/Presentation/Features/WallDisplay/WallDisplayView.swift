import SwiftUI

// MARK: - Wall Display View

/// Full-screen, always-on iPad wall display for ambient team status.
/// No navigation, exit via swipe-down gesture. Landscape-only.
struct WallDisplayView: View {

    @State private var viewModel = WallDisplayViewModel()
    @State private var showExitHint = false
    @State private var lastRefresh = Date()

    // MARK: - Computed

    private let orgName = "ORCA AI"

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }

    private var systemStatusText: String {
        if viewModel.attentionCount > 0 {
            return "\(viewModel.attentionCount) attention\(viewModel.attentionCount == 1 ? "" : "s") needed"
        }
        return "All systems nominal"
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Top Strip (80pt) ──
                    topStrip

                    Divider()
                        .background(AppColors.border)

                    // ── Agent Status Strip (120pt) ──
                    agentStatusStrip

                    Divider()
                        .background(AppColors.border)

                    // ── Main Activity Feed ──
                    activityFeed
                        .frame(maxHeight: .infinity)

                    Divider()
                        .background(AppColors.border)

                    // ── Bottom Strip (60pt) ──
                    bottomStrip
                }

                // Exit hint overlay (shown briefly after dismiss gesture detected)
                if showExitHint {
                    exitHintOverlay
                }
            }
            .wallDisplay(
                onWake: { viewModel.recordActivity() },
                isDimmed: viewModel.isDimmed
            )
            .gesture(dismissGesture)
            .refreshable {
                await viewModel.refresh()
            }
        }
        .task {
            await viewModel.loadAll()
            startAutoRefresh()
        }
    }

    // MARK: - Top Strip

    private var topStrip: some View {
        HStack {
            // Organization name
            Text(orgName)
                .podTextStyle(.title3, color: AppColors.textPrimary)
                .fontWeight(.semibold)

            Spacer()

            // Current time
            Text(timeFormatter.string(from: viewModel.currentTime))
                .font(.system(size: 40, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
                .contentTransition(.numericText())

            Spacer()

            // Date
            Text(dateFormatter.string(from: viewModel.currentTime))
                .podTextStyle(.subheadline, color: AppColors.textSecondary)
                .frame(minWidth: 180, alignment: .trailing)
        }
        .padding(.horizontal, Theme.lg)
        .frame(height: 80)
        .background(AppColors.backgroundSecondary)
    }

    // MARK: - Agent Status Strip

    private var agentStatusStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.sm) {
                ForEach(viewModel.agents) { agent in
                    AgentStatusCard(agent: agent)
                }
            }
            .padding(.horizontal, Theme.lg)
        }
        .frame(height: 120)
        .background(AppColors.backgroundSecondary)
    }

    // MARK: - Activity Feed

    private var activityFeed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.activities) { item in
                    WallActivityItemView(item: item)
                    Divider()
                        .background(AppColors.border)
                }
            }
        }
        .background(AppColors.backgroundPrimary)
    }

    // MARK: - Bottom Strip

    private var bottomStrip: some View {
        HStack {
            // Logo mark
            HStack(spacing: 6) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.accentElectric)
                Text("pod")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer()

            // System status
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.attentionCount > 0 ? AppColors.accentWarning : AppColors.accentSuccess)
                    .frame(width: 8, height: 8)

                Text(systemStatusText)
                    .podTextStyle(.caption, color: AppColors.textSecondary)
            }

            Spacer()

            // Last refresh
            Text("Refreshed \(RelativeTimeFormatter.shared.string(from: lastRefresh))")
                .podTextStyle(.caption, color: AppColors.textTertiary)
                .frame(minWidth: 100, alignment: .trailing)
        }
        .padding(.horizontal, Theme.lg)
        .frame(height: 60)
        .background(AppColors.backgroundSecondary)
    }

    // MARK: - Exit Hint Overlay

    private var exitHintOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "chevron.down")
                    .font(.system(size: 24, weight: .bold))
                Text("Swipe down to exit")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, Theme.lg)
            .padding(.vertical, Theme.sm)
            .background(AppColors.backgroundTertiary.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .padding(.bottom, Theme.xxl)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Dismiss Gesture

    private var dismissGesture: some Gesture {
        DragGesture()
            .onEnded { value in
                if value.translation.height > 100 && value.translation.width.magnitude < 80 {
                    // Swipe down detected — show hint instead of dismissing (UIKit manages exit)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showExitHint = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showExitHint = false
                        }
                    }
                }
            }
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                lastRefresh = Date()
                await viewModel.refresh()
            }
        }
    }
}

// MARK: - Agent Status Card

private struct AgentStatusCard: View {

    let agent: Agent

    private var statusColor: Color {
        switch agent.status {
        case .online:  return AppColors.accentSuccess
        case .busy:   return AppColors.accentWarning
        case .idle:   return AppColors.textTertiary
        case .offline: return AppColors.textMuted
        case .error:  return AppColors.accentDanger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            // Avatar + Name + Status dot
            HStack(spacing: Theme.xs) {
                AvatarView(
                    name: agent.name,
                    status: nil,
                    size: .lg,
                    image: nil
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .podTextStyle(.caption, color: AppColors.textPrimary)
                        .fontWeight(.medium)

                    // Status dot + label
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(agent.status.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }

            // Current task
            if let task = agent.currentTask {
                Text(task)
                    .podTextStyle(.caption, color: AppColors.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Idle")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
                    .italic()
            }
        }
        .padding(Theme.sm)
        .frame(width: 160)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }
}

// MARK: - Wall Activity Item View

private struct WallActivityItemView: View {

    let item: ActivityItem

    private var timestampText: String {
        RelativeTimeFormatter.shared.string(from: item.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(item.type.iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: item.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.type.iconColor)
            }

            // Description
            Text(item.description)
                .podTextStyle(.body, color: AppColors.textPrimary)
                .lineLimit(2)

            Spacer(minLength: Theme.sm)

            // Actor + Timestamp
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if item.isActorAgent {
                        Image(systemName: "cpu")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColors.accentAgent)
                    }
                    Text(item.actorName)
                        .podTextStyle(.caption, color: item.isActorAgent ? AppColors.accentAgent : AppColors.textSecondary)
                }

                Text(timestampText)
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            }
            .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, Theme.lg)
        .padding(.vertical, Theme.sm)
    }
}

#Preview {
    WallDisplayView()
        .preferredColorScheme(.dark)
}
