import SwiftUI

// MARK: - LabView
//
// Per SPEC-POD-LAB-TAB-2026-05-23. The product catalog surface — what we have, who runs it, what's spinning.
// Mirrors Team-Wiki/operating-system/LAB-SYSTEMS-INDEX.md through ORCA's wiki bridge.

struct LabView: View {

    // Per-section expand/collapse state (default per spec §2).
    @State private var catalogModel = LabCatalogModel()
    @State private var workflowCatalogModel = LabWorkflowCatalogModel()
    @State private var researchFlywheelModel = LabResearchFlywheelModel()
    @State private var fundLandingModel = FundLandingViewModel()
    @State private var fundUniverseLoopModel = FundUniverseLoopViewModel()
    @State private var fundProductsModel = LabFundProductsModel()
    @State private var fishExpanded      = false
    @State private var liveExperimentsExpanded = true
    @State private var fundResearchExpanded = true
    @State private var workflowsExpanded = false
    @State private var showingFishFeedSheet = false
    @State private var fishFeedTitle = ""
    @State private var fishFeedSummary = ""
    @State private var fishFeedLane = "next"
    @State private var fishFeedPriority = "high"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 44)
                        .padding(.bottom, 8)

                    fishSection
                    fundResearchSection
                    liveExperimentsSection
                    workflowsSection
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
                .safeAreaInset(edge: .top) {
                    AppColors.backgroundPrimary
                        .frame(height: 6)
                }
                .task {
                    await catalogModel.load()
                    await workflowCatalogModel.load()
                    await researchFlywheelModel.load()
                    await fundLandingModel.load()
                    await fundUniverseLoopModel.load()
                    await fundProductsModel.load()
                }
                .refreshable {
                    await catalogModel.load(force: true)
                    await workflowCatalogModel.load(force: true)
                    await researchFlywheelModel.load(force: true)
                    await fundLandingModel.load()
                    await fundUniverseLoopModel.load()
                    await fundProductsModel.load()
                }
                .sheet(isPresented: $showingFishFeedSheet) {
                    StarfishFeedStageSheet(
                        title: $fishFeedTitle,
                        summary: $fishFeedSummary,
                        lane: $fishFeedLane,
                        priority: $fishFeedPriority,
                        isStaging: researchFlywheelModel.isStaging
                    ) {
                        await stageStarfishFeed()
                    }
                }
        }
    }

    private func stageStarfishFeed() async {
        let staged = await researchFlywheelModel.stageStarfishFeed(
            title: fishFeedTitle,
            summary: fishFeedSummary,
            lane: fishFeedLane,
            priority: fishFeedPriority
        )
        guard staged else { return }
        fishFeedTitle = ""
        fishFeedSummary = ""
        fishFeedLane = "next"
        fishFeedPriority = "high"
        showingFishFeedSheet = false
    }

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lab")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            Text("Experiments: fish agents, protected research lanes, and workflows.")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Section card scaffold

    @ViewBuilder
    private func sectionCard<Header: View, Body: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> Body
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            body()
        }
        .background(AppColors.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func sectionHeader(title: String, count: Int? = nil, expanded: Bool, rightLabel: String? = nil, rightAction: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.textSecondary)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            if let count = count {
                Text("· \(count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
            if let label = rightLabel {
                Button {
                    rightAction?()
                } label: {
                    HStack(spacing: 2) {
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.accentElectric)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColors.accentElectric)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - FISH section
    //
    // Per LAB-SYSTEMS-INDEX §11: Fish are the *research substrate fleet* (Starfish, Chieffish).
    // The Crew (named operators + workers + compute) lives on the Agents tab — Lab does not duplicate.

    private var fishSection: some View {
        let liveFish = researchFlywheelModel.flywheel?.fish?.fish ?? []
        let total = liveFish.isEmpty
            ? catalogModel.fishFleet.count + catalogModel.fishAdjacent.count
            : liveFish.count + catalogModel.fishAdjacent.count
        return sectionCard {
            sectionHeader(title: "THE FISH 🐠", count: total, expanded: fishExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { fishExpanded.toggle() }
                }
        } body: {
            if fishExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    fishHeaderNote
                    fishFlywheelSummary
                    fishNextActionCard
                    starfishFeedStageCard
                    if liveFish.isEmpty {
                        fishStrip(title: "Research substrate fleet", fish: catalogModel.fishFleet)
                    } else {
                        liveFishStrip(title: "Live Workbench fish", fish: liveFish)
                    }
                    fishStrip(title: "Adjacent (chief-local, not Pod-surfaced)", fish: catalogModel.fishAdjacent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var fishHeaderNote: some View {
        Text("Long-running autonomous research agents. Each has a partner-operator who owns its directive queue. Not operators, not workers.")
            .font(.system(size: 11))
            .italic()
            .foregroundColor(AppColors.textTertiary)
    }

    private var fishNextActionCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppColors.accentElectric)
                .frame(width: 28, height: 28)
                .background(AppColors.accentElectric.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text("How to use this")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("Feed fish from Planner/Workbench, turn findings into Research Rail packets, then promote reviewed output into tasks, memory, or explicit dead ends.")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var fishFlywheelSummary: some View {
        let flywheel = researchFlywheelModel.flywheel
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                sourcePill(researchFlywheelModel.sourceLabel)
                if researchFlywheelModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                }
                if let generatedAt = flywheel?.generatedAt {
                    Text(generatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                if let error = researchFlywheelModel.error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }

            if let flywheel {
                let fishSummary = flywheel.fish?.summary ?? .empty
                let refSummary = flywheel.referenceCandidates?.summary
                let railCounts = flywheel.researchRail?.counts
                let fishRows = flywheel.fish?.fish ?? []
                let queueCount = fishRows.reduce(0) { total, item in
                    total + (item.queue?.pendingCount ?? 0)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    fishMetric("Fish", "\(fishSummary.count)", AppColors.accentElectric)
                    fishMetric("Blocked", "\(fishSummary.blocked)", fishSummary.blocked > 0 ? AppColors.accentWarning : AppColors.accentSuccess)
                    fishMetric("Refs", "\(refSummary?.instanceCount ?? 0)", AppColors.accentSuccess)
                    fishMetric("Requests", "\(railCounts?.activeRequests ?? 0)", AppColors.accentElectric)
                    fishMetric("Review", "\(railCounts?.awaitingReview ?? 0)", (railCounts?.awaitingReview ?? 0) > 0 ? AppColors.accentWarning : AppColors.accentSuccess)
                    fishMetric("Queue", "\(queueCount)", AppColors.textSecondary)
                }

                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    fishPolicyPill(flywheel.mode ?? "read only", clean: true)
                    fishPolicyPill(flywheel.sideEffects ?? "none", clean: true)
                    if let policy = flywheel.bodyPolicy {
                        fishPolicyPill("body reads \(policy.sourceBodiesRead ? "on" : "off")", clean: !policy.sourceBodiesRead)
                        fishPolicyPill("embeddings \(policy.embeddingsCreated ? "on" : "off")", clean: !policy.embeddingsCreated)
                        if let protectedResearch = policy.protectedResearch {
                            fishPolicyPill(protectedResearch.labDisplayLabel, clean: true)
                        }
                    }
                }

                if let loop = flywheel.flywheel?.recommendedReviewLoop {
                    Text(loop)
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var starfishFeedStageCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Starfish feed")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Planner staging for Maui")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer(minLength: 8)
                Button {
                    showingFishFeedSheet = true
                } label: {
                    Label("Stage", systemImage: "tray.and.arrow.down")
                        .font(.system(size: 12, weight: .bold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppColors.accentElectric.opacity(0.14))
                        .foregroundColor(AppColors.accentElectric)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(researchFlywheelModel.isStaging)
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                stageStatusPill("planner item", color: AppColors.accentSuccess)
                stageStatusPill("fish wake off", color: AppColors.textTertiary)
                stageStatusPill("queue write off", color: AppColors.textTertiary)
                if researchFlywheelModel.isStaging {
                    stageStatusPill("staging", color: AppColors.accentElectric)
                }
            }

            if let response = researchFlywheelModel.stageResponse {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Planner \(response.plannerItemId.prefix(8))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppColors.accentSuccess)
                    Text(response.sourceRef)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            if let error = researchFlywheelModel.stageError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.accentWarning)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stageStatusPill(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppColors.backgroundSecondary)
            .clipShape(Capsule())
    }

    private func fishMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fishPolicyPill(_ text: String, clean: Bool) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(clean ? AppColors.accentSuccess : AppColors.accentWarning)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppColors.backgroundSecondary)
            .clipShape(Capsule())
    }

    // MARK: - PROTECTED FUND RESEARCH section

    private var fundResearchSection: some View {
        let count = 2 + fundProductsModel.products.count
        return sectionCard {
            sectionHeader(title: "CHIEF/FUND RESEARCH", count: count, expanded: fundResearchExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { fundResearchExpanded.toggle() }
                }
        } body: {
            if fundResearchExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    fundResearchPolicyNote
                    fundLandingLabCard
                    fundUniverseLoopLabCard
                    fundProductStrip
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var fundResearchPolicyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppColors.accentWarning)
                .frame(width: 28, height: 28)
                .background(AppColors.accentWarning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text("Protected read-only lane")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("Lab shows research readiness, freshness, queues, and product status. No P&L expansion, broker actions, orders, positions, wallets, kill switches, or runtime mutations.")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(AppColors.accentWarning.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fundLandingLabCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "building.columns")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.accentWarning)
                Text("Fund OS Landing")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if fundLandingModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let landing = fundLandingModel.landing {
                    labStatusPill(landing.isAvailable ? "ORCA LIVE" : "DEGRADED", color: landing.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning)
                } else {
                    labStatusPill("WAITING", color: AppColors.textTertiary)
                }
            }

            if let landing = fundLandingModel.landing {
                Text(landing.degradedReason ?? "Chief's protected Fund snapshot is available through ORCA. Sensitive financial bodies stay out of Lab.")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    fundLabMetric("Mode", landing.mode ?? "—")
                    fundLabMetric("Readiness", landing.readiness ?? "—")
                    fundLabMetric("Gate", labBoolLabel(landing.gateReady))
                    fundLabMetric("Trades", landing.closedTrades.map(String.init) ?? "—")
                    fundLabMetric("Sharpe", labNumber(landing.sharpe))
                    fundLabMetric("Sync", landing.freshnessLabel)
                    fundLabMetric("REQ-008", labReq008Label(landing))
                    fundLabMetric("Promote", landing.promotionDecision ?? "—")
                    fundLabMetric("Data App", landing.summary?.dataApplicationStatus ?? landing.agentLanding?.dataApplication?.status ?? "—")
                }

                if !landing.blockers.isEmpty {
                    labCompactTextList(title: "Blockers", values: landing.blockers)
                }

                Text("Route: \(landing.route) · \(landing.sourceFresh ? "source fresh" : "source stale") · generated \(landing.generatedAt ?? "unknown")")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            } else {
                Text(fundLandingModel.errorMessage ?? "Waiting for ORCA Fund landing route.")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fundUniverseLoopLabCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                Text("Universe Loop")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if fundUniverseLoopModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let response = fundUniverseLoopModel.response {
                    labStatusPill(response.isAvailable ? "READ-ONLY" : "DEGRADED", color: response.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning)
                } else {
                    labStatusPill("WAITING", color: AppColors.textTertiary)
                }
            }

            if let response = fundUniverseLoopModel.response, let loop = response.data {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    fundLabMetric("Status", loop.displayStatus)
                    fundLabMetric("Miner", loop.minerStatus ?? "—")
                    fundLabMetric("Queue", loop.queueItems.map(String.init) ?? "—")
                    fundLabMetric("Reviews", loop.completedReviews.map(String.init) ?? "—")
                    fundLabMetric("Calibrate", loop.calibrationPendingRows.map(String.init) ?? "—")
                    fundLabMetric("Route", loop.routeImplementation ?? "—")
                }

                if let urgentSymbols = loop.urgentSymbols, !urgentSymbols.isEmpty {
                    labTokenRow(title: "Urgent queue", values: urgentSymbols)
                }

                let blockers = loop.displayBlockers
                if !blockers.isEmpty {
                    labCompactTextList(title: "Blockers", values: blockers)
                }

                if let nextActions = loop.nextActions, !nextActions.isEmpty {
                    labCompactTextList(title: "Next actions", values: nextActions)
                }

                Text("Route: \(response.route) · \(response.freshnessLabel) · \(response.readPolicy)")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            } else {
                Text(fundUniverseLoopModel.response?.degradedReason ?? fundUniverseLoopModel.errorMessage ?? "Waiting for ORCA Universe Loop route.")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fundProductStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("FUND RESEARCH PRODUCTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .tracking(0.5)
                Spacer()
                if fundProductsModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }

            if let error = fundProductsModel.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(fundProductsModel.products) { product in
                        fundProductCard(product)
                    }
                }
            }
        }
    }

    private func fundProductCard(_ product: LabFundProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: product.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(product.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning)
                    .frame(width: 28, height: 28)
                    .background((product.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)
                    Text(product.section.labDisplayLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            labStatusPill(product.isAvailable ? "AVAILABLE" : "DEGRADED", color: product.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning)

            Text(product.headline)
                .font(.system(size: 10))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                liveFishChip("keys \(product.dataKeyCount)", color: AppColors.textTertiary)
                liveFishChip(product.sourceFresh ? "fresh" : "stale", color: product.sourceFresh ? AppColors.accentSuccess : AppColors.accentWarning)
                liveFishChip(product.sourceAgeLabel, color: AppColors.textTertiary)
            }
        }
        .frame(width: 174, alignment: .topLeading)
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fundLabMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func labStatusPill(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func labCompactTextList(title: String, values: [String]) -> some View {
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

    private func labTokenRow(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.accentWarning)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(AppColors.accentWarning.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func labNumber(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    private func labBoolLabel(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "Yes" : "No"
    }

    private func labReq008Label(_ landing: FundLanding) -> String {
        let concentration = landing.req008OiConcentrationEth.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—"
        let threshold = landing.req008ThresholdPercent.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
        let breached = landing.req008Breached == true ? "breach" : "ok"
        return "\(concentration)/\(threshold)% · \(breached)"
    }

    // MARK: - LIVE EXPERIMENTS section

    private var liveExperimentsSection: some View {
        let total = catalogModel.projectSections.isEmpty
            ? catalogModel.currentlySpinning.count + catalogModel.currentlyBuilding.count
            : catalogModel.projectSections.reduce(0) { $0 + $1.projects.count }
        return sectionCard {
            sectionHeader(
                title: "LIVE EXPERIMENTS",
                count: total,
                expanded: liveExperimentsExpanded
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { liveExperimentsExpanded.toggle() }
            }
        } body: {
            if liveExperimentsExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        sourcePill(catalogModel.sourceLabel)
                        if catalogModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.65)
                        }
                        if let error = catalogModel.error {
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(2)
                        }
                    }

                    if catalogModel.projectSections.isEmpty {
                        experimentSpinningRows(catalogModel.currentlySpinning)
                        experimentBuildingRows(catalogModel.currentlyBuilding)
                    } else {
                        ForEach(catalogModel.projectSections) { section in
                            experimentProjectSection(section)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private func sourcePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(text == "ORCA" ? AppColors.accentSuccess : AppColors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.backgroundTertiary.opacity(0.75))
            .clipShape(Capsule())
    }

    private func experimentSpinningRows(_ items: [LabSpinningItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SPINNING NOW")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .tracking(0.5)
            ForEach(items) { item in
                experimentRow(title: item.title, stage: item.stage, owner: item.owner, layer: nil)
            }
        }
    }

    private func experimentBuildingRows(_ items: [LabBuildingItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE / BUILDING")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .tracking(0.5)
            ForEach(items) { item in
                experimentRow(title: item.title, stage: item.stage, owner: item.owner, layer: item.layer ?? item.shortId)
            }
        }
    }

    private func experimentProjectSection(_ section: LabProjectSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.layer.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .tracking(0.5)
            ForEach(section.projects) { project in
                experimentRow(title: project.title, stage: project.stage, owner: project.owner, layer: project.shortId)
            }
        }
    }

    private func experimentRow(title: String, stage: String, owner: String, layer: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                if let layer, !layer.isEmpty {
                    Text(layer)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(owner)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(AppColors.textSecondary)
            Text(stage)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.accentSuccess.opacity(stage.localizedCaseInsensitiveContains("live") ? 0.16 : 0.08))
                .foregroundColor(stage.localizedCaseInsensitiveContains("live") ? AppColors.accentSuccess : AppColors.accentCaptain)
                .clipShape(Capsule())
        }
        .padding(8)
        .background(AppColors.backgroundTertiary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - WORKFLOWS + PROTOCOLS section
    //
    // Per LAB-SYSTEMS-INDEX §13: STANDARDS govern what's right; PROTOCOLS govern how we coordinate.
    // Surfaces the canonical doctrine catalog so Tony + new agents can see procedure without grepping.

    private var workflowsSection: some View {
        let groups = workflowCatalogModel.groups
        let total = groups.reduce(0) { $0 + $1.items.count }
        return sectionCard {
            sectionHeader(title: "WORKFLOWS + PROTOCOLS", count: total, expanded: workflowsExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { workflowsExpanded.toggle() }
                }
        } body: {
            if workflowsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text(workflowCatalogModel.sourceLabel)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(workflowCatalogModel.sourceLabel == "ORCA" ? AppColors.accentSuccess : AppColors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.backgroundTertiary.opacity(0.75))
                            .clipShape(Capsule())
                        if workflowCatalogModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.65)
                        }
                        if let error = workflowCatalogModel.error {
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(2)
                        }
                    }

                    ForEach(groups) { group in
                        workflowGroupView(group)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private func workflowGroupView(_ group: LabWorkflowGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .tracking(0.5)
            ForEach(group.items) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer(minLength: 6)
                    Text(item.status)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(item.statusColor.opacity(0.15))
                        .foregroundColor(item.statusColor)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func fishStrip(title: String, fish: [LabFish]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .tracking(0.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(fish) { f in
                        fishCard(f)
                    }
                }
            }
        }
    }

    private func fishCard(_ f: LabFish) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(AppColors.backgroundTertiary)
                        .frame(width: 48, height: 48)
                    Text(f.emoji)
                        .font(.system(size: 26))
                }
                Circle()
                    .fill(f.status.color)
                    .frame(width: 7, height: 7)
                    .padding(2)
            }
            Text(f.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
            Text(f.role)
                .font(.system(size: 10))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 110)
        .padding(8)
        .background(AppColors.backgroundTertiary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func liveFishStrip(title: String, fish: [WorkbenchFishStatus]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .tracking(0.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(fish) { item in
                        liveFishCard(item)
                    }
                }
            }
        }
    }

    private func liveFishCard(_ item: WorkbenchFishStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(fishStatusColor(item).opacity(0.18))
                    .overlay(
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(fishStatusColor(item))
                    )
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fish.labDisplayLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(item.owner?.uppercased() ?? "ORCA")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer(minLength: 4)
            }

            Text((item.runtimeStatus ?? "unknown").labDisplayLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(fishStatusColor(item))
                .lineLimit(1)

            if let directive = item.directiveSlug, !directive.isEmpty {
                Text(directive.labDisplayLabel)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }

            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                liveFishChip("findings \(item.findings?.count ?? item.indexedFindings ?? 0)", color: AppColors.accentSuccess)
                liveFishChip("queue \(item.queue?.pendingCount ?? 0)", color: (item.queue?.pendingCount ?? 0) > 0 ? AppColors.accentWarning : AppColors.textTertiary)
                if item.autoresearch?.configured == true {
                    liveFishChip("autoresearch", color: AppColors.accentElectric)
                }
            }

            if let reason = item.statusReason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(width: 168, alignment: .topLeading)
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func liveFishChip(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppColors.backgroundSecondary)
            .clipShape(Capsule())
    }

    private func fishStatusColor(_ item: WorkbenchFishStatus) -> Color {
        let status = (item.runtimeStatus ?? "").lowercased()
        if status.contains("blocked") { return AppColors.accentWarning }
        if status.contains("producing") || status.contains("ready") { return AppColors.accentSuccess }
        if status.contains("idle") { return AppColors.textTertiary }
        return AppColors.accentElectric
    }

}

