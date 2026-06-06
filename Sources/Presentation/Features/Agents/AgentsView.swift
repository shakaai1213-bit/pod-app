import SwiftUI
import Observation

// MARK: - Agents View (Cockpit, per SPEC-POD-AGENTS-TAB-2026-05-23)
// Slice 1: section frames + headers + design tokens wired. Data + actions in subsequent slices.

@Observable
final class FundLandingViewModel {
    var landing: FundLanding?
    var isLoading = false
    var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            landing = try await apiClient.get(path: "/api/v1/fund/landing")
        } catch {
            errorMessage = "Fund landing unavailable from ORCA"
        }
    }
}

@Observable
final class FundUniverseLoopViewModel {
    var response: FundOSProductResponse?
    var isLoading = false
    var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            response = try await apiClient.get(path: "/api/v1/fund/os/universe-loop")
        } catch {
            errorMessage = "Universe Loop unavailable from ORCA"
        }
    }
}

struct FundLanding: Decodable {
    let status: String
    let schemaVersion: String
    let route: String
    let sourceArtifact: String
    let sourceReadable: Bool
    let sourceFresh: Bool
    let sourceMtime: String?
    let sourceAgeSeconds: Int?
    let generatedAt: String?
    let podPolicy: String
    let verifiedFinancialDataAvailable: Bool
    let mode: String?
    let readiness: String?
    let headline: String?
    let accountUsd: Double?
    let netPnlUsd: Double?
    let closedTrades: Int?
    let sharpe: Double?
    let gateReady: Bool?
    let killSwitchStatus: String?
    let req008OiConcentrationEth: Double?
    let req008ThresholdPercent: Double?
    let req008Breached: Bool?
    let promotionDecision: String?
    let algoControlStatus: String?
    let blockers: [String]
    let degradedReason: String?
    let summary: FundLandingSummary?
    let agentLanding: FundAgentLanding?

    enum CodingKeys: String, CodingKey {
        case status
        case schemaVersion = "schema_version"
        case route
        case sourceArtifact = "source_artifact"
        case sourceReadable = "source_readable"
        case sourceFresh = "source_fresh"
        case sourceMtime = "source_mtime"
        case sourceAgeSeconds = "source_age_seconds"
        case generatedAt = "generated_at"
        case podPolicy = "pod_policy"
        case verifiedFinancialDataAvailable = "verified_financial_data_available"
        case mode
        case readiness
        case headline
        case accountUsd = "account_usd"
        case netPnlUsd = "net_pnl_usd"
        case closedTrades = "closed_trades"
        case sharpe
        case gateReady = "gate_ready"
        case killSwitchStatus = "kill_switch_status"
        case req008OiConcentrationEth = "req008_oi_concentration_eth"
        case req008ThresholdPercent = "req008_threshold_percent"
        case req008Breached = "req008_breached"
        case promotionDecision = "promotion_decision"
        case algoControlStatus = "algo_control_status"
        case blockers
        case degradedReason = "degraded_reason"
        case summary
        case agentLanding = "agent_landing"
    }

    var isAvailable: Bool { status == "available" }
    var freshnessLabel: String {
        if let sourceAgeSeconds {
            if sourceAgeSeconds < 60 { return "\(sourceAgeSeconds)s old" }
            if sourceAgeSeconds < 3_600 { return "\(sourceAgeSeconds / 60)m old" }
            return "\(sourceAgeSeconds / 3_600)h old"
        }
        return sourceFresh ? "fresh" : "unknown age"
    }
}

struct FundOSProductResponse: Decodable {
    let status: String
    let schemaVersion: String
    let route: String
    let section: String
    let sourceArtifact: String
    let sourceReadable: Bool
    let sourceFresh: Bool
    let sourceMtime: String?
    let sourceAgeSeconds: Int?
    let generatedAt: String?
    let readPolicy: String
    let degradedReason: String?
    let data: FundUniverseLoopController?

    enum CodingKeys: String, CodingKey {
        case status
        case schemaVersion = "schema_version"
        case route
        case section
        case sourceArtifact = "source_artifact"
        case sourceReadable = "source_readable"
        case sourceFresh = "source_fresh"
        case sourceMtime = "source_mtime"
        case sourceAgeSeconds = "source_age_seconds"
        case generatedAt = "generated_at"
        case readPolicy = "read_policy"
        case degradedReason = "degraded_reason"
        case data
    }

    var isAvailable: Bool { status == "available" && data != nil }
    var freshnessLabel: String {
        if let sourceAgeSeconds {
            if sourceAgeSeconds < 60 { return "\(sourceAgeSeconds)s old" }
            if sourceAgeSeconds < 3_600 { return "\(sourceAgeSeconds / 60)m old" }
            return "\(sourceAgeSeconds / 3_600)h old"
        }
        return sourceFresh ? "fresh" : "unknown age"
    }
}

struct FundUniverseLoopController: Decodable {
    let universeLoopStatus: String?
    let status: String?
    let blocker: String?
    let blockers: [String]?
    let warnings: [String]?
    let urgentSymbols: [String]?
    let minerStatus: String?
    let completedReviews: Int?
    let calibrationPendingRows: Int?
    let routeImplementation: String?
    let queueItems: Int?
    let nextActions: [String]?

