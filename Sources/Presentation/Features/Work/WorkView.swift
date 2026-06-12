import SwiftUI

// MARK: - Work View
// Per SPEC-POD-TABS-HANDOFF §4 — stacked PROJECTS + TICKETS, no segmented control (v3 decision).

struct WorkView: View {
    @EnvironmentObject private var appState: AppState
    @State private var model = WorkViewModel()
    @State private var pushProjects = false
    @State private var pushTickets = false
    @State private var pushAgents = false
    @State private var pushKnowledge = false
    @State private var pushProjectId: UUID? = nil
    @State private var pushTicketId: String? = nil
    @State private var selectedFlowItem: TicketFlowItem?
    @State private var boardsModel = WorkBoardsModel()
    @State private var selectedBoard: WorkBoardSummary?
    @State private var showingBoardsArchitecture = false
    @State private var showingBoardDrift = false
    @State private var showingCascadeDetails = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 12)

                    workHealthStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    suggestionsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    boardsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    projectsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    ticketsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable {
                await model.load()
                await boardsModel.load(force: true)
            }
            .task {
                await model.load()
                await boardsModel.load()
            }
            .task { await model.startFlowReviewPolling() }
            .onAppear {
                configureReviewerIdentity()
                model.consumePendingFlowFilter()
            }
            .onChange(of: appState.currentUser?.name) { _, _ in
                configureReviewerIdentity()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pod.openWorkFlowFilter"))) { note in
                model.applyIncomingFlowFilter(note.object as? String)
            }
            .sheet(item: $selectedFlowItem) { flow in
                flowDetailSheet(flow)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(item: $selectedBoard) { board in
                WorkBoardDetailView(board: board)
            }
            .fullScreenCover(isPresented: $showingBoardsArchitecture) {
                WorkBoardsArchitectureView(
                    boards: boardsModel.boards,
                    sourceLabel: boardsModel.sourceLabel,
                    onSelectBoard: { board in
                        showingBoardsArchitecture = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            selectedBoard = board
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showingBoardDrift) {
                WorkBoardDriftDetailView(
                    drift: boardsModel.drift,
                    error: boardsModel.driftError,
                    onRefresh: {
                        Task { await boardsModel.load(force: true) }
                    }
                )
            }
            // Hidden navigation links for full-list push
            .navigationDestination(isPresented: $pushProjects) {
                ORCAProjectsView()
            }
            .navigationDestination(isPresented: $pushTickets) {
                TicketsView()
            }
            .navigationDestination(isPresented: $pushAgents) {
                AgentsView()
            }
            .navigationDestination(isPresented: $pushKnowledge) {
                KnowledgeView()
            }
            .overlay(alignment: .bottom) {
                if let toast = model.priorityToast {
                    priorityToastView(toast)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast.message)
                        .task(id: toast.message) {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if model.priorityToast == toast {
                                    model.priorityToast = nil
                                }
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.priorityToast)
        }
    }

    private func configureReviewerIdentity() {
        model.configureReviewerIdentity(from: appState.currentUser?.name ?? appState.authManager.currentUser?.name)
    }

    private func priorityToastView(_ toast: WorkViewModel.PriorityToast) -> some View {
        let bg = toast.isError ? AppColors.accentDanger : AppColors.backgroundTertiary
        let fg = toast.isError ? Color.white : AppColors.textPrimary
        return HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(fg)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(bg)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)
        .contentShape(Capsule())
        .onTapGesture {
            if let retry = toast.retry {
                model.priorityToast = nil
                retry()
            }
        }
        .accessibilityLabel(toast.message)
        .accessibilityAddTraits(toast.retry != nil ? .isButton : [])
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Work")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            Text("Committed work — projects and the tickets under them.")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var workHealthStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                healthChip(
                    title: "Suggestions",
                    count: model.schoolhouseDigest?.attentionStack.count ?? model.suggestions.count,
                    error: model.suggestionsError,
                    isLoading: model.isLoadingSuggestions
                ) { Task { await model.loadSuggestions() } }
                healthChip(
                    title: "Projects",
                    count: model.projects.count,
                    error: model.projectsError,
                    isLoading: model.isLoadingProjects
                ) { Task { await model.loadProjects() } }
                healthChip(
                    title: "Tickets",
                    count: model.activeTicketCount,
                    error: model.ticketsError,
                    isLoading: model.isLoadingTickets
                ) { Task { await model.loadTickets() } }
                healthChip(
                    title: "Flow",
                    count: model.ticketFlowReview?.counts.total ?? 0,
                    error: model.ticketFlowErrorMessage,
                    isLoading: false
                ) { Task { await model.loadTicketFlowReview() } }
            }
            .padding(.horizontal, 2)
        }
    }

    private func healthChip(
        title: String,
        count: Int,
        error: String?,
        isLoading: Bool,
        retry: @escaping () -> Void
    ) -> some View {
        let hasError = error != nil
        let color = hasError ? AppColors.accentWarning : AppColors.accentSuccess
        return Button(action: retry) {
            HStack(spacing: 5) {
                Image(systemName: isLoading ? "hourglass" : (hasError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.16), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(error ?? "\(title) loaded")
    }

    // MARK: - Suggestions Section

    private var suggestionsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SCHOOLHOUSE · \(model.schoolhouseDigest?.attentionStack.count ?? model.suggestions.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Button {
                    Task { await model.loadSuggestions() }
                } label: {
                    Image(systemName: model.isLoadingSuggestions ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingSuggestions)
                .accessibilityLabel("Refresh Schoolhouse suggestions")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            VStack(spacing: 8) {
                if let digest = model.schoolhouseDigest {
                    schoolhouseDigestSummary(digest)
                }

                if model.isLoadingSuggestions && model.suggestions.isEmpty {
                    suggestionSkeletons
                } else if let err = model.suggestionsError {
                    errorBanner(message: err) { Task { await model.loadSuggestions() } }
                } else if model.suggestions.isEmpty {
                    emptyState(icon: "sparkle.magnifyingglass", text: "Schoolhouse digest clear.")
                } else {
                    ForEach(model.suggestions.prefix(7)) { suggestion in
                        PodReviewCard(
                            item: suggestionReviewItem(suggestion),
                            isBusy: model.suggestionActionIds.contains(suggestion.id.uuidString),
                            onAction: { action in
                                if action.id == "open-memory-candidate" {
                                    if let candidateId = suggestion.memoryCandidateId {
                                        UserDefaults.standard.set(candidateId, forKey: "pod.pendingMemoryCandidateId")
                                    }
                                    UserDefaults.standard.set(KnowledgeChip.memory.rawValue, forKey: "pod.pendingKnowledgeChip")
                                    pushKnowledge = true
                                } else {
                                    Task { await model.handleSuggestionAction(action.id, suggestion: suggestion) }
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    private func schoolhouseDigestSummary(_ digest: SchoolhouseDigest) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(digest.attentionStack.prefix(3), id: \.self) { item in
                    Label(item, systemImage: digest.attentionIcon(for: item))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(digest.attentionColor(for: item))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(digest.attentionColor(for: item).opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 8) {
                digestMetric(
                    title: "Due",
                    value: "\(digest.suggestionCount)",
                    color: digest.suggestionCount > 0 ? AppColors.accentWarning : AppColors.accentSuccess
                )
                digestMetric(
                    title: "Awake stale",
                    value: "\(digest.staleSessionCount)",
                    color: digest.staleSessionCount > 0 ? AppColors.accentWarning : AppColors.textTertiary
                )
                digestMetric(
                    title: "Run review",
                    value: "\(digest.worker.pendingReviewCount)",
                    color: digest.worker.pendingReviewCount > 0 ? AppColors.accentWarning : AppColors.textTertiary
                )
                digestMetric(
                    title: "Activation",
                    value: "\(digest.activation?.attentionCount ?? 0)",
                    color: (digest.activation?.attentionCount ?? 0) > 0 ? AppColors.accentWarning : AppColors.accentSuccess
                )
                digestMetric(
                    title: "Cascade",
                    value: "\(digest.cascade?.triage.reviewBacklogCount ?? 0)",
                    color: (digest.cascade?.triage.reviewBacklogCount ?? 0) > 0 ? AppColors.accentWarning : AppColors.accentSuccess
                )
                Spacer(minLength: 0)
            }

            if digest.worker.pendingReviewCount > 0 {
                Button {
                    UserDefaults.standard.set("mermaid", forKey: "pod.pendingAgentRunReviewLane")
                    pushTickets = true
                } label: {
                    Label("Review Mermaid runs", systemImage: "checkmark.seal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.accentWarning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppColors.accentWarning.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }

            if let cascade = digest.cascade, cascade.needsAttention {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showingCascadeDetails.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.accentWarning)
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Cascade · \(cascade.doctrine.canaryStatusLabel)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                            Text(cascade.statusLine)
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: showingCascadeDetails ? "chevron.up.circle" : "chevron.down.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(AppColors.accentWarning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

                if showingCascadeDetails {
                    cascadeDetails(cascade)
                }
            }

            if let activation = digest.activation, !activation.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(activation.items.prefix(4)) { item in
                        Button {
                            UserDefaults.standard.set(item.agentName, forKey: "pod.pendingActivationAgentName")
                            pushAgents = true
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "person.crop.circle.badge.exclamationmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppColors.accentWarning)
                                    .frame(width: 14, height: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(item.agentName.capitalized) · \(item.statusLabel)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppColors.textPrimary)
                                        .lineLimit(1)
                                    Text(item.recommendedAction)
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }

    private func digestMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .frame(minWidth: 66, alignment: .leading)
    }

    private func cascadeDetails(_ cascade: SchoolhouseDigestCascade) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                digestMetric(
                    title: "Canary",
                    value: cascade.doctrine.canaryStatusLabel,
                    color: cascade.doctrine.canaryStatus == "current" ? AppColors.accentSuccess : AppColors.accentWarning
                )
                digestMetric(
                    title: "Loaded",
                    value: "\(cascade.doctrine.loadedCount ?? 0)/\(cascade.doctrine.totalAgents ?? 0)",
                    color: (cascade.doctrine.loadedCount ?? 0) > 0 ? AppColors.accentSuccess : AppColors.accentWarning
                )
                digestMetric(
                    title: "Quality",
                    value: cascade.triage.qualityStateLabel,
                    color: cascade.triage.qualityState == "live_healthy" ? AppColors.accentSuccess : AppColors.accentWarning
                )
                Spacer(minLength: 0)
            }

            if cascade.triage.reviewBacklogCount > 0 {
                Label("\(cascade.triage.reviewBacklogCount) unreviewed routing decisions", systemImage: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.accentWarning)
            }

            if let falseNegativeRate = cascade.triage.falseNegativeRate {
                Text("FN \(Int(falseNegativeRate * 100))% · FP \(Int((cascade.triage.falsePositiveRate ?? 0) * 100))% · agreement \(Int((cascade.triage.agreementRate ?? 0) * 100))%")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func suggestionReviewItem(_ suggestion: SchoolhouseSuggestion) -> PodReviewItem {
        var provenance = [
            suggestion.kind.replacingOccurrences(of: "_", with: " "),
            suggestion.source,
        ]
        if let owner = suggestion.ownerLane, !owner.isEmpty {
            provenance.append(owner)
        }
        if let defaultAction = suggestion.defaultAction, !defaultAction.isEmpty {
            provenance.append("action \(defaultAction)")
        }
        if let dedupeKey = suggestion.dedupeKey, !dedupeKey.isEmpty {
            provenance.append("dedupe \(String(dedupeKey.prefix(12)))")
        }
        if suggestion.dismissCount > 0 {
            provenance.append("dismissed \(suggestion.dismissCount)x")
        }
        if let snoozedUntil = suggestion.snoozedUntil {
            provenance.append("snoozed \(snoozedUntil.formatted(date: .abbreviated, time: .shortened))")
        }

        return PodReviewItem(
            id: suggestion.id.uuidString,
            eyebrow: suggestion.reviewEyebrow,
            title: suggestion.title,
            detail: suggestion.summary,
            status: "\(suggestion.riskLevel.uppercased()) · \(suggestion.status)",
            statusColor: suggestion.statusColor,
            provenance: provenance,
            traceId: suggestion.traceId,
            artifactHash: suggestion.artifactHash,
            actions: suggestionActions(for: suggestion)
        )
    }

    private func suggestionActions(for suggestion: SchoolhouseSuggestion) -> [PodReviewAction] {
        let isTerminal = ["accepted", "dismissed", "expired", "converted"].contains(suggestion.status.lowercased())
        var actions: [PodReviewAction] = []
        if suggestion.isMemoryCandidateReview {
            actions.append(
                PodReviewAction(
                    id: "open-memory-candidate",
                    title: "Open",
                    systemImage: "brain.head.profile",
                    style: .primary,
                    isDisabled: false
                )
            )
        }
        actions.append(contentsOf: [
            PodReviewAction(
                id: "accept",
                title: "Approve",
                systemImage: "checkmark.seal",
                style: .success,
                isDisabled: isTerminal
            ),
            PodReviewAction(
                id: "convert-ticket",
                title: "Ticket",
                systemImage: "text.badge.plus",
                style: .primary,
                isDisabled: isTerminal
            ),
            PodReviewAction(
                id: "snooze",
                title: "Snooze",
                systemImage: "clock",
                style: .warning,
                isDisabled: isTerminal
            ),
            PodReviewAction(
                id: "dismiss",
                title: "Dismiss",
                systemImage: "xmark.circle",
                style: .destructive,
                isDisabled: isTerminal
            ),
        ])
        return actions
    }

    // MARK: - Boards Section

    private var boardsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BOARDS · \(boardsModel.boards.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Text(boardsModel.sourceLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(boardsModel.sourceLabel == "ORCA" ? AppColors.accentSuccess : AppColors.textTertiary)
                Button {
                    showingBoardsArchitecture = true
                } label: {
                    Text("View all")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                Button {
                    Task { await boardsModel.load(force: true) }
                } label: {
                    Image(systemName: boardsModel.isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .disabled(boardsModel.isLoading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if boardsModel.boards.isEmpty && !boardsModel.isLoading {
                        boardsUnavailableTile
                    } else {
                        ForEach(boardsModel.boards) { board in
                            Button {
                                selectedBoard = board
                            } label: {
                                workBoardTile(board)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if boardsModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 44, height: 52)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, boardsModel.error == nil ? 10 : 6)
            }

            boardNeedsHomeStrip

            if let error = boardsModel.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var boardNeedsHomeStrip: some View {
        if let drift = boardsModel.drift, drift.needsHomeCount > 0 {
            Button {
                showingBoardDrift = true
            } label: {
                HStack(spacing: 10) {
                    Label("NEEDS HOME", systemImage: "tray.and.arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.accentWarning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 4)

                    driftMetric("Projects", drift.unboardedProjectCount)
                    driftMetric("Tickets", drift.unboardedTicketCount)
                    driftMetric("Canon", drift.canonicalDriftCount)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppColors.accentWarning.opacity(0.08))
            .overlay(
                Rectangle()
                    .fill(AppColors.accentWarning.opacity(0.16))
                    .frame(height: 0.5),
                alignment: .top
            )
        } else if let driftError = boardsModel.driftError {
            Text(driftError)
                .font(.system(size: 10))
                .foregroundColor(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }

    private var boardsUnavailableTile: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.accentWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Boards waiting on ORCA")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text("No local fallback shown")
                    .font(.system(size: 9))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .frame(width: 180, height: 52, alignment: .leading)
        .padding(8)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.accentWarning.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func driftMetric(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
            Text("\(value)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(value > 0 ? AppColors.accentWarning : AppColors.textTertiary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func workBoardTile(_ board: WorkBoardSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(board.icon)
                    .font(.system(size: 14))
                Text(board.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 5) {
                Text("\(board.projectCount)p")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.textSecondary)
                Text("\(board.activeCount)a")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.accentElectric)
                if board.ticketCount > 0 {
                    Text("\(board.ticketCount)t")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .frame(width: 92, height: 52, alignment: .topLeading)
        .padding(8)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("PROJECTS · \(model.projects.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Button {
                    model.showingNewProject = true
                } label: {
                    Text("+ New")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Card
            VStack(spacing: 0) {
                if model.isLoadingProjects && model.projects.isEmpty {
                    projectSkeletons
                } else if let err = model.projectsError {
                    errorBanner(message: err) { Task { await model.loadProjects() } }
                } else if model.projects.isEmpty {
                    emptyState(icon: "square.stack.3d.up", text: "No active projects. Tap + New to start one.")
                } else {
                    ForEach(Array(model.projects.prefix(6).enumerated()), id: \.element.id) { idx, project in
                        VStack(spacing: 0) {
                            if idx > 0 {
                                Divider()
                                    .background(AppColors.border)
                                    .padding(.horizontal, 14)
                            }
                            projectRow(project)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    pushProjectId = project.id
                                    pushProjects = true
                                }
                        }
                    }

                    // View all footer
                    Divider().background(AppColors.border)
                    Button {
                        pushProjects = true
                    } label: {
                        HStack {
                            Text("View all \(model.projects.count) projects ›")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.accentElectric)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
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

    private func projectRow(_ project: ProjectDTO) -> some View {
        HStack(spacing: 10) {
            // short_id chip
            Text(String(project.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hexString: "0e0e10"))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(AppColors.border, lineWidth: 0.5)
                )

            // Name
            Text(project.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Stage pill
            if let stage = project.stage {
                stagePill(stage)
            }

            // Priority dot — tap to change (P1–P5)
            Menu {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        Task { await model.updateProjectPriority(projectId: project.id, priority: level) }
                    } label: {
                        HStack {
                            Text("P\(level)")
                            if project.priority == level {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(priorityColorInt(project.priority))
                    .frame(width: 7, height: 7)
            }
            .accessibilityLabel("Priority P\(project.priority). Tap to change.")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }

    private func stagePill(_ stage: String) -> some View {
        let (text, fg, bg): (String, Color, Color) = {
            switch stage.lowercased() {
            case "live":       return ("live",      AppColors.accentSuccess,  AppColors.accentSuccess.opacity(0.15))
            case "blueprint":  return ("blueprint", AppColors.textTertiary,  AppColors.textTertiary.opacity(0.12))
            case "build":      return ("build",     AppColors.accentWarning, AppColors.accentWarning.opacity(0.12))
            case "dds":        return ("dds",       AppColors.accentElectric, AppColors.accentElectric.opacity(0.12))
            case "sop":        return ("sop",       AppColors.accentAgent,   AppColors.accentAgent.opacity(0.12))
            case "maintain":   return ("maintain",  AppColors.accentSuccess,  AppColors.accentSuccess.opacity(0.12))
            default:           return (stage,       AppColors.textTertiary,  AppColors.textTertiary.opacity(0.12))
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }

    // MARK: - Tickets Section

    private var ticketsSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("TICKETS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Text("\(model.activeTicketCount) active")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Card
            VStack(spacing: 0) {
                // Filter bar (sticky inside card)
                ticketFilterBar
                flowFilterBar
                activeFlowFiltersBar

                Divider().background(AppColors.border)

                if model.isLoadingTickets && model.tickets.isEmpty {
                    ticketSkeletons
                } else if let err = model.ticketsError {
                    errorBanner(message: err) { Task { await model.loadTickets() } }
                } else if model.filteredTickets.isEmpty {
                    emptyState(icon: "ticket", text: "No active tickets in this view.")
                } else {
                    ForEach(Array(model.filteredTickets.prefix(3).enumerated()), id: \.element.id) { idx, ticket in
                        VStack(spacing: 0) {
                            if idx > 0 {
                                Divider()
                                    .background(AppColors.border)
                                    .padding(.horizontal, 14)
                            }
                            ticketRow(ticket)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    pushTicketId = ticket.id
                                    pushTickets = true
                                }
                        }
                    }

                    // View all footer
                    Divider().background(AppColors.border)
                    Button {
                        pushTickets = true
                    } label: {
                        HStack {
                            Text("View all \(model.filteredTickets.count) tickets ›")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.accentElectric)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
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

    private var ticketFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkViewModel.TicketFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func filterChip(_ filter: WorkViewModel.TicketFilter) -> some View {
        let isOn = model.activeFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.activeFilter = filter
            }
        } label: {
            Text(filter.label)
                .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                .foregroundColor(isOn ? Color.black : AppColors.textSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(isOn ? AppColors.textPrimary : Color.clear)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isOn ? Color.clear : AppColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 30)
    }

    private var flowFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                flowMenu(
                    title: model.selectedFlowState.map(flowStateLabel) ?? "By flow state",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    options: model.flowStateOptions,
                    selected: model.selectedFlowState,
                    countProvider: { model.flowCount(for: $0, in: .flowState) },
                    onSelect: { model.selectedFlowState = $0 }
                )
                flowMenu(
                    title: model.selectedOwnerAgent.map { $0.capitalized } ?? "By owner",
                    systemImage: "person.crop.circle",
                    options: model.ownerOptions,
                    selected: model.selectedOwnerAgent,
                    countProvider: { model.flowCount(for: $0, in: .owner) },
                    onSelect: { model.selectedOwnerAgent = $0 }
                )
                flowMenu(
                    title: model.selectedSupportLane ?? "By support lane",
                    systemImage: "rectangle.3.group",
                    options: model.supportLaneOptions,
                    selected: model.selectedSupportLane,
                    countProvider: { model.flowCount(for: $0, in: .supportLane) },
                    onSelect: { model.selectedSupportLane = $0 }
                )
                flowToggleChip(label: "Dispatchable", systemImage: "bolt.fill", isOn: model.filterDispatchableOnly) {
                    model.filterDispatchableOnly.toggle()
                }
                flowToggleChip(label: "Noise review", systemImage: "exclamationmark.bubble.fill", isOn: model.filterNoiseReviewOnly) {
                    model.filterNoiseReviewOnly.toggle()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var activeFlowFiltersBar: some View {
        let chips = model.activeFlowFilterChips
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.id) { chip in
                        Button {
                            model.clearFlowFilter(chip.id)
                        } label: {
                            HStack(spacing: 5) {
                                Text(chip.label)
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(AppColors.accentElectric)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppColors.accentElectric.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    private func flowMenu(
        title: String,
        systemImage: String,
        options: [String],
        selected: String?,
        countProvider: @escaping (String) -> Int,
        onSelect: @escaping (String?) -> Void
    ) -> some View {
        Menu {
            Button("All") { onSelect(nil) }
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack {
                        Text("\(flowMenuLabel(option)) (\(countProvider(option)))")
                        if selected == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: selected == nil ? .regular : .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(selected == nil ? AppColors.textSecondary : Color.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected == nil ? Color.clear : AppColors.textPrimary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(selected == nil ? AppColors.border : Color.clear, lineWidth: 1))
        }
    }

    private func flowToggleChip(label: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(isOn ? Color.black : AppColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isOn ? AppColors.textPrimary : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : AppColors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func ticketRow(_ ticket: WorkTicketRow) -> some View {
        HStack(spacing: 8) {
            // Priority dot — tap to edit per Aloha 2026-05-23 (ticket 46ca818d)
            Menu {
                ForEach(["urgent", "high", "medium", "low"], id: \.self) { level in
                    Button {
                        Task { await model.updateTicketPriority(ticketId: ticket.id, priority: level) }
                    } label: {
                        HStack {
                            Circle().fill(priorityColor(level)).frame(width: 7, height: 7)
                            Text(level.capitalized)
                            if ticket.priority.lowercased() == level {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(priorityColor(ticket.priority))
                    .frame(width: 7, height: 7)
                    .padding(.leading, 4)
                    .frame(width: 24, height: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Priority: \(ticket.priority). Tap to change.")

            // short_id chip — mirrors Project card chip per Tony 2026-05-23
            ticketShortIdChip(ticket.id)

            if let flow = model.flow(for: ticket.id) {
                Button {
                    selectedFlowItem = flow
                } label: {
                    flowStatePill(flow)
                }
                .buttonStyle(.plain)

                if flow.protected {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.accentDanger)
                        .accessibilityLabel("Protected")
                }

                if flow.dispatchable {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.accentSuccess)
                        .accessibilityLabel("Dispatchable")
                }
            }

            // Title
            Text(ticket.title)
                .font(.system(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Owner · status · priority meta (owner is resolved agent name per ticket 7d4c89a7)
            Text("\(ticket.ownerShort) · \(ticket.status.replacingOccurrences(of: "_", with: " ")) · \(ticket.priority)")
                .font(.system(size: 11))
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
    }

    private func flowStatePill(_ flow: TicketFlowItem) -> some View {
        Text(flowStateLabel(flow.flowState))
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(flowStateColor(flow))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(flowStateColor(flow).opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Flow state \(flowStateLabel(flow.flowState))")
    }

    private func flowDetailSheet(_ flow: TicketFlowItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        flowStatePill(flow)
                        Text(flow.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppColors.textPrimary)
                        Text(String(flow.ticketId.prefix(8)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)
                    }

                    flowDetailBlock(title: "Next action", values: [flow.nextAction])
                    flowDetailBlock(title: "Owner", values: [flow.ownerAgent])
                    flowDetailBlock(title: "Support lane", values: [flow.supportLane ?? flow.workerLane ?? "standard"])
                    flowDetailBlock(title: "Blockers", values: flow.blockers.isEmpty ? ["None"] : flow.blockers)
                    flowDetailBlock(title: "Reasons", values: flow.reasons.isEmpty ? ["No reasons supplied"] : flow.reasons)
                }
                .padding(20)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Flow Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func flowDetailBlock(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func flowStateLabel(_ state: String) -> String {
        switch state {
        case "noise_review": return "noise"
        case "needs_approval": return "approval"
        case "needs_scope": return "scope"
        case "needs_dispatch_plan": return "plan"
        case "needs_owner_review": return "owner"
        case "ready_for_dispatch": return "ready"
        case "ready_to_close": return "close"
        case "in_progress": return "in flight"
        default: return state.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func flowMenuLabel(_ state: String) -> String {
        state.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func flowStateColor(_ flow: TicketFlowItem) -> Color {
        if flow.protected { return AppColors.accentDanger }
        switch flow.flowState {
        case "noise_review", "blocked": return AppColors.accentDanger
        case "needs_approval", "needs_scope", "needs_dispatch_plan", "needs_owner_review": return AppColors.accentWarning
        case "ready_for_dispatch", "ready_to_close": return AppColors.accentSuccess
        case "running", "in_progress": return AppColors.accentElectric
        default: return AppColors.textTertiary
        }
    }

    private func ticketShortIdChip(_ id: String) -> some View {
        Text(String(id.replacingOccurrences(of: "-", with: "").prefix(8)))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(hexString: "0e0e10"))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
            .accessibilityLabel("Ticket ID \(id.prefix(8))")
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "urgent": return AppColors.accentDanger
        case "high":   return AppColors.accentWarning
        case "medium": return AppColors.accentElectric
        default:       return AppColors.textTertiary
        }
    }

    private func priorityColorInt(_ priority: Int) -> Color {
        switch priority {
        case 1: return AppColors.accentDanger
        case 2: return AppColors.accentWarning
        case 3: return AppColors.accentElectric
        case 4: return AppColors.accentSuccess
        default: return AppColors.textTertiary
        }
    }

    // MARK: - Skeleton / Error / Empty

    private var projectSkeletons: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                skeletonRow(height: 44)
            }
        }
    }

    private var ticketSkeletons: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                skeletonRow(height: 40)
            }
        }
    }

    private var suggestionSkeletons: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { _ in
                skeletonRow(height: 74)
                    .background(AppColors.backgroundPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func skeletonRow(height: CGFloat) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.backgroundTertiary)
                .frame(width: 70, height: 16)
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.backgroundTertiary)
                .frame(height: 16)
        }
        .padding(.horizontal, 14)
        .frame(height: height)
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentDanger)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Button("Retry", action: retry)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)
        }
        .padding(14)
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

// MARK: - Work View Model

@Observable
final class WorkViewModel {
    // MARK: Projects
    var projects: [ProjectDTO] = []
    var isLoadingProjects = false
    var projectsError: String?

    // MARK: Tickets
    var tickets: [WorkTicketRow] = []
    var activeTicketCount = 0
    var isLoadingTickets = false
    var ticketsError: String?
    var activeFilter: TicketFilter = .all
    var ticketFlowReview: TicketFlowReview?
    var ticketFlowByTicketId: [String: TicketFlowItem] = [:]
    var ticketFlowErrorMessage: String?
    var selectedFlowState: String?
    var selectedOwnerAgent: String?
    var selectedSupportLane: String?
    var filterDispatchableOnly = false
    var filterNoiseReviewOnly = false
    var filterProtectedOnly = false
    var priorityToast: PriorityToast?

    // MARK: Suggestions
    var schoolhouseDigest: SchoolhouseDigest?
    var suggestions: [SchoolhouseSuggestion] = []
    var isLoadingSuggestions = false
    var suggestionsError: String?
    var suggestionActionIds: Set<String> = []
    var reviewerIdentity = "maui"

    struct PriorityToast: Equatable {
        let message: String
        let isError: Bool
        let retry: (() -> Void)?
        static func == (lhs: PriorityToast, rhs: PriorityToast) -> Bool {
            lhs.message == rhs.message && lhs.isError == rhs.isError
        }
    }

    func configureReviewerIdentity(from name: String?) {
        let normalized = (name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        reviewerIdentity = normalized.isEmpty ? "maui" : normalized
    }

    // MARK: Sheet
    var showingNewProject = false

    // MARK: - Ticket Filter

    enum TicketFilter: CaseIterable, Equatable {
        case all, mine, urgent, byProject

        var label: String {
            switch self {
            case .all:       return "All"
            case .mine:      return "Mine"
            case .urgent:    return "Urgent"
            case .byProject: return "By project"
            }
        }
    }

    var filteredTickets: [WorkTicketRow] {
        let base: [WorkTicketRow]
        switch activeFilter {
        case .all:
            base = tickets
        case .mine:
            base = tickets.filter { $0.ownerShort.lowercased().hasPrefix("mau") || $0.assigneeId == "maui" }
        case .urgent:
            base = tickets.filter { $0.priority.lowercased() == "urgent" }
        case .byProject:
            // Group by project — just sort by projectId for now
            base = tickets.sorted { ($0.projectId ?? "") < ($1.projectId ?? "") }
        }

        return base.filter { ticket in
            guard let flow = ticketFlowByTicketId[ticket.id] else {
                return selectedFlowState == nil
                    && selectedOwnerAgent == nil
                    && selectedSupportLane == nil
                    && !filterDispatchableOnly
                    && !filterNoiseReviewOnly
            }
            if let selectedFlowState, flow.flowState != selectedFlowState { return false }
            if let selectedOwnerAgent, flow.ownerAgent != selectedOwnerAgent { return false }
            if let selectedSupportLane, (flow.supportLane ?? flow.workerLane ?? "standard") != selectedSupportLane { return false }
            if filterDispatchableOnly && !flow.dispatchable { return false }
            if filterNoiseReviewOnly && !flow.noiseReview { return false }
            if filterProtectedOnly && !flow.protected { return false }
            return true
        }
    }

    enum FlowFilterKind {
        case flowState, owner, supportLane
    }

    struct ActiveFlowChip: Hashable {
        let id: String
        let label: String
    }

    var flowStateOptions: [String] {
        sortedKeys(ticketFlowReview?.counts.byFlowState ?? [:])
    }

    var ownerOptions: [String] {
        sortedKeys(ticketFlowReview?.counts.byOwnerAgent ?? [:])
    }

    var supportLaneOptions: [String] {
        sortedKeys(ticketFlowReview?.counts.bySupportLane ?? [:])
    }

    var activeFlowFilterChips: [ActiveFlowChip] {
        var chips: [ActiveFlowChip] = []
        if let selectedFlowState {
            chips.append(ActiveFlowChip(id: "flow_state", label: selectedFlowState.replacingOccurrences(of: "_", with: " ")))
        }
        if let selectedOwnerAgent {
            chips.append(ActiveFlowChip(id: "owner_agent", label: selectedOwnerAgent.capitalized))
        }
        if let selectedSupportLane {
            chips.append(ActiveFlowChip(id: "support_lane", label: selectedSupportLane))
        }
        if filterDispatchableOnly {
            chips.append(ActiveFlowChip(id: "dispatchable", label: "Dispatchable"))
        }
        if filterNoiseReviewOnly {
            chips.append(ActiveFlowChip(id: "noise_review", label: "Noise review"))
        }
        if filterProtectedOnly {
            chips.append(ActiveFlowChip(id: "protected", label: "Protected"))
        }
        return chips
    }

    func flow(for ticketId: String) -> TicketFlowItem? {
        ticketFlowByTicketId[ticketId]
    }

    func flowCount(for key: String, in kind: FlowFilterKind) -> Int {
        switch kind {
        case .flowState:
            return ticketFlowReview?.counts.byFlowState[key] ?? 0
        case .owner:
            return ticketFlowReview?.counts.byOwnerAgent[key] ?? 0
        case .supportLane:
            return ticketFlowReview?.counts.bySupportLane[key] ?? 0
        }
    }

    func clearFlowFilter(_ id: String) {
        switch id {
        case "flow_state": selectedFlowState = nil
        case "owner_agent": selectedOwnerAgent = nil
        case "support_lane": selectedSupportLane = nil
        case "dispatchable": filterDispatchableOnly = false
        case "noise_review": filterNoiseReviewOnly = false
        case "protected": filterProtectedOnly = false
        default: break
        }
    }

    func applyIncomingFlowFilter(_ filter: String?) {
        guard let filter, !filter.isEmpty else { return }
        if filter == "dispatchable" {
            filterDispatchableOnly = true
        } else if filter == "noise_review" {
            filterNoiseReviewOnly = true
        } else if filter == "protected" {
            filterProtectedOnly = true
        } else if flowStateOptions.contains(filter) {
            selectedFlowState = filter
        } else if ownerOptions.contains(filter) {
            selectedOwnerAgent = filter
        } else if supportLaneOptions.contains(filter) {
            selectedSupportLane = filter
        } else {
            selectedFlowState = filter
        }
        UserDefaults.standard.removeObject(forKey: "pod.pendingWorkFlowFilter")
    }

    func consumePendingFlowFilter() {
        let filter = UserDefaults.standard.string(forKey: "pod.pendingWorkFlowFilter")
        applyIncomingFlowFilter(filter)
    }

    private func sortedKeys(_ counts: [String: Int]) -> [String] {
        counts.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }
        .map(\.key)
    }

    // MARK: - Load

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSuggestions() }
            group.addTask { await self.loadProjects() }
            group.addTask { await self.loadTickets() }
            group.addTask { await self.loadTicketFlowReview() }
        }
    }

    @MainActor
    func loadSuggestions() async {
        isLoadingSuggestions = true
        suggestionsError = nil
        defer { isLoadingSuggestions = false }
        do {
            let digest: SchoolhouseDigest = try await APIClient.shared.get(path: "/api/v1/schoolhouse/digest?limit=7")
            schoolhouseDigest = digest

            var loadedSuggestions: [SchoolhouseSuggestion] = []
            for item in digest.suggestions {
                if let suggestion: SchoolhouseSuggestion = try? await APIClient.shared.get(
                    path: "/api/v1/schoolhouse/suggestions/\(item.id.uuidString)"
                ) {
                    loadedSuggestions.append(suggestion)
                }
            }

            if loadedSuggestions.isEmpty, digest.suggestionCount == 0 {
                suggestions = []
            } else if loadedSuggestions.isEmpty {
                let response: [SchoolhouseSuggestion] = try await APIClient.shared.get(path: "/api/v1/schoolhouse/suggestions?status=proposed&limit=7")
                suggestions = response.sorted { $0.sortScore > $1.sortScore }
            } else {
                let scoreById = Dictionary(uniqueKeysWithValues: digest.suggestions.map { ($0.id, $0.rankScore) })
                suggestions = loadedSuggestions.sorted {
                    (scoreById[$0.id] ?? $0.sortScore) > (scoreById[$1.id] ?? $1.sortScore)
                }
            }
        } catch {
            suggestionsError = "Suggestions unavailable"
        }
    }

    @MainActor
    func loadProjects() async {
        isLoadingProjects = true
        projectsError = nil
        defer { isLoadingProjects = false }
        do {
            let all = try await ProjectRepository().listProjects()
            // Show active-ish projects: exclude archived/cancelled
            projects = all.filter { p in
                let excluded = ["archived", "cancelled", "done"]
                return !excluded.contains(p.status.lowercased())
            }
            .sorted { $0.priority < $1.priority }
        } catch {
            projectsError = "Projects unavailable"
        }
    }

    @MainActor
    func loadTickets() async {
        isLoadingTickets = true
        ticketsError = nil
        defer { isLoadingTickets = false }
        do {
            struct TicketListItem: Decodable {
                let id: String
                let title: String
                let status: String
                let priority: String
                let assigneeAgentId: String?
                enum CodingKeys: String, CodingKey {
                    case id, title, status, priority
                    case assigneeAgentId = "assignee_agent_id"
                }
            }
            // Per ticket 7d4c89a7 (UUID→name resolution): fetch tickets AND agents in parallel,
            // resolve assigneeAgentId UUIDs to names client-side.
            async let ticketsAsync: WorkListResponse<TicketListItem> = APIClient.shared.get(path: "/api/v1/tickets?limit=200")
            async let agentsAsync: WorkListResponse<AgentNameOnly> = APIClient.shared.get(path: "/api/v1/agents?limit=200")

            let ticketResponse = try await ticketsAsync
            let agentResponse = try? await agentsAsync
            let raw = ticketResponse.items
            let agentList = agentResponse?.items ?? []
            let agentNames: [String: String] = Dictionary(uniqueKeysWithValues: agentList.map { ($0.id, $0.name) })

            activeTicketCount = raw.count

            // Priority sort order
            let order: [String: Int] = ["urgent": 0, "high": 1, "medium": 2, "low": 3]
            tickets = raw
                .sorted { (order[$0.priority] ?? 9) < (order[$1.priority] ?? 9) }
                .map { t in
                    let ownerLabel: String = {
                        guard let aid = t.assigneeAgentId else { return "—" }
                        // Look up name; fall back to UUID prefix for orphan IDs (logged but visible)
                        if let name = agentNames[aid] {
                            return name.lowercased()
                        }
                        return String(aid.prefix(6))
                    }()
                    return WorkTicketRow(
                        id: t.id,
                        title: t.title,
                        status: t.status,
                        priority: t.priority,
                        ownerShort: ownerLabel,
                        assigneeId: t.assigneeAgentId,
                        projectId: nil
                    )
                }
        } catch {
            ticketsError = "Tickets unavailable"
        }
    }

    @MainActor
    func loadTicketFlowReview(limit: Int = 200) async {
        do {
            let dto: WorkTicketFlowReviewDTO = try await APIClient.shared.get(
                path: "/api/v1/tickets/flow-review?limit=\(limit)&include_closed=false"
            )
            let review = dto.toDomain()
            ticketFlowReview = review
            ticketFlowByTicketId = review.items.reduce(into: [:]) { result, item in
                result[item.ticketId] = item
            }
            ticketFlowErrorMessage = nil
            consumePendingFlowFilter()
        } catch {
            ticketFlowReview = nil
            ticketFlowByTicketId = [:]
            ticketFlowErrorMessage = "Ticket flow review unavailable."
        }
    }

    @MainActor
    func startFlowReviewPolling() async {
        await loadTicketFlowReview()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if Task.isCancelled { break }
            await loadTicketFlowReview()
        }
    }

    // Tap-to-edit priority — optimistic local update, revert on failure.
    @MainActor
    func updateTicketPriority(ticketId: String, priority: String) async {
        guard let idx = tickets.firstIndex(where: { $0.id == ticketId }) else { return }
        let original = tickets[idx].priority
        guard original.lowercased() != priority.lowercased() else { return }
        tickets[idx].priority = priority
        struct Body: Encodable { let priority: String }
        do {
            let _: TicketPatchResponse = try await APIClient.shared.patch(
                path: "/api/v1/tickets/\(ticketId)",
                body: Body(priority: priority)
            )
            priorityToast = PriorityToast(
                message: "Priority → \(priority.capitalized)",
                isError: false,
                retry: nil
            )
        } catch {
            if let restoreIdx = tickets.firstIndex(where: { $0.id == ticketId }) {
                tickets[restoreIdx].priority = original
            }
            priorityToast = PriorityToast(
                message: "Couldn't update — tap to retry",
                isError: true,
                retry: { [weak self] in
                    Task { await self?.updateTicketPriority(ticketId: ticketId, priority: priority) }
                }
            )
        }
    }

    // Tap-to-edit project priority — optimistic local update, revert on failure.
    @MainActor
    func updateProjectPriority(projectId: UUID, priority: Int) async {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        let original = projects[idx].priority
        guard original != priority else { return }
        // Rebuild with updated priority (ProjectDTO is a let-struct)
        let old = projects[idx]
        projects[idx] = ProjectDTO(
            id: old.id, boardId: old.boardId, boardIds: old.boardIds,
            name: old.name, goal: old.goal, description: old.description,
            status: old.status, priority: priority, projectedCost: old.projectedCost,
            actualCost: old.actualCost, createdBy: old.createdBy, assignedTo: old.assignedTo,
            createdAt: old.createdAt, updatedAt: old.updatedAt,
            startedAt: old.startedAt, completedAt: old.completedAt, dueDate: old.dueDate,
            stage: old.stage, automationEnabled: old.automationEnabled,
            proposedMilestones: old.proposedMilestones, milestones: old.milestones,
            lastGenerationRunId: old.lastGenerationRunId
        )
        struct Body: Encodable { let priority: Int }
        do {
            let _: ProjectPatchResponse = try await APIClient.shared.patch(
                path: "/api/v1/projects/\(projectId)",
                body: Body(priority: priority)
            )
            priorityToast = PriorityToast(message: "Priority → P\(priority)", isError: false, retry: nil)
        } catch {
            if let restoreIdx = projects.firstIndex(where: { $0.id == projectId }) {
                let cur = projects[restoreIdx]
                projects[restoreIdx] = ProjectDTO(
                    id: cur.id, boardId: cur.boardId, boardIds: cur.boardIds,
                    name: cur.name, goal: cur.goal, description: cur.description,
                    status: cur.status, priority: original, projectedCost: cur.projectedCost,
                    actualCost: cur.actualCost, createdBy: cur.createdBy, assignedTo: cur.assignedTo,
                    createdAt: cur.createdAt, updatedAt: cur.updatedAt,
                    startedAt: cur.startedAt, completedAt: cur.completedAt, dueDate: cur.dueDate,
                    stage: cur.stage, automationEnabled: cur.automationEnabled,
                    proposedMilestones: cur.proposedMilestones, milestones: cur.milestones,
                    lastGenerationRunId: cur.lastGenerationRunId
                )
            }
            priorityToast = PriorityToast(
                message: "Couldn't update — tap to retry",
                isError: true,
                retry: { [weak self] in
                    Task { await self?.updateProjectPriority(projectId: projectId, priority: priority) }
                }
            )
        }
    }

    @MainActor
    func handleSuggestionAction(_ actionId: String, suggestion: SchoolhouseSuggestion) async {
        guard !suggestionActionIds.contains(suggestion.id.uuidString) else { return }
        suggestionActionIds.insert(suggestion.id.uuidString)
        defer { suggestionActionIds.remove(suggestion.id.uuidString) }

        do {
            let updated: SchoolhouseSuggestion
            let actor = reviewerIdentity
            switch actionId {
            case "accept":
                updated = try await APIClient.shared.post(
                    path: "/api/v1/schoolhouse/suggestions/\(suggestion.id.uuidString)/accept",
                    body: SuggestionDecisionBody(actor: actor, reason: "Accepted from Pod Work.")
                )
            case "dismiss":
                updated = try await APIClient.shared.post(
                    path: "/api/v1/schoolhouse/suggestions/\(suggestion.id.uuidString)/dismiss",
                    body: SuggestionDecisionBody(actor: actor, reason: "Dismissed from Pod Work.")
                )
            case "snooze":
                let until = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                updated = try await APIClient.shared.post(
                    path: "/api/v1/schoolhouse/suggestions/\(suggestion.id.uuidString)/snooze",
                    body: SuggestionSnoozeBody(snoozedUntil: until, actor: actor, reason: "Snoozed from Pod Work.")
                )
            case "convert-ticket":
                updated = try await APIClient.shared.post(
                    path: "/api/v1/schoolhouse/suggestions/\(suggestion.id.uuidString)/convert-to-ticket",
                    body: SuggestionConvertBody(
                        actor: actor,
                        title: suggestion.title,
                        description: suggestion.ticketDescription,
                        priority: suggestion.ticketPriority,
                        ticketType: "feature",
                        tags: ["schoolhouse", "suggestion", suggestion.kind]
                    )
                )
            default:
                return
            }
            replaceSuggestion(updated)
            priorityToast = PriorityToast(message: "Suggestion \(updated.status)", isError: false, retry: nil)
            await loadTickets()
        } catch {
            priorityToast = PriorityToast(
                message: "Suggestion action failed — tap to retry",
                isError: true,
                retry: { [weak self] in
                    Task { await self?.handleSuggestionAction(actionId, suggestion: suggestion) }
                }
            )
        }
    }

    private func replaceSuggestion(_ suggestion: SchoolhouseSuggestion) {
        if let idx = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
            if suggestion.status == "proposed" || suggestion.status == "snoozed" {
                suggestions[idx] = suggestion
            } else {
                suggestions.remove(at: idx)
            }
        } else if suggestion.status == "proposed" {
            suggestions.insert(suggestion, at: 0)
        }
    }
}

private struct SuggestionDecisionBody: Encodable {
    let actor: String
    let reason: String
}

private struct SuggestionSnoozeBody: Encodable {
    let snoozedUntil: Date
    let actor: String
    let reason: String
}

private struct SuggestionConvertBody: Encodable {
    let actor: String
    let title: String
    let description: String
    let priority: String
    let ticketType: String
    let tags: [String]
}

private struct TicketPatchResponse: Decodable {
    let id: String
}

private struct ProjectPatchResponse: Decodable {
    let id: UUID
}

private struct WorkListResponse<Item: Decodable>: Decodable {
    let items: [Item]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let values = try? container.decode([Item].self) {
            items = values
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let values = try? container.decode([Item].self, forKey: .items) {
            items = values
        } else if let values = try? container.decode([Item].self, forKey: .results) {
            items = values
        } else if let values = try? container.decode([Item].self, forKey: .data) {
            items = values
        } else {
            items = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case results
        case data
    }
}

private struct WorkTicketFlowReviewDTO: Decodable {
    let counts: WorkTicketFlowCountsDTO
    let items: [WorkTicketFlowItemDTO]

    func toDomain() -> TicketFlowReview {
        TicketFlowReview(
            counts: counts.toDomain(),
            items: items.map { $0.toDomain() }
        )
    }
}

private struct WorkTicketFlowCountsDTO: Decodable {
    let total: Int?
    let dispatchable: Int?
    let noiseReview: Int?
    let protected: Int?
    let byFlowState: [String: Int]?
    let byOwnerAgent: [String: Int]?
    let bySupportLane: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case total, dispatchable, protected
        case noiseReview = "noise_review"
        case byFlowState = "by_flow_state"
        case byOwnerAgent = "by_owner_agent"
        case bySupportLane = "by_support_lane"
    }

    func toDomain() -> TicketFlowCounts {
        TicketFlowCounts(
            total: total ?? 0,
            dispatchable: dispatchable ?? 0,
            noiseReview: noiseReview ?? 0,
            protected: protected ?? 0,
            byFlowState: byFlowState ?? [:],
            byOwnerAgent: byOwnerAgent ?? [:],
            bySupportLane: bySupportLane ?? [:]
        )
    }
}

private struct WorkTicketFlowItemDTO: Decodable {
    let ticketId: String
    let title: String?
    let status: String?
    let priority: String?
    let flowState: String?
    let nextAction: String?
    let ownerAgent: String?
    let ownerLane: String?
    let supportLane: String?
    let workerLane: String?
    let recommendedRuntime: String?
    let recommendedSurface: String?
    let runtimeReason: String?
    let handoffSubject: String?
    let approvalState: String?
    let approvalGate: String?
    let autonomyLevel: String?
    let dispatchable: Bool?
    let noiseReview: Bool?
    let protected: Bool?
    let staleFlag: Bool?
    let noiseFlag: Bool?
    let backlogFlag: Bool?
    let blockers: [String]?
    let reasons: [String]?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case title, status, priority, dispatchable, protected, blockers, reasons
        case ticketId = "ticket_id"
        case flowState = "flow_state"
        case nextAction = "next_action"
        case ownerAgent = "owner_agent"
        case ownerLane = "owner_lane"
        case supportLane = "support_lane"
        case workerLane = "worker_lane"
        case recommendedRuntime = "recommended_runtime"
        case recommendedSurface = "recommended_surface"
        case runtimeReason = "runtime_reason"
        case handoffSubject = "handoff_subject"
        case approvalState = "approval_state"
        case approvalGate = "approval_gate"
        case autonomyLevel = "autonomy_level"
        case noiseReview = "noise_review"
        case staleFlag = "stale_flag"
        case noiseFlag = "noise_flag"
        case backlogFlag = "backlog_flag"
        case updatedAt = "updated_at"
    }

    func toDomain() -> TicketFlowItem {
        TicketFlowItem(
            ticketId: ticketId,
            title: title ?? "Untitled ticket",
            status: status ?? "unknown",
            priority: priority ?? "normal",
            flowState: flowState ?? "unknown",
            nextAction: nextAction ?? "Review",
            ownerAgent: ownerAgent ?? "unassigned",
            ownerLane: ownerLane,
            supportLane: supportLane,
            workerLane: workerLane,
            recommendedRuntime: recommendedRuntime,
            recommendedSurface: recommendedSurface,
            runtimeReason: runtimeReason,
            handoffSubject: handoffSubject,
            approvalState: approvalState ?? "not_required",
            approvalGate: approvalGate,
            autonomyLevel: autonomyLevel ?? "owner-review",
            dispatchable: dispatchable ?? false,
            noiseReview: noiseReview ?? false,
            protected: protected ?? false,
            staleFlag: staleFlag ?? false,
            noiseFlag: noiseFlag ?? false,
            backlogFlag: backlogFlag ?? false,
            blockers: blockers ?? [],
            reasons: reasons ?? [],
            updatedAt: updatedAt ?? .distantPast
        )
    }
}

// MARK: - Schoolhouse Digest

struct SchoolhouseDigest: Decodable, Hashable {
    let generatedAt: Date
    let suggestionCount: Int
    let countsByStatus: [String: Int]
    let countsByKind: [String: Int]
    let attentionStack: [String]
    let suggestions: [SchoolhouseDigestSuggestion]
    let sessions: [SchoolhouseDigestSession]
    let worker: SchoolhouseDigestWorker
    let activation: SchoolhouseDigestActivation?
    let cascade: SchoolhouseDigestCascade?

    enum CodingKeys: String, CodingKey {
        case suggestions, sessions, worker, activation, cascade
        case generatedAt = "generated_at"
        case suggestionCount = "suggestion_count"
        case countsByStatus = "counts_by_status"
        case countsByKind = "counts_by_kind"
        case attentionStack = "attention_stack"
    }

    var staleSessionCount: Int {
        sessions.filter(\.stale).count
    }

    func attentionIcon(for item: String) -> String {
        let lower = item.lowercased()
        if lower.contains("mermaid") { return "hammer" }
        if lower.contains("session") { return "moon.zzz" }
        if lower.contains("clear") { return "checkmark.seal" }
        return "sparkle.magnifyingglass"
    }

    func attentionColor(for item: String) -> Color {
        item.lowercased().contains("clear") ? AppColors.accentSuccess : AppColors.accentWarning
    }
}

struct SchoolhouseDigestSuggestion: Decodable, Identifiable, Hashable {
    let id: UUID
    let rankScore: Int

    enum CodingKeys: String, CodingKey {
        case id
        case rankScore = "rank_score"
    }
}

struct SchoolhouseDigestSession: Decodable, Identifiable, Hashable {
    let id: UUID
    let stale: Bool
}

struct SchoolhouseDigestWorker: Decodable, Hashable {
    let queuedCount: Int
    let retryingCount: Int
    let pendingReviewCount: Int

    enum CodingKeys: String, CodingKey {
        case queuedCount = "queued_count"
        case retryingCount = "retrying_count"
        case pendingReviewCount = "pending_review_count"
    }
}

struct SchoolhouseDigestActivation: Decodable, Hashable {
    let totalAgents: Int
    let compliantAgents: Int
    let attentionCount: Int
    let byStatus: [String: Int]
    let items: [SchoolhouseDigestActivationItem]

    enum CodingKeys: String, CodingKey {
        case items
        case totalAgents = "total_agents"
        case compliantAgents = "compliant_agents"
        case attentionCount = "attention_count"
        case byStatus = "by_status"
    }
}

struct SchoolhouseDigestActivationItem: Decodable, Identifiable, Hashable {
    let agentName: String
    let status: String
    let missing: [String]
    let recommendedAction: String
    let minutesSinceHeartbeat: Int?

    var id: String { "\(agentName)-\(status)" }

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ")
    }

    enum CodingKeys: String, CodingKey {
        case status, missing
        case agentName = "agent_name"
        case recommendedAction = "recommended_action"
        case minutesSinceHeartbeat = "minutes_since_heartbeat"
    }
}

struct SchoolhouseDigestCascade: Decodable, Hashable {
    let doctrine: SchoolhouseDigestCascadeDoctrine
    let triage: SchoolhouseDigestCascadeTriage
    let recommendations: [String]

    var needsAttention: Bool {
        doctrine.canaryStatus != "current" || triage.reviewBacklogCount > 0
    }

    var statusLine: String {
        if let first = recommendations.first, !first.isEmpty {
            return first
        }
        if triage.reviewBacklogCount > 0 {
            return "\(triage.reviewBacklogCount) routing decisions need review"
        }
        return "Doctrine and triage cascade are visible"
    }
}

struct SchoolhouseDigestCascadeDoctrine: Decodable, Hashable {
    let status: String?
    let canaryStatus: String?
    let loadedCount: Int?
    let totalAgents: Int?

    var canaryStatusLabel: String {
        (canaryStatus ?? "unknown").replacingOccurrences(of: "_", with: " ")
    }

    enum CodingKeys: String, CodingKey {
        case status
        case canaryStatus = "canary_status"
        case loadedCount = "loaded_count"
        case totalAgents = "total_agents"
    }
}

struct SchoolhouseDigestCascadeTriage: Decodable, Hashable {
    let status: String?
    let sampleSize: Int?
    let reviewBacklogCount: Int
    let qualityGate: String?
    let qualityState: String?
    let agreementRate: Double?
    let falseNegativeRate: Double?
    let falsePositiveRate: Double?

    var qualityStateLabel: String {
        (qualityState ?? qualityGate ?? "unknown").replacingOccurrences(of: "_", with: " ")
    }

    enum CodingKeys: String, CodingKey {
        case status
        case sampleSize = "sample_size"
        case reviewBacklogCount = "review_backlog_count"
        case qualityGate = "quality_gate"
        case qualityState = "quality_state"
        case agreementRate = "agreement_rate"
        case falseNegativeRate = "false_negative_rate"
        case falsePositiveRate = "false_positive_rate"
    }
}

// MARK: - Schoolhouse Suggestions

struct SchoolhouseSuggestion: Decodable, Identifiable, Hashable {
    let id: UUID
    let kind: String
    let title: String
    let summary: String?
    let status: String
    let source: String
    let sourceRefs: [String: AgentRunJSONValue]?
    let provenance: [String: AgentRunJSONValue]?
    let riskLevel: String
    let ownerLane: String?
    let actionOptions: [AgentRunJSONValue]?
    let defaultAction: String?
    let dedupeKey: String?
    let dismissCount: Int
    let snoozedUntil: Date?
    let convertedTo: [String: AgentRunJSONValue]?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title, summary, status, source, provenance
        case sourceRefs = "source_refs"
        case riskLevel = "risk_level"
        case ownerLane = "owner_lane"
        case actionOptions = "action_options"
        case defaultAction = "default_action"
        case dedupeKey = "dedupe_key"
        case dismissCount = "dismiss_count"
        case snoozedUntil = "snoozed_until"
        case convertedTo = "converted_to"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var traceId: String? {
        stringValue(for: ["trace_id", "agent_run_id", "run_id"], in: provenance)
            ?? stringValue(for: ["trace_id", "agent_run_id", "run_id"], in: sourceRefs)
    }

    var artifactHash: String? {
        stringValue(for: ["sha256", "artifact_hash", "hash"], in: provenance)
            ?? stringValue(for: ["sha256", "artifact_hash", "hash"], in: sourceRefs)
    }

    var isMemoryCandidateReview: Bool {
        kind == "memory_candidate_review"
            || source == "orca.memory_candidates"
            || memoryCandidateId != nil
    }

    var memoryCandidateId: String? {
        stringValue(for: ["candidate_id", "memory_candidate_id"], in: sourceRefs)
            ?? stringValue(for: ["candidate_id", "memory_candidate_id"], in: provenance)
    }

    var reviewEyebrow: String {
        isMemoryCandidateReview ? "Memory candidate review" : "Schoolhouse suggestion"
    }

    var ticketPriority: String {
        switch riskLevel.lowercased() {
        case "protected", "tier1": return "high"
        case "tier2": return "medium"
        default: return "low"
        }
    }

    var ticketDescription: String {
        [
            "Converted from Schoolhouse suggestion \(id.uuidString).",
            summary,
            "Kind: \(kind)",
            "Risk: \(riskLevel)",
            ownerLane.map { "Owner lane: \($0)" },
            traceId.map { "Trace: \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    var statusColor: Color {
        switch status.lowercased() {
        case "accepted", "converted":
            return AppColors.accentSuccess
        case "dismissed", "expired":
            return AppColors.textTertiary
        case "snoozed":
            return AppColors.accentWarning
        default:
            switch riskLevel.lowercased() {
            case "protected", "tier1": return AppColors.accentDanger
            case "tier2": return AppColors.accentWarning
            default: return AppColors.accentElectric
            }
        }
    }

    var sortScore: Int {
        let riskScore: Int
        switch riskLevel.lowercased() {
        case "protected": riskScore = 400
        case "tier1": riskScore = 300
        case "tier2": riskScore = 200
        default: riskScore = 100
        }
        let age = min(99, Int(Date().timeIntervalSince(updatedAt) / 3600))
        return riskScore + age
    }

    private func stringValue(for keys: [String], in values: [String: AgentRunJSONValue]?) -> String? {
        guard let values else { return nil }
        for key in keys {
            if let value = values[key]?.displayValue, !value.isEmpty, value != "null" {
                return value
            }
        }
        return nil
    }
}

// MARK: - Work Ticket Row

struct WorkTicketRow: Identifiable {
    let id: String
    let title: String
    let status: String
    var priority: String
    let ownerShort: String   // resolved agent name (lowercased) or 6-char UUID prefix
    let assigneeId: String?
    let projectId: String?
}

// Lightweight agent decode for UUID→name resolution
private struct AgentNameOnly: Decodable {
    let id: String
    let name: String
}

// MARK: - Work Boards

private struct WorkBoardSummary: Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    let layer: String?
    let component: String?
    let boardDescription: String?
    let projectCount: Int
    let activeCount: Int
    let ticketCount: Int

    var icon: String { Self.iconMap[slug] ?? "📋" }

    var displayName: String {
        (component?.isEmpty == false ? component : nil)
            ?? Self.displayNameMap[slug]
            ?? name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var contextLabel: String {
        [layer, component]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    static let orderedSlugs = [
        "north-star", "pod", "surfaces", "orca", "memory", "compute", "nerve",
        "governance", "jarvis", "schoolhouse", "fund", "products", "tools"
    ]

    static let iconMap: [String: String] = [
        "north-star": "⭐", "pod": "📱", "surfaces": "💬", "orca": "🐋", "memory": "🧠",
        "compute": "🧮", "nerve": "⚡", "governance": "⚖️", "jarvis": "🧭",
        "schoolhouse": "🏫", "fund": "🔒", "products": "🧩", "tools": "🛠️"
    ]

    static let displayNameMap: [String: String] = [
        "north-star": "north-star", "pod": "pod", "surfaces": "surfaces", "orca": "orca", "memory": "memory",
        "compute": "compute", "nerve": "nerve", "governance": "governance",
        "jarvis": "Jarvis", "schoolhouse": "Schoolhouse", "fund": "Fund",
        "products": "Products", "tools": "Tools"
    ]
}

@MainActor
@Observable
private final class WorkBoardsModel {
    private(set) var boards: [WorkBoardSummary] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var sourceLabel = "ORCA"
    private(set) var drift: WorkBoardDriftResponse?
    private(set) var driftError: String?

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && sourceLabel == "ORCA" && !boards.isEmpty { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: WorkBoardListResponse = try await APIClient.shared.get(path: "/api/v1/boards")
            boards = Self.ordered(response.items.map(\.summary))
            sourceLabel = "ORCA"
        } catch {
            sourceLabel = "ORCA"
            self.error = boards.isEmpty
                ? "ORCA boards unavailable."
                : "ORCA boards refresh unavailable; showing last loaded boards."
        }
        await loadDrift()
    }

    private func loadDrift() async {
        do {
            drift = try await APIClient.shared.get(path: "/api/v1/boards/drift?limit=5")
            driftError = nil
        } catch {
            drift = nil
            driftError = "Needs Home unavailable."
        }
    }

    private static func ordered(_ boards: [WorkBoardSummary]) -> [WorkBoardSummary] {
        boards.sorted { lhs, rhs in
            let lhsIndex = WorkBoardSummary.orderedSlugs.firstIndex(of: lhs.slug) ?? Int.max
            let rhsIndex = WorkBoardSummary.orderedSlugs.firstIndex(of: rhs.slug) ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.displayName < rhs.displayName
        }
    }
}

private struct WorkBoardDriftResponse: Decodable, Hashable {
    let status: String
    let missingCanonicalSlugs: [String]
    let extraSlugs: [String]
    let projectBoardFieldPresent: Bool
    let activeProjectCount: Int
    let unboardedProjectCount: Int
    let activeTicketCount: Int
    let unboardedTicketCount: Int
    let recommendedAction: String?
    let samples: [String: [WorkBoardDriftItem]]

    var canonicalDriftCount: Int {
        missingCanonicalSlugs.count + extraSlugs.count
    }

    var needsHomeCount: Int {
        canonicalDriftCount
            + unboardedProjectCount
            + unboardedTicketCount
            + (projectBoardFieldPresent ? 0 : 1)
    }

    private enum CodingKeys: String, CodingKey {
        case status, samples
        case missingCanonicalSlugs = "missing_canonical_slugs"
        case extraSlugs = "extra_slugs"
        case projectBoardFieldPresent = "project_board_field_present"
        case activeProjectCount = "active_project_count"
        case unboardedProjectCount = "unboarded_project_count"
        case activeTicketCount = "active_ticket_count"
        case unboardedTicketCount = "unboarded_ticket_count"
        case recommendedAction = "recommended_action"
    }
}

private struct WorkBoardDriftItem: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let status: String?
    let priority: String?
    let source: String?
    let suggestedBoard: String?
    let reason: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeWorkFlexibleString(forKey: .id)
        title = try container.decodeWorkFlexibleStringIfPresent(forKey: .title) ?? "Untitled"
        status = try container.decodeWorkFlexibleStringIfPresent(forKey: .status)
        priority = try container.decodeWorkFlexibleStringIfPresent(forKey: .priority)
        source = try container.decodeWorkFlexibleStringIfPresent(forKey: .source)
        suggestedBoard = try container.decodeWorkFlexibleStringIfPresent(forKey: .suggestedBoard)
        reason = try container.decodeWorkFlexibleStringIfPresent(forKey: .reason) ?? "Needs board assignment."
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, status, priority, source, reason
        case suggestedBoard = "suggested_board"
    }
}

private struct WorkBoardListResponse: Decodable {
    let items: [WorkBoardDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [WorkBoardDTO] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(WorkBoardDTO.self))
            }
            items = values
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([WorkBoardDTO].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey { case items }
}

private struct WorkBoardDTO: Decodable {
    let id: String
    let slug: String
    let name: String
    let layer: String?
    let component: String?
    let description: String?
    let projectCount: Int?
    let projectsCount: Int?
    let totalProjects: Int?
    let activeCount: Int?
    let activeProjects: Int?
    let activeProjectCount: Int?
    let ticketCount: Int?
    let ticketsCount: Int?
    let directTicketCount: Int?

    var summary: WorkBoardSummary {
        WorkBoardSummary(
            id: id,
            slug: slug,
            name: name,
            layer: layer,
            component: component,
            boardDescription: description,
            projectCount: projectCount ?? projectsCount ?? totalProjects ?? 0,
            activeCount: activeCount ?? activeProjects ?? activeProjectCount ?? 0,
            ticketCount: ticketCount ?? ticketsCount ?? directTicketCount ?? 0
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeWorkFlexibleString(forKey: .id)
        slug = try container.decodeWorkFlexibleStringIfPresent(forKey: .slug) ?? id
        name = try container.decodeWorkFlexibleStringIfPresent(forKey: .name) ?? slug
        layer = try container.decodeWorkFlexibleStringIfPresent(forKey: .layer)
        component = try container.decodeWorkFlexibleStringIfPresent(forKey: .component)
        description = try container.decodeWorkFlexibleStringIfPresent(keys: [.description, .objective])
        projectCount = try container.decodeWorkFlexibleIntIfPresent(keys: [.projectCount, .projectsCount, .totalProjects])
        projectsCount = nil
        totalProjects = nil
        activeCount = try container.decodeWorkFlexibleIntIfPresent(keys: [.activeCount, .activeProjects, .activeProjectCount])
        activeProjects = nil
        activeProjectCount = nil
        ticketCount = try container.decodeWorkFlexibleIntIfPresent(keys: [.ticketCount, .ticketsCount, .directTicketCount])
        ticketsCount = nil
        directTicketCount = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, layer, component, description, objective
        case projectCount = "project_count"
        case projectsCount = "projects_count"
        case totalProjects = "total_projects"
        case activeCount = "active_count"
        case activeProjects = "active_projects"
        case activeProjectCount = "active_project_count"
        case ticketCount = "ticket_count"
        case ticketsCount = "tickets_count"
        case directTicketCount = "direct_ticket_count"
    }
}

private struct WorkBoardProjectListResponse: Decodable {
    let items: [ProjectDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [ProjectDTO] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(ProjectDTO.self))
            }
            items = values
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([ProjectDTO].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey { case items }
}

private struct WorkBoardTicketSummary: Identifiable, Decodable {
    let id: String
    let title: String
    let status: String
    let priority: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeWorkFlexibleString(forKey: .id)
        title = try container.decodeWorkFlexibleStringIfPresent(forKey: .title) ?? "Untitled ticket"
        status = try container.decodeWorkFlexibleStringIfPresent(forKey: .status) ?? "open"
        priority = try container.decodeWorkFlexibleStringIfPresent(forKey: .priority)
    }

    private enum CodingKeys: String, CodingKey { case id, title, status, priority }
}

private struct WorkBoardTicketListResponse: Decodable {
    let items: [WorkBoardTicketSummary]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [WorkBoardTicketSummary] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(WorkBoardTicketSummary.self))
            }
            items = values
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([WorkBoardTicketSummary].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey { case items }
}

@MainActor
@Observable
private final class WorkBoardDetailModel {
    private(set) var projects: [ProjectDTO] = []
    private(set) var directTickets: [WorkBoardTicketSummary] = []
    private(set) var isLoading = false
    private(set) var error: String?

    var activeProjects: [ProjectDTO] {
        projects.filter { project in
            let status = project.status.lowercased()
            return status != "done" && status != "archived"
        }
    }

    var projectStageBreakdown: [WorkBoardBreakdownItem] {
        breakdown(projects.map { project in
            let value = project.stage ?? project.status
            return value.isEmpty ? "uncategorized" : value
        })
    }

    var ticketStatusBreakdown: [WorkBoardBreakdownItem] {
        breakdown(directTickets.map { $0.status.isEmpty ? "open" : $0.status })
    }

    var ticketPriorityBreakdown: [WorkBoardBreakdownItem] {
        breakdown(directTickets.map { ($0.priority?.isEmpty == false ? $0.priority : nil) ?? "normal" })
    }

    func load(board: WorkBoardSummary) async {
        if isLoading { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        async let projectsTask = loadProjects(board: board)
        async let ticketsTask = loadTickets(board: board)
        let (loadedProjects, loadedTickets) = await (projectsTask, ticketsTask)

        projects = loadedProjects.projects
        directTickets = loadedTickets.tickets
        error = [loadedProjects.error, loadedTickets.error].compactMap { $0 }.joined(separator: " ")
        if error?.isEmpty == true { error = nil }
    }

    private func loadProjects(board: WorkBoardSummary) async -> (projects: [ProjectDTO], error: String?) {
        do {
            let response: WorkBoardProjectListResponse = try await APIClient.shared.get(path: "/api/v1/boards/\(board.id)/projects")
            return (response.items, nil)
        } catch {
            do {
                let response: WorkBoardProjectListResponse = try await APIClient.shared.get(path: "/api/v1/projects?board_id=\(board.id)")
                return (response.items, nil)
            } catch {
                return ([], "Projects unavailable.")
            }
        }
    }

    private func loadTickets(board: WorkBoardSummary) async -> (tickets: [WorkBoardTicketSummary], error: String?) {
        do {
            let response: WorkBoardTicketListResponse = try await APIClient.shared.get(path: "/api/v1/boards/\(board.id)/tickets")
            return (response.items, nil)
        } catch {
            return ([], "Direct tickets unavailable.")
        }
    }

    private func breakdown(_ values: [String]) -> [WorkBoardBreakdownItem] {
        Dictionary(grouping: values.map { $0.normalizedBoardLabel }, by: { $0 })
            .map { WorkBoardBreakdownItem(label: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count { return $0.label < $1.label }
                return $0.count > $1.count
            }
    }
}

private struct WorkBoardBreakdownItem: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let count: Int
}

private struct WorkBoardDriftDetailView: View {
    let drift: WorkBoardDriftResponse?
    let error: String?
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var sortedSamples: [(key: String, items: [WorkBoardDriftItem])] {
        guard let drift else { return [] }
        let preferred = ["unboarded_projects", "unboarded_tickets", "missing_canonical_slugs", "extra_slugs"]
        return drift.samples
            .map { (key: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                let left = preferred.firstIndex(of: lhs.key) ?? Int.max
                let right = preferred.firstIndex(of: rhs.key) ?? Int.max
                if left != right { return left < right }
                return lhs.key < rhs.key
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let drift {
                        countsGrid(drift)
                        canonicalSection("Missing canonical slugs", values: drift.missingCanonicalSlugs)
                        canonicalSection("Extra slugs", values: drift.extraSlugs)
                        projectSchemaSection(drift)
                        sampleSections
                    } else {
                        Text(error ?? "Board drift is unavailable.")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Needs Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                        .foregroundColor(AppColors.accentElectric)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onRefresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .foregroundColor(AppColors.accentElectric)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BOARD DRIFT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
                .kerning(0.5)
            Text("Read-only ORCA drift samples. Pod shows what needs a home, but does not backfill or silently assign boards.")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
    }

    private func countsGrid(_ drift: WorkBoardDriftResponse) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            driftCount("Projects", drift.unboardedProjectCount)
            driftCount("Tickets", drift.unboardedTicketCount)
            driftCount("Missing canon", drift.missingCanonicalSlugs.count)
            driftCount("Extra slugs", drift.extraSlugs.count)
        }
    }

    private func driftCount(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(value > 0 ? AppColors.accentWarning : AppColors.accentSuccess)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func canonicalSection(_ title: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func projectSchemaSection(_ drift: WorkBoardDriftResponse) -> some View {
        HStack(spacing: 10) {
            Image(systemName: drift.projectBoardFieldPresent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(drift.projectBoardFieldPresent ? AppColors.accentSuccess : AppColors.accentWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Project board field")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text(drift.projectBoardFieldPresent ? "ORCA projects can store board assignments." : "ORCA projects cannot store board assignments yet.")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var sampleSections: some View {
        if sortedSamples.isEmpty {
            Text("No drift samples returned by ORCA.")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textTertiary)
        } else {
            ForEach(sortedSamples, id: \.key) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.key.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                    ForEach(group.items) { item in
                        driftSampleRow(item)
                    }
                }
            }
        }
    }

    private func driftSampleRow(_ item: WorkBoardDriftItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                Spacer()
                Text(item.id)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if let status = item.status, !status.isEmpty {
                    driftPill(status)
                }
                if let priority = item.priority, !priority.isEmpty {
                    driftPill(priority)
                }
                if let suggested = item.suggestedBoard, !suggested.isEmpty {
                    driftPill("suggested \(suggested)")
                }
            }
            Text(item.reason)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
    }

    private func driftPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }
}

private struct WorkBoardsArchitectureView: View {
    let boards: [WorkBoardSummary]
    let sourceLabel: String
    let onSelectBoard: (WorkBoardSummary) -> Void
    @Environment(\.dismiss) private var dismiss

    private var groupedBoards: [(layer: String, boards: [WorkBoardSummary])] {
        let grouped = Dictionary(grouping: boards) { board in
            let raw = board.layer?.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw?.isEmpty == false ? raw! : "uncategorized"
        }
        return grouped
            .map { (layer: $0.key, boards: $0.value.sorted { $0.displayName < $1.displayName }) }
            .sorted {
                if $0.layer == "uncategorized" { return false }
                if $1.layer == "uncategorized" { return true }
                return $0.layer < $1.layer
            }
    }

    private var totalProjects: Int {
        boards.reduce(0) { $0 + $1.projectCount }
    }

    private var totalActive: Int {
        boards.reduce(0) { $0 + $1.activeCount }
    }

    private var totalTickets: Int {
        boards.reduce(0) { $0 + $1.ticketCount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    totalsGrid
                    ForEach(groupedBoards, id: \.layer) { group in
                        architectureGroup(group.layer, boards: group.boards)
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .foregroundColor(AppColors.accentElectric)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BOARD ARCHITECTURE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Text(sourceLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(sourceLabel == "ORCA" ? AppColors.accentSuccess : AppColors.textTertiary)
            }

            Text("Boards grouped by ORCA architecture layer. Tap any board to open its projects and direct tickets.")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
    }

    private var totalsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            architectureMetric("Boards", "\(boards.count)")
            architectureMetric("Projects", "\(totalProjects)")
            architectureMetric("Active", "\(totalActive)")
            architectureMetric("Tickets", "\(totalTickets)")
        }
    }

    private func architectureGroup(_ layer: String, boards: [WorkBoardSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(layer.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
                Text("· \(boards.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.textTertiary)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(boards) { board in
                    Button {
                        onSelectBoard(board)
                    } label: {
                        architectureBoardTile(board)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func architectureBoardTile(_ board: WorkBoardSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(board.icon)
                    .font(.system(size: 18))
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(board.displayName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(board.component ?? board.slug)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if let description = board.boardDescription, !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 5) {
                architecturePill("\(board.projectCount)p")
                architecturePill("\(board.activeCount)a")
                if board.ticketCount > 0 {
                    architecturePill("\(board.ticketCount)t")
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(10)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
    }

    private func architectureMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
    }

    private func architecturePill(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }
}

private struct WorkBoardDetailView: View {
    let board: WorkBoardSummary
    @State private var model = WorkBoardDetailModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    boardHero
                    boardOverviewGrid
                    boardBreakdowns
                    boardProjects
                    boardTickets
                    if let error = model.error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(board.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .foregroundColor(AppColors.accentElectric)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.load(board: board) }
                    } label: {
                        Image(systemName: model.isLoading ? "hourglass" : "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
            .task {
                await model.load(board: board)
            }
        }
    }

    private var boardHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(board.icon)
                    .font(.system(size: 38))
                    .frame(width: 48, height: 48)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.displayName.uppercased())
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(board.slug)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)
                    if !board.contextLabel.isEmpty {
                        Text(board.contextLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                Spacer()
            }

            if let description = board.boardDescription, !description.isEmpty {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Board command window")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.accentElectric)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.accentElectric.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(16)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
    }

    private var boardOverviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            boardMetricCard(title: "Projects", value: "\(model.projects.isEmpty ? board.projectCount : model.projects.count)", detail: "\(model.activeProjects.count) active")
            boardMetricCard(title: "Tickets", value: "\(model.directTickets.isEmpty ? board.ticketCount : model.directTickets.count)", detail: "direct to board")
            boardMetricCard(title: "Stages", value: "\(model.projectStageBreakdown.count)", detail: "project lanes")
            boardMetricCard(title: "Source", value: model.isLoading ? "..." : "ORCA", detail: "live breakdown")
        }
    }

    private var boardBreakdowns: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("BREAKDOWN", count: model.projectStageBreakdown.count + model.ticketStatusBreakdown.count)

            VStack(alignment: .leading, spacing: 12) {
                breakdownGroup(title: "Project stages", items: model.projectStageBreakdown, empty: "No project stages yet.")
                breakdownGroup(title: "Ticket status", items: model.ticketStatusBreakdown, empty: "No direct ticket statuses yet.")
                breakdownGroup(title: "Ticket priority", items: model.ticketPriorityBreakdown, empty: "No direct ticket priorities yet.")
            }
            .padding(12)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
        }
    }

    private var boardProjects: some View {
        boardListSection(title: "PROJECTS", count: model.projects.count, empty: "No projects on this board yet.") {
            ForEach(Array(model.projects.enumerated()), id: \.element.id) { idx, project in
                if idx > 0 {
                    Divider().background(AppColors.border)
                }
                projectBreakdownRow(project)
            }
        }
    }

    private var boardTickets: some View {
        boardListSection(title: "DIRECT TICKETS", count: model.directTickets.count, empty: "No direct tickets on this board.") {
            ForEach(Array(model.directTickets.enumerated()), id: \.element.id) { idx, ticket in
                if idx > 0 {
                    Divider().background(AppColors.border)
                }
                ticketBreakdownRow(ticket)
            }
        }
    }

    private func projectBreakdownRow(_ project: ProjectDTO) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)
                    if let summary = project.goal ?? project.description, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text(String(project.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(6)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
            }

            HStack(spacing: 6) {
                boardPill(project.stage ?? project.status)
                boardPill(project.status)
                boardPill("P\(project.priority)")
                if let due = project.dueDate {
                    boardPill(due.formatted(date: .abbreviated, time: .omitted))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private func ticketBreakdownRow(_ ticket: WorkBoardTicketSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Text(ticket.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(String(ticket.id.replacingOccurrences(of: "-", with: "").prefix(6)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
            }
            HStack(spacing: 6) {
                boardPill(ticket.status)
                if let priority = ticket.priority {
                    boardPill(priority)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private func boardListSection<Content: View>(title: String, count: Int, empty: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title, count: count)

            if model.isLoading && count == 0 {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else if count == 0 {
                Text(empty)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    content()
                }
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text("· \(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
    }

    private func boardMetricCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
    }

    private func breakdownGroup(title: String, items: [WorkBoardBreakdownItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            if items.isEmpty {
                Text(empty)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textTertiary)
            } else {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 5) {
                            Text(item.label)
                                .lineLimit(1)
                            Text("\(item.count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func boardPill(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }
}

private extension KeyedDecodingContainer {
    func decodeWorkFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(UUID.self, forKey: key) { return value.uuidString }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(codingPath: codingPath, debugDescription: "No string-like value for \(key.stringValue)")
        )
    }

    func decodeWorkFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(UUID.self, forKey: key) { return value.uuidString }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    func decodeWorkFlexibleStringIfPresent(keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try decodeWorkFlexibleStringIfPresent(forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeWorkFlexibleIntIfPresent(keys: [Key]) throws -> Int? {
        for key in keys {
            if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
            if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
            if let value = try? decodeIfPresent(String.self, forKey: key), let intValue = Int(value) { return intValue }
        }
        return nil
    }
}

private extension String {
    var normalizedBoardLabel: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
    }
}