private struct StarfishFeedStageSheet: View {
    @Binding var title: String
    @Binding var summary: String
    @Binding var lane: String
    @Binding var priority: String

    let isStaging: Bool
    let onStage: () async -> Void

    @Environment(\.dismiss) private var dismiss

    private var canStage: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStaging
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            stageSheetPill("Starfish", color: AppColors.accentElectric)
                            stageSheetPill("Maui", color: AppColors.accentSuccess)
                            stageSheetPill("Planner only", color: AppColors.textTertiary)
                        }

                        TextField("Directive title", text: $title, axis: .vertical)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.sentences)
                            .padding(10)
                            .background(AppColors.backgroundTertiary.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        TextField("Directive summary", text: $summary, axis: .vertical)
                            .font(.system(size: 13))
                            .lineLimit(3...7)
                            .textInputAutocapitalization(.sentences)
                            .padding(10)
                            .background(AppColors.backgroundTertiary.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("LANE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)
                        Picker("Lane", selection: $lane) {
                            Text("Now").tag("now")
                            Text("Next").tag("next")
                            Text("Waiting").tag("waiting")
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRIORITY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)
                        Picker("Priority", selection: $priority) {
                            Text("Low").tag("low")
                            Text("Medium").tag("medium")
                            Text("High").tag("high")
                        }
                        .pickerStyle(.segmented)
                    }

                    Button {
                        Task { await onStage() }
                    } label: {
                        HStack(spacing: 8) {
                            if isStaging {
                                ProgressView()
                                    .scaleEffect(0.75)
                            } else {
                                Image(systemName: "tray.and.arrow.down.fill")
                            }
                            Text(isStaging ? "Staging" : "Stage to Planner")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(canStage ? AppColors.accentElectric.opacity(0.18) : AppColors.backgroundTertiary.opacity(0.5))
                        .foregroundColor(canStage ? AppColors.accentElectric : AppColors.textTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStage)
                }
                .padding(18)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Starfish Feed")
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

    private func stageSheetPill(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppColors.backgroundTertiary.opacity(0.75))
            .clipShape(Capsule())
    }
}

// MARK: - ORCA-backed Lab catalog

private extension String {
    var labDisplayLabel: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    var labNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

@MainActor
@Observable
private final class LabResearchFlywheelModel {
    private(set) var flywheel: WorkbenchResearchFlywheel?
    private(set) var isLoading = false
    private(set) var isStaging = false
    private(set) var error: String?
    private(set) var stageError: String?
    private(set) var stageResponse: WorkbenchFishFeedStageResponse?
    private(set) var sourceLabel = "WORKBENCH"

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && flywheel != nil { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            flywheel = try await WorkbenchRepository().loadResearchFlywheel()
            sourceLabel = "WORKBENCH"
        } catch {
            flywheel = nil
            sourceLabel = "ORCA ERROR"
            self.error = "Research flywheel unavailable."
        }
    }

    func stageStarfishFeed(title: String, summary: String, lane: String, priority: String) async -> Bool {
        guard !isStaging else { return false }
        guard let cleanTitle = title.labNilIfBlank else {
            stageError = "Directive title required."
            return false
        }

        isStaging = true
        stageError = nil
        defer { isStaging = false }

        do {
            let request = WorkbenchFishFeedStageRequest(
                directiveTitle: cleanTitle,
                directiveSummary: summary.labNilIfBlank,
                lane: lane,
                priority: priority,
                traceId: "pod-workbench-\(UUID().uuidString)"
            )
            stageResponse = try await WorkbenchRepository().stageFishFeed(request)
            await load(force: true)
            return true
        } catch {
            stageError = "Starfish stage blocked or unavailable."
            return false
        }
    }
}

@MainActor
@Observable
final class LabCatalogModel {
    private(set) var stack: [LabStackLayer] = []
    private(set) var fishFleet: [LabFish] = []
    private(set) var fishAdjacent: [LabFish] = []
    private(set) var currentlySpinning: [LabSpinningItem] = []
    private(set) var projectSections: [LabProjectSection] = []
    private(set) var currentlyBuilding: [LabBuildingItem] = []
    private(set) var retiredItems: [LabRetiredItem] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var sourceLabel = "ORCA"

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && !stack.isEmpty { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: LabSectionsResponse = try await APIClient.shared.get(path: "/api/v1/lab/sections")
            let sections = Self.projectSections(from: response)
            guard !sections.isEmpty else {
                throw APIError.message("Lab sections parsed empty.", code: nil)
            }
            applyStaticContent()
            projectSections = sections
            currentlyBuilding = sections.flatMap(\.projects)
            sourceLabel = "ORCA"
        } catch {
            applyStaticContent()
            sourceLabel = "FALLBACK"
            self.error = "ORCA Lab sections unavailable."
        }
    }

    private func applyStaticContent() {
        stack = LabContent.stack
        fishFleet = LabContent.fishFleet
        fishAdjacent = LabContent.fishAdjacent
        currentlySpinning = LabContent.currentlySpinning
        projectSections = []
        currentlyBuilding = LabContent.currentlyBuilding
        retiredItems = LabContent.retiredItems
    }

    private struct ParsedCatalog {
        let stack: [LabStackLayer]
        let fishFleet: [LabFish]
        let fishAdjacent: [LabFish]
        let currentlySpinning: [LabSpinningItem]
        let currentlyBuilding: [LabBuildingItem]
        let retiredItems: [LabRetiredItem]
    }

    private static func parse(markdown: String) -> ParsedCatalog {
        let control = tableRows(in: markdown, headingPrefix: "## 1 ")
        let operating = tableRows(in: markdown, headingPrefix: "## 2 ")
        let compute = tableRows(in: markdown, headingPrefix: "## 3 ")
        let transport = tableRows(in: markdown, headingPrefix: "## 4 ")
        let memory = tableRows(in: markdown, headingPrefix: "## 5 ")
        let ops = tableRows(in: markdown, headingPrefix: "## 6 ")
        let stackRows = Array((control + operating + compute + transport + memory + ops).prefix(40))
        let stack = stackRows.compactMap(stackLayer(from:))
        let fishRows = tableRows(in: markdown, headingPrefix: "## 11 ")
        let fish = fishRows.compactMap(fishItem(from:))
        let buildingRows = tableRows(in: markdown, headingPrefix: "## 9 ")
        let building = buildingRows.compactMap(buildingItem(from:))
        let spinning = bulletItems(in: markdown, headingPrefix: "## 12 ")
            .prefix(8)
            .map { LabSpinningItem(title: $0, stage: "Experiment", owner: "ORCA") }

        return ParsedCatalog(
            stack: stack,
            fishFleet: fish.filter { $0.id != "octopus" },
            fishAdjacent: fish.filter { $0.id == "octopus" },
            currentlySpinning: Array(spinning),
            currentlyBuilding: building,
            retiredItems: []
        )
    }

    private static func projectSections(from response: LabSectionsResponse) -> [LabProjectSection] {
        response.sections.compactMap { section in
            let projects = section.projects.map { project in
                LabBuildingItem(
                    title: project.name,
                    stage: project.stage.isEmpty ? project.status : project.stage,
                    owner: layerCode(section.layer),
                    shortId: String(project.id.prefix(8)),
                    layer: section.layer
                )
            }
            guard !projects.isEmpty else { return nil }
            return LabProjectSection(layer: section.layer, boardId: section.boardId, projects: projects)
        }
    }

    private static func stackLayer(from columns: [String]) -> LabStackLayer? {
        guard columns.count >= 4 else { return nil }
        let title = stripMarkdown(columns[0])
        guard !title.isEmpty else { return nil }
        let id = slug(title)
        let status = labStatus(columns[1])
        let owner = ownerCode(columns[2])
        return LabStackLayer(
            id: id,
            title: title,
            oneLine: stripMarkdown(columns[3]),
            status: status,
            owner: owner,
            icon: icon(for: id),
            tint: tint(for: id, status: status)
        )
    }

    private static func fishItem(from columns: [String]) -> LabFish? {
        guard columns.count >= 5 else { return nil }
        let emoji = stripMarkdown(columns[0])
        let name = stripMarkdown(columns[1])
        guard !name.isEmpty else { return nil }
        let partner = stripMarkdown(columns[2])
        let lane = stripMarkdown(columns[3])
        return LabFish(
            id: slug(name),
            emoji: emoji.isEmpty ? "•" : emoji,
            name: name,
            role: "\(lane) · partner: \(partner)",
            status: labStatus(columns[4])
        )
    }

    private static func buildingItem(from columns: [String]) -> LabBuildingItem? {
        guard columns.count >= 4 else { return nil }
        let title = stripMarkdown(columns[0])
        guard !title.isEmpty else { return nil }
        return LabBuildingItem(
            title: title,
            stage: stripMarkdown(columns[1]),
            owner: ownerCode(columns[2]),
            shortId: shortRef(from: columns[0]),
            layer: nil
        )
    }

    private static func tableRows(in markdown: String, headingPrefix: String) -> [[String]] {
        guard let section = sectionText(in: markdown, headingPrefix: headingPrefix) else { return [] }
        return section
            .components(separatedBy: "\n")
            .compactMap { line in
                let columns = markdownTableColumns(line)
                guard !columns.isEmpty, !columns.contains(where: { $0.lowercased() == "system" || $0.lowercased() == "project" }) else {
                    return nil
                }
                return columns
            }
    }

    private static func bulletItems(in markdown: String, headingPrefix: String) -> [String] {
        guard let section = sectionText(in: markdown, headingPrefix: headingPrefix) else { return [] }
        return section
            .components(separatedBy: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("- ") else { return nil }
                let item = stripMarkdown(String(trimmed.dropFirst(2)))
                return item.isEmpty ? nil : item
            }
    }

    private static func sectionText(in markdown: String, headingPrefix: String) -> String? {
        let lines = markdown.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix(headingPrefix) }) else { return nil }
        let tail = lines[(start + 1)...]
        let endOffset = tail.firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.endIndex
        return lines[(start + 1)..<endOffset].joined(separator: "\n")
    }

    fileprivate static func markdownTableColumns(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|"), !trimmed.contains("---") else { return [] }
        return trimmed
            .dropFirst()
            .dropLast()
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    fileprivate static func stripMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: #"^\[(.*?)\]\(.*?\)"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func slug(_ value: String) -> String {
        stripMarkdown(value)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func labStatus(_ value: String) -> LabStatus {
        let lower = value.lowercased()
        if lower.contains("retired") || lower.contains("archived") { return .retired }
        if lower.contains("live") || lower.contains("active") || lower.contains("protected") { return .live }
        if lower.contains("building") || lower.contains("signed") { return .building }
        if lower.contains("partial") || lower.contains("prototype") || lower.contains("blueprint") { return .partial }
        return .planned
    }

    private static func ownerCode(_ value: String) -> String {
        let cleaned = stripMarkdown(value)
            .replacingOccurrences(of: #"[^A-Za-z]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = cleaned.components(separatedBy: " ").first, !first.isEmpty else { return "ORCA" }
        return String(first.prefix(3)).uppercased()
    }

    private static func layerCode(_ value: String) -> String {
        switch value.lowercased() {
        case "products":
            return "PRO"
        case "platform":
            return "PLT"
        default:
            return ownerCode(value)
        }
    }

    private static func shortRef(from value: String) -> String {
        if let match = value.range(of: #"`([^`]+)`"#, options: .regularExpression) {
            return value[match].replacingOccurrences(of: "`", with: "")
        }
        return String(slug(value).prefix(8))
    }

    private static func icon(for id: String) -> String {
        if id.contains("orca") { return "server.rack" }
        if id.contains("pod") { return "ipad.landscape" }
        if id.contains("wiki") { return "books.vertical.fill" }
        if id.contains("nats") || id.contains("track-b") { return "point.3.connected.trianglepath.dotted" }
        if id.contains("compute") || id.contains("spark") || id.contains("kimi") { return "cpu.fill" }
        if id.contains("memory") || id.contains("chroma") { return "brain" }
        if id.contains("schoolhouse") { return "graduationcap.fill" }
        return "square.stack.3d.up.fill"
    }

    private static func tint(for id: String, status: LabStatus) -> Color {
        if id.contains("nats") { return AppColors.accentSuccess }
        if id.contains("pod") || id.contains("orca") { return AppColors.accentElectric }
        return status.color
    }
}

struct LabProjectSection: Identifiable {
    let layer: String
    let boardId: String
    let projects: [LabBuildingItem]

    var id: String { boardId }
}

private struct LabSectionsResponse: Decodable {
    let sections: [LabSectionResponse]
}

private struct LabSectionResponse: Decodable {
    let layer: String
    let boardId: String
    let projects: [LabProjectResponse]

    enum CodingKeys: String, CodingKey {
        case layer
        case boardId = "board_id"
        case projects
    }
}

private struct LabProjectResponse: Decodable {
    let id: String
    let name: String
    let goal: String?
    let stage: String
    let status: String
}

// MARK: - Architecture diagram

@MainActor
@Observable
private final class LabWorkflowCatalogModel {
    private(set) var groups: [LabWorkflowGroup] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var sourceLabel = "ORCA"

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && sourceLabel == "ORCA" { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        async let protocolsResponse: WikiFileResponse = APIClient.shared.get(path: "/api/v1/wiki/file?path=sops/PROTOCOLS-INDEX.md")
        async let workflowsResponse: WikiFileResponse = APIClient.shared.get(path: "/api/v1/wiki/file?path=workflows/INDEX.md")

        do {
            let (protocols, workflows) = try await (protocolsResponse, workflowsResponse)
            let parsedGroups = Self.makeGroups(protocolsMarkdown: protocols.content, workflowsMarkdown: workflows.content)
            guard !parsedGroups.isEmpty else {
                groups = []
                sourceLabel = "ORCA"
                error = "ORCA wiki indexes parsed empty."
                return
            }
            groups = parsedGroups
            sourceLabel = "ORCA"
        } catch {
            groups = []
            sourceLabel = "ORCA ERROR"
            self.error = "ORCA wiki indexes unavailable."
        }
    }

    private static func makeGroups(protocolsMarkdown: String, workflowsMarkdown: String) -> [LabWorkflowGroup] {
        var result: [LabWorkflowGroup] = []
        let workflowItems = workflowRows(from: workflowsMarkdown)
        if !workflowItems.isEmpty {
            result.append(LabWorkflowGroup(title: "Canonical workflow index", items: workflowItems))
        }
        let protocolItems = protocolRows(from: protocolsMarkdown)
        if !protocolItems.isEmpty {
            result.append(LabWorkflowGroup(title: "Canonical protocol index", items: protocolItems))
        }
        return result
    }

    private static func workflowRows(from markdown: String) -> [LabWorkflowItem] {
        markdown
            .components(separatedBy: "\n")
            .compactMap { line -> LabWorkflowItem? in
                let columns = LabCatalogModel.markdownTableColumns(line)
                guard columns.count >= 3, columns[0].contains("](") else { return nil }
                let workflow = LabCatalogModel.stripMarkdown(columns[0])
                let roles = LabCatalogModel.stripMarkdown(columns[1])
                let trigger = LabCatalogModel.stripMarkdown(columns[2])
                return LabWorkflowItem(
                    title: "\(workflow) — \(roles)",
                    status: trigger,
                    statusColor: AppColors.accentElectric
                )
            }
    }

    private static func protocolRows(from markdown: String) -> [LabWorkflowItem] {
        markdown
            .components(separatedBy: "\n")
            .compactMap { line -> LabWorkflowItem? in
                let columns = LabCatalogModel.markdownTableColumns(line)
                guard columns.count >= 4, columns[0].contains("PROTOCOL-") else { return nil }
                let proto = LabCatalogModel.stripMarkdown(columns[0])
                let cadence = LabCatalogModel.stripMarkdown(columns[1])
                let owner = LabCatalogModel.stripMarkdown(columns[2])
                let enforcement = LabCatalogModel.stripMarkdown(columns[3])
                return LabWorkflowItem(
                    title: "\(proto) — \(cadence) · \(owner)",
                    status: enforcement,
                    statusColor: AppColors.accentSuccess
                )
            }
    }

}

private struct LabFundProductSpec: Identifiable, Hashable {
    let id: String
    let title: String
    let path: String
    let icon: String

    static let all: [LabFundProductSpec] = [
        LabFundProductSpec(id: "data", title: "Data Intelligence", path: "/api/v1/fund/os/data", icon: "externaldrive.connected.to.line.below"),
        LabFundProductSpec(id: "universe", title: "Universe", path: "/api/v1/fund/os/universe", icon: "scope"),
        LabFundProductSpec(id: "radar", title: "Prediction Radar", path: "/api/v1/fund/os/radar", icon: "dot.radiowaves.left.and.right"),
        LabFundProductSpec(id: "predictions-m3", title: "Predictions M3", path: "/api/v1/fund/os/predictions-m3", icon: "chart.line.uptrend.xyaxis"),
        LabFundProductSpec(id: "evidence", title: "Evidence Pointers", path: "/api/v1/fund/os/evidence", icon: "checkmark.seal")
    ]
}

private struct LabFundProductResponse: Decodable {
    let status: String
    let route: String
    let section: String
    let sourceFresh: Bool
    let sourceAgeSeconds: Int?
    let generatedAt: String?
    let degradedReason: String?
    let data: AgentRunJSONValue?

    enum CodingKeys: String, CodingKey {
        case status, route, section, data
        case sourceFresh = "source_fresh"
        case sourceAgeSeconds = "source_age_seconds"
        case generatedAt = "generated_at"
        case degradedReason = "degraded_reason"
    }

    var isAvailable: Bool {
        status == "available"
    }
}

private struct LabFundProduct: Identifiable, Hashable {
    let id: String
    let title: String
    let path: String
    let icon: String
    let status: String
    let route: String
    let section: String
    let sourceFresh: Bool
    let sourceAgeSeconds: Int?
    let generatedAt: String?
    let degradedReason: String?
    let data: AgentRunJSONValue?

    var isAvailable: Bool {
        status == "available"
    }

    var dataKeyCount: Int {
        switch data {
        case .object(let object): return object.count
        case .array(let array): return array.count
        case .string, .int, .double, .bool, .null, .none: return 0
        }
    }

    var headline: String {
        if let degradedReason, !degradedReason.isEmpty {
            return degradedReason
        }
        if case .object(let object) = data {
            let candidates = [
                object["status"]?.labStringValue,
                object["readiness"]?.labStringValue,
                object["decision"]?.labStringValue,
                object["purpose"]?.labStringValue,
                object["blocked_use"]?.labStringValue
            ]
            if let first = candidates.compactMap({ $0?.labNilIfBlank }).first {
                return first
            }
        }
        if let generatedAt {
            return "Protected research product generated \(generatedAt)."
        }
        return "Protected research product available through ORCA."
    }

    var sourceAgeLabel: String {
        guard let sourceAgeSeconds else { return "unknown age" }
        if sourceAgeSeconds < 60 { return "\(sourceAgeSeconds)s" }
        if sourceAgeSeconds < 3_600 { return "\(sourceAgeSeconds / 60)m" }
        if sourceAgeSeconds < 86_400 { return "\(sourceAgeSeconds / 3_600)h" }
        return "\(sourceAgeSeconds / 86_400)d"
    }

    init(spec: LabFundProductSpec, response: LabFundProductResponse) {
        id = spec.id
        title = spec.title
        path = spec.path
        icon = spec.icon
        status = response.status
        route = response.route
        section = response.section
        sourceFresh = response.sourceFresh
        sourceAgeSeconds = response.sourceAgeSeconds
        generatedAt = response.generatedAt
        degradedReason = response.degradedReason
        data = response.data
    }

    init(spec: LabFundProductSpec, error: Error) {
        id = spec.id
        title = spec.title
        path = spec.path
        icon = spec.icon
        status = "degraded"
        route = spec.path
        section = spec.id
        sourceFresh = false
        sourceAgeSeconds = nil
        generatedAt = nil
        degradedReason = "Unavailable from ORCA."
        data = nil
    }
}

@MainActor
@Observable
private final class LabFundProductsModel {
    private(set) var products: [LabFundProduct] = []
    private(set) var isLoading = false
    private(set) var error: String?

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && !products.isEmpty { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        var fetched: [LabFundProduct] = []
        for spec in LabFundProductSpec.all {
            do {
                let response: LabFundProductResponse = try await APIClient.shared.get(path: spec.path)
                fetched.append(LabFundProduct(spec: spec, response: response))
            } catch {
                fetched.append(LabFundProduct(spec: spec, error: error))
            }
        }

        products = fetched
        if fetched.allSatisfy({ !$0.isAvailable }) {
            error = "Protected Fund research products are unavailable from ORCA."
        }
    }
}

private extension AgentRunJSONValue {
    var labStringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return value.formatted(.number.precision(.fractionLength(2)))
        case .bool(let value):
            return value ? "true" : "false"
        case .object, .array, .null:
            return nil
        }
    }
}