    private enum CodingKeys: String, CodingKey {
        case universeLoopStatus = "universe_loop_status"
        case status
        case blocker
        case blockers
        case warnings
        case urgentSymbols = "urgent_symbols"
        case minerStatus = "miner_status"
        case completedReviews = "completed_reviews"
        case calibrationPendingRows = "calibration_pending_rows"
        case routeImplementation = "route_implementation"
        case queueItems = "queue_items"
        case nextActions = "next_actions"
        case queue
        case miner
        case reviews
        case calibration
        case orcaRoute = "orca_route"
    }

    private enum QueueKeys: String, CodingKey {
        case items
        case urgentSymbols = "urgent_symbols"
    }

    private enum MinerKeys: String, CodingKey {
        case status
    }

    private enum ReviewKeys: String, CodingKey {
        case completedReviews = "completed_reviews"
    }

    private enum CalibrationKeys: String, CodingKey {
        case pendingRows = "pending_rows"
    }

    private enum ActionKeys: String, CodingKey {
        case action
        case owner
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        universeLoopStatus = try container.decodeIfPresent(String.self, forKey: .universeLoopStatus)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        blockers = try container.decodeIfPresent([String].self, forKey: .blockers)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings)

        let queue = try? container.nestedContainer(keyedBy: QueueKeys.self, forKey: .queue)
        urgentSymbols = try container.decodeIfPresent([String].self, forKey: .urgentSymbols)
            ?? queue?.decodeIfPresent([String].self, forKey: .urgentSymbols)

        let miner = try? container.nestedContainer(keyedBy: MinerKeys.self, forKey: .miner)
        minerStatus = try container.decodeIfPresent(String.self, forKey: .minerStatus)
            ?? miner?.decodeIfPresent(String.self, forKey: .status)

        let reviews = try? container.nestedContainer(keyedBy: ReviewKeys.self, forKey: .reviews)
        completedReviews = try container.decodeIfPresent(Int.self, forKey: .completedReviews)
            ?? reviews?.decodeIfPresent(Int.self, forKey: .completedReviews)

        let calibration = try? container.nestedContainer(keyedBy: CalibrationKeys.self, forKey: .calibration)
        calibrationPendingRows = try container.decodeIfPresent(Int.self, forKey: .calibrationPendingRows)
            ?? calibration?.decodeIfPresent(Int.self, forKey: .pendingRows)

        queueItems = try container.decodeIfPresent(Int.self, forKey: .queueItems)
            ?? queue?.decodeIfPresent(Int.self, forKey: .items)

        routeImplementation = try container.decodeIfPresent(String.self, forKey: .routeImplementation)
            ?? container.decodeIfPresent(String.self, forKey: .orcaRoute)

        if let blocker = try container.decodeIfPresent(String.self, forKey: .blocker) {
            self.blocker = blocker
        } else {
            self.blocker = blockers?.first
        }

        if let strings = try? container.decodeIfPresent([String].self, forKey: .nextActions) {
            nextActions = strings
        } else if var actions = try? container.nestedUnkeyedContainer(forKey: .nextActions) {
            var values: [String] = []
            while !actions.isAtEnd {
                let item = try actions.nestedContainer(keyedBy: ActionKeys.self)
                let action = try item.decodeIfPresent(String.self, forKey: .action)
                let owner = try item.decodeIfPresent(String.self, forKey: .owner)
                let status = try item.decodeIfPresent(String.self, forKey: .status)
                let parts = [action, owner.map { "owner: \($0)" }, status.map { "status: \($0)" }]
                    .compactMap { $0 }
                if !parts.isEmpty {
                    values.append(parts.joined(separator: " · "))
                }
            }
            nextActions = values
        } else {
            nextActions = nil
        }
    }

    var displayStatus: String { universeLoopStatus ?? status ?? "unknown" }
    var displayBlockers: [String] {
        var values = blockers ?? []
        if let blocker, !blocker.isEmpty, !values.contains(blocker) {
            values.insert(blocker, at: 0)
        }
        return values
    }
}

struct FundLandingSummary: Decodable {
    let agentLandingReady: Bool?
    let dataApplicationStatus: String?

    enum CodingKeys: String, CodingKey {
        case agentLandingReady = "agent_landing_ready"
        case dataApplicationStatus = "data_application_status"
    }
}

struct FundAgentLanding: Decodable {
    let canonicalDoc: String?
    let localPointer: String?
    let dataApplication: FundDataApplication?
    let howToStart: [String]?
    let standards: [String]?

    enum CodingKeys: String, CodingKey {
        case canonicalDoc = "canonical_doc"
        case localPointer = "local_pointer"
        case dataApplication = "data_application"
        case howToStart = "how_to_start"
        case standards
    }
}

struct FundDataApplication: Decodable {
    let status: String?
    let intendedUse: String?
    let tradingActionable: Bool?
    let rawDataPolicy: String?
    let feedCount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case intendedUse = "intended_use"
        case tradingActionable = "trading_actionable"
        case rawDataPolicy = "raw_data_policy"
        case feedCount = "feed_count"
    }
}

