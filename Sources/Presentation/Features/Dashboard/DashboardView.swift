import SwiftUI

// MARK: - Dashboard View

struct DashboardView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var voiceCoordinator: VoiceCoordinator
    @State private var viewModel = DashboardViewModel()
    @State private var briefingModel = DashboardBriefingDoctrineModel()
    @State private var dailyBriefingModel = DailyBriefingPanelModel()
    @State private var fundLandingModel = FundLandingViewModel()
    @State private var fundUniverseLoopModel = FundUniverseLoopViewModel()
    @State private var selectedAgent: Agent?
    @State private var selectedBriefingSheet: DashboardBriefingSheetKind?
    @State private var isDailyBriefingExpanded = false
    @State private var expandedDailyBriefingSections: Set<DailyBriefingSection> = []
    @State private var isGeneratingBriefing = false
    @State private var showingFundLanding = false
    @State private var showingVoiceRoom = false
    @State private var showingSettings = false
    @State private var playgroundModel = PlaygroundPanelModel()
    @AppStorage("orca_display_name") private var displayName: String = "Captain"

    // MARK: - Body
    // L3 classroom — no scroll on iPhone portrait (SPEC-POD-LAYOUT-REVAMP-2026-W22 §1)
    // Four sections only: Sign queue · Agent strip · Briefing line · Top flow card
    // Overflow (metrics, startup truth, live state, needs attention) → Runtime tab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    // 1. Agent status strip — fast lab pulse before owner-action queues.
                    agentStatusStrip

                    // 2. Voice room status — primary realtime chat surface.
                    dashboardVoiceBanner

                    // 3. Protected Fund visibility — read-only, no controls.
                    dashboardFundLandingCard

                    // 4. Daily briefing — collapsible read-only note from ORCA.
                    dailyBriefingPanel

                    // 5. Tier 1 sign queue — "what needs your eyes"
                    CockpitSignQueueSection()

                    // 6. Playground NATS tail — unread inbox + action-required
                    PlaygroundPanelView(model: playgroundModel, onChatTap: {
                        appState.navigateTo(.chat)
                    })

                    // 7. Compact briefing + doctrine velocity line
                    classroomBriefingLine

                    // 8. Top flow card — one blocker, tap → Work
                    classroomFlowCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.md)
                .padding(.top, Theme.sm)
                .padding(.bottom, 100)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await viewModel.loadDashboard()
                            await briefingModel.load(force: true)
                            await dailyBriefingModel.load(force: true)
                            await fundLandingModel.load()
                            await fundUniverseLoopModel.load()
                            await playgroundModel.load()
                        }
                    } label: {
                        Image(systemName: viewModel.isLoading ? "hourglass" : "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppColors.accentElectric)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
            .sheet(item: $selectedAgent) { agent in
                AgentDetailSheet(agent: agent)
            }
            .sheet(item: $selectedBriefingSheet) { sheet in
                switch sheet {
                case .briefing:
                    MorningBriefingDetailSheet(briefing: briefingModel.briefing)
                case .doctrine:
                    DoctrineLedgerDetailSheet(ledger: briefingModel.ledger)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingFundLanding) {
                FundLandingDetailSheet(
                    landing: fundLandingModel.landing,
                    universeLoop: fundUniverseLoopModel.response
                )
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingVoiceRoom) {
                VoiceCompanionView(viewModel: voiceCoordinator.viewModel)
            }
            .task {
                await viewModel.loadDashboard()
                await briefingModel.load()
                await dailyBriefingModel.load()
                await fundLandingModel.load()
                await fundUniverseLoopModel.load()
                await playgroundModel.load()
            }
            .task {
                await viewModel.startFlowReviewPolling()
            }
        }
    }

    // MARK: - Fund Landing

    private var dashboardVoiceBanner: some View {
        Button {
            if voiceCoordinator.isActive {
                showingVoiceRoom = true
            } else {
                Task {
                    await voiceCoordinator.connect(agentSlug: voiceCoordinator.activeAgentSlug)
                    showingVoiceRoom = true
                }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(voiceStatusColor.opacity(0.14))
                        .frame(width: 34, height: 34)

                    Image(systemName: voiceBannerIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(voiceStatusColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Pod Voice Room")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)

                    Text(voiceBannerSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(voiceBannerBadge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(voiceStatusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(voiceStatusColor.opacity(0.12))
                    .clipShape(Capsule())

                Image(systemName: "phone.arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(voiceStatusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(voiceStatusColor.opacity(0.22), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    private var voiceBannerIcon: String {
        if voiceCoordinator.isRealtimeConnected { return "waveform.circle.fill" }
        switch voiceCoordinator.realtimeProviderStatus {
        case .checking:
            return "mic.circle.fill"
        case .configured:
            return "phone.circle.fill"
        case .needsConfiguration, .unavailable, .failed:
            return "exclamationmark.circle.fill"
        }
    }

    private var voiceBannerSubtitle: String {
        if voiceCoordinator.isRealtimeConnected {
            return voiceCoordinator.realtimeRemoteParticipantCount > 0
                ? "Live with \(voiceCoordinator.activeAgentDisplayName)"
                : "Connected; waiting for \(voiceCoordinator.activeAgentDisplayName) worker"
        }
        if voiceCoordinator.isPreparingRealtimeSession {
            return "Preparing LiveKit room"
        }
        if let sessionText = voiceCoordinator.realtimeSessionText, sessionText.localizedCaseInsensitiveContains("ready") {
            return "Session ready to join"
        }
        switch voiceCoordinator.realtimeProviderStatus {
        case .checking:
            return "Checking ORCA voice package"
        case .configured:
            return "LiveKit configured; no active room"
        case .needsConfiguration:
            return "LiveKit needs ORCA credentials"
        case .unavailable:
            return "No voice package registered"
        case .failed:
            return "Could not verify voice package"
        }
    }

    private var voiceBannerBadge: String {
        if voiceCoordinator.isRealtimeConnected {
            return voiceCoordinator.realtimeRemoteParticipantCount > 0 ? "LIVE" : "WAITING"
        }
        if voiceCoordinator.isPreparingRealtimeSession { return "PREP" }
        if let sessionText = voiceCoordinator.realtimeSessionText, sessionText.localizedCaseInsensitiveContains("ready") {
            return "SESSION"
        }
        switch voiceCoordinator.realtimeProviderStatus {
        case .checking:
            return "CHECK"
        case .configured:
            return "CONFIG"
        case .needsConfiguration:
            return "SETUP"
        case .unavailable:
            return "OFF"
        case .failed:
            return "ERROR"
        }
    }

    private var voiceStatusColor: Color {
        if voiceCoordinator.isRealtimeConnected {
            return voiceCoordinator.realtimeRemoteParticipantCount > 0 ? AppColors.accentSuccess : AppColors.accentWarning
        }
        if voiceCoordinator.isPreparingRealtimeSession { return AppColors.accentElectric }
        if let sessionText = voiceCoordinator.realtimeSessionText, sessionText.localizedCaseInsensitiveContains("ready") {
            return AppColors.accentElectric
        }
        switch voiceCoordinator.realtimeProviderStatus {
        case .checking, .configured:
            return AppColors.accentElectric
        case .needsConfiguration:
            return AppColors.accentWarning
        case .unavailable, .failed:
            return AppColors.accentDanger
        }
    }

    private var dashboardFundLandingCard: some View {
        Button {
            showingFundLanding = true
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentWarning)

                    Text("FUND")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .tracking(0.5)

                    Spacer()

                    if fundLandingModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.65)
                    } else if let landing = fundLandingModel.landing {
                        dashboardFundStatusPill(
                            landing.isAvailable ? "LIVE" : "DEGRADED",
                            color: landing.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning
                        )
                    } else {
                        dashboardFundStatusPill("WAITING", color: AppColors.textTertiary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                }

                if let landing = fundLandingModel.landing {
                    Text(landing.headline ?? landing.degradedReason ?? "Fund landing is waiting for ORCA.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        dashboardFundMetric("Mode", landing.mode ?? "-")
                        dashboardFundMetric("Ready", landing.readiness ?? "-")
                        dashboardFundMetric("P&L", dashboardMoney(landing.netPnlUsd))
                        dashboardFundMetric("Sharpe", dashboardNumber(landing.sharpe))
                    }

                    Text("ORCA \(landing.route) · \(landing.freshnessLabel) · read-only")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(fundLandingModel.errorMessage ?? "Waiting for ORCA Fund landing route.")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.accentWarning.opacity(0.2), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    private func dashboardFundMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func dashboardFundStatusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func dashboardMoney(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private func dashboardNumber(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    // MARK: - Daily Briefing Panel

    private var dailyBriefingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isDailyBriefingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Briefing")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppColors.textPrimary)
                        Text(dailyBriefingFreshnessText)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if dailyBriefingModel.isLoading || isGeneratingBriefing {
                        ProgressView()
                            .scaleEffect(0.65)
                    } else {
                        Button {
                            isGeneratingBriefing = true
                            Task {
                                await dailyBriefingModel.generate()
                                isGeneratingBriefing = false
                                isDailyBriefingExpanded = true
                            }
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.accentElectric)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Generate briefing")
                    }

                    Image(systemName: isDailyBriefingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if isDailyBriefingExpanded {
                if let briefing = dailyBriefingModel.briefing {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(DailyBriefingSection.allCases) { section in
                            dailyBriefingSectionRow(section, briefing: briefing)
                        }
                    }
                } else {
                    Text("No briefing posted today")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    private var dailyBriefingFreshnessText: String {
        if let createdAt = dailyBriefingModel.briefing?.createdAt {
            return "Posted \(createdAt.relativeFormatted)"
        }
        return dailyBriefingModel.isLoading ? "Loading latest briefing" : "No briefing posted today"
    }

    private func dailyBriefingSectionRow(_ section: DailyBriefingSection, briefing: DailyBriefingNote) -> some View {
        let isExpanded = expandedDailyBriefingSections.contains(section)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedDailyBriefingSections.remove(section)
                    } else {
                        expandedDailyBriefingSections.insert(section)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(AppColors.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(briefing.sectionText(section))
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 3)
            }
        }
    }

    // MARK: - Classroom Briefing Line (compact — combines briefing + doctrine)

    private var classroomBriefingLine: some View {
        HStack(spacing: Theme.sm) {
            // Briefing tap → full sheet
            Button { selectedBriefingSheet = .briefing } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.accentWarning)
                    if let briefing = briefingModel.briefing {
                        Text(briefing.summary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(2)
                    } else {
                        Text(briefingModel.isLoadingBriefing ? "Loading briefing…" : "No briefing yet today")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(AppColors.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            // Doctrine tap → ledger sheet
            Button { selectedBriefingSheet = .doctrine } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                    if let ledger = briefingModel.ledger {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ledger.shippedCount) shipped")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.textPrimary)
                            if ledger.debtCount > 0 {
                                Text("\(ledger.debtCount) debt")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.accentWarning)
                            }
                        }
                    } else {
                        Text(briefingModel.isLoadingLedger ? "…" : "—")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .frame(width: 84)
                .padding(10)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(AppColors.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Classroom Flow Card (top blocker — tap → Work)

    private var classroomFlowCard: some View {
        Button { openWorkFlowFilter(nil) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("FLOW")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                        .kerning(0.5)
                    Spacer()
                    if let review = viewModel.ticketFlowReview {
                        Text("\(review.counts.total) tickets · \(flowUpdatedText)")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }

                if let review = viewModel.ticketFlowReview {
                    HStack(spacing: 8) {
                        classroomFlowChip(
                            label: "Dispatch",
                            value: review.counts.dispatchable,
                            icon: "bolt.fill",
                            color: AppColors.accentSuccess,
                            key: "dispatchable"
                        )
                        classroomFlowChip(
                            label: "Noise",
                            value: review.counts.noiseReview,
                            icon: "exclamationmark.bubble.fill",
                            color: AppColors.accentWarning,
                            key: "noise_review"
                        )
                        classroomFlowChip(
                            label: "Protected",
                            value: review.counts.protected,
                            icon: "lock.shield.fill",
                            color: AppColors.accentDanger,
                            key: "protected"
                        )
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text(viewModel.ticketFlowErrorMessage ?? "Loading flow…")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
            .padding(Theme.md)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func classroomFlowChip(label: String, value: Int, icon: String, color: Color, key: String) -> some View {
        Button { openWorkFlowFilter(key) } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                    Text("\(value)")
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundColor(value > 0 ? color : AppColors.textTertiary)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(value > 0 ? 0.08 : 0.03))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
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

    // MARK: - Morning Briefing + Doctrine Velocity

    private var morningBriefingSection: some View {
        Button {
            selectedBriefingSheet = .briefing
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                dashboardMiniHeader(
                    title: "BRIEFING · Today 07:00 PT",
                    icon: "sunrise.fill",
                    isLoading: briefingModel.isLoadingBriefing
                )

                if let briefing = briefingModel.briefing {
                    Text(briefing.summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)

                    if !briefing.highlights.isEmpty {
                        Text(briefing.highlights.prefix(2).joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                } else {
                    Text("No briefing yet today — check back at 07:00 PT")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .dashboardInfoCard()
        }
        .buttonStyle(.plain)
    }

    private var doctrineVelocitySection: some View {
        Button {
            selectedBriefingSheet = .doctrine
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                dashboardMiniHeader(
                    title: "DOCTRINE · Yesterday",
                    icon: "doc.text.magnifyingglass",
                    isLoading: briefingModel.isLoadingLedger
                )

                if let ledger = briefingModel.ledger {
                    Text("\(ledger.shippedCount) docs shipped · \(ledger.debtCount) debt flag · \(ledger.blockedCount) blocked")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    if !ledger.byType.isEmpty {
                        Text(ledger.typeSummary)
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Ledger building — first entry coming")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .dashboardInfoCard()
        }
        .buttonStyle(.plain)
    }

    private func dashboardMiniHeader(title: String, icon: String, isLoading: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .kerning(0.5)
            Spacer()
            if isLoading {
                ProgressView()
                    .scaleEffect(0.65)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
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

            dashboardPresenceRollupStrip

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

    @ViewBuilder
    private var dashboardPresenceRollupStrip: some View {
        if let rollup = viewModel.presenceRollup {
            HStack(spacing: 7) {
                Text("live:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)

                presenceCount("active", rollup.active, color: AppColors.accentSuccess)
                presenceCount("idle", rollup.idle, color: AppColors.accentWarning)
                presenceCount("offline", rollup.offline, color: AppColors.textTertiary)
                if viewModel.archivedAgentsCount > 0 {
                    presenceCount("archived", viewModel.archivedAgentsCount, color: AppColors.textMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
        }
    }

    private func presenceCount(_ label: String, _ count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
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

// MARK: - Briefing + Doctrine Models

private enum DashboardBriefingSheetKind: String, Identifiable {
    case briefing
    case doctrine

    var id: String { rawValue }
}

private struct FundLandingDetailSheet: View {
    let landing: FundLanding?
    let universeLoop: FundOSProductResponse?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(AppColors.accentWarning)
                        Text("Read-only Fund landing")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                    }

                    if let landing {
                        Text(landing.headline ?? landing.degradedReason ?? "No Fund landing summary available.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            detailMetric("Status", landing.status)
                            detailMetric("Mode", landing.mode ?? "-")
                            detailMetric("Readiness", landing.readiness ?? "-")
                            detailMetric("Account", money(landing.accountUsd))
                            detailMetric("Net P&L", money(landing.netPnlUsd))
                            detailMetric("Closed", landing.closedTrades.map(String.init) ?? "-")
                            detailMetric("Sharpe", number(landing.sharpe))
                            detailMetric("Gate", boolLabel(landing.gateReady))
                            detailMetric("Kill", landing.killSwitchStatus ?? "-")
                            detailMetric("REQ-008", req008Label(landing))
                            detailMetric("Breached", boolLabel(landing.req008Breached))
                            detailMetric("Promote", landing.promotionDecision ?? "-")
                            detailMetric("Landing", landing.summary?.agentLandingReady == true ? "ready" : "-")
                            detailMetric("Data App", landing.summary?.dataApplicationStatus ?? landing.agentLanding?.dataApplication?.status ?? "-")
                        }

                        universeLoopCard

                        if let agentLanding = landing.agentLanding {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AGENT LANDING")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppColors.textTertiary)
                                if let canonicalDoc = agentLanding.canonicalDoc {
                                    Text("Canonical: \(canonicalDoc)")
                                }
                                if let localPointer = agentLanding.localPointer {
                                    Text("Local pointer: \(localPointer)")
                                }
                                if let dataApplication = agentLanding.dataApplication {
                                    Text("Data application: \(dataApplication.status ?? "unknown") · research-only · trading_actionable=\(dataApplication.tradingActionable == true ? "true" : "false")")
                                    if let rawDataPolicy = dataApplication.rawDataPolicy {
                                        Text(rawDataPolicy)
                                    }
                                }
                                if let howToStart = agentLanding.howToStart, !howToStart.isEmpty {
                                    Text("How to start")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppColors.textTertiary)
                                    ForEach(howToStart, id: \.self) { step in
                                        Text(step)
                                    }
                                }
                                if let standards = agentLanding.standards, !standards.isEmpty {
                                    Text("Standards")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppColors.textTertiary)
                                    ForEach(standards, id: \.self) { standard in
                                        Text(standard)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textSecondary)
                            .textSelection(.enabled)
                            .padding(12)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        if !landing.blockers.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("BLOCKERS")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppColors.textTertiary)
                                ForEach(landing.blockers, id: \.self) { blocker in
                                    Text(blocker)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(12)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("SOURCE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.textTertiary)
                            Text("ORCA \(landing.route)")
                            Text(landing.sourceArtifact)
                            Text("\(landing.freshnessLabel) · generated \(landing.generatedAt ?? "-")")
                            Text(landing.podPolicy)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .textSelection(.enabled)
                    } else {
                        Text("Fund landing is not available from ORCA yet.")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(18)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Fund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var universeLoopCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundColor(AppColors.accentWarning)
                Text("UNIVERSE LOOP")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                Spacer()
                if let universeLoop {
                    detailStatusPill(universeLoop.isAvailable ? "READ-ONLY" : "DEGRADED", color: universeLoop.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning)
                } else {
                    detailStatusPill("WAITING", color: AppColors.textTertiary)
                }
            }

            if let universeLoop, let loop = universeLoop.data {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    detailMetric("Loop", loop.displayStatus)
                    detailMetric("Miner", loop.minerStatus ?? "-")
                    detailMetric("Queue", loop.queueItems.map(String.init) ?? "-")
                    detailMetric("Urgent", loop.urgentSymbols?.joined(separator: ", ") ?? "-")
                    detailMetric("Reviews", loop.completedReviews.map(String.init) ?? "-")
                    detailMetric("Calibration", loop.calibrationPendingRows.map(String.init) ?? "-")
                }
                if !loop.displayBlockers.isEmpty {
                    Text("Blockers: \(loop.displayBlockers.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                }
                if let nextActions = loop.nextActions, !nextActions.isEmpty {
                    Text("Next: \(nextActions.joined(separator: " · "))")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                }
                Text("No Miner dispatch, broker action, strategy promotion, or runtime mutation.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.accentWarning)
            } else {
                Text(universeLoop?.degradedReason ?? "Universe Loop is waiting for ORCA.")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func detailMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func detailStatusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func money(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private func number(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    private func boolLabel(_ value: Bool?) -> String {
        guard let value else { return "-" }
        return value ? "Yes" : "No"
    }

    private func req008Label(_ landing: FundLanding) -> String {
        let concentration = landing.req008OiConcentrationEth.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "-"
        let threshold = landing.req008ThresholdPercent.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "-"
        return "\(concentration)/\(threshold)%"
    }
}

private enum DailyBriefingSection: String, CaseIterable, Identifiable {
    case research
    case lessons
    case objectives
    case pnl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .research: return "Research"
        case .lessons: return "Lessons"
        case .objectives: return "Objectives"
        case .pnl: return "P&L"
        }
    }

    var aliases: [String] {
        switch self {
        case .research: return ["research"]
        case .lessons: return ["lessons", "lesson"]
        case .objectives: return ["objectives", "objective", "goals", "priorities"]
        case .pnl: return ["p&l", "pnl", "p/l", "profit and loss"]
        }
    }
}

@MainActor
@Observable
private final class DailyBriefingPanelModel {
    private(set) var briefing: DailyBriefingNote?
    private(set) var isLoading = false

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && briefing != nil { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response: PaginatedResponse<DailyBriefingNoteDTO> = try await APIClient.shared.get(
                path: "/api/v1/notes?type=daily_briefing&limit=1"
            )
            briefing = response.items.first?.toDomain()
        } catch {
            do {
                let notes: [DailyBriefingNoteDTO] = try await APIClient.shared.get(
                    path: "/api/v1/notes?type=daily_briefing&limit=1"
                )
                briefing = notes.first?.toDomain()
            } catch {
                briefing = nil
            }
        }
    }

    func generate() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result: BriefingGenerateResponse = try await APIClient.shared.post(
                path: "/api/v1/briefing/generate",
                body: EmptyEncodable()
            )
            briefing = DailyBriefingNote(
                id: result.noteId ?? result.generatedAt ?? UUID().uuidString,
                body: result.body,
                createdAt: Date(),
                sections: DailyBriefingNoteDTO.parseSectionsPublic(result.body)
            )
        } catch {
            // silently fail — briefing is best-effort
        }
    }
}

private struct EmptyEncodable: Encodable {}

private struct BriefingGenerateResponse: Decodable {
    let body: String
    let noteId: String?
    let generatedAt: String?
    enum CodingKeys: String, CodingKey {
        case body
        case noteId = "note_id"
        case generatedAt = "generated_at"
    }
}

private struct DailyBriefingNote: Hashable {
    let id: String
    let body: String
    let createdAt: Date?
    let sections: [DailyBriefingSection: String]

    func sectionText(_ section: DailyBriefingSection) -> String {
        sections[section]?.nilIfBlank ?? "No \(section.title.lowercased()) in briefing yet"
    }
}

private struct DailyBriefingNoteDTO: Codable {
    let id: String?
    let body: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case content
        case text
        case markdown
        case createdAt = "created_at"
        case created
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        body = try container.decodeIfPresent(String.self, forKey: .body)
            ?? container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .markdown)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? container.decodeIfPresent(Date.self, forKey: .created)
            ?? container.decodeIfPresent(Date.self, forKey: .timestamp)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    func toDomain() -> DailyBriefingNote {
        DailyBriefingNote(
            id: id ?? body,
            body: body,
            createdAt: createdAt,
            sections: Self.parseSections(body)
        )
    }

    static func parseSectionsPublic(_ markdown: String) -> [DailyBriefingSection: String] {
        parseSections(markdown)
    }

    private static func parseSections(_ markdown: String) -> [DailyBriefingSection: String] {
        var parsed: [DailyBriefingSection: String] = [:]
        var current: DailyBriefingSection?
        var buffer: [String] = []

        func flush() {
            guard let current else { return }
            let value = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                parsed[current] = value
            }
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("##") {
                flush()
                let title = trimmed
                    .drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                current = DailyBriefingSection.allCases.first { section in
                    section.aliases.contains { title == $0 || title.contains($0) }
                }
                buffer = []
            } else if current != nil {
                buffer.append(line)
            }
        }
        flush()

        if parsed.isEmpty, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsed[.research] = markdown
        }

        return parsed
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
@Observable
private final class DashboardBriefingDoctrineModel {
    private(set) var briefing: MorningBriefingDTO?
    private(set) var ledger: DoctrineLedgerDTO?
    private(set) var isLoadingBriefing = false
    private(set) var isLoadingLedger = false

    func load(force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadBriefing(force: force) }
            group.addTask { await self.loadLedger(force: force) }
        }
    }

    func loadBriefing(force: Bool = false) async {
        if isLoadingBriefing { return }
        if !force && briefing != nil { return }

        isLoadingBriefing = true
        defer { isLoadingBriefing = false }

        do {
            briefing = try await APIClient.shared.get(path: "/api/v1/briefings/today")
        } catch {
            briefing = nil
        }
    }

    func loadLedger(force: Bool = false) async {
        if isLoadingLedger { return }
        if !force && ledger != nil { return }

        isLoadingLedger = true
        defer { isLoadingLedger = false }

        do {
            ledger = try await APIClient.shared.get(path: "/api/v1/doc-ledger/yesterday")
        } catch {
            ledger = nil
        }
    }
}

private struct MorningBriefingDTO: Decodable {
    let date: String
    let summary: String
    let highlights: [String]
    let generatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case date
        case summary
        case highlights
        case generatedAt = "generated_at"
    }
}

private struct DoctrineLedgerDTO: Decodable {
    let date: String
    let shippedCount: Int
    let debtCount: Int
    let blockedCount: Int
    let byType: [String: Int]
    let events: [DoctrineLedgerEvent]

    enum CodingKeys: String, CodingKey {
        case date
        case shippedCount = "shipped_count"
        case debtCount = "debt_count"
        case blockedCount = "blocked_count"
        case byType = "by_type"
        case events
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? "yesterday"
        shippedCount = try container.decodeIfPresent(Int.self, forKey: .shippedCount) ?? 0
        debtCount = try container.decodeIfPresent(Int.self, forKey: .debtCount) ?? 0
        blockedCount = try container.decodeIfPresent(Int.self, forKey: .blockedCount) ?? 0
        byType = try container.decodeIfPresent([String: Int].self, forKey: .byType) ?? [:]
        events = try container.decodeIfPresent([DoctrineLedgerEvent].self, forKey: .events) ?? []
    }

    var typeSummary: String {
        byType
            .sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key.uppercased())" }
            .joined(separator: " · ")
    }
}

private struct DoctrineLedgerEvent: Decodable, Identifiable {
    let id: String
    let title: String
    let docType: String?
    let status: String?
    let path: String?
    let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case docType = "doc_type"
        case type
        case status
        case path
        case timestamp
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .path)
            ?? "Doctrine event"
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? title
        docType = try container.decodeIfPresent(String.self, forKey: .docType)
            ?? container.decodeIfPresent(String.self, forKey: .type)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
            ?? container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

private struct MorningBriefingDetailSheet: View {
    let briefing: MorningBriefingDTO?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let briefing {
                        Text(briefing.date)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary)
                        Text(briefing.summary)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !briefing.highlights.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("HIGHLIGHTS")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppColors.textTertiary)
                                ForEach(briefing.highlights, id: \.self) { highlight in
                                    Label(highlight, systemImage: "sparkle")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if let generatedAt = briefing.generatedAt {
                            Text("Generated \(generatedAt.relativeFormatted)")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.textTertiary)
                        }
                    } else {
                        Text("No briefing yet today — check back at 07:00 PT")
                            .font(.system(size: 15))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(20)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Morning Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DoctrineLedgerDetailSheet: View {
    let ledger: DoctrineLedgerDTO?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let ledger {
                        Text(ledger.date)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary)
                        Text("\(ledger.shippedCount) docs shipped · \(ledger.debtCount) debt flag · \(ledger.blockedCount) blocked")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)

                        if !ledger.byType.isEmpty {
                            Text(ledger.typeSummary)
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textSecondary)
                        }

                        if ledger.events.isEmpty {
                            Text("No ledger events returned yet.")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textTertiary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(ledger.events) { event in
                                    doctrineEventRow(event)
                                    if event.id != ledger.events.last?.id {
                                        Divider().background(AppColors.border)
                                    }
                                }
                            }
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        }
                    } else {
                        Text("Ledger building — first entry coming")
                            .font(.system(size: 15))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(20)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Doctrine Velocity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func doctrineEventRow(_ event: DoctrineLedgerEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
            HStack(spacing: 6) {
                if let docType = event.docType {
                    ledgerPill(docType.uppercased())
                }
                if let status = event.status {
                    ledgerPill(status)
                }
                if let timestamp = event.timestamp {
                    Text(timestamp.relativeFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            if let path = event.path {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func ledgerPill(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }
}

private extension View {
    func dashboardInfoCard() -> some View {
        self
            .padding(Theme.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
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
