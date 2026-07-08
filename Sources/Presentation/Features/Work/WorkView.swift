import SwiftData
import SwiftUI

// MARK: - Work View
// Per SPEC-POD-TABS-HANDOFF §4 — stacked PROJECTS + TICKETS, no segmented control (v3 decision).

private func boardAccentColor(_ slug: String) -> Color {
    switch slug {
    case "products":
        return AppColors.accentSuccess
    case "platform":
        return AppColors.accentElectric
    case "operations":
        return AppColors.accentWarning
    default:
        return AppColors.textTertiary
    }
}

struct WorkView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Bindable var directChatViewModel: DirectChatViewModel
    @State private var model = WorkViewModel()
    @State private var pushProjects = false
    @State private var pushTickets = false
    @State private var pushAgents = false
    @State private var pushKnowledge = false
    @State private var pushProjectId: UUID? = nil
    @State private var pushTicketId: String? = nil
    @State private var selectedFlowItem: TicketFlowItem?
    @State private var selectedWorkbenchItem: WorkbenchWorkItem?
    @State private var flowCommentText: String = ""
    @State private var workbenchActionComment: String = ""
    @State private var isPostingComment = false
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

                    AnyView(WorkHealthStripView(model: model))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    AnyView(
                        WorkbenchAgentCockpitSection(
                            directChatViewModel: directChatViewModel,
                            modelContext: modelContext
                        )
                    )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    AnyView(WorkbenchDivisionToolRunnerSection(model: model))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    AnyView(WorkbenchCalendarCockpitSection(model: model))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    AnyView(approvalLaneSection)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    AnyView(ticketsSection)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    AnyView(
                        WorkbenchTasksSection(
                            model: model,
                            onOpenTicket: { ticketId in
                                pushTicketId = ticketId
                                pushTickets = true
                            },
                            onComment: { item in
                                selectedWorkbenchItem = item
                            }
                        )
                    )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    AnyView(workbenchQueueSection)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    AnyView(suggestionsSection)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    AnyView(boardsSection)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    AnyView(projectsSection)
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
            .task {
                await directChatViewModel.loadAgentRegistry()
                await directChatViewModel.loadAgentPresence()
                await directChatViewModel.loadORCAChannelSummaries()
            }
            .task { await model.startFlowReviewPolling() }
            .onAppear {
                directChatViewModel.setModelContext(modelContext)
                directChatViewModel.navigationPath = NavigationPath()
                directChatViewModel.startPresenceMonitoring()
                configureReviewerIdentity()
                model.consumePendingFlowFilter()
            }
            .onDisappear {
                directChatViewModel.stopPresenceMonitoring()
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
            .sheet(item: $selectedWorkbenchItem) { item in
                workbenchActionSheet(item)
                    .presentationDetents([.medium, .large])
                    .onAppear {
                        workbenchActionComment = ""
                        model.resetWorkbenchActionPreview()
                    }
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
            Text("Workbench")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            Text("1:1 lanes, approvals, tasks, projects, and tickets.")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Approval Lane

    private var approvalLaneSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("APPROVALS · \(model.approvalAttentionCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Button {
                    Task { await model.loadActionPreview() }
                } label: {
                    Image(systemName: model.isLoadingActionPreview ? "hourglass" : "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingActionPreview)
                .accessibilityLabel("Preview Workbench action rail")
                Button {
                    Task { await model.loadApprovalAttention() }
                } label: {
                    Image(systemName: model.isLoadingApprovalAttention ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingApprovalAttention)
                .accessibilityLabel("Refresh approvals")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            VStack(spacing: 8) {
                approvalActionRailSummary

                if model.isLoadingApprovalAttention && model.approvalAttentionItems.isEmpty {
                    suggestionSkeletons
                } else if let err = model.approvalAttentionError {
                    errorBanner(message: err) { Task { await model.loadApprovalAttention() } }
                } else if model.approvalAttentionItems.isEmpty {
                    emptyState(icon: "checkmark.seal", text: "No approval attention waiting.")
                } else {
                    ForEach(model.approvalAttentionItems.prefix(5)) { item in
                        PodReviewCard(
                            item: approvalReviewItem(item),
                            isBusy: model.previewingApprovalIds.contains(item.id),
                            onAction: { action in
                                switch action.id {
                                case "open-ticket":
                                    pushTicketId = item.id
                                    pushTickets = true
                                case "preview-action":
                                    Task { await model.previewApprovalAction(item) }
                                default:
                                    break
                                }
                            }
                        )
                    }

                    if model.approvalAttentionItems.count > 5 {
                        Text("+\(model.approvalAttentionItems.count - 5) more in Tickets")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
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

    private var approvalActionRailSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Label("Action rail", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                Spacer()
                if let preview = model.actionPreview {
                    Text(preview.sideEffects == "none" && !preview.wouldWrite ? "no-write preview" : "check preview")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(preview.wouldWrite ? AppColors.accentWarning : AppColors.accentSuccess)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((preview.wouldWrite ? AppColors.accentWarning : AppColors.accentSuccess).opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                railPolicyPill("Preview", value: model.actionPreview?.sideEffects ?? "none")
                railPolicyPill("Writes", value: model.actionPreview?.wouldWrite == true ? "would write" : "blocked here")
                railPolicyPill("NATS", value: model.actionPreview?.wouldPublishNats == true ? "would publish" : "silent")
                if let controls = model.workbench?.buckets.controls {
                    railPolicyPill("Endpoint", value: controls.actionsEndpoint ?? "/agent/actions")
                }
            }

            if let error = model.actionPreviewError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.accentWarning)
            } else {
                Text(model.actionPreviewLine)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
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

    private func railPolicyPill(_ title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text(value.replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(AppColors.backgroundTertiary)
        .clipShape(Capsule())
    }

    private func approvalReviewItem(_ item: WorkbenchApprovalAttentionItem) -> PodReviewItem {
        let latestRun = item.latestRun.map { "\($0.runType.replacingOccurrences(of: "_", with: " ")) · \($0.status.replacingOccurrences(of: "_", with: " "))" }
        let reasons = item.reasons.map { $0.replacingOccurrences(of: "_", with: " ") }
        let detail = (reasons + [latestRun].compactMap { $0 }).joined(separator: " · ")
        return PodReviewItem(
            id: item.id,
            eyebrow: "Ticket \(String(item.id.replacingOccurrences(of: "-", with: "").prefix(8)))",
            title: item.title,
            detail: detail.isEmpty ? "Approval attention requested." : detail,
            status: item.approvalGate ?? item.approvalState.replacingOccurrences(of: "_", with: " "),
            statusColor: AppColors.accentWarning,
            provenance: [
                item.priority.uppercased(),
                item.status.replacingOccurrences(of: "_", with: " "),
                item.latestRun?.workerLane
            ].compactMap { $0 },
            actions: [
                PodReviewAction(
                    id: "open-ticket",
                    title: "Open",
                    systemImage: "ticket",
                    style: .primary
                ),
                PodReviewAction(
                    id: "preview-action",
                    title: "Preview",
                    systemImage: "eye",
                    style: .neutral
                )
            ]
        )
    }

    // MARK: - Workbench Queue

    private var workbenchQueueSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WORKBENCH · \(model.visibleWorkbenchRows.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                if model.workbenchActionableRows.count > 0 {
                    Text("ACTIONS · \(model.workbenchActionableRows.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.accentSuccess)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.accentSuccess.opacity(0.1))
                        .clipShape(Capsule())
                }
                Spacer()
                Button {
                    Task { await model.loadWorkbench() }
                } label: {
                    Image(systemName: model.isLoadingWorkbench ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingWorkbench)
                .accessibilityLabel("Refresh Workbench")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            VStack(spacing: 8) {
                if model.isLoadingWorkbench && model.visibleWorkbenchRows.isEmpty {
                    suggestionSkeletons
                } else if let err = model.workbenchError {
                    errorBanner(message: err) { Task { await model.loadWorkbench() } }
                } else if model.visibleWorkbenchRows.isEmpty {
                    emptyState(icon: "tray", text: "No Workbench queue rows.")
                } else {
                    ForEach(model.displayedWorkbenchRows) { item in
                        workbenchRowCard(item)
                    }

                    if model.visibleWorkbenchRows.count > model.displayedWorkbenchRows.count {
                        Text("+\(model.visibleWorkbenchRows.count - model.displayedWorkbenchRows.count) more Workbench rows")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
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

    private func workbenchRowCard(_ item: WorkbenchWorkItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: workbenchIcon(for: item))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(workbenchColor(for: item))
                    .frame(width: 26, height: 26)
                    .background(workbenchColor(for: item).opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.safeTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)
                    Text(workbenchRowDetail(item))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                if item.isProtected {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.accentWarning)
                        .accessibilityLabel("Protected")
                }
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                railPolicyPill("Kind", value: item.kind)
                if let status = item.status {
                    railPolicyPill("State", value: status)
                }
                if let priority = item.priority {
                    railPolicyPill("Priority", value: priority)
                }
                if let route = item.route ?? item.room {
                    railPolicyPill("Route", value: route)
                }
                if let freshness = item.workbenchFreshnessLabel {
                    railPolicyPill("When", value: freshness)
                }
            }

            WorkbenchAgentToolsShelf(
                projection: model.toolProjection(for: item),
                isLoading: model.isLoadingToolProjection(for: item),
                error: model.toolProjectionError(for: item)
            )

            HStack(spacing: 8) {
                if let ticketId = item.sourceTicketId ?? (item.kind == "ticket" ? item.id : nil) {
                    Button {
                        pushTicketId = ticketId
                        pushTickets = true
                    } label: {
                        Label("Open", systemImage: "ticket")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentElectric)
                }

                if item.canUseAgentActionNote {
                    Button {
                        selectedWorkbenchItem = item
                    } label: {
                        Label("Note", systemImage: "square.and.pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentSuccess)
                }

                if let statusAction = item.nextTaskStatusAction {
                    Button {
                        Task { await model.commitWorkbenchStatusAdvance(item: item) }
                    } label: {
                        Label(statusAction.label, systemImage: statusAction.icon)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentWarning)
                    .disabled(model.isCommittingWorkbenchAction)
                }

                if item.canAddToPlanner {
                    Button {
                        Task { await model.commitWorkbenchPlannerAdd(item: item) }
                    } label: {
                        Label("Plan", systemImage: "calendar.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentElectric)
                    .disabled(model.isCommittingWorkbenchAction)
                }

                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }

    private func workbenchActionSheet(_ item: WorkbenchWorkItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.safeTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppColors.textPrimary)
                        Text(workbenchRowDetail(item))
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.kind == "ticket" ? "TICKET NOTE" : "TASK NOTE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary)
                        TextField("Add a pointer-safe note", text: $workbenchActionComment, axis: .vertical)
                            .lineLimit(4...8)
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textPrimary)
                            .padding(10)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(AppColors.border, lineWidth: 1)
                            )
                    }

                    if let preview = model.workbenchActionPreview {
                        actionPreviewBlock(preview)
                    } else if let error = model.workbenchActionError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.accentWarning)
                    }

                    if item.nextTaskStatusAction != nil || item.canAddToPlanner {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QUICK ACTIONS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.textTertiary)
                            VStack(spacing: 8) {
                                if let statusAction = item.nextTaskStatusAction {
                                    Button {
                                        Task {
                                            let success = await model.commitWorkbenchStatusAdvance(item: item)
                                            if success {
                                                selectedWorkbenchItem = nil
                                            }
                                        }
                                    } label: {
                                        actionButtonLabel(
                                            title: statusAction.label,
                                            icon: statusAction.icon,
                                            color: AppColors.accentWarning
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(model.isCommittingWorkbenchAction)
                                }

                                if item.canAddToPlanner {
                                    Button {
                                        Task {
                                            let success = await model.commitWorkbenchPlannerAdd(item: item)
                                            if success {
                                                selectedWorkbenchItem = nil
                                            }
                                        }
                                    } label: {
                                        actionButtonLabel(
                                            title: "Add to Planner",
                                            icon: "calendar.badge.plus",
                                            color: AppColors.accentElectric
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(model.isCommittingWorkbenchAction)
                                }
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        Button {
                            let text = workbenchActionComment.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { await model.previewWorkbenchNote(item: item, message: text) }
                        } label: {
                            actionButtonLabel(
                                title: model.isPreviewingWorkbenchAction ? "Previewing" : "Preview",
                                icon: model.isPreviewingWorkbenchAction ? "hourglass" : "eye",
                                color: AppColors.accentElectric
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isPreviewingWorkbenchAction || workbenchActionComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            let text = workbenchActionComment.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                let success = await model.commitWorkbenchNote(item: item, message: text)
                                if success {
                                    selectedWorkbenchItem = nil
                                    workbenchActionComment = ""
                                }
                            }
                        } label: {
                            actionButtonLabel(
                                title: model.isCommittingWorkbenchAction ? "Posting" : "Post Note",
                                icon: model.isCommittingWorkbenchAction ? "hourglass" : "paperplane.fill",
                                color: model.hasFreshWorkbenchActionPreview(item: item, message: workbenchActionComment)
                                    ? AppColors.accentSuccess
                                    : AppColors.backgroundTertiary,
                                foregroundColor: model.hasFreshWorkbenchActionPreview(item: item, message: workbenchActionComment)
                                    ? Color.white
                                    : AppColors.textTertiary
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            model.isCommittingWorkbenchAction
                                || !model.hasFreshWorkbenchActionPreview(item: item, message: workbenchActionComment)
                        )
                    }
                }
                .padding(20)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Workbench Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { selectedWorkbenchItem = nil }
                }
            }
        }
    }

    private func actionPreviewBlock(_ preview: WorkbenchPlaygroundPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(preview.blocked ? "Blocked" : "Preview clear", systemImage: preview.blocked ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(preview.blocked ? AppColors.accentWarning : AppColors.accentSuccess)
                Spacer()
                Text(preview.sideEffects)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.textTertiary)
            }
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                railPolicyPill("Writes", value: preview.wouldWrite ? "would write" : "preview only")
                railPolicyPill("NATS", value: preview.wouldPublishNats ? "would publish" : "silent")
                if let endpoint = preview.result["would_call"]?.displayValue.nilIfBlankForWork {
                    railPolicyPill("Endpoint", value: endpoint)
                }
            }
            if let warning = preview.warnings.first {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.accentWarning)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func actionButtonLabel(
        title: String,
        icon: String,
        color: Color,
        foregroundColor: Color = Color.white
    ) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func workbenchRowDetail(_ item: WorkbenchWorkItem) -> String {
        let detail = [
            item.nextAction,
            item.waitingOn.map { "waiting on \($0)" },
            item.blockedOn.map { "blocked on \($0)" },
            item.contentPolicy
        ]
        .compactMap { $0?.replacingOccurrences(of: "_", with: " ") }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        return detail.nilIfBlankForWork ?? "Ready in Workbench."
    }

    private func workbenchIcon(for item: WorkbenchWorkItem) -> String {
        if item.isProtected { return "lock.shield.fill" }
        switch item.kind {
        case "task": return "checklist"
        case "ticket": return "ticket"
        case "planner": return "calendar.badge.clock"
        default: return "tray.full"
        }
    }

    private func workbenchColor(for item: WorkbenchWorkItem) -> Color {
        if item.isProtected { return AppColors.accentWarning }
        if item.stale { return AppColors.accentDanger }
        switch item.priority?.lowercased() {
        case "urgent", "high": return AppColors.accentWarning
        case "low": return AppColors.textTertiary
        default: return AppColors.accentElectric
        }
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
                            },
                            onNoteSubmit: { note in
                                Task { await model.postSuggestionNote(note, suggestion: suggestion) }
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

        // For idea_intake suggestions, surface the cascade stage + best available detail
        var statusLine = "\(suggestion.riskLevel.uppercased()) · \(suggestion.status)"
        var detail = suggestion.summary
        if suggestion.isIdeaIntake {
            statusLine = suggestion.cascadeStageBadge
            if let scope = suggestion.discoveryScope {
                // project_ready: show the richer discovery scope
                detail = scope
            } else if let assessment = suggestion.provenance?["assessment"],
                      case let .object(obj) = assessment,
                      let rationale = obj["rationale"],
                      case let .string(text) = rationale, !text.isEmpty {
                // discovering / assessed: show assessment rationale
                detail = text
            }
        }

        return PodReviewItem(
            id: suggestion.id.uuidString,
            eyebrow: suggestion.reviewEyebrow,
            title: suggestion.title,
            detail: detail,
            status: statusLine,
            statusColor: suggestion.isIdeaIntake ? suggestion.ideaStageColor : suggestion.statusColor,
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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(boardAccentColor(board.slug))
                .frame(height: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 8,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 8
                ))
        }
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
                    ForEach(model.projects.prefix(6)) { project in
                        projectRow(project)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                pushProjectId = project.id
                                pushProjects = true
                            }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 2)

                    // View all footer
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(priorityColorInt(project.priority).opacity(0.12))
                    Image(systemName: projectIcon(project))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(priorityColorInt(project.priority))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)

                    Text(project.goal ?? project.description ?? project.status.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

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
                    projectPriorityPill(project.priority)
                }
                .accessibilityLabel("Priority P\(project.priority). Tap to change.")
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                if let stage = project.stage {
                    stagePill(stage)
                }
                compactWorkPill(project.status.replacingOccurrences(of: "_", with: " "), color: AppColors.textSecondary)
                compactWorkPill(String(project.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)), color: AppColors.textTertiary)
                if project.automationEnabled == true {
                    compactWorkPill("auto", color: AppColors.accentSuccess)
                }
            }

            HStack(spacing: 8) {
                Label("Open", systemImage: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                Spacer()
                if let dueDate = project.dueDate {
                    Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }

    private func projectIcon(_ project: ProjectDTO) -> String {
        switch (project.stage ?? project.status).lowercased() {
        case "live", "maintain": return "checkmark.seal.fill"
        case "build", "in-progress", "in_progress": return "hammer.fill"
        case "dds", "blueprint": return "doc.text.magnifyingglass"
        default: return "folder.fill"
        }
    }

    private func projectPriorityPill(_ priority: Int) -> some View {
        Text("P\(priority)")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(priorityColorInt(priority))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(priorityColorInt(priority).opacity(0.12))
            .clipShape(Capsule())
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

    private func compactWorkPill(_ text: String, color: Color) -> some View {
        Text(text.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
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
                    ForEach(model.filteredTickets.prefix(4)) { ticket in
                        ticketRow(ticket)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                pushTicketId = ticket.id
                                pushTickets = true
                            }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 2)

                    // View all footer
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
        let flow = model.flow(for: ticket.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(priorityColor(ticket.priority).opacity(0.12))
                    Image(systemName: flow?.protected == true ? "lock.shield.fill" : "ticket.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(flow?.protected == true ? AppColors.accentDanger : priorityColor(ticket.priority))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ticket.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Text("\(ticket.ownerShort) · \(ticket.status.replacingOccurrences(of: "_", with: " "))")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

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
                    compactWorkPill(ticket.priority, color: priorityColor(ticket.priority))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Priority: \(ticket.priority). Tap to change.")
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ticketShortIdChip(ticket.id)
                compactWorkPill(ticket.status.replacingOccurrences(of: "_", with: " "), color: AppColors.textSecondary)
                if let flow {
                    Button {
                        selectedFlowItem = flow
                    } label: {
                        flowStatePill(flow)
                    }
                    .buttonStyle(.plain)
                    if flow.dispatchable {
                        compactWorkPill("dispatch", color: AppColors.accentSuccess)
                    }
                    if flow.protected {
                        compactWorkPill("protected", color: AppColors.accentDanger)
                    }
                }
            }

            HStack(spacing: 8) {
                Label("Open", systemImage: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                if flow != nil {
                    Label("Flow", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
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

                    // Comment / Note field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ADD NOTE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary)
                        TextField("Type a note or comment…", text: $flowCommentText, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.textPrimary)
                            .padding(10)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        flowCommentText.isEmpty ? AppColors.border : AppColors.accentElectric.opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                        Button {
                            let text = flowCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty, !isPostingComment else { return }
                            isPostingComment = true
                            let ticketId = flow.ticketId
                            Task {
                                await model.postTicketComment(text, ticketId: ticketId)
                                isPostingComment = false
                                flowCommentText = ""
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isPostingComment {
                                    ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "bubble.left.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text(isPostingComment ? "Posting…" : "Post Note")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                flowCommentText.trimmingCharacters(in: .whitespaces).isEmpty || isPostingComment
                                    ? AppColors.backgroundTertiary
                                    : AppColors.accentElectric
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(flowCommentText.trimmingCharacters(in: .whitespaces).isEmpty || isPostingComment)
                    }
                }
                .padding(20)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Flow Detail")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { flowCommentText = "" }
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

private struct WorkbenchAgentCockpitSection: View {
    @Bindable var directChatViewModel: DirectChatViewModel
    let modelContext: ModelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("1:1 LANES")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.textTertiary)
                    Text("Agent cockpit")
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                }

                Spacer()

                Button {
                    directChatViewModel.refreshSonarSurface()
                } label: {
                    Image(systemName: directChatViewModel.isLoadingRooms ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(directChatViewModel.isLoadingRooms)
                .accessibilityLabel("Refresh direct agent lanes")
            }

            if agents.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(agents) { agent in
                            NavigationLink {
                                AnyView(
                                    LockerChatView(viewModel: directChatViewModel, agent: agent)
                                        .onAppear {
                                            directChatViewModel.setModelContext(modelContext)
                                            directChatViewModel.selectAgent(agent)
                                        }
                                )
                            } label: {
                                agentCard(agent)
                            }
                            .buttonStyle(.plain)
                            .disabled(!directChatViewModel.canStartChat(with: agent))
                            .opacity(directChatViewModel.canStartChat(with: agent) ? 1 : 0.45)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
        .onAppear {
            directChatViewModel.setModelContext(modelContext)
        }
    }

    private var agents: [AgentInfo] {
        directChatViewModel.directChatAgents
            .filter { $0.lane != .dormantAdvisor }
            .sorted { lhs, rhs in
                let lhsRank = lhs.lane == .main ? 0 : 1
                let rhsRank = rhs.lane == .main ? 0 : 1
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
            Text("No direct lanes available.")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(14)
    }

    private func agentCard(_ agent: AgentInfo) -> some View {
        let tint = Color(hexString: agent.color)
        let presence = directChatViewModel.presence(for: agent)
        let preview = directChatViewModel.lastMessagePreview(for: agent)
        let unread = directChatViewModel.unreadCount(for: agent)
        let canStart = directChatViewModel.canStartChat(with: agent)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: agent.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(tint)
                    Circle()
                        .fill(presence.state.color)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(AppColors.backgroundSecondary, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(canStart ? directChatViewModel.rosterBadgeText(for: agent) : "Unavailable")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.accentElectric)
                        .clipShape(Capsule())
                }
            }

            Text(preview.text)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
                .frame(height: 34, alignment: .topLeading)

            HStack(spacing: 6) {
                pill(presence.state.label, color: presence.state.color)
                if let channel = directChatViewModel.shortChannelId(for: agent) {
                    pill(channel, color: AppColors.textTertiary)
                } else {
                    pill(agent.defaultDeliveryMode.displayLabel, color: AppColors.textTertiary)
                }
            }
        }
        .padding(12)
        .frame(width: 210, height: 150, alignment: .topLeading)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct WorkbenchDivisionToolRunnerSection: View {
    let model: WorkViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let workflow = model.divisionWorkflow {
                divisionBlock(workflow)
            } else if model.isLoadingWorkbench {
                loadingLine("Loading division cockpit")
            } else if model.workbenchError != nil {
                errorLine(model.workbenchError ?? "Workbench unavailable")
            }

            toolShelfBlock
            recentRunsBlock
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("COCKPIT")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
                Text("Workflow & tools")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
            }

            Spacer()

            Button {
                Task {
                    await model.loadWorkbench()
                    await model.loadToolRuns()
                }
            } label: {
                Image(systemName: model.isLoadingToolRuns || model.isLoadingWorkbench ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingToolRuns || model.isLoadingWorkbench)
            .accessibilityLabel("Refresh workflow and tool runs")
        }
    }

    private func divisionBlock(_ workflow: WorkbenchDivisionWorkflow) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                    .frame(width: 30, height: 30)
                    .background(AppColors.accentElectric.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(workflow.division)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)
                    Text(workflow.role)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(3)
                }
            }

            if !workflow.operatingLoop.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(workflow.operatingLoop.prefix(5)) { step in
                        toolPill(step.label, icon: stepIcon(step.id), color: AppColors.accentElectric)
                    }
                }
            }

            if !workflow.recurringDuties.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(workflow.recurringDuties.prefix(3)), id: \.self) { duty in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppColors.accentSuccess)
                                .padding(.top, 2)
                            Text(duty)
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var toolShelfBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Label("Tool shelf", systemImage: "wrench.and.screwdriver.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.accentElectric)

                Spacer()

                if let shelf = model.toolShelf {
                    Text("\(shelf.availableTools.count) live")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.accentSuccess)
                    Text("\(shelf.approvalTools.count) gated")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.accentWarning)
                }
            }

            HStack(spacing: 8) {
                toolButton(
                    "Queue",
                    icon: "list.bullet.rectangle",
                    color: AppColors.accentElectric,
                    disabled: model.isRunningWorkbenchTool,
                    action: { Task { await model.runQueueSummaryTool() } }
                )
                toolButton(
                    "Focus",
                    icon: "plus.circle.fill",
                    color: AppColors.accentSuccess,
                    disabled: model.isRunningWorkbenchTool,
                    action: { Task { await model.runPlannerFocusTool() } }
                )
                toolButton(
                    "Review",
                    icon: "checkmark.shield.fill",
                    color: AppColors.accentWarning,
                    disabled: model.isRunningWorkbenchTool,
                    action: { Task { await model.runReviewRequestTool() } }
                )
            }

            if let error = model.toolRunsError {
                errorLine(error)
            } else if model.isRunningWorkbenchTool {
                loadingLine("Running governed tool")
            } else if let shelf = model.toolShelf, !shelf.tools.isEmpty {
                FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(shelf.tools.prefix(5)) { tool in
                        toolPill(
                            tool.label,
                            icon: tool.approvalRequired ? "lock.shield.fill" : "bolt.fill",
                            color: tool.approvalRequired ? AppColors.accentWarning : AppColors.textTertiary
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var recentRunsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent receipts")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if model.isLoadingToolRuns {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            if model.toolRuns.isEmpty && !model.isLoadingToolRuns {
                Text("No governed tool receipts yet.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
            } else {
                ForEach(model.toolRuns.prefix(4)) { run in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: run.approvalRequired ? "checkmark.shield" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(run.approvalRequired ? AppColors.accentWarning : AppColors.accentSuccess)
                            .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.toolLabel ?? run.toolId ?? "Tool run")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                            Text("\(run.summary) · \(run.modelLabel)")
                                .font(.caption2)
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        Text(run.status.replacingOccurrences(of: "_", with: " "))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(run.approvalRequired ? AppColors.accentWarning : AppColors.accentSuccess)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func toolButton(
        _ label: String,
        icon: String,
        color: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private func toolPill(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    private func loadingLine(_ message: String) -> some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.mini)
            Text(message)
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func errorLine(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundColor(AppColors.accentWarning)
            .lineLimit(2)
    }

    private func stepIcon(_ id: String) -> String {
        switch id {
        case "wake": return "sunrise.fill"
        case "triage": return "arrow.triangle.branch"
        case "execute": return "play.fill"
        case "evidence": return "doc.badge.checkmark"
        case "sleep": return "moon.fill"
        default: return "circle.grid.cross"
        }
    }
}

private struct WorkHealthStripView: View {
    let model: WorkViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(metrics) { metric in
                    WorkHealthChip(metric: metric)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var metrics: [WorkHealthMetric] {
        [
            WorkHealthMetric(
                id: "suggestions",
                title: "Suggestions",
                count: model.schoolhouseDigest?.attentionStack.count ?? model.suggestions.count,
                error: model.suggestionsError,
                isLoading: model.isLoadingSuggestions,
                retry: { Task { await model.loadSuggestions() } }
            ),
            WorkHealthMetric(
                id: "workbench",
                title: "Workbench",
                count: model.workbenchReadyCount,
                error: model.workbenchError,
                isLoading: model.isLoadingWorkbench,
                retry: { Task { await model.loadWorkbench() } }
            ),
            WorkHealthMetric(
                id: "approvals",
                title: "Approvals",
                count: model.approvalAttentionCount,
                error: model.approvalAttentionError,
                isLoading: model.isLoadingApprovalAttention,
                retry: { Task { await model.loadApprovalAttention() } }
            ),
            WorkHealthMetric(
                id: "projects",
                title: "Projects",
                count: model.projects.count,
                error: model.projectsError,
                isLoading: model.isLoadingProjects,
                retry: { Task { await model.loadProjects() } }
            ),
            WorkHealthMetric(
                id: "tickets",
                title: "Tickets",
                count: model.activeTicketCount,
                error: model.ticketsError,
                isLoading: model.isLoadingTickets,
                retry: { Task { await model.loadTickets() } }
            ),
            WorkHealthMetric(
                id: "flow",
                title: "Flow",
                count: model.ticketFlowReview?.counts.total ?? 0,
                error: model.ticketFlowErrorMessage,
                isLoading: false,
                retry: { Task { await model.loadTicketFlowReview() } }
            )
        ]
    }
}

private struct WorkHealthMetric: Identifiable {
    let id: String
    let title: String
    let count: Int
    let error: String?
    let isLoading: Bool
    let retry: () -> Void
}

private struct WorkHealthChip: View {
    let metric: WorkHealthMetric

    var body: some View {
        Button(action: metric.retry) {
            HStack(spacing: 5) {
                Image(systemName: metric.isLoading ? "hourglass" : (hasError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                    .font(.system(size: 10, weight: .semibold))
                Text(metric.title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(metric.count)")
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
        .accessibilityLabel(metric.error ?? "\(metric.title) loaded")
    }

    private var hasError: Bool {
        metric.error != nil
    }

    private var color: Color {
        hasError ? AppColors.accentWarning : AppColors.accentSuccess
    }
}

private struct WorkbenchAgentToolsShelf: View {
    let projection: WorkbenchAgentToolsProjection?
    let isLoading: Bool
    let error: String?

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Loading ORCA tools")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }
            } else if let projection {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Label("Tools", systemImage: "wrench.and.screwdriver.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColors.accentElectric)

                        Spacer(minLength: 0)

                        Text("\(projection.availableCapabilities.count) live")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColors.accentSuccess)

                        Text("\(projection.disabledCapabilities.count) held")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary)
                    }

                    FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                        ForEach(projection.capabilities.prefix(6)) { capability in
                            toolChip(capability)
                        }
                    }

                    Text("\(projection.provenanceSourceLabel) · \(projection.richToolsPolicy.replacingOccurrences(of: "_", with: " "))")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(AppColors.backgroundSecondary.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppColors.border.opacity(0.7), lineWidth: 0.5)
                )
            } else if let error {
                Label(error, systemImage: "wrench.adjustable")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentWarning)
                    .lineLimit(2)
            }
        }
    }

    private func toolChip(_ capability: WorkbenchAgentToolCapability) -> some View {
        let color = chipColor(for: capability)
        return HStack(spacing: 4) {
            Image(systemName: chipIcon(for: capability))
                .font(.system(size: 9, weight: .semibold))
            Text(capability.label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            if capability.requiresApproval {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
        .accessibilityLabel("\(capability.label) \(capability.status)")
    }

    private func chipColor(for capability: WorkbenchAgentToolCapability) -> Color {
        switch capability.normalizedStatus {
        case "available":
            return capability.requiresApproval ? AppColors.accentWarning : AppColors.accentSuccess
        case "disabled", "blocked":
            return AppColors.textTertiary
        default:
            return AppColors.accentElectric
        }
    }

    private func chipIcon(for capability: WorkbenchAgentToolCapability) -> String {
        switch capability.toolClass {
        case "read_context": return "book"
        case "preview": return "eye"
        case "workspace_artifact": return "folder.badge.gearshape"
        case "agent_action": return "paperplane"
        case "compute": return "cpu"
        case "external_or_desktop": return "desktopcomputer"
        case "protected": return "lock.shield"
        default: return capability.requiresApproval ? "checkmark.shield" : "wrench.and.screwdriver"
        }
    }
}

enum WorkbenchTaskLane: String, CaseIterable, Identifiable {
    case mine
    case newest
    case oldest
    case waiting
    case blocking
    case stale
    case ready
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mine: return "Mine"
        case .newest: return "New"
        case .oldest: return "Oldest"
        case .waiting: return "Waiting"
        case .blocking: return "Blocking"
        case .stale: return "Stale"
        case .ready: return "Ready"
        case .all: return "All"
        }
    }

    var icon: String {
        switch self {
        case .mine: return "person.crop.circle"
        case .newest: return "sparkle.magnifyingglass"
        case .oldest: return "clock.arrow.circlepath"
        case .waiting: return "person.badge.clock"
        case .blocking: return "exclamationmark.octagon"
        case .stale: return "clock.badge.exclamationmark"
        case .ready: return "bolt.fill"
        case .all: return "tray.full"
        }
    }
}

private struct WorkbenchCalendarCockpitSection: View {
    let model: WorkViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = model.calendarError {
                errorLine(error)
            } else if model.isLoadingCalendar && model.calendarBlocks.isEmpty {
                loadingLine("Loading calendar cockpit")
            } else {
                summaryStrip
                currentBlock
                blockList
            }
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PLANNER")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
                Text("Calendar cockpit")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
            }

            Spacer()

            Button {
                Task { await model.scheduleWorkbenchFocusBlock() }
            } label: {
                Image(systemName: model.isMutatingCalendar ? "hourglass" : "calendar.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                    .frame(width: 30, height: 30)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.isMutatingCalendar || !model.canUseCalendarCockpit)
            .accessibilityLabel("Schedule focus block")

            Button {
                Task { await model.loadCalendarCockpit() }
            } label: {
                Image(systemName: model.isLoadingCalendar ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingCalendar)
            .accessibilityLabel("Refresh calendar cockpit")
        }
    }

    private var summaryStrip: some View {
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            toolPill("\(model.calendarBlocks.count) today", icon: "calendar", color: AppColors.accentElectric)
            if let total = model.planningContext?.overdueTotal {
                toolPill("\(total) overdue", icon: "exclamationmark.triangle.fill", color: AppColors.accentWarning)
            }
            toolPill("\(model.planningContext?.readyNow.count ?? 0) ready", icon: "bolt.fill", color: AppColors.accentSuccess)
            if let current = model.currentPlanningTitle {
                toolPill(current, icon: "play.fill", color: AppColors.accentSuccess)
            }
        }
    }

    @ViewBuilder
    private var currentBlock: some View {
        if let block = model.activeCalendarBlock {
            calendarBlockCard(block, featured: true)
        } else if let current = model.planningContext?.currentBlock {
            VStack(alignment: .leading, spacing: 5) {
                Label("Current", systemImage: "play.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.accentSuccess)
                Text(current.titleShort ?? current.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.calendarBlocks.isEmpty {
                Text("No scheduled blocks in the current org day.")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(model.calendarBlocks.prefix(4)) { block in
                    calendarBlockCard(block, featured: false)
                }
            }
        }
    }

    private func calendarBlockCard(_ block: WorkbenchCalendarBlock, featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(calendarColor(block).opacity(0.12))
                    Image(systemName: block.isActive ? "play.fill" : "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(calendarColor(block))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(block.displayTitle)
                        .font(.system(size: featured ? 15 : 13, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)
                    Text("\(block.startsText)-\(block.endsText) · \(block.lane ?? block.kind ?? "block")")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text((block.status ?? "planned").replacingOccurrences(of: "_", with: " "))
                    .font(.caption2.weight(.bold))
                    .foregroundColor(calendarColor(block))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(calendarColor(block).opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                if !block.isActive && !block.isClosed {
                    Button {
                        Task { await model.startCalendarBlock(block) }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentSuccess)
                    .disabled(model.isMutatingCalendar)
                }

                if block.isActive {
                    Button {
                        Task { await model.finishCalendarBlock(block) }
                    } label: {
                        Label("Finish", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentElectric)
                    .disabled(model.isMutatingCalendar)
                }

                if !block.isClosed {
                    Button {
                        Task { await model.cancelCalendarBlock(block) }
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.textTertiary)
                    .disabled(model.isMutatingCalendar)
                }

                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(featured ? AppColors.accentSuccess.opacity(0.08) : AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func toolPill(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    private func loadingLine(_ message: String) -> some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.mini)
            Text(message)
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
        .padding(10)
        .background(AppColors.backgroundTertiary.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func errorLine(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundColor(AppColors.accentWarning)
            .lineLimit(2)
    }

    private func calendarColor(_ block: WorkbenchCalendarBlock) -> Color {
        switch block.status {
        case "active": return AppColors.accentSuccess
        case "done": return AppColors.accentElectric
        case "cancelled": return AppColors.textTertiary
        case "overdue": return AppColors.accentWarning
        default: return AppColors.accentElectric
        }
    }
}

private struct WorkbenchTasksSection: View {
    var model: WorkViewModel
    let onOpenTicket: (String) -> Void
    let onComment: (WorkbenchWorkItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TASKS · \(model.taskRows(for: model.selectedTaskLane).count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Button {
                    Task { await model.loadWorkbench() }
                } label: {
                    Image(systemName: model.isLoadingWorkbench ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingWorkbench)
                .accessibilityLabel("Refresh tasks")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            taskLaneBar

            VStack(spacing: 8) {
                if model.isLoadingWorkbench && model.visibleTaskRows.isEmpty {
                    taskSkeletons
                } else if let error = model.workbenchError, model.visibleTaskRows.isEmpty {
                    taskError(message: error)
                } else if model.taskRows(for: model.selectedTaskLane).isEmpty {
                    emptyState
                } else {
                    ForEach(model.displayedTaskRows) { item in
                        taskCard(item)
                    }

                    let overflow = model.taskRows(for: model.selectedTaskLane).count - model.displayedTaskRows.count
                    if overflow > 0 {
                        Text("+\(overflow) more tasks in this lane")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
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

    private var taskLaneBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkbenchTaskLane.allCases) { lane in
                    taskLaneChip(lane)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func taskLaneChip(_ lane: WorkbenchTaskLane) -> some View {
        let isOn = model.selectedTaskLane == lane
        let count = model.taskLaneCount(lane)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.selectedTaskLane = lane
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: lane.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(lane.label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isOn ? Color.black.opacity(0.7) : AppColors.textTertiary)
            }
            .foregroundColor(isOn ? Color.black : AppColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isOn ? AppColors.textPrimary : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isOn ? Color.clear : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func taskCard(_ item: WorkbenchWorkItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(taskColor(item).opacity(0.12))
                    Image(systemName: item.isProtected ? "lock.shield.fill" : "checklist")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(taskColor(item))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.safeTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)

                    Text(taskDetail(item))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                if item.canUseAgentActionNote {
                    taskPill("action", color: AppColors.accentSuccess)
                } else if item.isProtected {
                    taskPill("protected", color: AppColors.accentWarning)
                }
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                taskPill(item.status ?? item.kind, color: AppColors.textSecondary)
                if let priority = item.priority {
                    taskPill(priority, color: taskColor(item))
                }
                if let route = item.route ?? item.room {
                    taskPill(route, color: AppColors.textTertiary)
                }
                if let freshness = item.workbenchFreshnessLabel {
                    taskPill(freshness, color: AppColors.textTertiary)
                }
                if item.stale {
                    taskPill("stale", color: AppColors.accentDanger)
                }
            }

            WorkbenchAgentToolsShelf(
                projection: model.toolProjection(for: item),
                isLoading: model.isLoadingToolProjection(for: item),
                error: model.toolProjectionError(for: item)
            )

            HStack(spacing: 8) {
                if let ticketId = item.sourceTicketId {
                    Button {
                        onOpenTicket(ticketId)
                    } label: {
                        Label("Open", systemImage: "ticket")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentElectric)
                }

                if item.canUseAgentActionNote {
                    Button {
                        onComment(item)
                    } label: {
                        Label("Note", systemImage: "square.and.pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentSuccess)
                }

                if let statusAction = item.nextTaskStatusAction {
                    Button {
                        Task { await model.commitWorkbenchStatusAdvance(item: item) }
                    } label: {
                        Label(statusAction.label, systemImage: statusAction.icon)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentWarning)
                    .disabled(model.isCommittingWorkbenchAction)
                }

                if item.canAddToPlanner {
                    Button {
                        Task { await model.commitWorkbenchPlannerAdd(item: item) }
                    } label: {
                        Label("Plan", systemImage: "calendar.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentElectric)
                    .disabled(model.isCommittingWorkbenchAction)
                }

                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }

    private var taskSkeletons: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.backgroundTertiary)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.backgroundTertiary)
                            .frame(height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.backgroundTertiary)
                            .frame(width: 150, height: 10)
                    }
                }
                .padding(10)
                .background(AppColors.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
            Text("No tasks in this lane.")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
        .padding(14)
    }

    private func taskError(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentDanger)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
        .padding(14)
    }

    private func taskDetail(_ item: WorkbenchWorkItem) -> String {
        [
            item.nextAction,
            item.waitingOn.map { "waiting on \($0)" },
            item.blockedOn.map { "blocked on \($0)" },
            item.contentPolicy
        ]
        .compactMap { $0?.replacingOccurrences(of: "_", with: " ") }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        .nilIfBlankForWork ?? "Ready in Workbench."
    }

    private func taskColor(_ item: WorkbenchWorkItem) -> Color {
        if item.isProtected { return AppColors.accentWarning }
        if item.stale { return AppColors.accentDanger }
        switch item.priority?.lowercased() {
        case "urgent", "high": return AppColors.accentWarning
        case "low": return AppColors.textTertiary
        default: return AppColors.accentElectric
        }
    }

    private func taskPill(_ text: String, color: Color) -> some View {
        Text(text.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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
    var workbench: WorkbenchEnvelope?
    var workbenchRows: [WorkbenchWorkItem] = []
    var isLoadingWorkbench = false
    var workbenchError: String?
    var workbenchViewerName: String?
    var divisionWorkflow: WorkbenchDivisionWorkflow?
    var toolShelf: WorkbenchToolShelf?
    var calendarBlocks: [WorkbenchCalendarBlock] = []
    var planningContext: WorkbenchPlanningContext?
    var isLoadingCalendar = false
    var isMutatingCalendar = false
    var calendarError: String?
    var toolRuns: [WorkbenchToolRunRecord] = []
    var toolRunsError: String?
    var isLoadingToolRuns = false
    var isRunningWorkbenchTool = false
    var approvalAttention: WorkbenchApprovalAttention?
    var approvalAttentionItems: [WorkbenchApprovalAttentionItem] = []
    var isLoadingApprovalAttention = false
    var approvalAttentionError: String?
    var actionPreview: WorkbenchPlaygroundPreview?
    var actionPreviewError: String?
    var isLoadingActionPreview = false
    var previewingApprovalIds: Set<String> = []
    var workbenchActionPreview: WorkbenchPlaygroundPreview?
    var workbenchActionPreviewSignature: String?
    var workbenchActionError: String?
    var isPreviewingWorkbenchAction = false
    var isCommittingWorkbenchAction = false
    var toolProjectionsByItemKey: [String: WorkbenchAgentToolsProjection] = [:]
    var loadingToolProjectionKeys: Set<String> = []
    var toolProjectionErrorsByItemKey: [String: String] = [:]
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
    var selectedTaskLane: WorkbenchTaskLane = .mine

    // MARK: Suggestions
    var schoolhouseDigest: SchoolhouseDigest?
    var suggestions: [SchoolhouseSuggestion] = []
    var isLoadingSuggestions = false
    var suggestionsError: String?
    var suggestionActionIds: Set<String> = []
    var reviewerIdentity = "pod"

    var workbenchReadyCount: Int {
        workbench?.buckets.workQueue?.counts["ready_now"] ?? visibleWorkbenchRows.count
    }

    var canUseCalendarCockpit: Bool {
        calendarAgentName != nil
    }

    var activeCalendarBlock: WorkbenchCalendarBlock? {
        calendarBlocks.first(where: { $0.isActive })
    }

    var currentPlanningTitle: String? {
        guard let current = planningContext?.currentBlock else { return nil }
        return current.titleShort ?? current.title
    }

    private var calendarAgentName: String? {
        let candidate = (workbenchViewerName ?? reviewerIdentity)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !candidate.isEmpty, candidate != "pod", candidate != "captain" else {
            return nil
        }
        return candidate
    }

    var visibleTaskRows: [WorkbenchWorkItem] {
        taskRows(for: selectedTaskLane)
    }

    var displayedTaskRows: [WorkbenchWorkItem] {
        Array(visibleTaskRows.prefix(6))
    }

    func taskLaneCount(_ lane: WorkbenchTaskLane) -> Int {
        taskRows(for: lane).count
    }

    func taskRows(for lane: WorkbenchTaskLane) -> [WorkbenchWorkItem] {
        guard let queue = workbench?.buckets.workQueue else {
            return dedupedTaskRows(workbenchRows)
        }

        switch lane {
        case .mine:
            return dedupedTaskRows(queue.assignedToMe)
        case .newest:
            return dedupedTaskRows(queue.recentlyAssigned)
        case .oldest:
            return dedupedTaskRows(queue.longestWaiting)
        case .waiting:
            return dedupedTaskRows(queue.waitingOnMe)
        case .blocking:
            return dedupedTaskRows(queue.blockingOthers + queue.blockedByMe)
        case .stale:
            return dedupedTaskRows(queue.staleOwnedWork)
        case .ready:
            return dedupedTaskRows(queue.readyNow)
        case .all:
            return dedupedTaskRows([
                queue.readyNow,
                queue.assignedToMe,
                queue.recentlyAssigned,
                queue.longestWaiting,
                queue.waitingOnMe,
                queue.blockingOthers,
                queue.blockedByMe,
                queue.staleOwnedWork,
                queue.recentChanges
            ].flatMap { $0 })
        }
    }

    private func dedupedTaskRows(_ candidates: [WorkbenchWorkItem]) -> [WorkbenchWorkItem] {
        var seen = Set<String>()
        var rows: [WorkbenchWorkItem] = []
        for item in candidates where item.isTaskLike {
            let key = workbenchRowKey(item)
            guard seen.insert(key).inserted else { continue }
            rows.append(item)
        }
        return rows
    }

    var visibleWorkbenchRows: [WorkbenchWorkItem] {
        guard let queue = workbench?.buckets.workQueue else {
            return workbenchRows
        }
        let groups = [
            queue.readyNow,
            queue.assignedToMe,
            queue.recentlyAssigned,
            queue.longestWaiting,
            queue.waitingOnMe,
            queue.blockedByMe,
            queue.staleOwnedWork,
            queue.recentChanges
        ]
        var seen = Set<String>()
        var rows: [WorkbenchWorkItem] = []
        for item in groups.flatMap({ $0 }) {
            let key = workbenchRowKey(item)
            guard seen.insert(key).inserted else { continue }
            rows.append(item)
        }
        return rows
    }

    var workbenchActionableRows: [WorkbenchWorkItem] {
        visibleWorkbenchRows.filter { $0.canUseAgentActionNote }
    }

    var displayedWorkbenchRows: [WorkbenchWorkItem] {
        let rows = visibleWorkbenchRows
        let actionable = rows.filter { $0.canUseAgentActionNote }
        let passive = rows.filter { !$0.canUseAgentActionNote }
        var seen = Set<String>()
        var featured: [WorkbenchWorkItem] = []
        for item in Array(actionable.prefix(4)) + passive + Array(actionable.dropFirst(4)) {
            let key = workbenchRowKey(item)
            guard seen.insert(key).inserted else { continue }
            featured.append(item)
            if featured.count >= 8 { break }
        }
        return featured
    }

    private func workbenchRowKey(_ item: WorkbenchWorkItem) -> String {
        "\(item.kind):\(item.id):\(item.sourceTaskId ?? ""):\(item.sourceTicketId ?? "")"
    }

    var approvalAttentionCount: Int {
        approvalAttention?.counts.total ?? approvalAttentionItems.count
    }

    var actionPreviewLine: String {
        guard let preview = actionPreview else {
            return "Preview validates action payloads without writing ORCA rows or publishing NATS."
        }
        if preview.blocked {
            return preview.warnings.first ?? "Preview blocked by backend policy."
        }
        if preview.wouldWrite || preview.wouldPublishNats {
            return "Preview returned a side-effect warning; commit remains disabled in this lane."
        }
        return "Preview is read-only. Mutations must use visible confirmation and the signed action rail."
    }

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
        reviewerIdentity = normalized.isEmpty ? "pod" : normalized
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
            base = tickets.filter(isMineTicket)
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

    private func isMineTicket(_ ticket: WorkTicketRow) -> Bool {
        let workbenchIds = mineWorkbenchTicketIds
        if !workbenchIds.isEmpty {
            return workbenchIds.contains(ticket.id)
        }

        let identities = mineIdentityKeys
        guard !identities.isEmpty else { return false }
        let owner = ticket.ownerShort.lowercased()
        if identities.contains(owner) { return true }
        if let assigneeId = ticket.assigneeId?.lowercased(), identities.contains(assigneeId) {
            return true
        }
        return false
    }

    private var mineWorkbenchTicketIds: Set<String> {
        Set(workbenchRows.compactMap { item in
            guard item.kind == "ticket" else { return item.sourceTicketId }
            return item.sourceTicketId ?? item.id
        })
    }

    private var mineIdentityKeys: Set<String> {
        Set([workbenchViewerName, reviewerIdentity]
            .compactMap { value in
                let normalized = value?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard let normalized, !normalized.isEmpty, normalized != "pod", normalized != "captain" else {
                    return nil
                }
                return normalized
            })
    }

    // MARK: - Load

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSuggestions() }
            group.addTask { await self.loadWorkbench() }
            group.addTask { await self.loadToolRuns() }
            group.addTask { await self.loadApprovalAttention() }
            group.addTask { await self.loadActionPreview() }
            group.addTask { await self.loadProjects() }
            group.addTask { await self.loadTickets() }
            group.addTask { await self.loadTicketFlowReview() }
        }
    }

    @MainActor
    func loadWorkbench() async {
        isLoadingWorkbench = true
        workbenchError = nil
        defer { isLoadingWorkbench = false }
        do {
            let envelope = try await WorkbenchRepository().load(view: .mine, limit: 50)
            workbench = envelope
            workbenchViewerName = envelope.viewer.name
            divisionWorkflow = envelope.buckets.divisionWorkflow
            toolShelf = envelope.buckets.toolShelf
            workbenchRows = envelope.buckets.workQueue?.assignedToMe ?? []
            await loadAgentToolsForVisibleWorkbenchRows()
            await loadCalendarCockpit(agentName: envelope.viewer.name)
        } catch let error as APIError where error.code == 401 {
            workbench = nil
            workbenchRows = []
            workbenchViewerName = nil
            divisionWorkflow = nil
            toolShelf = nil
            calendarBlocks = []
            planningContext = nil
            toolProjectionsByItemKey = [:]
            loadingToolProjectionKeys = []
            toolProjectionErrorsByItemKey = [:]
            workbenchError = "Agent token required"
        } catch {
            workbench = nil
            workbenchRows = []
            workbenchViewerName = nil
            divisionWorkflow = nil
            toolShelf = nil
            calendarBlocks = []
            planningContext = nil
            toolProjectionsByItemKey = [:]
            loadingToolProjectionKeys = []
            toolProjectionErrorsByItemKey = [:]
            workbenchError = "Workbench unavailable"
        }
    }

    @MainActor
    func loadCalendarCockpit(agentName explicitAgentName: String? = nil) async {
        guard let agentName = explicitAgentName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ?? calendarAgentName else {
            calendarBlocks = []
            planningContext = nil
            calendarError = "Agent token required"
            return
        }
        isLoadingCalendar = true
        calendarError = nil
        defer { isLoadingCalendar = false }
        do {
            async let blocks = WorkbenchRepository().loadCalendarToday(agentName: agentName)
            async let context = WorkbenchRepository().loadPlanningContext(agentName: agentName)
            calendarBlocks = try await blocks
            planningContext = try await context
        } catch let error as APIError {
            calendarBlocks = []
            planningContext = nil
            calendarError = error.message
        } catch {
            calendarBlocks = []
            planningContext = nil
            calendarError = "Calendar unavailable"
        }
    }

    @MainActor
    func scheduleWorkbenchFocusBlock() async {
        guard let agentName = calendarAgentName, !isMutatingCalendar else { return }
        let title = visibleWorkbenchRows.first?.safeTitle
            ?? divisionWorkflow?.recurringDuties.first
            ?? "Workbench focus block"
        isMutatingCalendar = true
        calendarError = nil
        defer { isMutatingCalendar = false }
        do {
            _ = try await WorkbenchRepository().scheduleCalendarBlock(agentName: agentName, title: title, minutes: 30)
            priorityToast = PriorityToast(message: "Focus block scheduled", isError: false, retry: nil)
            await loadCalendarCockpit(agentName: agentName)
        } catch let error as APIError {
            calendarError = error.message
            priorityToast = PriorityToast(message: "Calendar action failed", isError: true, retry: nil)
        } catch {
            calendarError = "Calendar action failed"
            priorityToast = PriorityToast(message: "Calendar action failed", isError: true, retry: nil)
        }
    }

    @MainActor
    func startCalendarBlock(_ block: WorkbenchCalendarBlock) async {
        guard let agentName = calendarAgentName, !isMutatingCalendar else { return }
        isMutatingCalendar = true
        calendarError = nil
        defer { isMutatingCalendar = false }
        do {
            _ = try await WorkbenchRepository().startCalendarBlock(agentName: agentName, eventId: block.eventId)
            priorityToast = PriorityToast(message: "Calendar block started", isError: false, retry: nil)
            await loadCalendarCockpit(agentName: agentName)
        } catch let error as APIError {
            calendarError = error.message
            priorityToast = PriorityToast(message: "Start failed", isError: true, retry: nil)
        } catch {
            calendarError = "Start failed"
            priorityToast = PriorityToast(message: "Start failed", isError: true, retry: nil)
        }
    }

    @MainActor
    func finishCalendarBlock(_ block: WorkbenchCalendarBlock) async {
        guard let agentName = calendarAgentName, !isMutatingCalendar else { return }
        isMutatingCalendar = true
        calendarError = nil
        defer { isMutatingCalendar = false }
        do {
            _ = try await WorkbenchRepository().finishCalendarBlock(
                agentName: agentName,
                eventId: block.eventId,
                outcome: "Finished from Pod Bench calendar cockpit."
            )
            priorityToast = PriorityToast(message: "Calendar block finished", isError: false, retry: nil)
            await loadCalendarCockpit(agentName: agentName)
        } catch let error as APIError {
            calendarError = error.message
            priorityToast = PriorityToast(message: "Finish failed", isError: true, retry: nil)
        } catch {
            calendarError = "Finish failed"
            priorityToast = PriorityToast(message: "Finish failed", isError: true, retry: nil)
        }
    }

    @MainActor
    func cancelCalendarBlock(_ block: WorkbenchCalendarBlock) async {
        guard let agentName = calendarAgentName, !isMutatingCalendar else { return }
        isMutatingCalendar = true
        calendarError = nil
        defer { isMutatingCalendar = false }
        do {
            _ = try await WorkbenchRepository().cancelCalendarBlock(agentName: agentName, eventId: block.eventId)
            priorityToast = PriorityToast(message: "Calendar block cancelled", isError: false, retry: nil)
            await loadCalendarCockpit(agentName: agentName)
        } catch let error as APIError {
            calendarError = error.message
            priorityToast = PriorityToast(message: "Cancel failed", isError: true, retry: nil)
        } catch {
            calendarError = "Cancel failed"
            priorityToast = PriorityToast(message: "Cancel failed", isError: true, retry: nil)
        }
    }

    @MainActor
    func loadToolRuns() async {
        isLoadingToolRuns = true
        toolRunsError = nil
        defer { isLoadingToolRuns = false }
        do {
            let response = try await WorkbenchRepository().loadToolRuns(limit: 12)
            toolShelf = response.toolShelf
            toolRuns = response.runs
        } catch let error as APIError where error.code == 401 {
            toolRuns = []
            toolRunsError = "Agent token required"
        } catch {
            toolRuns = []
            toolRunsError = "Tool runs unavailable"
        }
    }

    @MainActor
    func runQueueSummaryTool() async {
        await runWorkbenchTool(
            WorkbenchToolRunRequest(
                toolId: "workbench.summarize_queue",
                traceId: "pod-workbench-summary-\(UUID().uuidString)",
                runtimeSurface: "pod.workbench",
                runtimeName: "Pod Bench",
                llmProvider: "agent",
                llmModel: workbenchViewerName
            ),
            successMessage: "Queue summary recorded"
        )
    }

    @MainActor
    func runPlannerFocusTool() async {
        let title = divisionWorkflow?.recurringDuties.first
            ?? visibleWorkbenchRows.first?.safeTitle
            ?? "Review Workbench ready-now queue"
        await runWorkbenchTool(
            WorkbenchToolRunRequest(
                toolId: "planner.add_focus_item",
                input: [
                    "title": title,
                    "body": "Created from Pod Bench governed tool shelf.",
                    "lane": "now",
                    "priority": "medium"
                ],
                traceId: "pod-workbench-planner-\(UUID().uuidString)",
                runtimeSurface: "pod.workbench",
                runtimeName: "Pod Bench",
                llmProvider: "agent",
                llmModel: workbenchViewerName
            ),
            successMessage: "Planner focus added"
        )
    }

    @MainActor
    func runReviewRequestTool() async {
        await runWorkbenchTool(
            WorkbenchToolRunRequest(
                toolId: "approval.request_review",
                input: [
                    "reason": "Workbench requested a reviewer check from the governed tool shelf."
                ],
                traceId: "pod-workbench-review-\(UUID().uuidString)",
                runtimeSurface: "pod.workbench",
                runtimeName: "Pod Bench",
                llmProvider: "agent",
                llmModel: workbenchViewerName
            ),
            successMessage: "Review request recorded"
        )
    }

    @MainActor
    private func runWorkbenchTool(_ request: WorkbenchToolRunRequest, successMessage: String) async {
        guard !isRunningWorkbenchTool else { return }
        isRunningWorkbenchTool = true
        toolRunsError = nil
        defer { isRunningWorkbenchTool = false }
        do {
            let receipt = try await WorkbenchRepository().executeToolRun(request)
            priorityToast = PriorityToast(
                message: receipt.approvalRequired ? "Tool waiting on approval" : successMessage,
                isError: false,
                retry: nil
            )
            await loadToolRuns()
            if request.toolId == "planner.add_focus_item" {
                await loadWorkbench()
            }
        } catch let error as APIError {
            toolRunsError = error.message
            priorityToast = PriorityToast(message: "Tool run failed", isError: true, retry: nil)
        } catch {
            toolRunsError = "Tool run failed"
            priorityToast = PriorityToast(message: "Tool run failed", isError: true, retry: nil)
        }
    }

    func toolProjection(for item: WorkbenchWorkItem) -> WorkbenchAgentToolsProjection? {
        guard let key = toolProjectionKey(for: item) else { return nil }
        return toolProjectionsByItemKey[key]
    }

    func isLoadingToolProjection(for item: WorkbenchWorkItem) -> Bool {
        guard let key = toolProjectionKey(for: item) else { return false }
        return loadingToolProjectionKeys.contains(key)
    }

    func toolProjectionError(for item: WorkbenchWorkItem) -> String? {
        guard let key = toolProjectionKey(for: item) else { return nil }
        return toolProjectionErrorsByItemKey[key]
    }

    @MainActor
    private func loadAgentToolsForVisibleWorkbenchRows() async {
        let candidates = Array((displayedTaskRows + displayedWorkbenchRows).prefix(12))
        var seen = Set<String>()
        for item in candidates {
            guard let key = toolProjectionKey(for: item),
                  seen.insert(key).inserted,
                  toolProjectionsByItemKey[key] == nil else {
                continue
            }
            await loadAgentTools(for: item, key: key)
        }
    }

    @MainActor
    private func loadAgentTools(for item: WorkbenchWorkItem, key: String? = nil) async {
        guard let request = toolProjectionRequest(for: item) else { return }
        let resolvedKey = key ?? request.key
        guard !loadingToolProjectionKeys.contains(resolvedKey) else { return }

        loadingToolProjectionKeys.insert(resolvedKey)
        toolProjectionErrorsByItemKey[resolvedKey] = nil
        defer { loadingToolProjectionKeys.remove(resolvedKey) }

        do {
            let projection = try await WorkbenchRepository().loadAgentTools(
                agentName: request.agentName,
                ticketId: request.ticketId,
                taskId: request.taskId
            )
            toolProjectionsByItemKey[resolvedKey] = projection
        } catch let apiError as APIError {
            toolProjectionsByItemKey[resolvedKey] = nil
            toolProjectionErrorsByItemKey[resolvedKey] = apiError.message
        } catch {
            toolProjectionsByItemKey[resolvedKey] = nil
            toolProjectionErrorsByItemKey[resolvedKey] = "Tool projection unavailable"
        }
    }

    private struct ToolProjectionRequest {
        let key: String
        let agentName: String
        let ticketId: String?
        let taskId: String?
    }

    private func toolProjectionRequest(for item: WorkbenchWorkItem) -> ToolProjectionRequest? {
        let agent = (workbenchViewerName ?? reviewerIdentity)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !agent.isEmpty, agent != "pod", agent != "captain" else { return nil }

        let ticketId = item.sourceTicketId ?? (item.kind == "ticket" ? item.id : nil)
        let taskId = item.effectiveTaskId
        guard ticketId != nil || taskId != nil else { return nil }

        return ToolProjectionRequest(
            key: "\(agent)|\(ticketId ?? "-")|\(taskId ?? "-")",
            agentName: agent,
            ticketId: ticketId,
            taskId: taskId
        )
    }

    private func toolProjectionKey(for item: WorkbenchWorkItem) -> String? {
        toolProjectionRequest(for: item)?.key
    }

    @MainActor
    func loadApprovalAttention() async {
        isLoadingApprovalAttention = true
        approvalAttentionError = nil
        defer { isLoadingApprovalAttention = false }
        do {
            let response = try await WorkbenchRepository().loadApprovalAttention(limit: 25)
            approvalAttention = response
            approvalAttentionItems = response.items
        } catch {
            approvalAttention = nil
            approvalAttentionItems = []
            approvalAttentionError = "Approvals unavailable"
        }
    }

    @MainActor
    func loadActionPreview() async {
        isLoadingActionPreview = true
        actionPreviewError = nil
        defer { isLoadingActionPreview = false }
        do {
            actionPreview = try await WorkbenchRepository().previewAgentAction(action: "resolve_approval")
        } catch {
            actionPreview = nil
            actionPreviewError = "Action preview unavailable"
        }
    }

    @MainActor
    func previewApprovalAction(_ item: WorkbenchApprovalAttentionItem) async {
        guard !previewingApprovalIds.contains(item.id) else { return }
        previewingApprovalIds.insert(item.id)
        actionPreviewError = nil
        defer { previewingApprovalIds.remove(item.id) }
        do {
            actionPreview = try await WorkbenchRepository().previewAgentAction(action: "resolve_approval")
            priorityToast = PriorityToast(message: "Preview checked: no write", isError: false, retry: nil)
        } catch {
            actionPreviewError = "Preview unavailable for \(String(item.id.prefix(8)))"
            priorityToast = PriorityToast(
                message: "Preview failed — tap to retry",
                isError: true,
                retry: { [weak self] in
                    Task { await self?.previewApprovalAction(item) }
                }
            )
        }
    }

    func resetWorkbenchActionPreview() {
        workbenchActionPreview = nil
        workbenchActionPreviewSignature = nil
        workbenchActionError = nil
    }

    func hasFreshWorkbenchActionPreview(item: WorkbenchWorkItem, message: String) -> Bool {
        guard let signature = workbenchActionSignature(item: item, message: message),
              signature == workbenchActionPreviewSignature,
              let preview = workbenchActionPreview else {
            return false
        }
        return !preview.blocked && !preview.wouldWrite && !preview.wouldPublishNats
    }

    @MainActor
    func previewWorkbenchNote(item: WorkbenchWorkItem, message: String) async {
        guard !isPreviewingWorkbenchAction else { return }
        guard let signature = workbenchActionSignature(item: item, message: message),
              let request = workbenchNoteRequest(item: item, message: message) else {
            workbenchActionPreview = nil
            workbenchActionPreviewSignature = nil
            workbenchActionError = "Note needs a task or ticket target plus a message."
            return
        }
        isPreviewingWorkbenchAction = true
        workbenchActionError = nil
        defer { isPreviewingWorkbenchAction = false }
        do {
            workbenchActionPreview = try await WorkbenchRepository().previewAgentAction(request)
            workbenchActionPreviewSignature = signature
        } catch {
            workbenchActionPreview = nil
            workbenchActionPreviewSignature = nil
            workbenchActionError = "Preview unavailable."
        }
    }

    @MainActor
    func commitWorkbenchNote(item: WorkbenchWorkItem, message: String) async -> Bool {
        guard !isCommittingWorkbenchAction else { return false }
        guard hasFreshWorkbenchActionPreview(item: item, message: message),
              let request = workbenchNoteRequest(item: item, message: message) else {
            workbenchActionError = "Preview this exact note before posting."
            return false
        }
        isCommittingWorkbenchAction = true
        workbenchActionError = nil
        defer { isCommittingWorkbenchAction = false }
        do {
            let response = try await WorkbenchRepository().executeAgentAction(request)
            resetWorkbenchActionPreview()
            priorityToast = PriorityToast(
                message: "\(response.objectType.replacingOccurrences(of: "_", with: " ").capitalized) note posted",
                isError: false,
                retry: nil
            )
            await loadWorkbench()
            return true
        } catch let error as APIError {
            workbenchActionError = error.message
            priorityToast = PriorityToast(message: "Workbench action failed", isError: true, retry: nil)
            return false
        } catch {
            workbenchActionError = "Workbench action failed."
            priorityToast = PriorityToast(message: "Workbench action failed", isError: true, retry: nil)
            return false
        }
    }

    @MainActor
    func commitWorkbenchStatusAdvance(item: WorkbenchWorkItem) async -> Bool {
        guard !isCommittingWorkbenchAction else { return false }
        guard let request = workbenchTaskStatusRequest(item: item),
              let statusAction = item.nextTaskStatusAction else {
            workbenchActionError = "Task status action is unavailable."
            return false
        }
        isCommittingWorkbenchAction = true
        workbenchActionError = nil
        defer { isCommittingWorkbenchAction = false }
        do {
            _ = try await WorkbenchRepository().executeAgentAction(request)
            priorityToast = PriorityToast(message: "\(statusAction.label) sent", isError: false, retry: nil)
            await loadWorkbench()
            return true
        } catch let error as APIError {
            workbenchActionError = error.message
            priorityToast = PriorityToast(message: "Status action failed", isError: true, retry: nil)
            return false
        } catch {
            workbenchActionError = "Status action failed."
            priorityToast = PriorityToast(message: "Status action failed", isError: true, retry: nil)
            return false
        }
    }

    @MainActor
    func commitWorkbenchPlannerAdd(item: WorkbenchWorkItem) async -> Bool {
        guard !isCommittingWorkbenchAction else { return false }
        guard let request = workbenchPlannerAddRequest(item: item) else {
            workbenchActionError = "Planner action is unavailable."
            return false
        }
        isCommittingWorkbenchAction = true
        workbenchActionError = nil
        defer { isCommittingWorkbenchAction = false }
        do {
            _ = try await WorkbenchRepository().executeAgentAction(request)
            priorityToast = PriorityToast(message: "Added to planner", isError: false, retry: nil)
            await loadWorkbench()
            return true
        } catch let error as APIError {
            workbenchActionError = error.message
            priorityToast = PriorityToast(message: "Planner action failed", isError: true, retry: nil)
            return false
        } catch {
            workbenchActionError = "Planner action failed."
            priorityToast = PriorityToast(message: "Planner action failed", isError: true, retry: nil)
            return false
        }
    }

    private func workbenchActionSignature(item: WorkbenchWorkItem, message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let boardId = item.boardId, let taskId = item.effectiveTaskId {
            return "task|\(boardId)|\(taskId)|\(trimmed)"
        }
        if let ticketId = item.effectiveTicketId {
            return "ticket|\(ticketId)|\(trimmed)"
        }
        return nil
    }

    private func workbenchNoteRequest(item: WorkbenchWorkItem, message: String) -> WorkbenchAgentActionRequest? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, item.canUseAgentActionNote else {
            return nil
        }
        if let boardId = item.boardId, let taskId = item.effectiveTaskId {
            return WorkbenchAgentActionRequest(
                action: "comment_task",
                boardId: boardId,
                taskId: taskId,
                comment: WorkbenchTaskComment(
                    message: trimmed,
                    actionRequired: false
                )
            )
        }
        guard let ticketId = item.effectiveTicketId else { return nil }
        return WorkbenchAgentActionRequest(
            action: "ticket_comment",
            ticketId: ticketId,
            comment: WorkbenchTaskComment(
                message: trimmed,
                actionRequired: false
            )
        )
    }

    private func workbenchTaskStatusRequest(item: WorkbenchWorkItem) -> WorkbenchAgentActionRequest? {
        guard let boardId = item.boardId,
              let taskId = item.effectiveTaskId,
              let statusAction = item.nextTaskStatusAction else {
            return nil
        }
        return WorkbenchAgentActionRequest(
            action: "update_task",
            boardId: boardId,
            taskId: taskId,
            taskUpdate: WorkbenchTaskUpdate(
                status: statusAction.status,
                comment: "Pod Bench: \(statusAction.label.lowercased())."
            )
        )
    }

    private func workbenchPlannerAddRequest(item: WorkbenchWorkItem) -> WorkbenchAgentActionRequest? {
        guard item.canAddToPlanner else { return nil }
        let sourceType = item.isTaskLike ? "task" : item.kind
        let sourceRef = item.effectiveTaskId ?? item.effectiveTicketId ?? item.id
        return WorkbenchAgentActionRequest(
            action: "create_planner_item",
            plannerItem: WorkbenchPlannerItem(
                title: item.safeTitle,
                body: "\(sourceType.capitalized) \(String(sourceRef.prefix(8))) from Pod Bench.",
                lane: "now",
                priority: item.plannerPriority,
                sourceType: sourceType,
                sourceRef: sourceRef
            )
        )
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
            async let ticketsAsync: WorkListResponse<TicketListItem> = APIClient.shared.get(path: "/api/v1/tickets?limit=1000")
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

    func postTicketComment(_ message: String, ticketId: String) async {
        do {
            try await APIClient.shared.postVoid(
                path: "/api/v1/tickets/\(ticketId)/comments",
                body: TicketCommentBody(message: message, source: "pod.work.flow")
            )
            priorityToast = PriorityToast(message: "Comment posted", isError: false, retry: nil)
        } catch {
            priorityToast = PriorityToast(
                message: "Comment failed",
                isError: true,
                retry: { [weak self] in
                    Task { await self?.postTicketComment(message, ticketId: ticketId) }
                }
            )
        }
    }

    func postSuggestionNote(_ text: String, suggestion: SchoolhouseSuggestion) async {
        do {
            try await APIClient.shared.postVoid(
                path: "/api/v1/notes",
                body: NoteCreateBody(
                    targetType: "suggestion",
                    targetId: suggestion.id.uuidString,
                    noteType: "comment",
                    title: String(text.prefix(80)),
                    body: text
                )
            )
            priorityToast = PriorityToast(message: "Note saved", isError: false, retry: nil)
        } catch {
            priorityToast = PriorityToast(
                message: "Note failed to save",
                isError: true,
                retry: { [weak self] in
                    Task { await self?.postSuggestionNote(text, suggestion: suggestion) }
                }
            )
        }
    }
}

private struct TicketCommentBody: Encodable {
    let message: String
    let source: String?
    let lane: String? = nil
    let traceId: String? = nil
    enum CodingKeys: String, CodingKey {
        case message, source, lane
        case traceId = "trace_id"
    }
}

private struct NoteCreateBody: Encodable {
    let targetType: String
    let targetId: String
    let noteType: String
    let title: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case targetType = "target_type"
        case targetId = "target_id"
        case noteType = "note_type"
        case title, body
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

    var isIdeaIntake: Bool { kind == "idea_intake" }

    var memoryCandidateId: String? {
        stringValue(for: ["candidate_id", "memory_candidate_id"], in: sourceRefs)
            ?? stringValue(for: ["candidate_id", "memory_candidate_id"], in: provenance)
    }

    // cascade stage stored in provenance.stage by the M2 assessment endpoint
    var cascadeStage: String? {
        stringValue(for: ["stage"], in: provenance)
    }

    var reviewEyebrow: String {
        if isMemoryCandidateReview { return "Memory candidate review" }
        if isIdeaIntake { return "Maker idea" }
        return "Schoolhouse suggestion"
    }

    var cascadeStageBadge: String {
        switch cascadeStage {
        case "assessing":          return "Assessment ↻"
        case "assessed":           return "Assessed"
        case "discovering",
             "discovering_active": return "Discovery ↻"
        case "project_ready":
            let effort = discoveryEffortSize
            return effort.isEmpty ? "Project-ready" : "Project-ready · \(effort)"
        default:                   return "Intake"
        }
    }

    var ideaStageColor: Color {
        switch cascadeStage {
        case "discovering",
             "discovering_active": return AppColors.accentSuccess
        case "project_ready":      return AppColors.accentElectric
        case "assessing":          return AppColors.accentWarning
        case "assessed":           return AppColors.textSecondary
        default:                   return AppColors.textTertiary
        }
    }

    var discoveryScope: String? {
        guard let disc = provenance?["discovery"],
              case let .object(obj) = disc,
              let scopeVal = obj["scope"],
              case let .string(text) = scopeVal, !text.isEmpty else { return nil }
        return text
    }

    var discoveryEffortSize: String {
        guard let disc = provenance?["discovery"],
              case let .object(obj) = disc,
              let effortVal = obj["effort_estimate"],
              case let .string(text) = effortVal, !text.isEmpty else { return "" }
        // Extract just the t-shirt size prefix (XS/S/M/L/XL) before the dash or space
        let firstWord = text.split(separator: " ").first.map(String.init) ?? ""
        let sizeLabels = ["XS", "S", "M", "L", "XL"]
        return sizeLabels.contains(firstWord) ? firstWord : ""
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
    @State private var selectedProject: ProjectDTO?
    @State private var projectsViewModel = ORCAProjectsViewModel()
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
            .sheet(item: $selectedProject) { project in
                ORCAProjectDetailView(project: project, viewModel: projectsViewModel)
            }
        }
    }

    private var boardHero: some View {
        let accent = boardAccentColor(board.slug)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(board.icon)
                    .font(.system(size: 38))
                    .frame(width: 48, height: 48)
                    .background(accent.opacity(0.14))
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
                .foregroundColor(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accent.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(16)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent)
                .frame(height: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 8,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 8
                ))
        }
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedProject = project
                    }
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
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

private func workbenchCompactDuration(hours: Double) -> String {
    if hours < 1 {
        return "now"
    }
    if hours < 24 {
        return "\(max(1, Int(hours.rounded())))h"
    }
    let days = max(1, Int((hours / 24).rounded()))
    if days < 14 {
        return "\(days)d"
    }
    let weeks = max(2, Int((Double(days) / 7).rounded()))
    return "\(weeks)w"
}

private extension WorkbenchWorkItem {
    var isTaskLike: Bool {
        kind == "task" || sourceTaskId != nil
    }

    var workbenchFreshnessLabel: String? {
        if let waitingHours {
            return "assigned \(workbenchCompactDuration(hours: waitingHours))"
        }
        if let ageHours {
            return "created \(workbenchCompactDuration(hours: ageHours))"
        }
        return nil
    }

    var effectiveTaskId: String? {
        sourceTaskId ?? (kind == "task" ? id : nil)
    }

    var effectiveTicketId: String? {
        sourceTicketId ?? (kind == "ticket" ? id : nil)
    }

    var canUseAgentActionComment: Bool {
        canUseAgentActionNote
    }

    var canUseAgentActionNote: Bool {
        guard !isProtected else { return false }
        if effectiveTaskId != nil && boardId != nil { return true }
        return effectiveTicketId != nil
    }

    var canAddToPlanner: Bool {
        !isProtected && !safeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var nextTaskStatusAction: WorkbenchTaskStatusAction? {
        guard !isProtected, effectiveTaskId != nil, boardId != nil else { return nil }
        switch (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "inbox", "open", "claimed":
            return WorkbenchTaskStatusAction(status: "in_progress", label: "Start", icon: "play.fill")
        case "in_progress":
            return WorkbenchTaskStatusAction(status: "review", label: "Review", icon: "checkmark.seal")
        case "review":
            return WorkbenchTaskStatusAction(status: "done", label: "Done", icon: "checkmark.circle.fill")
        default:
            return nil
        }
    }

    var plannerPriority: String {
        switch (priority ?? "medium").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "urgent", "critical", "p0", "high":
            return "high"
        case "low":
            return "low"
        default:
            return "medium"
        }
    }
}

private struct WorkbenchTaskStatusAction: Hashable {
    let status: String
    let label: String
    let icon: String
}

private extension String {
    var nilIfBlankForWork: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedBoardLabel: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
    }
}