struct AgentsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var viewModel = AgentsViewModel()
    @State private var focusModel = AgentFocusCardsModel()
    @State private var fundLandingModel = FundLandingViewModel()
    @State private var fundUniverseLoopModel = FundUniverseLoopViewModel()
    @State private var selectedAgent: Agent?
    @State private var selectedFocusCard: AgentFocusCard?
    @State private var showingLogStream: Agent?
    @State private var agentsFilter: AgentsFilter = .active

    enum AgentsFilter: String, CaseIterable, Identifiable {
        case all, active, support, archived
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 16)

                    focusCardsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    lanesStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    workersSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable {
                await focusModel.load(force: true)
                await fundLandingModel.load()
                await fundUniverseLoopModel.load()
                await viewModel.loadAgents()
                await viewModel.loadAllInboxTails()
            }
            .sheet(item: $selectedFocusCard) { card in
                AgentFocusCardDetailSheet(card: card)
            }
            .sheet(item: $selectedAgent) { agent in
                AgentDetailSheet(
                    agent: agent,
                    onViewLogs: { showingLogStream = agent },
                    onStatusChanged: { newStatus in
                        Task { await viewModel.updateAgentState(agent.id, newStatus) }
                    },
                    onPause: { Task { await viewModel.pauseAgent(agent.id) } },
                    onRestart: { Task { await viewModel.restartAgent(agent.id) } },
                    onStartChat: { appState.pendingDirectChatAgentId = agent.name.lowercased() }
                )
            }
            .fullScreenCover(item: $showingLogStream) { agent in
                LogStreamView(agent: agent)
            }
            .task {
                await focusModel.load()
                await fundLandingModel.load()
                await fundUniverseLoopModel.load()
                await viewModel.loadAgents()
                consumePendingActivationAgent()
                viewModel.subscribeToAgentState()
                await viewModel.loadAllInboxTails()
            }
            .onDisappear { viewModel.disconnectSSE() }
        }
    }

    @MainActor
    private func consumePendingActivationAgent() {
        let name = UserDefaults.standard.string(forKey: "pod.pendingActivationAgentName")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let name, !name.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: "pod.pendingActivationAgentName")
        selectedAgent = viewModel.agents.first { $0.name.lowercased() == name }
    }

    // MARK: - FOCUS CARDS

    private var focusCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FOCUS CARDS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                if focusModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(focusModel.mainCards) { card in
                    focusCardView(card)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let agent = agentForFocusCard(card) {
                                selectedAgent = agent
                            } else {
                                selectedFocusCard = card
                            }
                        }
                }
            }

            deputyStrip
        }
    }

    private func focusCardView(_ card: AgentFocusCard) -> some View {
        let agent = agentForFocusCard(card)
        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.emoji)
                    .font(.system(size: 22))
                Text(card.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                if let agent {
                    focusStatusPill(agent)
                }
                Spacer(minLength: 8)
                if let unread = agent.map({ viewModel.unreadCount(for: $0.name) }), unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                }
                Text(card.lastUpdatedLabel)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }

            // Charter
            Text(card.charter)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let agent {
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(agent.status.color)
                    Text(agent.currentTask ?? agent.role)
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text((agent.lastActivity ?? Date()).relativeFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(agent.status.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            Divider()

            // STRETCH + ROADMAP side-by-side (Tony 2026-05-25 reframe)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STRETCH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .kerning(0.5)
                    if card.hasStretch {
                        ForEach(Array(card.stretch.prefix(3).enumerated()), id: \.offset) { idx, item in
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AppColors.textTertiary)
                                Text(item)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(2)
                            }
                        }
                    } else {
                        pendingORCARow("Stretch not published")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ROADMAP")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .kerning(0.5)
                    if card.hasRoadmap {
                        roadmapRow("30d", card.roadmap.d30)
                        roadmapRow("60d", card.roadmap.d60)
                        roadmapRow("90d", card.roadmap.d90)
                    } else {
                        pendingORCARow("Roadmap not published")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // THIS WEEK — from GET /api/v1/agents/{name}/weekly-plan (graceful 404 = nil)
            VStack(alignment: .leading, spacing: 4) {
                Text("THIS WEEK")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                if let milestones = card.thisWeek, !milestones.isEmpty {
                    ForEach(Array(milestones.prefix(5).enumerated()), id: \.element.id) { _, milestone in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(milestone.statusDot)
                                .font(.system(size: 11))
                            Text(milestone.title)
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } else {
                    pendingORCARow("Weekly plan not published")
                }
            }

            Divider()

            // Today's 3 from morning daily log + Fish chip
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TODAY'S 3")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .kerning(0.5)
                    if card.hasFocusAreas {
                        ForEach(Array(card.focusAreas.prefix(3).enumerated()), id: \.offset) { idx, area in
                            if !area.label.isEmpty {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(idx + 1).")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(AppColors.textTertiary)
                                    Text(area.label)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                    } else {
                        pendingORCARow("Morning log not published")
                    }
                }
                Spacer(minLength: 8)
                if card.hasFish {
                    fishChip(card.fish)
                } else {
                    sourcePill("Fish pending")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(card.tint.opacity(0.35), lineWidth: 1)
        )
    }

    private func agentForFocusCard(_ card: AgentFocusCard) -> Agent? {
        viewModel.agents.first { $0.name.lowercased() == card.id }
    }

    private func focusStatusPill(_ agent: Agent) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(agent.status.color)
                .frame(width: 6, height: 6)
            Text(agent.status.displayName.lowercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(agent.status.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(agent.status.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var deputyStrip: some View {
        HStack(spacing: 8) {
            ForEach(focusModel.deputies) { deputy in
                let agent = viewModel.agents.first { $0.name.localizedCaseInsensitiveCompare(deputy.displayName) == .orderedSame }
                HStack(spacing: 8) {
                    Text(deputy.emoji)
                        .font(.system(size: 18))
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(deputy.displayName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                            Circle()
                                .fill(agent?.status.color ?? deputy.statusColor)
                                .frame(width: 6, height: 6)
                        }
                        Text(agent?.currentTask ?? deputy.currentTicket)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 64)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(AppColors.border, lineWidth: 0.5)
                )
            }
        }
    }

    private func roadmapRow(_ horizon: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(horizon)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(AppColors.accentElectric)
                .frame(width: 24, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 11))
                .foregroundColor(value.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                .lineLimit(2)
        }
    }

    private func pendingORCARow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
                .lineLimit(2)
        }
        .foregroundColor(AppColors.textTertiary)
    }

    private func sourcePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }

    private func fishChip(_ fish: AgentFocusFish) -> some View {
        HStack(spacing: 4) {
            Text(fish.icon)
            Text(fish.name)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(AppColors.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(AppColors.backgroundTertiary)
        .clipShape(Capsule())
    }

    // MARK: - Protected Chief/Fund

    private var protectedChiefFundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("PROTECTED · CHIEF/FUND")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Text("Read-only")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.accentWarning)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColors.accentWarning.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 2)

            Text("P&L, positions, orders, wallets, bot changes, and kill switches stay Chief/Rooster/Tony gated. Pod shows registry context only.")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
                .padding(10)
                .background(AppColors.accentWarning.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            fundLandingCard

            fundUniverseLoopCard

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(ChiefFundContent.bots) { bot in
                    chiefFundMiniCard(bot)
                }
            }
        }
    }

    private func chiefFundMiniCard(_ bot: ChiefFundBot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(bot.emoji)
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bot.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(bot.owner)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    Image(systemName: bot.mode.icon)
                        .font(.system(size: 8, weight: .bold))
                    Text(bot.mode.label)
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(bot.mode.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(bot.mode.color.opacity(0.12))
                .clipShape(Capsule())
            }

            Text(bot.role)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)

            Text(bot.reviewGate.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.accentWarning)
                .lineLimit(1)
        }
        .padding(10)
        .frame(minHeight: 92, alignment: .topLeading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColors.accentWarning.opacity(0.18), lineWidth: 1)
        )
    }

    private var fundUniverseLoopCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.accentWarning)
                Text("Universe Loop")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if fundUniverseLoopModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let response = fundUniverseLoopModel.response {
                    statusPill(response.isAvailable ? "READ-ONLY" : "DEGRADED", color: response.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning)
                } else {
                    statusPill("WAITING", color: AppColors.textTertiary)
                }
            }

            if let response = fundUniverseLoopModel.response, let loop = response.data {
                Text("Protected visibility only. No Miner dispatch, NATS publish, broker action, or runtime mutation.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    fundMetric("Status", loop.displayStatus)
                    fundMetric("Miner", loop.minerStatus ?? "—")
                    fundMetric("Queue", loop.queueItems.map(String.init) ?? "—")
                    fundMetric("Reviews", loop.completedReviews.map(String.init) ?? "—")
                    fundMetric("Calibration", loop.calibrationPendingRows.map(String.init) ?? "—")
                    fundMetric("Route", loop.routeImplementation ?? "—")
                }

                if let urgentSymbols = loop.urgentSymbols, !urgentSymbols.isEmpty {
                    wrappedTokenRow(title: "Urgent queue", values: urgentSymbols)
                }

                let blockers = loop.displayBlockers
                if !blockers.isEmpty {
                    compactTextList(title: "Blockers", values: blockers)
                }

                if let warnings = loop.warnings, !warnings.isEmpty {
                    compactTextList(title: "Warnings", values: warnings)
                }

                if let nextActions = loop.nextActions, !nextActions.isEmpty {
                    compactTextList(title: "Next actions", values: nextActions)
                }

                Text("Source: ORCA \(response.route) · \(response.freshnessLabel) · \(response.readPolicy)")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(3)
            } else {
                Text(fundUniverseLoopModel.response?.degradedReason ?? fundUniverseLoopModel.errorMessage ?? "Waiting for ORCA Universe Loop route.")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColors.accentWarning.opacity(0.22), lineWidth: 1)
        )
    }

    private func wrappedTokenRow(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.accentWarning)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(AppColors.accentWarning.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func compactTextList(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            ForEach(values.prefix(4), id: \.self) { value in
                Text("• \(value)")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fundLandingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.accentWarning)
                Text("Fund Landing")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if fundLandingModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let landing = fundLandingModel.landing {
                    statusPill(landing.isAvailable ? "ORCA LIVE" : "DEGRADED", color: landing.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning)
                } else {
                    statusPill("WAITING", color: AppColors.textTertiary)
                }
            }

            if let landing = fundLandingModel.landing {
                Text(landing.headline ?? landing.degradedReason ?? "No Fund landing artifact available.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    fundMetric("Mode", landing.mode ?? "—")
                    fundMetric("Readiness", landing.readiness ?? "—")
                    fundMetric("Account", money(landing.accountUsd))
                    fundMetric("Net P&L", money(landing.netPnlUsd))
                    fundMetric("Trades", landing.closedTrades.map(String.init) ?? "—")
                    fundMetric("Sharpe", number(landing.sharpe))
                    fundMetric("Gate", boolLabel(landing.gateReady))
                    fundMetric("Kill", landing.killSwitchStatus ?? "—")
                    fundMetric("REQ-008", req008Label(landing))
                    fundMetric("Promote", landing.promotionDecision ?? "—")
                    fundMetric("Landing", landing.summary?.agentLandingReady == true ? "ready" : "—")
                    fundMetric("Data App", landing.summary?.dataApplicationStatus ?? landing.agentLanding?.dataApplication?.status ?? "—")
                }

                if let agentLanding = landing.agentLanding {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Agent start")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.textTertiary)
                        if let canonicalDoc = agentLanding.canonicalDoc {
                            Text(canonicalDoc)
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        if let dataApplication = agentLanding.dataApplication {
                            Text("Data application: \(dataApplication.status ?? "unknown") · research-only · trading_actionable=\(dataApplication.tradingActionable == true ? "true" : "false")")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !landing.blockers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blockers")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.textTertiary)
                        ForEach(landing.blockers, id: \.self) { blocker in
                            Text("• \(blocker)")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text("Source: ORCA \(landing.route) · \(landing.freshnessLabel) · read-only")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            } else {
                Text(fundLandingModel.errorMessage ?? "Waiting for ORCA Fund landing route.")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColors.accentWarning.opacity(0.22), lineWidth: 1)
        )
    }

    private func fundMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func money(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private func number(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    private func boolLabel(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "Yes" : "No"
    }

    private func req008Label(_ landing: FundLanding) -> String {
        let concentration = landing.req008OiConcentrationEth.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—"
        let threshold = landing.req008ThresholdPercent.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
        let breached = landing.req008Breached == true ? "breach" : "ok"
        return "\(concentration)/\(threshold)% · \(breached)"
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agents")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            Text("The crew — who's alive, who's doing what.")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - AGENTS Section (§3)

    private var agentsSection: some View {
        let allFiltered = filteredAgents
        return VStack(spacing: 0) {
            HStack {
                Text("AGENTS · \(activeCount) active")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            filterChipRow
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.agents.isEmpty {
                    skeletonAgentRows
                } else if allFiltered.isEmpty {
                    emptyState(icon: "person.crop.circle.dashed", text: "No agents matching filter. Try All.")
                } else {
                    ForEach(Array(allFiltered.enumerated()), id: \.element.id) { idx, agent in
                        VStack(spacing: 0) {
                            if idx > 0 {
                                Divider().background(AppColors.border).padding(.horizontal, 14)
                            }
                            agentRow(agent)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedAgent = agent }
                        }
                    }
                }
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
        }
    }

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AgentsFilter.allCases) { filter in
                    let isOn = agentsFilter == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { agentsFilter = filter }
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                            .foregroundColor(isOn ? Color.black : AppColors.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(isOn ? AppColors.textPrimary : Color.clear)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(isOn ? Color.clear : AppColors.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 30)
                }
            }
        }
    }

    private var filteredAgents: [Agent] {
        let all = viewModel.agents
        switch agentsFilter {
        case .all:      return AgentRosterPolicy.filterActive(all) + AgentRosterPolicy.filterDormant(all)
        case .active:   return all.filter { $0.rosterLane == .activeMain }
                             .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .support:  return all.filter { $0.rosterLane == .supportRuntime }
                             .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .archived: return AgentRosterPolicy.filterDormant(all)
        }
    }

    private var activeCount: Int {
        viewModel.agents.filter { $0.rosterLane == .activeMain }.count
    }

    // Per spec §3.2 — emoji avatar (charter-tinted), name, charter line, last-seen, NATS lane.
    private func agentRow(_ agent: Agent) -> some View {
        HStack(spacing: 12) {
            agentGlyph(agent)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    let unread = viewModel.unreadCount(for: agent.name)
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                    }
                }
                Text(agent.role)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                statusPill(agent)
                Text((agent.lastActivity ?? Date()).relativeFormatted)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
    }

    // Charter-tinted background, emoji glyph centered. Mapping from TEAM.md (verified).
    private func agentGlyph(_ agent: Agent) -> some View {
        let n = agent.name.lowercased()
        let emoji: String = {
            switch n {
            case "aloha": return "🌸"
            case "maui": return "🪝"
            case "chief": return "🦅"
            case "rooster": return "🐓"
            case "coral": return "🪸"
            case "reef": return "🐚"
            case "aurora": return "🌋"
            case "shaka", "shaka-agent": return "🤙"
            case "luna": return "🌙"
            default: return "🐠"
            }
        }()
        let tint = Color(hexString: agent.avatarColor ?? "#6B46C1")
        return ZStack {
            Circle().fill(tint.opacity(0.18)).frame(width: 36, height: 36)
            Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1).frame(width: 36, height: 36)
            Text(emoji).font(.system(size: 20))
        }
    }

    private func statusPill(_ agent: Agent) -> some View {
        let (label, color): (String, Color) = {
            if AgentRosterPolicy.isDormantOrArchived(agent) {
                return ("archived", AppColors.textTertiary)
            }
            switch agent.rosterLane {
            case .activeMain:     return ("active", AppColors.accentSuccess)
            case .supportRuntime: return ("support", AppColors.accentSuccess.opacity(0.7))
            case .dormantArchive: return ("archived", AppColors.textTertiary)
            case .unknown:        return ("review", AppColors.accentWarning)
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
        }
    }

    // MARK: - LANES mini-strip (Addendum A.2: Merman lives here, not in WORKERS)

    private var lanesStrip: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LANES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            HStack(spacing: 10) {
                laneCard(emoji: "🧜‍♂️", name: "Merman", desc: "Triage (T2 rules)")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    private func laneCard(emoji: String, name: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - WORKERS Section (§4) — Slice 1: shell with hardcoded names; dispatch in later slice

    private var workersSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WORKERS · idle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Button {
                    // Slice 5 will wire dispatch sheet.
                } label: {
                    Text("+ Dispatch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            VStack(spacing: 0) {
                workerRow(emoji: "🧜‍♀️", name: "Mermaid", lane: "Bounded worker · briefs, evidence", status: "live", statusColor: AppColors.accentSuccess)
                Divider().background(AppColors.border).padding(.horizontal, 14)
                workerRow(emoji: "🐢", name: "Turtle", lane: "Slow-path coordinator", status: "building", statusColor: AppColors.accentWarning)
                Divider().background(AppColors.border).padding(.horizontal, 14)
                workerRow(emoji: "⛏️", name: "Miner", lane: "Index, extraction, mining", status: "live", statusColor: AppColors.accentSuccess)
                Divider().background(AppColors.border).padding(.horizontal, 14)
                workerRow(emoji: "🦪", name: "Pearl", lane: "Spawned Claude pearls (Maui-only)", status: "live", statusColor: AppColors.accentSuccess)
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
        }
    }

    private func workerRow(emoji: String, name: String, lane: String, status: String, statusColor: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.15)).frame(width: 36, height: 36)
                Text(emoji).font(.system(size: 20))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(lane)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    // MARK: - Skeleton / Empty helpers

    private var skeletonAgentRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(AppColors.backgroundTertiary).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(AppColors.backgroundTertiary).frame(width: 90, height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(AppColors.backgroundTertiary).frame(width: 140, height: 10)
                    }
                    Spacer()
                }
                .padding(14)
                Divider().background(AppColors.border)
            }
        }
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(14)
    }
}