@MainActor
@Observable
final class ArchitectureDiagramModel {
    private(set) var markdown = ""
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var sourceLabel = "ORCA"

    var previewText: String {
        Self.firstMermaidBlock(in: markdown) ?? markdown
    }

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && sourceLabel == "ORCA" { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: WikiFileResponse = try await APIClient.shared.get(
                path: "/api/v1/wiki/file?path=architecture/ARCHITECTURE-DIAGRAM.md"
            )
            markdown = response.content
            sourceLabel = "ORCA"
        } catch {
            do {
                let response: WikiFileResponse = try await APIClient.shared.get(
                    path: "/api/v1/wiki/file?path=operating-system/architecture/ARCHITECTURE-DIAGRAM.md"
                )
                markdown = response.content
                sourceLabel = "ORCA"
            } catch {
                markdown = ""
                sourceLabel = "ORCA ERROR"
                self.error = "Architecture diagram unavailable through ORCA."
            }
        }
    }

    private static func firstMermaidBlock(in markdown: String) -> String? {
        guard let openRange = markdown.range(of: "```mermaid") else { return nil }
        let bodyStart = openRange.upperBound
        guard let closeRange = markdown[bodyStart...].range(of: "```") else { return nil }
        let block = markdown[bodyStart..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return block.isEmpty ? nil : block
    }
}

struct WikiFileResponse: Decodable {
    let content: String

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let value = try? single.decode(String.self) {
            content = value
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .content) {
            content = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .markdown) {
            content = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .text) {
            content = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .body) {
            content = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.content,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No wiki file content field")
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case markdown
        case text
        case body
    }
}

struct ArchitectureDiagramSheet: View {
    let markdown: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(markdown)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(16)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 0.75), 2.8)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Architecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.accentElectric)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        scale = max(0.75, scale - 0.15)
                        lastScale = scale
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Button {
                        scale = min(2.8, scale + 0.15)
                        lastScale = scale
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                }
            }
        }
    }
}