// MARK: - Agent Focus Cards

private struct AgentFocusArea: Identifiable, Hashable {
    let id: String
    let label: String
    let evidenceRef: String?
}

private struct AgentFocusFish: Hashable {
    let name: String
    let icon: String
}

// L7c reshape (SPEC-POD-AGENT-FOCUS-CARDS v1, Tony 2026-05-25):
// Card = STRETCH (3 aspirational items) + ROADMAP (30d/60d/90d) + THIS WEEK + Fish + Today's 3.

private struct WeeklyMilestone: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let status: String  // "planned" | "shipped" | "dropped"

    var statusDot: String {
        switch status {
        case "shipped": return "✅"
        case "dropped": return "❌"
        default:        return "🔲"
        }
    }
}

private struct AgentRoadmap: Hashable {
    let d30: String
    let d60: String
    let d90: String

    static let empty = AgentRoadmap(d30: "", d60: "", d90: "")
}

private struct AgentFocusCard: Identifiable, Hashable {
    let agentId: String
    let displayName: String
    let emoji: String
    let charter: String
    let stretch: [String]            // 3 aspirational areas (REFRAME)
    let roadmap: AgentRoadmap         // 30d / 60d / 90d trajectory
    let thisWeek: [WeeklyMilestone]?  // Weekly plan milestones from /api/v1/agents/{name}/weekly-plan
    let focusAreas: [AgentFocusArea]  // Today's 3 from morning daily log
    let fish: AgentFocusFish
    let lastLogExcerpt: String?
    let lastUpdated: Date?
    let isSkeleton: Bool
    let hasStretch: Bool
    let hasRoadmap: Bool
    let hasFish: Bool
    let hasFocusAreas: Bool

    var id: String { agentId.lowercased() }

    var tint: Color {
        switch id {
        case "maui": return AppColors.accentSuccess
        case "aloha": return Color(hexString: "A855F7")
        case "chief": return Color(hexString: "22C55E")
        case "rooster": return AppColors.accentDanger
        default: return AppColors.accentElectric
        }
    }

    var lastUpdatedLabel: String {
        guard let lastUpdated else { return "pending" }
        return lastUpdated.relativeFormatted
    }

    static func skeleton(agentId: String) -> AgentFocusCard {
        let meta = AgentFocusDefaults.mainAgentMeta[agentId]!
        return AgentFocusCard(
            agentId: agentId,
            displayName: meta.name,
            emoji: meta.emoji,
            charter: meta.charter,
            stretch: [],
            roadmap: .empty,
            thisWeek: nil,
            focusAreas: [
                AgentFocusArea(id: "1", label: "", evidenceRef: nil),
                AgentFocusArea(id: "2", label: "", evidenceRef: nil),
                AgentFocusArea(id: "3", label: "", evidenceRef: nil)
            ],
            fish: AgentFocusFish(name: "—", icon: "—"),
            lastLogExcerpt: nil,
            lastUpdated: nil,
            isSkeleton: true,
            hasStretch: false,
            hasRoadmap: false,
            hasFish: false,
            hasFocusAreas: false
        )
    }
}

private struct AgentFocusDeputy: Identifiable {
    let id: String
    let displayName: String
    let emoji: String
    let currentTicket: String
    let statusColor: Color
}

private enum AgentFocusDefaults {
    static let mainAgentOrder = ["maui", "aloha", "chief", "rooster"]
    static let mainAgentMeta: [String: (name: String, emoji: String, charter: String)] = [
        "maui": ("Maui", "🪝", "Pod / Lifecycle / Compute / Codex orchestrator"),
        "aloha": ("Aloha", "🌸", "Backbone / Nerve / Flywheel / Doctrine gate"),
        "chief": ("Chief", "🦅", "Trading / P&L / Funding"),
        "rooster": ("Rooster", "🐓", "Security / Research / Knowledge")
    ]
}

@MainActor
@Observable
private final class AgentFocusCardsModel {
    private(set) var mainCards: [AgentFocusCard] = AgentFocusDefaults.mainAgentOrder.map { AgentFocusCard.skeleton(agentId: $0) }
    let deputies: [AgentFocusDeputy] = [
        AgentFocusDeputy(id: "coral", displayName: "Coral", emoji: "🪸", currentTicket: "Compute support", statusColor: AppColors.accentSuccess),
        AgentFocusDeputy(id: "reef", displayName: "Reef", emoji: "🐡", currentTicket: "Tools support", statusColor: AppColors.accentSuccess)
    ]
    private(set) var isLoading = false

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && mainCards.contains(where: { !$0.isSkeleton }) { return }

        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: AgentFocusCard.self) { group in
            for agentId in AgentFocusDefaults.mainAgentOrder {
                group.addTask {
                    await Self.loadCard(agentId: agentId)
                }
            }

            var loaded: [AgentFocusCard] = []
            for await card in group {
                loaded.append(card)
            }
            mainCards = AgentFocusDefaults.mainAgentOrder.compactMap { id in
                loaded.first { $0.id == id }
            }
        }
    }

    private static func loadCard(agentId: String) async -> AgentFocusCard {
        // Fetch focus card + weekly plan concurrently; graceful fallback on either.
        async let focusCardResult: AgentFocusCardDTO? = {
            (try? await APIClient.shared.get(path: "/api/v1/agents/\(agentId)/focus-card"))
        }()
        async let weeklyPlanResult: [WeeklyMilestone]? = {
            (try? await APIClient.shared.get(path: "/api/v1/agents/\(agentId)/weekly-plan"))
        }()

        let (dto, weeklyPlan) = await (focusCardResult, weeklyPlanResult)
        guard let dto else { return AgentFocusCard.skeleton(agentId: agentId) }
        return dto.toDomain(fallbackId: agentId, weeklyPlan: weeklyPlan)
    }
}

private struct AgentFocusCardDTO: Decodable {
    let agentId: String
    let displayName: String
    let charter: String
    let focusAreas: [FocusAreaDTO]
    let fish: FishDTO?
    let lastLogExcerpt: String?
    let lastUpdated: Date?
    let stretch: [String]?
    let roadmap: RoadmapDTO?
    let thisWeek: [WeeklyMilestone]?

    enum CodingKeys: String, CodingKey {
        case charter, fish, stretch, roadmap
        case agentId = "agent_id"
        case displayName = "display_name"
        case focusAreas = "focus_areas"
        case lastLogExcerpt = "last_log_excerpt"
        case lastUpdated = "last_updated"
        case thisWeek = "this_week"
    }

    func toDomain(fallbackId: String, weeklyPlan: [WeeklyMilestone]? = nil) -> AgentFocusCard {
        let id = agentId.lowercased()
        let meta = AgentFocusDefaults.mainAgentMeta[id] ?? AgentFocusDefaults.mainAgentMeta[fallbackId]!
        let normalizedAreas = Array(focusAreas.prefix(3)).enumerated().map { idx, area in
            AgentFocusArea(
                id: String(area.id ?? idx + 1),
                label: area.label,
                evidenceRef: area.evidenceRef
            )
        }
        let paddedAreas = normalizedAreas + (normalizedAreas.count..<3).map {
            AgentFocusArea(id: String($0 + 1), label: "", evidenceRef: nil)
        }

        let stretchValues = stretch.map { Array($0.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.prefix(3)) } ?? []
        let roadmapValue = roadmap.map { AgentRoadmap(d30: $0.d30 ?? "", d60: $0.d60 ?? "", d90: $0.d90 ?? "") }
            ?? .empty
        let fishValue = fish.map { AgentFocusFish(name: $0.name, icon: $0.icon) }
            ?? AgentFocusFish(name: "—", icon: "—")

        // weekly-plan endpoint takes precedence; DTO field is fallback; nil = endpoint not live yet.
        let thisWeekValue = weeklyPlan ?? thisWeek
        let hasRoadmap = !roadmapValue.d30.isEmpty || !roadmapValue.d60.isEmpty || !roadmapValue.d90.isEmpty
        let hasFish = fishValue.name != "—" || fishValue.icon != "—"
        let hasFocusAreas = paddedAreas.contains { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return AgentFocusCard(
            agentId: id,
            displayName: displayName.replacingOccurrences(of: meta.emoji, with: "").trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: meta.emoji,
            charter: charter.isEmpty ? meta.charter : charter,
            stretch: stretchValues,
            roadmap: roadmapValue,
            thisWeek: thisWeekValue,
            focusAreas: paddedAreas,
            fish: fishValue,
            lastLogExcerpt: lastLogExcerpt,
            lastUpdated: lastUpdated,
            isSkeleton: false,
            hasStretch: !stretchValues.isEmpty,
            hasRoadmap: hasRoadmap,
            hasFish: hasFish,
            hasFocusAreas: hasFocusAreas
        )
    }

    struct FocusAreaDTO: Decodable {
        let id: Int?
        let label: String
        let evidenceRef: String?

        enum CodingKeys: String, CodingKey {
            case id, label
            case evidenceRef = "evidence_ref"
        }
    }

    struct FishDTO: Decodable {
        let name: String
        let icon: String
    }

    struct RoadmapDTO: Decodable {
        let d30: String?
        let d60: String?
        let d90: String?

        enum CodingKeys: String, CodingKey {
            case d30 = "30d"
            case d60 = "60d"
            case d90 = "90d"
        }
    }
}

private struct AgentFocusCardDetailSheet: View {
    let card: AgentFocusCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Text(card.emoji)
                            .font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(AppColors.textPrimary)
                            Text(card.charter)
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Spacer()
                    }

                    // STRETCH (3 aspirational areas)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STRETCH")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.textTertiary)
                            .kerning(0.5)
                        if card.hasStretch {
                            ForEach(Array(card.stretch.prefix(3).enumerated()), id: \.offset) { idx, item in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(idx + 1).")
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundColor(AppColors.textTertiary)
                                    Text(item)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(AppColors.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        } else {
                            detailPendingRow("ORCA has not published stretch areas for this agent.")
                        }
                    }

                    // ROADMAP (30d/60d/90d trajectory)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROADMAP")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.textTertiary)
                            .kerning(0.5)
                        if card.hasRoadmap {
                            detailRoadmapRow("30d", card.roadmap.d30)
                            detailRoadmapRow("60d", card.roadmap.d60)
                            detailRoadmapRow("90d", card.roadmap.d90)
                        } else {
                            detailPendingRow("ORCA has not published a roadmap for this agent.")
                        }
                    }

                    HStack {
                        if card.hasFish {
                            fishPill
                        } else {
                            detailPendingPill("Fish pending")
                        }
                        Spacer()
                        Text(card.lastUpdatedLabel)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                    }

                    // Today's 3 from morning daily log
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TODAY'S 3 (from morning log)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.textTertiary)
                            .kerning(0.5)
                        if card.hasFocusAreas {
                            ForEach(Array(card.focusAreas.prefix(3).enumerated()), id: \.offset) { idx, area in
                                if !area.label.isEmpty {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(idx + 1).")
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                            .foregroundColor(AppColors.textTertiary)
                                        Text(area.label)
                                            .font(.system(size: 13))
                                            .foregroundColor(AppColors.textPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        } else {
                            detailPendingRow("ORCA has not published today's focus areas.")
                        }
                    }

                    if let excerpt = card.lastLogExcerpt, !excerpt.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LAST LOG")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.textTertiary)
                                .kerning(0.5)
                            Text(excerpt)
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(20)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Focus Card")
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

    private var fishPill: some View {
        HStack(spacing: 5) {
            Text(card.fish.icon)
            Text(card.fish.name)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(AppColors.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(AppColors.backgroundSecondary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
    }

    private func detailRoadmapRow(_ horizon: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(horizon)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(AppColors.accentElectric)
                .frame(width: 36, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13))
                .foregroundColor(value.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailPendingRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(AppColors.textTertiary)
    }

    private func detailPendingPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppColors.backgroundSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
    }
}

// MARK: - Agent Status Extension (kept for back-compat with other surfaces)

extension AgentState {
    var color: Color {
        switch self {
        case .online: return AppColors.accentSuccess
        case .busy:   return AppColors.accentWarning
        case .idle:   return AppColors.textTertiary
        case .offline: return AppColors.textMuted
        case .error:  return AppColors.accentDanger
        case .provisioning: return AppColors.accentWarning
        }
    }

    static var displayOrder: [AgentState] {
        [.online, .busy, .idle, .error, .offline]
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
