import SwiftUI

private struct TicketTimelineItem: Identifiable {
    enum Kind {
        case comment(TicketComment)
        case agentRun(AgentRun)
        case note(TicketNoteRecord)
        case approval(TicketApprovalRecord)
    }

    let id: String
    let createdAt: Date
    let kind: Kind
}

private struct TicketEvidenceLink: Identifiable {
    var id: String { path }
    let label: String
    let detail: String
    let icon: String
    let path: String
    let color: Color
}

private struct TicketRoutePacketField: Identifiable {
    var id: String { label }
    let label: String
    let value: String
}

private enum TicketEvidenceLens: String, CaseIterable, Identifiable {
    case timeline
    case runs
    case evidence
    case trace
    case health

    var id: String { rawValue }

    var label: String {
        switch self {
        case .timeline: return "Timeline"
        case .runs: return "Runs"
        case .evidence: return "Evidence"
        case .trace: return "Trace"
        case .health: return "Health"
        }
    }
}

private enum TicketTimelineFilter: String, CaseIterable, Identifiable {
    case all
    case runs
    case evidence
    case approvals
    case comments
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .runs: return "Runs"
        case .evidence: return "Evidence"
        case .approvals: return "Approvals"
        case .comments: return "Comments"
        case .notes: return "Notes"
        }
    }
}

// MARK: - Tickets View

struct TicketsView: View {
    @State private var viewModel = TicketsViewModel()
    @State private var agents: [AgentDTO] = []
    @State private var selectedTicketId: String? = nil
    @State private var showingIntegrityReview = false
    @State private var showingBackfillReview = false
    @State private var showingBacklogReprocessReview = false
    @State private var showingAgentRunReviewQueue = false

    private var selectedTicket: Binding<Ticket?> {
        Binding(
            get: {
                guard let selectedTicketId else { return nil }
                return viewModel.ticket(withId: selectedTicketId)
            },
            set: { ticket in
                selectedTicketId = ticket?.id
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status filter bar
                statusFilterBar
                savedViewsBar
                liveStatusBar
                groomingSummaryBar

                Divider().background(AppColors.border)

                if viewModel.isLoading && viewModel.tickets.isEmpty {
                    loadingView
                } else if viewModel.filtered.isEmpty {
                    emptyView
                } else {
                    ticketList
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Tickets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(AppColors.accentElectric)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
            .task {
                await viewModel.load()
                await loadAgents()
                viewModel.startLiveUpdates()  // b9bbe115: subscribe to /tickets/stream
            }
            .onDisappear {
                viewModel.stopLiveUpdates()
            }
            .sheet(isPresented: $viewModel.showCreateSheet) {
                CreateTicketSheet(viewModel: viewModel, agents: agents)
            }
            .sheet(item: selectedTicket) { ticket in
                TicketDetailSheet(ticket: ticket, viewModel: viewModel, agents: agents)
            }
            .sheet(isPresented: $showingIntegrityReview) {
                WorkControlIntegrityReviewSheet(
                    summary: viewModel.workControlIntegritySummary,
                    workControlExportResult: viewModel.workControlReviewExportResult,
                    workControlExportMessage: viewModel.workControlReviewExportMessage,
                    isExportingWorkControl: viewModel.isExportingWorkControlReview,
                    legacyExportResult: viewModel.legacyLinkageExportResult,
                    legacyExportMessage: viewModel.legacyLinkageExportMessage,
                    isExportingLegacy: viewModel.isExportingLegacyLinkage
                ) { ticketId in
                    showingIntegrityReview = false
                    if viewModel.ticket(withId: ticketId) != nil {
                        selectedTicketId = ticketId
                    }
                } onWorkControlExport: {
                    await viewModel.exportWorkControlIntegrityReview()
                } onLegacyExport: {
                    await viewModel.exportLegacyLinkageDryRun()
                }
            }
            .sheet(isPresented: $showingBackfillReview) {
                WorkControlBackfillReviewSheet(summary: viewModel.workControlBackfillSummary) { ticketId in
                    showingBackfillReview = false
                    if viewModel.ticket(withId: ticketId) != nil {
                        selectedTicketId = ticketId
                    }
                }
            }
            .sheet(isPresented: $showingBacklogReprocessReview) {
                BacklogReprocessReviewSheet(summary: viewModel.backlogReprocessDryRun) { ticketId in
                    showingBacklogReprocessReview = false
                    if viewModel.ticket(withId: ticketId) != nil {
                        selectedTicketId = ticketId
                    }
                } onRefresh: {
                    await viewModel.loadBacklogReprocessDryRun()
                }
            }
            .sheet(isPresented: $showingAgentRunReviewQueue) {
                AgentRunReviewQueueSheet(viewModel: viewModel) { ticketId in
                    showingAgentRunReviewQueue = false
                    if viewModel.ticket(withId: ticketId) != nil {
                        selectedTicketId = ticketId
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Status Filter Bar

    private var statusFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", status: nil)
                filterChip(label: "Open", status: .open)
                filterChip(label: "Claimed", status: .claimed)
                filterChip(label: "In Progress", status: .inProgress)
                filterChip(label: "Closed", status: .closed)
                filterChip(label: "Cancelled", status: .cancelled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppColors.backgroundSecondary)
    }

    private func filterChip(label: String, status: TicketStatus?) -> some View {
        let isSelected = viewModel.selectedStatus == status
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.selectedStatus = status
            }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : AppColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AppColors.accentElectric : AppColors.backgroundTertiary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var savedViewsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                savedViewChip(label: "Ops", view: nil, count: viewModel.tickets.count)
                ForEach(TicketSavedView.allCases, id: \.self) { view in
                    savedViewChip(label: view.label, view: view, count: viewModel.count(for: view))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(AppColors.backgroundSecondary)
    }

    private func savedViewChip(label: String, view: TicketSavedView?, count: Int) -> some View {
        let isSelected = viewModel.selectedSavedView == view
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.selectedSavedView = view
            }
        } label: {
            Text("\(label) \(count)")
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : AppColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AppColors.accentAgent : AppColors.backgroundTertiary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var liveStatusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.liveStatus.icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(viewModel.liveStatus.color)
            Text(viewModel.liveStatus.label)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
            Text(viewModel.liveStatusDetail)
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(AppColors.backgroundSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.liveStatus.label). \(viewModel.liveStatusDetail)")
    }

    @ViewBuilder
    private var groomingSummaryBar: some View {
        if let summary = viewModel.groomingSummary {
            let approvalAttentionCount = viewModel.count(for: .waitingApproval)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                summaryPill(label: "Review", value: summary.needsHumanCount, color: Color.orange)
                    summaryPill(label: "Keep", value: summary.keepCount, color: AppColors.accentSuccess)
                    summaryPill(label: "Test", value: summary.staleTestCount, color: AppColors.textTertiary)
                    if approvalAttentionCount > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.selectedSavedView = .waitingApproval
                                viewModel.selectedStatus = nil
                            }
                        } label: {
                            summaryPill(label: "Approval", value: approvalAttentionCount, color: AppColors.accentWarning)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show tickets waiting for human approval review")
                    }
                    if let flow = viewModel.ticketFlowReview?.counts {
                        if flow.dispatchable > 0 {
                            summaryPill(label: "Flow Ready", value: flow.dispatchable, color: AppColors.accentAgent)
                        }
                        if flow.noiseReview > 0 {
                            summaryPill(label: "Noise", value: flow.noiseReview, color: AppColors.accentDanger)
                        }
                        if let coral = flow.bySupportLane["coral-support-runtime"], coral > 0 {
                            summaryPill(label: "Coral", value: coral, color: AppColors.accentElectric)
                        }
                        if let reef = flow.bySupportLane["reef-support-runtime"], reef > 0 {
                            summaryPill(label: "Reef", value: reef, color: AppColors.accentAgent)
                        }
                    } else if viewModel.ticketFlowErrorMessage != nil {
                        summaryPill(label: "Flow Offline", value: 0, color: AppColors.accentDanger)
                    }
                    if let integrity = viewModel.workControlIntegritySummary, integrity.issues > 0 {
                        summaryPill(label: "Source Link", value: integrity.sourceLinkGapCount, color: AppColors.accentDanger)
                        summaryPill(label: "Triage Link", value: integrity.triageLinkGapCount, color: Color.orange)
                        if integrity.otherGapCount > 0 {
                            summaryPill(label: "Other Gaps", value: integrity.otherGapCount, color: AppColors.textTertiary)
                        }
                    }
                    if let backfill = viewModel.workControlBackfillSummary, backfill.needsBackfill > 0 {
                        summaryPill(label: "Fields", value: backfill.needsBackfill, color: AppColors.accentAgent)
                    }
                    if summary.duplicateCount > 0 {
                        summaryPill(label: "Dupes", value: summary.duplicateCount, color: AppColors.accentDanger)
                    }
                    if summary.supersededCount > 0 {
                        summaryPill(label: "Old", value: summary.supersededCount, color: AppColors.textTertiary)
                    }
                    if let reprocess = viewModel.backlogReprocessDryRun {
                        summaryPill(label: "Reprocess", value: reprocess.total, color: AppColors.accentElectric)
                    }
                    if !viewModel.agentRunReviewQueue.isEmpty {
                        summaryPill(label: "Run Review", value: viewModel.agentRunReviewQueue.count, color: AppColors.accentWarning)
                    }
                    Spacer(minLength: 0)
                    Button {
                        showingAgentRunReviewQueue = true
                        Task { await viewModel.loadAgentRunReviewQueue() }
                    } label: {
                        if viewModel.isLoadingAgentRunReviewQueue {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark.seal")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentWarning)
                    .disabled(viewModel.isLoadingAgentRunReviewQueue)
                    .accessibilityLabel("Review agent runs needing owner review")
                    if viewModel.workControlIntegritySummary?.issues ?? 0 > 0 {
                        Button {
                            showingIntegrityReview = true
                        } label: {
                            Image(systemName: "link.badge.plus")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(AppColors.accentDanger)
                        .accessibilityLabel("Review source and triage link gaps")
                    }
                    if viewModel.backlogReprocessDryRun != nil {
                        Button {
                            showingBacklogReprocessReview = true
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(AppColors.accentElectric)
                        .accessibilityLabel("Review backlog reprocess dry-run")
                    }
                    if viewModel.workControlBackfillSummary?.needsBackfill ?? 0 > 0 {
                        Button {
                            showingBackfillReview = true
                        } label: {
                            Image(systemName: "list.bullet.clipboard")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(AppColors.accentAgent)
                        .accessibilityLabel("Review work-control backfill candidates")
                    }
                    Button {
                        Task { await viewModel.postBacklogGroomingComments() }
                    } label: {
                        if viewModel.isPostingGroomingComments {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "text.badge.checkmark")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentElectric)
                    .disabled(viewModel.isPostingGroomingComments)
                    .accessibilityLabel("Write backlog grooming review comments")
                }
                    if let message = viewModel.groomingActionMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(2)
                    } else if let reprocess = viewModel.backlogReprocessDryRun {
                        let actions = reprocess.reviewActionCounts
                            .sorted { $0.value > $1.value }
                            .prefix(3)
                            .map { "\(displayLabel($0.key)): \($0.value)" }
                            .joined(separator: ", ")
                        Text("Reprocess dry-run is comments-first and non-mutating\(actions.isEmpty ? "." : ": \(actions).")")
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(2)
                    } else if let integrity = viewModel.workControlIntegritySummary, integrity.issues > 0 {
                        let topIssues = integrity.countsByField
                            .sorted { $0.value > $1.value }
                            .prefix(3)
                            .map { "\(displayLabel($0.key)): \($0.value)" }
                            .joined(separator: ", ")
                        Text("Source links missing on \(integrity.sourceLinkGapCount) tickets; triage links missing on \(integrity.triageLinkGapCount)\(topIssues.isEmpty ? "." : ". Top gaps: \(topIssues).")")
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(2)
                    } else if let backfill = viewModel.workControlBackfillSummary, backfill.needsBackfill > 0 {
                        let topMissing = backfill.countsByMissingField
                            .sorted { $0.value > $1.value }
                        .prefix(3)
                        .map { "\($0.key): \($0.value)" }
                        .joined(separator: ", ")
                    Text("Work-control backfill needed on \(backfill.needsBackfill) tickets\(topMissing.isEmpty ? "" : ": \(topMissing)").")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .background(AppColors.backgroundSecondary)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Backlog grooming: \(summary.needsHumanCount) need review, \(summary.keepCount) keep, \(summary.staleTestCount) test artifacts")
        } else if let message = viewModel.groomingErrorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(Color.orange)
                Text(message)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .background(AppColors.backgroundSecondary)
        }
    }

    private func summaryPill(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(value)")
                .font(.caption.bold())
                .foregroundColor(AppColors.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(AppColors.backgroundTertiary)
        .clipShape(Capsule())
    }

    private func displayLabel(_ rawValue: String) -> String {
        rawValue.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private struct AgentRunReviewQueueSheet: View {
        let viewModel: TicketsViewModel
        let onOpenTicket: (String) -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        HStack(spacing: 10) {
                            summaryMetric("Needs Review", value: viewModel.agentRunReviewQueue.count, color: AppColors.accentWarning)
                            summaryMetric("Tickets", value: ticketCount, color: AppColors.accentElectric)
                            summaryMetric("Failed", value: failedCount, color: AppColors.accentDanger)
                        }
                        .listRowBackground(AppColors.backgroundSecondary)
                    } footer: {
                        Text("ORCA terminal execution runs from /api/v1/agent-runs?review_required=true. Review decisions write back to the Agent Run record.")
                    }

                    Section {
                        Button {
                            Task { await viewModel.exportAgentRunReviewQueue() }
                        } label: {
                            HStack(spacing: 10) {
                                if viewModel.isExportingAgentRunReview {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "square.and.arrow.up.on.square")
                                        .foregroundColor(AppColors.accentElectric)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.isExportingAgentRunReview ? "Exporting review packet" : "Export review packet")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(AppColors.textPrimary)
                                    Text("Owner-review artifact for terminal worker runs.")
                                        .font(.caption2)
                                        .foregroundColor(AppColors.textTertiary)
                                }

                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isExportingAgentRunReview)

                        if let message = viewModel.agentRunReviewExportMessage {
                            Label(message, systemImage: viewModel.agentRunReviewExportResult == nil ? "exclamationmark.triangle" : "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(viewModel.agentRunReviewExportResult == nil ? Color.orange : AppColors.accentSuccess)
                        }

                        if let path = viewModel.agentRunReviewExportResult?.path, !path.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Path")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(AppColors.textTertiary)
                                Text(path)
                                    .font(.caption.monospaced())
                                    .foregroundColor(AppColors.textSecondary)
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                            }
                        }
                    } footer: {
                        Text("Export only; no Agent Run review decision is recorded.")
                    }

                    if viewModel.isLoadingAgentRunReviewQueue && viewModel.agentRunReviewQueue.isEmpty {
                        Section {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading review queue")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            .listRowBackground(AppColors.backgroundSecondary)
                        }
                    } else if let error = viewModel.agentRunReviewQueueErrorMessage, viewModel.agentRunReviewQueue.isEmpty {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(AppColors.accentWarning)
                                .listRowBackground(AppColors.backgroundSecondary)
                        }
                    } else if viewModel.agentRunReviewQueue.isEmpty {
                        Section {
                            Text("No agent runs currently need owner review.")
                                .font(.caption)
                                .foregroundColor(AppColors.textTertiary)
                                .listRowBackground(AppColors.backgroundSecondary)
                        }
                    } else {
                        Section("Runs") {
                            ForEach(viewModel.agentRunReviewQueue) { run in
                                reviewRunRow(run)
                                    .listRowBackground(AppColors.backgroundSecondary)
                            }
                        }

                        if let error = viewModel.agentRunReviewQueueErrorMessage {
                            Section {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundColor(AppColors.accentWarning)
                                    .listRowBackground(AppColors.backgroundSecondary)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.backgroundPrimary)
                .navigationTitle("Run Review")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await viewModel.loadAgentRunReviewQueue() }
                        } label: {
                            if viewModel.isLoadingAgentRunReviewQueue {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(viewModel.isLoadingAgentRunReviewQueue)
                        .accessibilityLabel("Refresh agent run review queue")
                    }
                }
                .task {
                    if viewModel.agentRunReviewQueue.isEmpty {
                        await viewModel.loadAgentRunReviewQueue()
                    }
                }
            }
        }

        private var ticketCount: Int {
            Set(viewModel.agentRunReviewQueue.map(\.ticketId)).count
        }

        private var failedCount: Int {
            viewModel.agentRunReviewQueue.filter { $0.status == .failed || $0.status == .blocked }.count
        }

        private func summaryMetric(_ label: String, value: Int, color: Color) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(value)")
                    .font(.headline.weight(.bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func reviewRunRow(_ run: AgentRun) -> some View {
            let ticket = viewModel.ticket(withId: run.ticketId)
            let owner = ticket?.assigneeAgentName ?? ticket?.assigneeAgentId ?? run.agentId ?? run.caller ?? "Unassigned"
            let worker = run.workerLane ?? run.lane ?? "unknown"
            let review = run.reviewStatus?.replacingOccurrences(of: "_", with: " ") ?? "review required"

            return VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: run.status.icon)
                        .font(.caption.weight(.bold))
                        .foregroundColor(run.status.color)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ticket?.title ?? run.ticketId)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(2)

                        Text("Run \(shortRef(run.id)) / Ticket \(shortRef(run.ticketId))")
                            .font(.caption2.monospaced())
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(run.updatedAt.relativeTimeString)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)
                        Text(run.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                runMetaPillCloud([
                    "owner: \(owner)",
                    "worker: \(worker)",
                    "status: \(run.status.label)",
                    "review: \(review)",
                    run.backend,
                    run.model
                ])

                if let summary = outcomeSummary(for: run) {
                    Text(summary.text)
                        .font(.caption)
                        .foregroundColor(summary.color)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if ticket != nil {
                        Button {
                            onOpenTicket(run.ticketId)
                        } label: {
                            Label("Ticket", systemImage: "arrow.right.circle")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(AppColors.accentElectric)
                    }

                    if let ticket {
                        Button {
                            Task {
                                await viewModel.reviewAgentRun(run, ticket: ticket, reviewStatus: "accepted")
                                await viewModel.loadAgentRunReviewQueue()
                            }
                        } label: {
                            Label("Accept", systemImage: "checkmark.seal")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(AppColors.accentSuccess)

                        Button {
                            Task {
                                await viewModel.reviewAgentRun(run, ticket: ticket, reviewStatus: "needs_changes")
                                await viewModel.loadAgentRunReviewQueue()
                            }
                        } label: {
                            Label("Needs changes", systemImage: "arrow.uturn.backward.circle")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(AppColors.accentWarning)
                    }
                }
            }
        }

        private func outcomeSummary(for run: AgentRun) -> (text: String, color: Color)? {
            if let error = clean(run.error) {
                return ("Error: \(error)", AppColors.accentDanger)
            }
            if let outcome = clean(run.outcome) {
                return ("Outcome: \(outcome)", AppColors.textPrimary)
            }
            if let input = clean(run.inputSummary) {
                return ("Input: \(input)", AppColors.textSecondary)
            }
            if let evidence = clean(run.evidence) {
                return ("Evidence: \(evidence)", AppColors.textSecondary)
            }
            return nil
        }

        private func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        private func shortRef(_ value: String) -> String {
            if value.count <= 10 { return value }
            return "\(value.prefix(8))..."
        }

        private func runMetaPillCloud(_ values: [String?]) -> some View {
            let cleaned = values
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(cleaned, id: \.self) { value in
                    Text(value)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private struct WorkControlIntegrityReviewSheet: View {
        let summary: WorkControlIntegritySummary?
        let workControlExportResult: LegacyLinkageExportResult?
        let workControlExportMessage: String?
        let isExportingWorkControl: Bool
        let legacyExportResult: LegacyLinkageExportResult?
        let legacyExportMessage: String?
        let isExportingLegacy: Bool
        let onOpen: (String) -> Void
        let onWorkControlExport: () async -> Void
        let onLegacyExport: () async -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    workControlExportSection
                    legacyLinkageExportSection

                    if let summary {
                        Section {
                            HStack(spacing: 10) {
                                summaryMetric("Source Link", value: summary.sourceLinkGapCount, color: AppColors.accentDanger)
                                summaryMetric("Triage Link", value: summary.triageLinkGapCount, color: Color.orange)
                                summaryMetric("Clean", value: summary.clean, color: AppColors.accentSuccess)
                            }
                            .listRowBackground(AppColors.backgroundSecondary)
                        } footer: {
                            Text("Read-only integrity review from WorkControlIntegritySummary. Source link means a chat or thread source is missing; triage link means Merman triage id or trace is missing.")
                        }

                        Section("Link Gaps") {
                            integrityCountRow("Source chat/thread link", value: summary.sourceLinkGapCount, color: AppColors.accentDanger)
                            integrityCountRow("Triage id or trace", value: summary.triageLinkGapCount, color: Color.orange)
                            if summary.otherGapCount > 0 {
                                integrityCountRow("Other work-control fields", value: summary.otherGapCount, color: AppColors.textTertiary)
                            }
                        }

                        if !summary.countsByField.isEmpty {
                            Section("Missing Fields") {
                                ForEach(summary.countsByField.sorted(by: { $0.value > $1.value }), id: \.key) { field, count in
                                    integrityCountRow(displayLabel(field), value: count, color: color(for: field))
                                }
                            }
                        }

                        Section("Tickets") {
                            ForEach(summary.items) { item in
                                Button {
                                    onOpen(item.ticketId)
                                } label: {
                                    integrityItemRow(item)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(AppColors.backgroundSecondary)
                            }
                        }
                    } else {
                        Text("Work-control integrity summary is unavailable.")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.backgroundPrimary)
                .navigationTitle("Link Integrity")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await onWorkControlExport() }
                        } label: {
                            if isExportingWorkControl {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up.on.square")
                            }
                        }
                        .disabled(isExportingWorkControl)
                        .accessibilityLabel("Export work-control review")
                    }
                }
            }
        }

        private var workControlExportSection: some View {
            exportSection(
                title: "Work-Control Export",
                buttonTitle: isExportingWorkControl ? "Exporting review packet" : "Export review packet",
                detail: "Grouped approval, scope, execution-policy, and lineage gaps for owner review.",
                result: workControlExportResult,
                message: workControlExportMessage,
                isExporting: isExportingWorkControl,
                action: onWorkControlExport
            )
        }

        private var legacyLinkageExportSection: some View {
            exportSection(
                title: "Legacy Linkage Export",
                buttonTitle: isExportingLegacy ? "Exporting dry-run" : "Export dry-run",
                detail: "Legacy source and triage linkage artifact for ORCA backfill review.",
                result: legacyExportResult,
                message: legacyExportMessage,
                isExporting: isExportingLegacy,
                action: onLegacyExport
            )
        }

        private func exportSection(
            title: String,
            buttonTitle: String,
            detail: String,
            result: LegacyLinkageExportResult?,
            message: String?,
            isExporting: Bool,
            action: @escaping () async -> Void
        ) -> some View {
            Section {
                Button {
                    Task { await action() }
                } label: {
                    HStack(spacing: 10) {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up.on.square")
                                .foregroundColor(AppColors.accentElectric)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(buttonTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textPrimary)
                            Text(detail)
                                .font(.caption2)
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isExporting)

                if let message {
                    Label(message, systemImage: result == nil ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(result == nil ? Color.orange : AppColors.accentSuccess)
                }

                if let path = result?.path, !path.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Path")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.textTertiary)
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundColor(AppColors.textSecondary)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                }

                if let counts = result?.counts, !counts.isEmpty {
                    ForEach(counts.sorted(by: { $0.value > $1.value }), id: \.key) { key, count in
                        integrityCountRow(displayLabel(key), value: count, color: AppColors.accentElectric)
                    }
                }
            } header: {
                Text(title)
            } footer: {
                Text("Dry-run export only; no tickets are mutated from this action.")
            }
        }

        private func summaryMetric(_ label: String, value: Int, color: Color) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(value)")
                    .font(.headline.weight(.bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func integrityCountRow(_ label: String, value: Int, color: Color) -> some View {
            HStack {
                Label(label, systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text("\(value)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(color)
            }
        }

        private func integrityItemRow(_ item: WorkControlIntegrityItem) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.hasSourceLinkGap ? "link.badge.plus" : "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(item.hasSourceLinkGap ? AppColors.accentDanger : Color.orange)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(2)

                        if let status = item.status {
                            Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption2)
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }

                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    if item.hasSourceLinkGap {
                        chip("Missing source link", color: AppColors.accentDanger)
                    }
                    if item.hasTriageLinkGap {
                        chip("Missing triage link", color: Color.orange)
                    }
                    ForEach(item.fields.filter { $0 != "source_chat_or_thread_link" && $0 != "triage_id" && $0 != "triage_trace_id" }.prefix(4), id: \.self) { field in
                        chip(displayLabel(field), color: AppColors.textTertiary)
                    }
                }

                if let note = item.notes.first, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }

        private func chip(_ text: String, color: Color) -> some View {
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundColor(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(AppColors.backgroundTertiary)
                .clipShape(Capsule())
        }

        private func color(for field: String) -> Color {
            if field.contains("source") { return AppColors.accentDanger }
            if field.contains("triage") { return Color.orange }
            return AppColors.textTertiary
        }

        private func displayLabel(_ rawValue: String) -> String {
            rawValue.replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    private struct BacklogReprocessReviewSheet: View {
        let summary: BacklogGroomingSummary?
        let onOpen: (String) -> Void
        let onRefresh: () async -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    if let summary {
                        Section {
                            HStack(spacing: 10) {
                                summaryMetric("Tickets", value: summary.total, color: AppColors.accentElectric)
                                summaryMetric("Review", value: summary.reviewActionCounts.values.reduce(0, +), color: Color.orange)
                                summaryMetric("Commented", value: summary.items.filter { ($0.existingCommentCount ?? 0) > 0 }.count, color: AppColors.accentSuccess)
                            }
                            .listRowBackground(AppColors.backgroundSecondary)
                        } footer: {
                            Text("Dry-run only. This surface previews owner/lane recommendations and comment evidence without mutating tickets.")
                        }

                        countSection("Classification", counts: summary.counts)
                        countSection("Review Action", counts: summary.reviewActionCounts)
                        countSection("Suggested Owner", counts: summary.suggestedOwnerCounts)

                        Section("Tickets") {
                            ForEach(summary.items.prefix(20)) { item in
                                Button {
                                    onOpen(item.ticketId)
                                } label: {
                                    reprocessItemRow(item)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(AppColors.backgroundSecondary)
                            }
                        }
                    } else {
                        Text("Backlog reprocess dry-run is unavailable.")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.backgroundPrimary)
                .navigationTitle("Reprocess Dry-Run")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await onRefresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh backlog reprocess dry-run")
                    }
                }
            }
        }

        private func countSection(_ title: String, counts: [String: Int]) -> some View {
            Section(title) {
                if counts.isEmpty {
                    Text("No counts returned.")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                } else {
                    ForEach(counts.sorted(by: { $0.value > $1.value }), id: \.key) { key, count in
                        HStack {
                            Text(displayLabel(key))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }
            }
        }

        private func summaryMetric(_ label: String, value: Int, color: Color) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(value)")
                    .font(.headline.weight(.bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func reprocessItemRow(_ item: BacklogGroomingItem) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: item))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(color(for: item))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(2)

                        Text("\(displayLabel(item.classification)) / \(displayLabel(item.reviewAction ?? "review")) / \(displayLabel(item.confidence ?? "medium")) confidence")
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }

                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    if let owner = item.suggestedOwner ?? item.assignmentSuggestion?.owner {
                        chip("Owner \(displayLabel(owner))", color: AppColors.accentAgent)
                    }
                    if let lane = item.suggestedWorkerLane ?? item.assignmentSuggestion?.workerLane {
                        chip(displayLabel(lane), color: AppColors.accentElectric)
                    }
                    ForEach((item.signals ?? []).prefix(4), id: \.self) { signal in
                        chip(displayLabel(signal), color: AppColors.textTertiary)
                    }
                }

                if let preview = item.reprocessPreview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(3)
                }

                if let latest = item.latestCommentPreview, !latest.isEmpty {
                    Label(latest, systemImage: "quote.bubble")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }

        private func chip(_ text: String, color: Color) -> some View {
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundColor(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(AppColors.backgroundTertiary)
                .clipShape(Capsule())
        }

        private func icon(for item: BacklogGroomingItem) -> String {
            switch item.reviewAction {
            case "needs_human_review", "write_review_comment":
                return "text.bubble.badge.clock"
            case "skip_test_artifact", "skip_duplicate", "skip_superseded":
                return "nosign"
            default:
                return "doc.text.magnifyingglass"
            }
        }

        private func color(for item: BacklogGroomingItem) -> Color {
            switch item.classification {
            case "needs-human":
                return Color.orange
            case "keep":
                return AppColors.accentSuccess
            case "duplicate":
                return AppColors.accentDanger
            default:
                return AppColors.accentElectric
            }
        }

        private func displayLabel(_ rawValue: String) -> String {
            rawValue.replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    private struct WorkControlBackfillReviewSheet: View {
        let summary: WorkControlBackfillSummary?
        let onOpen: (String) -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    if let summary {
                        Section {
                            HStack(spacing: 10) {
                                summaryMetric("Needs", value: summary.needsBackfill, color: AppColors.accentAgent)
                                summaryMetric("Clean", value: summary.clean, color: AppColors.accentSuccess)
                                summaryMetric("Total", value: summary.total, color: AppColors.textTertiary)
                            }
                            .listRowBackground(AppColors.backgroundSecondary)
                        }

                        if !summary.countsByMissingField.isEmpty {
                            Section("Top Missing Fields") {
                                ForEach(summary.countsByMissingField.sorted(by: { $0.value > $1.value }), id: \.key) { field, count in
                                    HStack {
                                        Text(field.replacingOccurrences(of: "_", with: " "))
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(AppColors.textPrimary)
                                        Spacer()
                                        Text("\(count)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(AppColors.textTertiary)
                                    }
                                }
                            }
                        }

                        Section("Tickets") {
                            ForEach(summary.items) { item in
                                Button {
                                    onOpen(item.ticketId)
                                } label: {
                                    backfillItemRow(item)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(AppColors.backgroundSecondary)
                            }
                        }
                    } else {
                        Text("Work-control backfill summary is unavailable.")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.backgroundPrimary)
                .navigationTitle("Field Backfill")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }

        private func summaryMetric(_ label: String, value: Int, color: Color) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(value)")
                    .font(.headline.weight(.bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func backfillItemRow(_ item: WorkControlBackfillItem) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.classification == "needs_human" ? "person.crop.circle.badge.exclamationmark" : "doc.badge.gearshape")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(item.classification == "needs_human" ? Color.orange : AppColors.accentAgent)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(2)

                        Text("\(item.status.replacingOccurrences(of: "_", with: " ")) / \(item.classification.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(item.missingFields.prefix(6), id: \.self) { field in
                        Text(field.replacingOccurrences(of: "_", with: " "))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(AppColors.backgroundTertiary)
                            .clipShape(Capsule())
                    }
                }

                if let note = item.notes.first, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Ticket List (POD-4: tree view)

    private var ticketList: some View {
        List {
            ForEach(viewModel.filteredRootTickets) { ticket in
                TicketTreeNode(
                    ticket: ticket,
                    viewModel: viewModel,
                    depth: 0,
                    onStatusChange: { changedTicket, newStatus in
                        Task { await viewModel.updateStatus(ticketId: changedTicket.id, status: newStatus) }
                    },
                    onTap: { tappedTicket in
                        selectedTicketId = tappedTicket.id
                    },
                    subtasksProvider: { viewModel.filteredSubtasks(of: $0) }
                )
                .listRowBackground(AppColors.backgroundSecondary)
                .listRowSeparatorTint(AppColors.border)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
        .listStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 92)
        }
        .refreshable { await viewModel.load() }
    }

    // MARK: - Loading / Empty

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(AppColors.accentElectric)
            Text("Loading tickets...")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "ticket")
                .font(.system(size: 44))
                .foregroundColor(AppColors.textTertiary)
            Text(viewModel.emptyStateTitle)
                .font(.headline)
                .foregroundColor(AppColors.textSecondary)
            Text(viewModel.emptyStateSubtitle)
                .font(.subheadline)
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.showCreateSheet = true
            } label: {
                Text("Create Ticket")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(AppColors.accentElectric)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding()
    }

    // MARK: - Load Agents

    private func loadAgents() async {
        do {
            let response: PaginatedResponse<AgentDTO> = try await APIClient.shared.get(path: "/api/v1/agents")
            agents = response.items
                .filter { AgentRosterPolicy.isActiveOrSupport($0.name) }
                .sorted {
                    AgentRosterPolicy.sortKey(for: $0.name) < AgentRosterPolicy.sortKey(for: $1.name)
                }
        } catch {}
    }
}

// MARK: - Ticket Row

struct TicketRowView: View {
    let ticket: Ticket
    let viewModel: TicketsViewModel
    let onStatusChange: (TicketStatus) -> Void

    var body: some View {
        let signal = viewModel.ticketListSignal(for: ticket)
        let summary = viewModel.evidenceSummary(for: ticket)

        VStack(alignment: .leading, spacing: 8) {
            // Top row: priority + title
            HStack(alignment: .top, spacing: 8) {
                // Priority indicator — tap to edit per Aloha 2026-05-23 (Tony's ask, ticket 46ca818d)
                Menu {
                    ForEach([TicketPriority.urgent, .high, .medium, .low], id: \.self) { level in
                        Button {
                            Task { await viewModel.updatePriority(ticketId: ticket.id, priority: level) }
                        } label: {
                            HStack {
                                Image(systemName: level.icon)
                                Text(level.label)
                                if ticket.priority == level {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: ticket.priority.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ticket.priority.color)
                        .frame(width: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Priority: \(ticket.priority.label). Tap to change.")

                // short_id chip — mirrors Project card chip per Tony 2026-05-23
                Text(String(ticket.id.replacingOccurrences(of: "-", with: "").prefix(8)))
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
                    .accessibilityLabel("Ticket ID \(ticket.id.prefix(8))")

                Text(ticket.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)

                Spacer()

                // Status badge
                statusBadge
            }

            operationalBadges
            operationalDebtStrip

            executionStrip(signal: signal, summary: summary)

            if let latest = viewModel.latestTicketActivity(for: ticket) {
                Label(latest, systemImage: "text.bubble")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }

            // Bottom row: assignee + date + type
            HStack(spacing: 12) {
                if let agentName = ticket.assigneeAgentName {
                    Label(agentName.capitalized, systemImage: "cpu")
                        .font(.caption)
                        .foregroundColor(AppColors.accentAgent)
                } else if ticket.assigneeAgentId != nil {
                    Label("Agent", systemImage: "cpu")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }

                if let type = ticket.ticketType {
                    Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                Text(ticket.createdAt.relativeTimeString)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(TicketStatus.allCases, id: \.self) { status in
                if status != ticket.status && !status.isTerminal {
                    Button {
                        onStatusChange(status)
                    } label: {
                        Label("Mark \(status.label)", systemImage: status.icon)
                    }
                }
            }
        }
    }

    private func executionStrip(signal: TicketListSignal, summary: TicketEvidenceSummary) -> some View {
        HStack(spacing: 7) {
            Label(signal.label, systemImage: signal.icon)
                .font(.caption2.weight(.bold))
                .foregroundColor(signal.color)
                .lineLimit(1)

            Text(signal.detail)
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if summary.runCount > 0 {
                miniMetric(icon: "bolt.badge.clock", value: "\(summary.runCount)", color: summary.failedRunCount > 0 ? AppColors.accentDanger : AppColors.accentAgent)
            }
            if summary.commentCount > 0 {
                miniMetric(icon: "quote.bubble", value: "\(summary.commentCount)", color: AppColors.accentElectric)
            }
            if summary.approvalCount > 0 {
                miniMetric(icon: "person.crop.circle.badge.exclamationmark", value: "\(summary.approvalCount)", color: Color.orange)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(signal.color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func miniMetric(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(value)
        }
        .font(.caption2.weight(.bold))
        .foregroundColor(color)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: ticket.status.icon)
                .font(.system(size: 9))
            Text(ticket.status.label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(ticket.status.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(ticket.status.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var operationalBadges: some View {
        let badges = badgeItems
        return HStack(spacing: 6) {
            ForEach(badges, id: \.label) { badge in
                Label(badge.label, systemImage: badge.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(badge.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(badge.color.opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var operationalDebtStrip: some View {
        let debts = viewModel.operationalDebts(for: ticket)
        if !debts.isEmpty {
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(debts.first?.color ?? AppColors.accentWarning)
                Text("Ops debt")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(debts.first?.color ?? AppColors.accentWarning)
                ForEach(Array(debts.prefix(3))) { debt in
                    Text(debt.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(debt.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(debt.color.opacity(0.12))
                        .clipShape(Capsule())
                }
                if debts.count > 3 {
                    Text("+\(debts.count - 3)")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((debts.first?.color ?? AppColors.accentWarning).opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke((debts.first?.color ?? AppColors.accentWarning).opacity(0.18), lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Operational debt: \(debts.map { $0.label }.joined(separator: ", "))")
        }
    }

    private var badgeItems: [(label: String, icon: String, color: Color)] {
        let haystack = "\(ticket.title) \(ticket.description ?? "") \(ticket.ticketType ?? "") \(ticket.computeTag ?? "")".lowercased()
        let grooming = viewModel.groomingItem(for: ticket.id)
        let summary = viewModel.evidenceSummary(for: ticket)
        var items: [(String, String, Color)] = []
        if ticket.approvalState == "waiting_for_human"
            || summary.latestRunStatus == .waitingForHuman
            || summary.blockers.contains("waiting_for_human") {
            items.append(("Waiting", "person.crop.circle.badge.exclamationmark", Color.orange))
        }
        if let latestRunStatus = summary.latestRunStatus, [.queued, .running, .retrying].contains(latestRunStatus) {
            items.append(("Live Run", "dot.radiowaves.left.and.right", AppColors.accentAgent))
        }
        if routePacketBool(summary.latestRoutePacket, keys: ["fallback_used", "fallback", "used_fallback"]) == true {
            items.append(("Fallback", "arrow.triangle.2.circlepath", AppColors.accentWarning))
        }
        if grooming?.classification == "needs-human"
            || grooming?.suggestedApprovalState == "waiting_for_human"
            || ticket.priority == .urgent
            || ticket.priority == .high
            || haystack.contains("approval")
            || haystack.contains("needs human") {
            items.append(("Needs Human", "person.crop.circle.badge.exclamationmark", Color.orange))
        }
        if grooming?.classification == "keep"
            && grooming?.suggestedWorkerLane == "mermaid"
            && grooming?.suggestedApprovalState != "waiting_for_human" {
            items.append(("Dispatchable", "paperplane.fill", AppColors.accentAgent))
        }
        if viewModel.needsOwnerReview(for: ticket) {
            items.append(("Review Mermaid", "checkmark.seal", Color.orange))
        }
        if ticket.triageId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || ticket.triageTraceId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            items.append(("Merman", "arrow.triangle.branch", AppColors.accentElectric))
        }
        if ticket.chatThreadId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            items.append(("Chat", "bubble.left.and.bubble.right", AppColors.accentSuccess))
        }
        if (ticket.updatedAt.timeIntervalSinceNow < -72 * 60 * 60 || grooming?.healthFlags?.contains("health_review") == true)
            && ticket.status != .closed
            && ticket.status != .cancelled {
            items.append(("Stale", "clock.badge.exclamationmark", AppColors.accentWarning))
        }
        if haystack.contains("chief")
            || haystack.contains("fund")
            || haystack.contains("trading")
            || haystack.contains("p&l")
            || grooming?.suggestedWorkerLane == "protected-chief-review" {
            items.append(("Chief/Fund", "lock.shield", AppColors.accentDanger))
        }
        if haystack.contains("pod") && (ticket.ticketType == "bug" || haystack.contains("bug") || haystack.contains("broken") || haystack.contains("not working")) {
            items.append(("Pod Bug", "ladybug.fill", AppColors.accentElectric))
        }
        return Array(items.prefix(3))
    }

    private func routePacketBool(_ packet: [String: AgentRunJSONValue]?, keys: [String]) -> Bool? {
        guard let packet else { return nil }
        for key in keys {
            guard let rawValue = packet[key] else { continue }
            switch rawValue {
            case .bool(let value):
                return value
            case .string(let value):
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "yes", "1"].contains(normalized) { return true }
                if ["false", "no", "0"].contains(normalized) { return false }
            case .int(let value):
                return value != 0
            default:
                continue
            }
        }
        return nil
    }
}

// MARK: - Ticket Tree Node (POD-4: subtask hierarchy)

struct TicketTreeNode: View {
    let ticket: Ticket
    let viewModel: TicketsViewModel
    let depth: Int
    let onStatusChange: (Ticket, TicketStatus) -> Void
    let onTap: (Ticket) -> Void
    let subtasksProvider: (Ticket) -> [Ticket]

    @State private var expanded = false

    var body: some View {
        let children = subtasksProvider(ticket)
        let hasChildren = !children.isEmpty

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Indent
                if depth > 0 {
                    Text("  ")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }

                // Expand/collapse chevron
                if hasChildren {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            expanded.toggle()
                        }
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }

                TicketRowView(ticket: ticket, viewModel: viewModel) { newStatus in
                    onStatusChange(ticket, newStatus)
                }
                    .onTapGesture {
                        onTap(ticket)
                    }
            }
            .background(AppColors.backgroundSecondary)

            // Children (POD-4: lessons-learned visible when expanded)
            if expanded {
                if let lessons = ticket.lessonsLearned, !lessons.isEmpty {
                    HStack(spacing: 8) {
                        if depth > 0 { Text("  ").font(.caption) }
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                            .foregroundColor(Color.yellow)
                        Text(lessons)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.leading, CGFloat(depth) * 16 + 24)
                    .padding(.vertical, 4)
                    .background(AppColors.backgroundTertiary.opacity(0.5))
                }

                ForEach(children) { child in
                    TicketTreeNode(
                        ticket: child,
                        viewModel: viewModel,
                        depth: depth + 1,
                        onStatusChange: onStatusChange,
                        onTap: onTap,
                        subtasksProvider: subtasksProvider
                    )
                }
            }
        }
    }
}

// MARK: - Ticket Row View (updated to support onStatusChange closure)

struct CreateTicketSheet: View {
    @Bindable var viewModel: TicketsViewModel
    let agents: [AgentDTO]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Triage Intake") {
                    TextField("Paste rough request for compute triage", text: $viewModel.roughIntake, axis: .vertical)
                        .lineLimit(3...8)
                        .foregroundColor(AppColors.textPrimary)

                    Button {
                        Task { await viewModel.previewDirection(agents: agents) }
                    } label: {
                        HStack {
                            Image(systemName: "signpost.right")
                            Text(viewModel.isPreviewingDirection ? "Asking ORCA..." : "Ask ORCA Where This Goes")
                            Spacer()
                            if viewModel.isPreviewingDirection {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(
                        viewModel.isPreviewingDirection ||
                        [viewModel.roughIntake, viewModel.newTitle, viewModel.newDescription]
                            .joined()
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )

                    Button {
                        Task { await viewModel.draftTicketFromIntake(agents: agents) }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(viewModel.isDrafting ? "Drafting..." : "Draft with Compute")
                            Spacer()
                            if viewModel.isDrafting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.roughIntake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isDrafting)

                    if let message = viewModel.draftMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    if let message = viewModel.directionPreviewMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    if let preview = viewModel.directionPreview {
                        DirectionPreviewCard(preview: preview)
                    }
                }

                Section("Details") {
                    TextField("Title", text: $viewModel.newTitle)
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Description (optional)", text: $viewModel.newDescription, axis: .vertical)
                        .lineLimit(3...6)
                        .foregroundColor(AppColors.textPrimary)
                }

                Section("Acceptance") {
                    TextField("Acceptance criteria", text: $viewModel.newAcceptanceCriteria, axis: .vertical)
                        .lineLimit(3...8)
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Done means", text: $viewModel.newDoneMeans, axis: .vertical)
                        .lineLimit(2...5)
                        .foregroundColor(AppColors.textPrimary)
                }

                Section("Priority") {
                    Picker("Priority", selection: $viewModel.newPriority) {
                        ForEach(TicketPriority.allCases, id: \.self) { p in
                            Label(p.label, systemImage: p.icon)
                                .tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Assign to Agent") {
                    Picker("Agent", selection: $viewModel.newAssigneeAgentId) {
                        Text("Unassigned").tag("")
                        ForEach(agents) { agent in
                            Text(agent.name.prefix(1).uppercased() + agent.name.dropFirst())
                                .tag(agent.id)
                        }
                    }
                }

                Section("Routing") {
                    Picker("Type", selection: $viewModel.newTicketType) {
                        Text("Support").tag("support")
                        Text("Feature").tag("feature")
                        Text("Bug").tag("bug")
                        Text("Incident").tag("incident")
                    }

                    TextField("Tags", text: $viewModel.newTags)
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Compute Tag", text: $viewModel.newComputeTag)
                        .textInputAutocapitalization(.never)
                        .foregroundColor(AppColors.textPrimary)
                }

                Section("Work Control") {
                    TextField("Worker lane", text: $viewModel.newWorkerLane)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Tool policy", text: $viewModel.newToolPolicy)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Approval state", text: $viewModel.newApprovalState)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Approval gate", text: $viewModel.newApprovalGate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Autonomy level", text: $viewModel.newAutonomyLevel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(AppColors.textPrimary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("New Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await viewModel.createTicket() }
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(viewModel.newTitle.isEmpty ? AppColors.textTertiary : AppColors.accentElectric)
                    .disabled(viewModel.newTitle.isEmpty || viewModel.isCreating)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct DirectionPreviewCard: View {
    let preview: TicketDirectionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(preview.intentType.replacingOccurrences(of: "_", with: " "), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)
                Spacer()
                Text(preview.riskLevel.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(preview.needsApproval ? AppColors.accentWarning : AppColors.textTertiary)
            }

            HStack(spacing: 6) {
                DirectionChip(icon: "person.crop.circle", text: preview.ownerDisplay)
                DirectionChip(icon: "cpu", text: preview.suggestedComputeRoute)
                if let worker = preview.suggestedWorker, !worker.isEmpty {
                    DirectionChip(icon: "hammer", text: worker)
                }
            }

            Text(preview.reason)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let approval = preview.approvalGate, !approval.isEmpty {
                Label(approval, systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(AppColors.accentWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }
}

private struct DirectionChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }
}
// MARK: - Ticket Detail Sheet

struct TicketDetailSheet: View {
    let initialTicket: Ticket
    @Bindable var viewModel: TicketsViewModel
    let agents: [AgentDTO]
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var editedTitle: String
    @State private var editedDescription: String
    @State private var editedStatus: TicketStatus
    @State private var editedPriority: TicketPriority
    @State private var editedAcceptanceCriteria: String
    @State private var editedDesiredOutcome: String
    @State private var editedApprovalState: String
    @State private var editedAutonomyLevel: String
    @State private var editedWorkerLane: String
    @State private var editedToolPolicy: String
    @State private var editedLessonsLearned: String
    @State private var editedResolutionNotes: String
    @State private var lifecycleAgentId: String
    @State private var showingStatusPicker = false
    @State private var pendingAction: PendingTicketAction?
    @State private var evidenceLens: TicketEvidenceLens = .timeline
    @State private var timelineFilter: TicketTimelineFilter = .all
    @State private var sharedNoteText = ""
    @State private var isPostingSharedNote = false
    @State private var sharedNoteStatus: String?
    @State private var orcaNoteTitle = ""
    @State private var orcaNoteBody = ""
    @State private var orcaNoteType = "note"
    @State private var isPostingOrcaNote = false
    @State private var orcaNoteStatus: String?

    private var ticket: Ticket {
        viewModel.ticket(withId: initialTicket.id) ?? initialTicket
    }

    init(ticket: Ticket, viewModel: TicketsViewModel, agents: [AgentDTO]) {
        self.initialTicket = ticket
        self.viewModel = viewModel
        self.agents = agents
        _editedTitle = State(initialValue: ticket.title)
        _editedDescription = State(initialValue: ticket.description ?? "")
        _editedStatus = State(initialValue: ticket.status)
        _editedPriority = State(initialValue: ticket.priority)
        _editedAcceptanceCriteria = State(initialValue: (ticket.acceptanceCriteria ?? []).joined(separator: "\n"))
        _editedDesiredOutcome = State(initialValue: ticket.desiredOutcome ?? "")
        _editedApprovalState = State(initialValue: ticket.approvalState ?? "not_required")
        _editedAutonomyLevel = State(initialValue: ticket.autonomyLevel ?? "draft_only")
        _editedWorkerLane = State(initialValue: ticket.workerLane ?? SchoolhouseTicketDispatchService.workerLane(for: ticket))
        _editedToolPolicy = State(initialValue: ticket.toolPolicy ?? SchoolhouseTicketDispatchService.toolPolicy(for: ticket))
        _editedLessonsLearned = State(initialValue: ticket.lessonsLearned ?? "")
        _editedResolutionNotes = State(initialValue: ticket.resolutionNotes ?? "")
        _lifecycleAgentId = State(initialValue: ticket.assigneeAgentId ?? Self.defaultAgentId(from: agents))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Ticket title", text: $editedTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                }

                Section("Status & Priority") {
                    Button {
                        showingStatusPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: editedStatus.icon)
                                .font(.system(size: 12))
                            Text(editedStatus.label)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .foregroundColor(editedStatus.color)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(TicketPriority.allCases, id: \.self) { priority in
                            Button {
                                editedPriority = priority
                            } label: {
                                HStack {
                                    Image(systemName: priority.icon)
                                        .foregroundColor(priority.color)
                                    Text(priority.label)
                                    if editedPriority == priority {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: editedPriority.icon)
                                .font(.system(size: 12))
                                .foregroundColor(editedPriority.color)
                            Text(editedPriority.label)
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    workOrderSection
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    evidenceSnapshotSection
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    operationalDebtSection
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    evidenceLinksSection
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    currentRunSection
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    executionReadinessSection
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    quickActionsSection
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    workSpineSection
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("Shared Note") {
                    TextField("Add a note for Maui and everyone on this ticket", text: $sharedNoteText, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(3...8)

                    Button {
                        Task { await postSharedNote() }
                    } label: {
                        HStack {
                            Label(isPostingSharedNote ? "Adding Note" : "Add Note", systemImage: "text.bubble.fill")
                            Spacer()
                            if isPostingSharedNote {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                    }
                    .disabled(sharedNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPostingSharedNote)

                    if let sharedNoteStatus {
                        Text(sharedNoteStatus)
                            .font(.caption)
                            .foregroundColor(sharedNoteStatus.localizedCaseInsensitiveContains("couldn't") ? AppColors.accentDanger : AppColors.textTertiary)
                    }
                }

                Section {
                    ticketNotesSection
                } header: {
                    Label("Notes & Decisions", systemImage: "note.text")
                }

                if !controlSections.isEmpty {
                    Section {
                        controlRecordSection
                    }
                }

                Section("Description") {
                    TextField("Description", text: $editedDescription, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(4...12)

                    if !editedDescription.isEmpty {
                        Button("Clear") {
                            editedDescription = ""
                        }
                        .font(.caption)
                        .foregroundColor(AppColors.accentElectric)
                    }
                }

                Section("Work Control") {
                    TextField("Acceptance criteria, one per line", text: $editedAcceptanceCriteria, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(3...8)

                    TextField("Desired outcome", text: $editedDesiredOutcome, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2...5)

                    TextField("Approval state", text: $editedApprovalState)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Autonomy level", text: $editedAutonomyLevel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Worker lane", text: $editedWorkerLane)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Tool policy", text: $editedToolPolicy)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Lifecycle") {
                    Picker("Agent", selection: $lifecycleAgentId) {
                        ForEach(lifecycleAgents) { agent in
                            Text(agent.name.capitalized).tag(agent.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(lifecycleAgents.isEmpty)

                    HStack(spacing: 10) {
                        lifecycleButton("Claim", icon: "hand.raised.fill", enabled: ticket.status == .open) {
                            await viewModel.claimTicket(ticketId: ticket.id, agentId: lifecycleAgentId)
                        }

                        lifecycleButton("Start", icon: "play.circle.fill", enabled: ticket.status == .open || ticket.status == .claimed) {
                            await viewModel.startTicket(ticketId: ticket.id, agentId: lifecycleAgentId)
                        }

                        lifecycleButton("Close", icon: "checkmark.circle.fill", enabled: canCloseTicket, dismissOnCompletion: false) {
                            pendingAction = .close
                        }
                    }

                    if let message = closeGateMessage {
                        Label(message, systemImage: "checkmark.seal")
                            .font(.caption2)
                            .foregroundColor(AppColors.accentWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Lifecycle actions call ORCA directly and post system activity to the ticket thread when the backend has one. Dispatch and cancellation live in Actions above so higher-risk operations stay gated in one place.")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }

                Section {
                    TextField("Lessons learned", text: $editedLessonsLearned, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(3...10)

                    if !editedLessonsLearned.isEmpty {
                        Button("Clear") {
                            editedLessonsLearned = ""
                        }
                        .font(.caption)
                        .foregroundColor(AppColors.accentElectric)
                    }

                    Text("Capture insights from this ticket for future reference")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                } header: {
                    Label("Lessons Learned", systemImage: "lightbulb.fill")
                        .foregroundColor(Color.yellow)
                }

                if editedStatus == .closed || editedStatus == .cancelled || !editedResolutionNotes.isEmpty || ticket.status == .claimed || ticket.status == .inProgress {
                    Section("Resolution Notes") {
                        TextField("Resolution notes", text: $editedResolutionNotes, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(3...10)

                        if !editedResolutionNotes.isEmpty {
                            Button("Clear") {
                                editedResolutionNotes = ""
                            }
                            .font(.caption)
                            .foregroundColor(AppColors.accentElectric)
                        }
                    }
                }

                Section("Metadata") {
                    metadataRow(label: "ID", value: ticket.id.prefix(8) + "...")
                    metadataRow(label: "Created", value: ticket.createdAt.formatted(date: .abbreviated, time: .shortened))
                    metadataRow(label: "Updated", value: ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    if let agent = ticket.assigneeAgentName {
                        metadataRow(label: "Assignee", value: agent)
                    }
                    if let type = ticket.ticketType {
                        metadataRow(label: "Type", value: type)
                    }
                    if let source = ticket.source, !source.isEmpty {
                        metadataRow(label: "Source", value: source)
                    }
                    if hasSourceProvenance {
                        sourceProvenanceRows
                    }
                    if let chatThreadId = ticket.chatThreadId, !chatThreadId.isEmpty {
                        metadataRow(label: "Chat Thread", value: chatThreadId.prefix(8) + "...")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.visible)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Ticket Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveChanges() }
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.accentElectric)
                }
            }
            .confirmationDialog("Change Status", isPresented: $showingStatusPicker, titleVisibility: .visible) {
                ForEach(TicketStatus.allCases, id: \.self) { status in
                    Button {
                        editedStatus = status
                    } label: {
                        Label(status.label, systemImage: status.icon)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                pendingAction?.title ?? "Confirm Action",
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { if !$0 { pendingAction = nil } }
                ),
                presenting: pendingAction
            ) { action in
                Button(action.confirmTitle, role: action.role) {
                    Task { await confirm(action) }
                }
                Button("Back", role: .cancel) {
                    pendingAction = nil
                }
            } message: { action in
                Text(action.message(ticket: ticket, context: viewModel.actionContext(for: ticket), cancellationReason: cancellationReason, resolutionNotes: editedResolutionNotes))
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: ticket.id) {
            let workerLane = SchoolhouseTicketDispatchService.workerLane(for: ticket)
            async let comments: Void = viewModel.loadComments(ticketId: ticket.id)
            async let notes: Void = viewModel.loadNotes(ticketId: ticket.id)
            async let approvals: Void = viewModel.loadApprovals(ticketId: ticket.id)
            async let approvalRegistry: Void = viewModel.loadApprovalRegistry()
            async let runs: Void = viewModel.loadAgentRuns(ticketId: ticket.id)
            async let preview: Void = viewModel.loadDispatchPreview(ticketId: ticket.id)
            async let runtime: Void = viewModel.loadRuntimeHealthTags()
            async let queue: Void = viewModel.loadWorkerQueue(workerLane: workerLane)
            _ = await (comments, notes, approvals, approvalRegistry, runs, preview, runtime, queue)
        }
        .onChange(of: ticket.status) { _, newStatus in
            editedStatus = newStatus
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(AppColors.textTertiary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var hasSourceProvenance: Bool {
        sourceURL(ticket.sourceChatURL) != nil || sourceURL(ticket.sourceThreadURL) != nil
    }

    @ViewBuilder
    private var sourceProvenanceRows: some View {
        if let chatURL = sourceURL(ticket.sourceChatURL) {
            sourceProvenanceButton(label: "Source Chat", url: chatURL)
        }
        if let threadURL = sourceURL(ticket.sourceThreadURL) {
            sourceProvenanceButton(label: "Source Thread", url: threadURL)
        }
    }

    private func sourceProvenanceButton(label: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack {
                Label(label, systemImage: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundColor(AppColors.accentElectric)
                Spacer()
                Text(url.host ?? url.absoluteString)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(label.lowercased())")
    }

    private func sourceURL(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return URL(string: value)
    }

    private var evidenceLinksSection: some View {
        let links = evidenceLinks

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("EVIDENCE LINKS", systemImage: "link")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textTertiary)

                Spacer()

                Text("\(links.count) refs")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(links) { link in
                    evidenceLinkButton(link)
                }
            }

            Text("Links open the live ORCA API record behind this ticket, so runs, comments, notes, traces, and artifacts are easy to follow from Pod.")
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var evidenceLinks: [TicketEvidenceLink] {
        let runs = viewModel.agentRuns(for: ticket.id).sorted { $0.updatedAt > $1.updatedAt }
        let primaryTrace = ticket.triageTraceId?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? runs.first(where: { !($0.traceId ?? "").isEmpty })?.traceId
        let latestRun = runs.first

        var links: [TicketEvidenceLink] = [
            TicketEvidenceLink(label: "Ticket", detail: shortRef(ticket.id), icon: "ticket", path: "/api/v1/tickets/\(urlPath(ticket.id))", color: AppColors.accentElectric),
            TicketEvidenceLink(label: "Summary", detail: "counts", icon: "checklist", path: "/api/v1/tickets/\(urlPath(ticket.id))/summary", color: AppColors.accentSuccess),
            TicketEvidenceLink(label: "Comments", detail: "\(viewModel.comments(for: ticket.id).count)", icon: "quote.bubble", path: "/api/v1/tickets/\(urlPath(ticket.id))/comments", color: AppColors.accentElectric),
            TicketEvidenceLink(label: "Approvals", detail: "\(viewModel.approvals(for: ticket.id).count)", icon: "person.crop.circle.badge.exclamationmark", path: "/api/v1/tickets/\(urlPath(ticket.id))/approvals", color: Color.orange),
            TicketEvidenceLink(label: "Notes", detail: "\(viewModel.notes(for: ticket.id).count)", icon: "note.text", path: "/api/v1/notes/tickets/\(urlPath(ticket.id))", color: AppColors.accentAgent),
            TicketEvidenceLink(label: "Agent Runs", detail: "\(runs.count)", icon: "bolt.badge.clock", path: "/api/v1/tickets/\(urlPath(ticket.id))/agent-runs", color: latestRun?.status.color ?? AppColors.textTertiary)
        ]

        if let traceId = primaryTrace, !traceId.isEmpty {
            links.append(TicketEvidenceLink(label: "Trace", detail: shortRef(traceId), icon: "point.topleft.down.curvedto.point.bottomright.up", path: "/api/v1/agent-runs/traces/\(urlPath(traceId))", color: AppColors.accentAgent))
            links.append(TicketEvidenceLink(label: "Compute", detail: shortRef(traceId), icon: "cpu", path: "/api/v1/compute/runs?trace_id=\(urlQuery(traceId))", color: AppColors.accentElectric))
        }

        if let latestRun {
            links.append(TicketEvidenceLink(label: "Artifacts", detail: shortRef(latestRun.id), icon: "paperclip", path: "/api/v1/agent-runs/\(urlPath(latestRun.id))/artifacts", color: AppColors.accentSuccess))
        }

        return links
    }

    private func evidenceLinkButton(_ link: TicketEvidenceLink) -> some View {
        Button {
            if let url = backendURL(path: link.path) {
                openURL(url)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: link.icon)
                    .font(.caption.weight(.bold))
                    .foregroundColor(link.color)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(link.label)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(link.detail)
                        .font(.caption2.monospaced())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(9)
            .background(AppColors.backgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(link.color.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(link.label) evidence link")
    }

    private func backendURL(path: String) -> URL? {
        URL(string: "\(AppState.backendURL)\(path)")
    }

    private func urlPath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func urlQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func shortRef(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return trimmed }
        return "\(trimmed.prefix(6))...\(trimmed.suffix(4))"
    }

    private var ticketNotesSection: some View {
        let notes = viewModel.notes(for: ticket.id)
        let error = viewModel.notesError(for: ticket.id)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Title", text: $orcaNoteTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .textInputAutocapitalization(.sentences)

                    Picker("Type", selection: $orcaNoteType) {
                        Text("Note").tag("note")
                        Text("Decision").tag("decision")
                        Text("Handoff").tag("handoff")
                        Text("Finding").tag("finding")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.caption)
                }

                TextField("Durable ORCA note", text: $orcaNoteBody, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(3...8)

                Button {
                    Task { await postOrcaTicketNote() }
                } label: {
                    HStack {
                        Label(isPostingOrcaNote ? "Saving" : "Save ORCA Note", systemImage: "square.and.pencil")
                        Spacer()
                        if isPostingOrcaNote {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
                .disabled(
                    orcaNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || orcaNoteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isPostingOrcaNote
                )

                if let orcaNoteStatus {
                    Text(orcaNoteStatus)
                        .font(.caption2)
                        .foregroundColor(orcaNoteStatus.localizedCaseInsensitiveContains("couldn't") ? AppColors.accentDanger : AppColors.textTertiary)
                }
            }
            .padding(10)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if viewModel.isLoadingNotes(for: ticket.id) && notes.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading ORCA notes")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(AppColors.accentWarning)
            } else if notes.isEmpty {
                Text("No ORCA notes recorded for this ticket.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
            } else {
                ForEach(notes.prefix(6)) { note in
                    ticketNoteRow(note)
                }
            }
        }
    }

    private func ticketNoteRow(_ note: TicketNoteRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: note.noteType == "decision" ? "checkmark.seal" : "note.text")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(note.noteType == "decision" ? AppColors.accentSuccess : AppColors.accentElectric)
                    .frame(width: 18)

                Text(note.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(note.typeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(Capsule())
            }

            Text(note.body)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let source = note.source, !source.isEmpty {
                    Label(source, systemImage: "tray")
                }
                if let signState = note.signState, !signState.isEmpty {
                    Label(signState.replacingOccurrences(of: "_", with: " "), systemImage: "signature")
                }
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption2)
            .foregroundColor(AppColors.textTertiary)

            if let traceId = note.traceId, !traceId.isEmpty {
                traceReferenceButton(label: "Trace", traceId: traceId)
            }

            if note.owner?.isEmpty == false || note.reviewer?.isEmpty == false {
                HStack(spacing: 8) {
                    if let owner = note.owner, !owner.isEmpty {
                        Label(owner, systemImage: "person.crop.circle")
                    }
                    if let reviewer = note.reviewer, !reviewer.isEmpty {
                        Label(reviewer, systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(10)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var controlRecordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("CONTROL RECORD", systemImage: "checklist.checked")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.accentAgent)

            ForEach(controlSections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.textTertiary)

                    Text(section.body)
                        .font(.callout)
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var controlSections: [TicketControlSection] {
        TicketControlSection.parse(editedDescription)
    }

    private var latestAgentRun: AgentRun? {
        viewModel.agentRuns(for: ticket.id).sorted { $0.updatedAt < $1.updatedAt }.last
    }

    private var workOrderSection: some View {
        let summary = viewModel.evidenceSummary(for: ticket)
        let context = viewModel.actionContext(for: ticket)
        let approval = needsApproval ? "Needs human" : (hasClearedApproval ? "Approved" : normalizedApprovalState.replacingOccurrences(of: "_", with: " ").capitalized)
        let criteriaCount = editedAcceptanceCriteria
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("WORK ORDER", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textTertiary)

                Spacer()

                Text(context.workerLane)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(context.workerLane.hasPrefix("protected-") ? AppColors.accentDanger : AppColors.accentAgent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((context.workerLane.hasPrefix("protected-") ? AppColors.accentDanger : AppColors.accentAgent).opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 6) {
                workOrderRow(label: "Intent", value: workOrderIntent, icon: "scope")
                workOrderRow(label: "Next", value: summary.nextAction ?? computedNextAction(summary: summary), icon: "arrow.forward.circle")
                workOrderRow(label: "Owner", value: context.owner, icon: "person.crop.circle")
                workOrderRow(label: "Approval", value: approval.isEmpty ? "Not required" : approval, icon: needsApproval ? "person.crop.circle.badge.exclamationmark" : "checkmark.shield")
                workOrderRow(label: "Done", value: workOrderDoneMeans, icon: "flag.checkered")
                workOrderRow(label: "Scope", value: criteriaCount > 0 ? "\(criteriaCount) acceptance item\(criteriaCount == 1 ? "" : "s")" : "Needs acceptance criteria", icon: criteriaCount > 0 ? "checklist.checked" : "doc.badge.ellipsis")
            }

            if let note = latestWorkNote {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Latest Note", systemImage: "text.bubble")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.textTertiary)
                    Text(note)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(AppColors.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func workOrderRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.accentElectric)
                .frame(width: 18, height: 18)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 56, alignment: .leading)

            Text(value.isEmpty ? "Not set" : value)
                .font(.caption)
                .foregroundColor(value.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var workOrderIntent: String {
        let desired = editedDesiredOutcome.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desired.isEmpty {
            return desired
        }
        let description = editedDescription
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
        return description.isEmpty ? editedTitle : description
    }

    private var workOrderDoneMeans: String {
        let desired = editedDesiredOutcome.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desired.isEmpty {
            return desired
        }
        return "Evidence or resolution note confirms the requested outcome."
    }

    private var latestWorkNote: String? {
        viewModel.comments(for: ticket.id)
            .sorted { $0.createdAt < $1.createdAt }
            .last { comment in
                let lane = comment.lane?.lowercased() ?? ""
                let source = comment.source?.lowercased() ?? ""
                return lane.contains("note") || source.contains("note") || lane.contains("human") || source.contains("pod.tickets")
            }?
            .message
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var preferredChatAgentId: String {
        let candidates = [
            ticket.assigneeAgentName,
            ticket.assigneeAgentId,
            ticket.workerLane,
            ticket.computeTag,
            ticket.ticketType,
            ticket.title
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if candidates.contains("aloha") || ticket.ticketType == "triage" {
            return "aloha"
        }
        if candidates.contains("chief") || candidates.contains("fund") || candidates.contains("trading") || candidates.contains("p&l") {
            return "chief"
        }
        if candidates.contains("rooster") || candidates.contains("security") || candidates.contains("token") || candidates.contains("credential") {
            return "rooster"
        }
        if candidates.contains("coral") || candidates.contains("watchdog") || candidates.contains("daemon") {
            return "coral"
        }
        if candidates.contains("reef") {
            return "reef"
        }
        return "maui"
    }

    private func computedNextAction(summary: TicketEvidenceSummary) -> String {
        if needsApproval {
            return "Human approval required before mutation or protected execution."
        }
        if editedAcceptanceCriteria.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add acceptance criteria so Maui/Mermaid can verify completion."
        }
        if summary.dispatchCount == 0 && canDispatch {
            return "Dispatch to Schoolhouse when the owner accepts scope."
        }
        if summary.latestRunStatus == .failed || summary.latestRunStatus == .blocked {
            return "Review failed run evidence and retry or leave a blocker note."
        }
        if summary.finalVerification == "Pending" {
            return "Attach evidence or resolution notes before closure."
        }
        return "Ready for owner review."
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIONS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textTertiary)

            HStack(spacing: 10) {
                if canDispatch {
                    Button {
                        pendingAction = .approve
                    } label: {
                        Label(hasClearedApproval ? "Approved" : "Request Approval", systemImage: hasClearedApproval ? "checkmark.seal" : "person.crop.circle.badge.exclamationmark")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background((hasClearedApproval ? AppColors.accentSuccess : AppColors.accentWarning).opacity(hasClearedApproval ? 0.08 : 0.16))
                            .foregroundColor(hasClearedApproval ? AppColors.textTertiary : AppColors.accentWarning)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(hasClearedApproval || viewModel.isDispatching)
                }

                Button {
                    pendingAction = .dispatch
                } label: {
                    Label(viewModel.isDispatching ? "Dispatching" : "Dispatch", systemImage: "bolt.badge.clock")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(canDispatch ? AppColors.accentAgent.opacity(0.16) : AppColors.backgroundTertiary)
                        .foregroundColor(canDispatch ? AppColors.accentAgent : AppColors.textTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!canDispatch || viewModel.isDispatching)

                Button(role: .destructive) {
                    pendingAction = .cancel
                } label: {
                    Label("Cancel Ticket", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppColors.accentDanger.opacity(ticket.status == .closed || ticket.status == .cancelled ? 0.06 : 0.14))
                        .foregroundColor(ticket.status == .closed || ticket.status == .cancelled ? AppColors.textTertiary : AppColors.accentDanger)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(ticket.status == .closed || ticket.status == .cancelled)
            }

            Button {
                appState.pendingDirectChatTicketTitle = ticket.title
                appState.pendingDirectChatAgentId = preferredChatAgentId
                appState.pendingDirectChatTicketId = ticket.id
                appState.pendingDirectChatChannelId = ticket.chatThreadId
                dismiss()
            } label: {
                Label(ticket.chatThreadId == nil ? "Continue In Chat" : "Open Linked Chat", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(AppColors.accentElectric.opacity(0.14))
                    .foregroundColor(AppColors.accentElectric)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            dispatchPreview

            if let message = viewModel.dispatchMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(message)
                }
                .font(.caption)
                .foregroundColor(AppColors.accentSuccess)
            }
        }
    }

    private var currentRunSection: some View {
        let summary = viewModel.evidenceSummary(for: ticket)
        let context = viewModel.actionContext(for: ticket)
        let workerHealth = viewModel.workerHealthSummary(for: ticket)
        let queue = viewModel.workerQueue(for: context.workerLane)
        let run = latestAgentRun
        let status = run?.status ?? summary.latestRunStatus
        let route = summary.latestRunRoute ?? "\(context.workerLane) / \(context.toolPolicy)"
        let routePacket = summary.latestRoutePacket
        let routeTruth = routePacket.flatMap { routePacketValue($0, keys: ["route", "suggested_compute_route", "requested_route", "actual_route", "route_mode"]) } ?? route
        let sourceTruth = run?.operationalSourceLabel
            ?? routePacket.flatMap { routePacketValue($0, keys: ["actual_backend", "backend", "model", "actual_tier", "tier", "surface", "source"]) }
        let fallbackUsed = routePacketBool(routePacket, keys: ["fallback_used", "fallback", "used_fallback"]) == true
        let hasLiveRun = status == .queued || status == .running || status == .retrying
        let title = run.map { $0.runType.replacingOccurrences(of: "_", with: " ").capitalized } ?? "No Agent Run"
        let subtitle: String = {
            if let run {
                return [
                    run.workerLane.map { "worker \($0)" },
                    run.backend ?? run.model,
                    run.elapsedLabel
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .prefix(3)
                    .joined(separator: " / ")
            }
            if needsApproval {
                return "Waiting for approval before execution."
            }
            if canDispatch {
                return "Ready to dispatch when scope is accepted."
            }
            return "Dispatch unavailable for this ticket state."
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: status?.icon ?? "bolt.badge.clock")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(status?.color ?? AppColors.textTertiary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)

                    Text(subtitle.isEmpty ? route : subtitle)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if let status {
                    Text(status.label)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(status.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(status.color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                if hasLiveRun {
                    runTruthBadge("Live", icon: "dot.radiowaves.left.and.right", color: AppColors.accentAgent)
                }
                if status == .waitingForHuman || needsApproval {
                    runTruthBadge("Waiting approval", icon: "person.crop.circle.badge.exclamationmark", color: Color.orange)
                }
                if fallbackUsed {
                    runTruthBadge("Fallback", icon: "arrow.triangle.2.circlepath", color: AppColors.accentWarning)
                }
                if sourceTruth != nil {
                    runTruthBadge("Source recorded", icon: "server.rack", color: AppColors.accentElectric)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                compactMetadataRow(label: "Route", value: routeTruth)
                if let sourceTruth {
                    compactMetadataRow(label: "Source", value: sourceTruth)
                }
                compactMetadataRow(label: "Worker", value: run?.workerLane ?? context.workerLane)
                compactMetadataRow(label: "Health", value: workerHealth.isUnknown ? "No live worker tag" : workerHealth.label)
                compactMetadataRow(label: "Queue", value: queue.isEmpty ? "No queued \(context.workerLane) runs" : "\(queue.count) queued \(context.workerLane) run\(queue.count == 1 ? "" : "s")")
                compactMetadataRow(label: "Policy", value: run?.toolPolicy ?? context.toolPolicy)
                if let traceId = run?.traceId, !traceId.isEmpty {
                    traceReferenceButton(label: "Trace", traceId: traceId)
                }
                if let reviewStatus = run?.reviewStatus, !reviewStatus.isEmpty {
                    compactMetadataRow(label: "Review", value: reviewStatus.replacingOccurrences(of: "_", with: " "))
                }
            }
            .padding(10)
            .background(AppColors.backgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let run, let preview = currentRunPreview(for: run) {
                Text(preview)
                    .font(.caption)
                    .foregroundColor(run.status == .failed || run.status == .blocked ? AppColors.accentDanger : AppColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                evidenceLens = .runs
            } label: {
                Label(run == nil ? "Open Runs" : "View Run Evidence", systemImage: "arrow.down.doc")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppColors.accentElectric.opacity(0.12))
                    .foregroundColor(AppColors.accentElectric)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if let run, run.workerLane == "mermaid", [.failed, .blocked, .retrying].contains(run.status) {
                Button {
                    Task { await viewModel.retryAgentRun(run, ticket: ticket) }
                } label: {
                    Label("Retry Mermaid Run", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppColors.accentWarning.opacity(0.12))
                        .foregroundColor(AppColors.accentWarning)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else if let run, run.workerLane == "mermaid", run.status == .succeeded, run.reviewStatus == nil {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    HStack(spacing: Theme.xs) {
                        Button {
                            Task { await viewModel.reviewAgentRun(run, ticket: ticket, reviewStatus: "accepted") }
                        } label: {
                            Label("Accept Mermaid", systemImage: "checkmark.seal")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(AppColors.accentSuccess.opacity(run.hasReviewEvidence ? 0.12 : 0.06))
                                .foregroundColor(run.hasReviewEvidence ? AppColors.accentSuccess : AppColors.textTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(!run.hasReviewEvidence)

                        Button {
                            Task { await viewModel.reviewAgentRun(run, ticket: ticket, reviewStatus: "needs_changes") }
                        } label: {
                            Label("Needs Changes", systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(AppColors.accentWarning.opacity(0.12))
                                .foregroundColor(AppColors.accentWarning)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    if !run.hasReviewEvidence {
                        Label("Accept requires run evidence, outcome, or artifacts.", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(AppColors.accentWarning)
                    }
                }
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func currentRunPreview(for run: AgentRun) -> String? {
        if let error = run.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            return error
        }
        if let outcome = run.outcome?.trimmingCharacters(in: .whitespacesAndNewlines), !outcome.isEmpty {
            return outcome
        }
        if let evidence = run.evidence?.trimmingCharacters(in: .whitespacesAndNewlines), !evidence.isEmpty {
            return evidence
        }
        return run.inputSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runTruthBadge(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var evidenceSnapshotSection: some View {
        let summary = viewModel.evidenceSummary(for: ticket)
        let context = viewModel.actionContext(for: ticket)
        let routePacket = summary.latestRoutePacket
        let fallbackUsed = routePacketBool(routePacket, keys: ["fallback_used", "fallback", "used_fallback"]) == true

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("EVIDENCE SNAPSHOT", systemImage: "checklist")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textTertiary)

                Spacer()

                if let status = summary.latestRunStatus {
                    Label(status.label, systemImage: status.icon)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(status.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(status.color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                evidenceMetric("Comments", value: "\(summary.commentCount)", icon: "quote.bubble", color: AppColors.accentElectric)
                evidenceMetric("Agent Runs", value: "\(summary.runCount)", icon: "bolt.badge.clock", color: summary.failedRunCount > 0 ? AppColors.accentDanger : AppColors.accentAgent)
                evidenceMetric("Approvals", value: "\(summary.approvalCount)", icon: "person.crop.circle.badge.exclamationmark", color: summary.approvalCount > 0 ? Color.orange : AppColors.textTertiary)
                evidenceMetric("Final Verify", value: summary.finalVerification, icon: "checkmark.seal", color: summary.finalVerificationColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let routePacket {
                    ForEach(routePacketFields(routePacket)) { field in
                        compactMetadataRow(label: field.label, value: field.value)
                    }
                    if routePacketValue(routePacket, keys: ["owner_agent", "suggested_owner", "owner", "owner_id"]) == nil {
                        compactMetadataRow(label: "Owner", value: context.owner)
                    }
                } else {
                    compactMetadataRow(label: "Route", value: summary.latestRunRoute ?? "\(context.workerLane) / \(context.toolPolicy)")
                    compactMetadataRow(label: "Owner", value: context.owner)
                }
                compactMetadataRow(label: "Dispatches", value: "\(summary.dispatchCount)")
                let routePacketHasNextAction = summary.latestRoutePacket.flatMap { routePacketValue($0, keys: ["next_action"]) } != nil
                if let nextAction = summary.nextAction, !nextAction.isEmpty, !routePacketHasNextAction {
                    compactMetadataRow(label: "Next", value: nextAction)
                }
                if fallbackUsed {
                    compactMetadataRow(label: "Compute", value: "Fallback route used")
                }
                if summary.latestRunStatus == .waitingForHuman || needsApproval {
                    compactMetadataRow(label: "Approval", value: "Waiting for human before protected execution")
                }
                if let latestRun = latestAgentRun, let source = latestRun.operationalSourceLabel {
                    compactMetadataRow(label: "Run Source", value: source)
                }
            }
            .padding(10)
            .background(AppColors.backgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !summary.blockers.isEmpty {
                Label(summary.blockers.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: " / "), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(AppColors.accentWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var operationalDebtSection: some View {
        let debts = viewModel.operationalDebts(for: ticket)
        if !debts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("OPERATIONAL DEBT", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(debts.first?.color ?? AppColors.accentWarning)

                    Spacer()

                    Text("\(debts.count) open")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColors.backgroundPrimary)
                        .clipShape(Capsule())
                }

                ForEach(debts) { debt in
                    operationalDebtRow(debt)
                }

                Text("These are read-only scan signals from the existing ticket summary, work-control integrity/backfill dry-runs, and loaded run evidence.")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func operationalDebtRow(_ debt: TicketOperationalDebt) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: debt.icon)
                .font(.caption.weight(.bold))
                .foregroundColor(debt.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(debt.label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(debt.detail)
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var executionReadinessSection: some View {
        let summary = viewModel.evidenceSummary(for: ticket)
        let context = viewModel.actionContext(for: ticket)
        let workerHealth = viewModel.workerHealthSummary(for: ticket)
        let queueCount = viewModel.workerQueue(for: context.workerLane).count
        let hasScope = !(ticket.acceptanceCriteria ?? []).isEmpty
            || !(ticket.desiredOutcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !controlSections.isEmpty
        let approvalValue: String
        let approvalColor: Color
        if needsApproval {
            approvalValue = "Waiting for human"
            approvalColor = Color.orange
        } else if let state = ticket.approvalState, !state.isEmpty {
            approvalValue = state.replacingOccurrences(of: "_", with: " ").capitalized
            approvalColor = AppColors.accentSuccess
        } else {
            approvalValue = "Not required"
            approvalColor = AppColors.accentSuccess
        }

        let dispatchValue: String
        let dispatchColor: Color
        if summary.dispatchCount > 0 {
            dispatchValue = "\(summary.dispatchCount) recorded"
            dispatchColor = AppColors.accentSuccess
        } else if canDispatch {
            dispatchValue = "Ready"
            dispatchColor = AppColors.accentAgent
        } else {
            dispatchValue = "Blocked"
            dispatchColor = AppColors.textTertiary
        }

        let runValue = summary.latestRunStatus?.label ?? "No run yet"
        let runColor = summary.latestRunStatus?.color ?? AppColors.textTertiary
        let evidenceReady = summary.finalVerification != "Pending"
        let workerColor: Color = {
            if workerHealth.error > 0 { return AppColors.accentDanger }
            if workerHealth.stale > 0 || workerHealth.isUnknown { return AppColors.accentWarning }
            return AppColors.accentSuccess
        }()

        return VStack(alignment: .leading, spacing: 10) {
            Label("EXECUTION CHECKLIST", systemImage: "checklist.checked")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textTertiary)

            VStack(spacing: 6) {
                executionStepRow(
                    label: "Scope",
                    value: hasScope ? "Defined" : "Needs acceptance criteria",
                    icon: hasScope ? "checkmark.circle.fill" : "doc.badge.ellipsis",
                    color: hasScope ? AppColors.accentSuccess : AppColors.accentWarning
                )
                executionStepRow(
                    label: "Approval",
                    value: approvalValue,
                    icon: needsApproval ? "person.crop.circle.badge.exclamationmark" : "checkmark.shield",
                    color: approvalColor
                )
                executionStepRow(
                    label: "Worker",
                    value: "\(workerHealth.lane): \(workerHealth.label) / \(queueCount) queued",
                    icon: workerHealth.error > 0 ? "exclamationmark.triangle.fill" : "waveform.path.ecg",
                    color: workerColor
                )
                executionStepRow(
                    label: "Dispatch",
                    value: dispatchValue,
                    icon: summary.dispatchCount > 0 ? "paperplane.circle.fill" : "paperplane",
                    color: dispatchColor
                )
                executionStepRow(
                    label: "Run",
                    value: runValue,
                    icon: summary.latestRunStatus?.icon ?? "bolt.badge.clock",
                    color: runColor
                )
                executionStepRow(
                    label: "Evidence",
                    value: summary.finalVerification,
                    icon: evidenceReady ? "checkmark.seal.fill" : "checkmark.seal",
                    color: summary.finalVerificationColor
                )
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func executionStepRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundColor(color)
                .frame(width: 18, height: 18)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var workSpineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("WORK SPINE", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textTertiary)

                Spacer()
            }

            Picker("Work Spine", selection: $evidenceLens) {
                ForEach(TicketEvidenceLens.allCases) { lens in
                    Text(lens.label).tag(lens)
                }
            }
            .pickerStyle(.segmented)

            switch evidenceLens {
            case .timeline:
                timelineSection
            case .runs:
                agentRunsSection
            case .evidence:
                evidenceSection
            case .trace:
                traceSection
            case .health:
                runtimeHealthSection
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func evidenceMetric(_ label: String, value: String, icon: String, color: Color) -> some View {
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }

    private func compactMetadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func routePacketSummary(_ packet: [String: AgentRunJSONValue]) -> String {
        let owner = packet["owner_agent"]?.displayValue
        let worker = packet["worker_lane"]?.displayValue
        let route = packet["route"]?.displayValue ?? packet["suggested_compute_route"]?.displayValue ?? packet["requested_route"]?.displayValue
        let risk = packet["risk_level"]?.displayValue
        let action = packet["next_action"]?.displayValue
        let parts = [
            route.map { "route \($0)" },
            owner.map { "owner \($0)" },
            worker.map { "worker \($0)" },
            risk.map { "risk \($0)" },
            action
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "null" }
        return parts.isEmpty ? "Route packet recorded" : parts.prefix(3).joined(separator: " / ")
    }

    private func routePacketFields(_ packet: [String: AgentRunJSONValue]) -> [TicketRoutePacketField] {
        let fields: [(String, [String])] = [
            ("Route", ["route", "suggested_compute_route", "requested_route", "actual_route", "route_mode"]),
            ("Owner", ["owner_agent", "suggested_owner", "owner", "owner_id"]),
            ("Worker", ["worker_lane", "suggested_worker", "recommended_lane", "lane"]),
            ("Source", ["source", "surface", "caller"]),
            ("Backend", ["actual_backend", "backend"]),
            ("Model", ["model", "actual_model"]),
            ("Tier", ["actual_tier", "tier"]),
            ("Fallback", ["fallback_used", "fallback", "used_fallback"]),
            ("Risk", ["risk_level", "risk"]),
            ("Approval", ["approval_state", "approval_gate", "needs_approval", "approval_required"]),
            ("Autonomy", ["autonomy_level", "autonomy"]),
            ("Next", ["next_action"])
        ]

        let rows = fields.compactMap { label, keys -> TicketRoutePacketField? in
            guard let value = routePacketValue(packet, keys: keys) else { return nil }
            return TicketRoutePacketField(label: label, value: value)
        }

        if rows.isEmpty {
            return [TicketRoutePacketField(label: "Intel", value: routePacketSummary(packet))]
        }
        return rows
    }

    private func routePacketValue(_ packet: [String: AgentRunJSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let rawValue = packet[key] else { continue }
            let value = rawValue.displayValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != "null" else { continue }
            return value.replacingOccurrences(of: "_", with: " ")
        }
        return nil
    }

    private func routePacketBool(_ packet: [String: AgentRunJSONValue]?, keys: [String]) -> Bool? {
        guard let packet else { return nil }
        for key in keys {
            guard let rawValue = packet[key] else { continue }
            switch rawValue {
            case .bool(let value):
                return value
            case .string(let value):
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "yes", "1"].contains(normalized) { return true }
                if ["false", "no", "0"].contains(normalized) { return false }
            case .int(let value):
                return value != 0
            default:
                continue
            }
        }
        return nil
    }

    private func traceReferenceButton(label: String, traceId: String) -> some View {
        Button {
            evidenceLens = .trace
            Task { await viewModel.loadTrace(traceId: traceId) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .frame(width: 64, alignment: .leading)

                Label(traceId, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentElectric)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Load trace \(traceId)")
    }

    @ViewBuilder
    private func artifactValueView(_ value: String) -> some View {
        if let url = URL(string: value), url.scheme?.isEmpty == false {
            Link(destination: url) {
                Label(value, systemImage: "arrow.up.right")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentElectric)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        } else {
            Text(value)
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var dispatchPreview: some View {
        let context = viewModel.actionContext(for: ticket)
        let backendPreview = viewModel.dispatchPreview(for: ticket.id)
        let previewError = viewModel.dispatchPreviewError(for: ticket.id)
        let workerHealth = viewModel.workerHealthSummary(for: ticket)
        let queue = viewModel.workerQueue(for: context.workerLane)
        let queueError = viewModel.workerQueueError(for: context.workerLane)
        let workerLane = backendPreview?.workerLane ?? context.workerLane
        let toolPolicy = backendPreview?.toolPolicy ?? context.toolPolicy
        let computeTag = backendPreview?.computeTag ?? context.computeTag
        let isProtected = backendPreview?.protectedLane ?? workerLane.hasPrefix("protected-")
        let blockers = backendPreview?.blockers ?? []

        return VStack(alignment: .leading, spacing: 7) {
            Label("Dispatch Preview", systemImage: "doc.text.magnifyingglass")
                .font(.caption2.weight(.bold))
                .foregroundColor(AppColors.textTertiary)

            metadataRow(label: "Owner", value: context.owner)
            metadataRow(label: "Worker lane", value: workerLane)
        metadataRow(label: "Tool policy", value: toolPolicy)
        metadataRow(label: "Compute tag", value: computeTag)
        metadataRow(label: "Approval authority", value: approvalAuthority(workerLane: workerLane, toolPolicy: toolPolicy, computeTag: computeTag))
        metadataRow(label: "Worker health", value: workerHealth.isUnknown ? "No live \(workerLane) tag" : "\(workerHealth.label) (\(workerHealth.total) tag\(workerHealth.total == 1 ? "" : "s"))")
            metadataRow(label: "Queue", value: queue.isEmpty ? "No queued \(workerLane) runs" : "\(queue.count) queued \(workerLane) run\(queue.count == 1 ? "" : "s")")
            if let backendPreview {
                metadataRow(label: "Next state", value: backendPreview.nextState.replacingOccurrences(of: "_", with: " "))
            }

            if let queueError {
                Label(queueError, systemImage: "tray.and.arrow.down")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if workerHealth.isUnknown {
                Label("No live worker state tag is available. Treat dispatch as queued evidence until the worker confirms pickup.", systemImage: "waveform.path.ecg")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentWarning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if workerHealth.error > 0 || workerHealth.stale > 0 {
                Label("Worker state is \(workerHealth.label.lowercased()). Review runtime health before expecting execution.", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(workerHealth.error > 0 ? AppColors.accentDanger : AppColors.accentWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isProtected {
                Label("Protected lane: dispatch records planning evidence; mutation still needs approval.", systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !blockers.isEmpty {
                Label(blockers.joined(separator: " • "), systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentWarning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if backendPreview != nil {
                Label("ORCA preview says this ticket is dispatch-ready.", systemImage: "checkmark.seal")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentSuccess)
            } else if let previewError {
                Label(previewError, systemImage: "wifi.exclamationmark")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func approvalAuthority(workerLane: String, toolPolicy: String, computeTag: String) -> String {
        let haystack = "\(workerLane) \(toolPolicy) \(computeTag) \(ticket.title) \(ticket.description ?? "")".lowercased()
        if haystack.contains("chief") || haystack.contains("fund") || haystack.contains("trading") || haystack.contains("financial") {
            return "Tony + Chief/Rooster review for financial/protected work"
        }
        if haystack.contains("rooster") || haystack.contains("credential") || haystack.contains("secret") || haystack.contains("security") {
            return "Rooster + Tony review for security/credential work"
        }
        if haystack.contains("archive") || haystack.contains("memory") || haystack.contains("soul") || haystack.contains("identity") {
            return "Aloha/Maui/Tony review for memory, archive, or identity work"
        }
        if haystack.contains("launchagent") || haystack.contains("daemon") || haystack.contains("deploy") || haystack.contains("runtime") {
            return "Maui/service-owner review for runtime changes"
        }
        return "Owner review before execution; no protected authority detected"
    }

    private var runtimeHealthSection: some View {
        let tags = viewModel.healthTags(for: ticket)
        let staleCount = tags.filter(\.stale).count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("RUNTIME HEALTH", systemImage: "waveform.path.ecg")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textTertiary)

                if staleCount > 0 {
                    Text("\(staleCount) stale")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.accentWarning)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColors.accentWarning.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    Task { await viewModel.loadRuntimeHealthTags() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .accessibilityLabel("Refresh runtime health")
            }

            if let message = viewModel.runtimeHealthErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(AppColors.accentDanger)
            } else if tags.isEmpty {
                Text("No runtime health tags available for this ticket.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
            } else {
                VStack(spacing: 6) {
                    ForEach(tags) { tag in
                        LiveStateRow(tag: tag)
                    }
                }
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var timelineSection: some View {
        let items = timelineItems
        let summary = viewModel.evidenceSummary(for: ticket)
        let commentsLoading = viewModel.isLoadingComments(for: ticket.id)
        let runsLoading = viewModel.isLoadingAgentRuns(for: ticket.id)
        let notesLoading = viewModel.isLoadingNotes(for: ticket.id)
        let approvalsLoading = viewModel.isLoadingApprovals(for: ticket.id)
        let commentsError = viewModel.commentsError(for: ticket.id)
        let runsError = viewModel.agentRunsError(for: ticket.id)
        let notesError = viewModel.notesError(for: ticket.id)
        let approvalsError = viewModel.approvalsError(for: ticket.id)
        let isLoading = commentsLoading || runsLoading || notesLoading || approvalsLoading

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("OPS TIMELINE", systemImage: "list.bullet.rectangle")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textTertiary)

                if summary.failedRunCount > 0 {
                    Text("\(summary.failedRunCount) failed")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.accentDanger)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColors.accentDanger.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    Task {
                        await viewModel.loadComments(ticketId: ticket.id)
                        await viewModel.loadNotes(ticketId: ticket.id)
                        await viewModel.loadApprovals(ticketId: ticket.id)
                        await viewModel.loadAgentRuns(ticketId: ticket.id)
                    }
                } label: {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh ticket timeline")
            }

            Picker("Timeline Filter", selection: $timelineFilter) {
                ForEach(TicketTimelineFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if isLoading && items.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading ORCA timeline...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            } else if items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No \(timelineFilter.label.lowercased()) timeline items yet.")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                    if let commentsError {
                        Text(commentsError)
                            .font(.caption2)
                            .foregroundColor(AppColors.accentDanger)
                    }
                    if let runsError {
                        Text(runsError)
                            .font(.caption2)
                            .foregroundColor(AppColors.accentDanger)
                    }
                    if let notesError {
                        Text(notesError)
                            .font(.caption2)
                            .foregroundColor(AppColors.accentDanger)
                    }
                    if let approvalsError {
                        Text(approvalsError)
                            .font(.caption2)
                            .foregroundColor(AppColors.accentDanger)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(items.prefix(15))) { item in
                        timelineRow(item)
                    }
                }

                if let route = summary.latestRunRoute {
                    Label(route, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if commentsError != nil || runsError != nil || notesError != nil || approvalsError != nil {
                    VStack(alignment: .leading, spacing: 3) {
                        if let commentsError {
                            Text(commentsError)
                        }
                        if let runsError {
                            Text(runsError)
                        }
                        if let notesError {
                            Text(notesError)
                        }
                        if let approvalsError {
                            Text(approvalsError)
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var timelineItems: [TicketTimelineItem] {
        timelineItemsWithAllFilters
            .filter(timelineItemMatchesFilter)
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var timelineItemsWithAllFilters: [TicketTimelineItem] {
        let comments = viewModel.comments(for: ticket.id).map {
            TicketTimelineItem(id: "comment-\($0.id)", createdAt: $0.createdAt, kind: .comment($0))
        }
        let runs = viewModel.agentRuns(for: ticket.id).map {
            TicketTimelineItem(id: "run-\($0.id)", createdAt: $0.createdAt, kind: .agentRun($0))
        }
        let notes = viewModel.notes(for: ticket.id).map {
            TicketTimelineItem(id: "note-\($0.id)", createdAt: $0.updatedAt, kind: .note($0))
        }
        let approvals = viewModel.approvals(for: ticket.id).map {
            TicketTimelineItem(id: "approval-\($0.id)", createdAt: $0.createdAt, kind: .approval($0))
        }
        return comments + runs + notes + approvals
    }

    private func timelineItemMatchesFilter(_ item: TicketTimelineItem) -> Bool {
        switch timelineFilter {
        case .all:
            return true
        case .runs:
            if case .agentRun = item.kind { return true }
            return false
        case .comments:
            if case .comment = item.kind { return true }
            return false
        case .notes:
            if case .note = item.kind { return true }
            return false
        case .evidence:
            switch item.kind {
            case .agentRun(let run):
                return !(run.evidence ?? "").isEmpty || !(run.outcome ?? "").isEmpty
            case .comment(let comment):
                let category = evidenceCategory(for: comment).label
                return category == "Dispatch" || category == "Verification"
            case .note(let note):
                return note.noteType == "decision" || note.noteType == "finding"
            case .approval:
                return true
            }
        case .approvals:
            switch item.kind {
            case .agentRun(let run):
                return run.status == .waitingForHuman || approvalTextSignal(run.toolPolicy ?? "")
            case .comment(let comment):
                return evidenceCategory(for: comment).label == "Approval"
            case .note(let note):
                return approvalTextSignal(note.title) || approvalTextSignal(note.body)
            case .approval:
                return true
            }
        }
    }

    private func timelineTraceId(for item: TicketTimelineItem) -> String? {
        switch item.kind {
        case .agentRun(let run):
            return run.traceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        case .comment(let comment):
            return comment.traceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        case .note(let note):
            return note.traceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        case .approval(let approval):
            return approval.traceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func approvalTextSignal(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("approval")
            || lower.contains("waiting_for_human")
            || lower.contains("needs human")
            || lower.contains("protected")
    }

    @ViewBuilder
    private func timelineRow(_ item: TicketTimelineItem) -> some View {
        switch item.kind {
        case .comment(let comment):
            evidenceRow(comment)
        case .agentRun(let run):
            agentRunRow(run)
        case .note(let note):
            ticketNoteRow(note)
        case .approval(let approval):
            approvalRow(approval)
        }
    }

    private var evidenceSection: some View {
        let comments = viewModel.comments(for: ticket.id)
            .sorted { $0.createdAt > $1.createdAt }
        let evidenceRuns = viewModel.agentRuns(for: ticket.id)
            .filter { !($0.evidence ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !($0.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
        let approvals = viewModel.approvals(for: ticket.id)
            .sorted { ($0.resolvedAt ?? $0.createdAt) > ($1.resolvedAt ?? $1.createdAt) }
        let isLoading = viewModel.isLoadingComments(for: ticket.id)
            || viewModel.isLoadingAgentRuns(for: ticket.id)
            || viewModel.isLoadingApprovals(for: ticket.id)
        let error = viewModel.commentsError(for: ticket.id)
            ?? viewModel.agentRunsError(for: ticket.id)
            ?? viewModel.approvalsError(for: ticket.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("EVIDENCE", systemImage: "quote.bubble")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textTertiary)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadComments(ticketId: ticket.id)
                        await viewModel.loadAgentRuns(ticketId: ticket.id)
                        await viewModel.loadApprovals(ticketId: ticket.id)
                    }
                } label: {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh evidence")
            }

            if isLoading && comments.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading ORCA comments...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            } else if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.accentDanger)
            } else if comments.isEmpty && evidenceRuns.isEmpty && approvals.isEmpty {
                Text("No ORCA comments, approvals, or Schoolhouse evidence yet.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(approvals.prefix(3))) { approval in
                        approvalRow(approval)
                    }
                    ForEach(Array(evidenceRuns.prefix(3))) { run in
                        agentRunRow(run)
                    }
                    ForEach(Array(comments.prefix(6))) { comment in
                        evidenceRow(comment)
                    }
                }
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var agentRunsSection: some View {
        let runs = viewModel.agentRuns(for: ticket.id)
            .sorted { $0.updatedAt > $1.updatedAt }
        let isLoading = viewModel.isLoadingAgentRuns(for: ticket.id)
        let error = viewModel.agentRunsError(for: ticket.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("AGENT RUNS", systemImage: "bolt.badge.clock")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textTertiary)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadAgentRuns(ticketId: ticket.id)
                    }
                } label: {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh Agent Runs")
            }

            if isLoading && runs.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading Agent Runs...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            } else if runs.isEmpty {
                Text(error ?? "No Schoolhouse Agent Runs yet.")
                    .font(.caption)
                    .foregroundColor(error == nil ? AppColors.textTertiary : AppColors.accentDanger)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(runs.prefix(7))) { run in
                        agentRunRow(run)
                    }
                }

                if let error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var traceSection: some View {
        let groups = traceGroups

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("TRACE VIEW", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textTertiary)

                Spacer()

                Text("\(groups.count) traces")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
            }

            if groups.isEmpty {
                Text("No trace IDs are attached to this ticket yet.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
            } else {
                VStack(spacing: 8) {
                    traceChainCard

                    ForEach(Array(groups.enumerated()), id: \.element.traceId) { _, group in
                        traceGroupCard(traceId: group.traceId, items: group.items)
                    }
                }
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var traceChainCard: some View {
        let runs = viewModel.agentRuns(for: ticket.id)
        let primaryTrace = ticket.triageTraceId?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? runs.first(where: { !($0.traceId ?? "").isEmpty })?.traceId
            ?? traceGroups.first?.traceId
        let dispatch = runs.first { $0.runType == "dispatch" }
        let execution = runs.first { $0.runType == "execution" }
        let triageId = ticket.triageId?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? dispatch?.artifacts?["triage_id"]?.displayValue
            ?? execution?.artifacts?["triage_id"]?.displayValue

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Schoolhouse Chain", systemImage: "link")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if let primaryTrace, !primaryTrace.isEmpty {
                    Button {
                        Task { await viewModel.loadTrace(traceId: primaryTrace) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.accentElectric)
                    .accessibilityLabel("Refresh trace chain")
                }
            }

            traceChainStep(
                title: "Merman decision",
                value: triageId?.isEmpty == false ? triageId! : "Not linked yet",
                state: triageId?.isEmpty == false ? .succeeded : .queued
            )
            traceChainStep(
                title: "Chat-created ticket",
                value: ticket.source == "pod_chat" ? "Pod Chat -> ORCA ticket" : (ticket.source ?? "ORCA ticket"),
                state: .succeeded
            )
            traceChainStep(
                title: "Dispatch run",
                value: dispatch.map { "\($0.status.label) · \($0.workerLane ?? "no worker")" } ?? "No dispatch run yet",
                state: dispatch?.status ?? .queued
            )
            traceChainStep(
                title: "Worker execution",
                value: execution.map { "\($0.status.label) · \($0.workerLane ?? "no worker")" } ?? "No execution run yet",
                state: execution?.status ?? .queued
            )
            traceChainStep(
                title: "Evidence",
                value: evidenceStateLabel(dispatch: dispatch, execution: execution),
                state: evidenceState(dispatch: dispatch, execution: execution)
            )

            runMetaPillCloud([
                primaryTrace.map { "trace \($0)" },
                triageId.map { "triage \($0)" },
                ticket.chatThreadId.map { "chat \($0.prefix(8))" }
            ])
        }
        .padding(10)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func traceChainStep(title: String, value: String, state: AgentRunStatus) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: state.icon)
                .font(.caption)
                .foregroundColor(state.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.textSecondary)
                Text(value)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private func evidenceState(dispatch: AgentRun?, execution: AgentRun?) -> AgentRunStatus {
        if let execution, !(execution.evidence ?? "").isEmpty || !(execution.outcome ?? "").isEmpty {
            return execution.status
        }
        if let dispatch, !(dispatch.evidence ?? "").isEmpty || !(dispatch.outcome ?? "").isEmpty {
            return dispatch.status
        }
        return .queued
    }

    private func evidenceStateLabel(dispatch: AgentRun?, execution: AgentRun?) -> String {
        if let execution, !(execution.evidence ?? "").isEmpty {
            return "Worker evidence recorded"
        }
        if let dispatch, !(dispatch.evidence ?? "").isEmpty {
            return "Dispatch evidence recorded"
        }
        return "Waiting for evidence"
    }

    private var traceGroups: [(traceId: String, items: [TicketTimelineItem])] {
        let grouped = Dictionary(grouping: timelineItemsWithAllFilters) { item in
            timelineTraceId(for: item) ?? ""
        }
        return grouped
            .filter { !$0.key.isEmpty }
            .map { (traceId: $0.key, items: $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { lhs, rhs in
                (lhs.items.last?.createdAt ?? .distantPast) > (rhs.items.last?.createdAt ?? .distantPast)
            }
    }

    private func traceGroupCard(traceId: String, items: [TicketTimelineItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(traceId, systemImage: "number")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.accentElectric)
                    .lineLimit(1)

                Spacer()

                Button {
                    Task { await viewModel.loadTrace(traceId: traceId) }
                } label: {
                    if viewModel.isLoadingTrace(traceId) {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(AppColors.accentElectric)
                .disabled(viewModel.isLoadingTrace(traceId))
                .accessibilityLabel("Expand trace")
            }

            ForEach(items.suffix(8)) { item in
                timelineRow(item)
            }

            if let trace = viewModel.traceLookup(for: traceId) {
                traceExpansion(trace)
            } else if let error = viewModel.traceError(for: traceId) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentWarning)
            }
        }
        .padding(10)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func traceExpansion(_ trace: AgentRunTrace) -> some View {
        let computeRuns = viewModel.computeRuns(for: trace.traceId)
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(AppColors.border)

            runMetaPillCloud([
                "\(trace.agentRuns.count) runs",
                "\(trace.events.count) events",
                "\(computeRuns.count) compute",
                "\(trace.chatMessages.count) chat",
                "\(trace.notes.count) notes",
                "ORCA trace"
            ])

            ForEach(trace.chatMessages.suffix(3)) { message in
                traceChatMessageRow(message)
            }

            ForEach(trace.notes.suffix(3)) { note in
                ticketNoteRow(note)
            }

            ForEach(trace.agentRuns.suffix(3)) { run in
                agentRunRow(run)
            }

            ForEach(computeRuns.suffix(3)) { run in
                computeRunRow(run)
            }

            ForEach(trace.events.suffix(3)) { event in
                traceEventRow(event)
            }
        }
    }

    private func computeRunRow(_ run: ComputeRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("\(run.taskHint) / \(run.status)", systemImage: "cpu")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(run.fallbackUsed ? AppColors.accentWarning : AppColors.accentElectric)

                Spacer()

                Text(run.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            runMetaPillCloud([
                "requested \(run.requestedRoute ?? run.route)",
                run.actualTier.map { "tier \($0)" },
                run.actualBackend.map { "backend \($0)" },
                run.backend,
                run.model,
                run.latencyMs.map { "\($0)ms" },
                run.inputTokens.map { "in \($0)t" },
                run.outputTokens.map { "out \($0)t" },
                run.fallbackUsed ? "fallback" : nil
            ])

            if let error = run.error, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(AppColors.accentDanger)
                    .lineLimit(2)
            }

            if let preview = run.outputPreview, !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(4)
            }
        }
        .padding(8)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func traceChatMessageRow(_ message: AgentRunTraceChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(message.provenance ?? message.source ?? message.messageType, systemImage: "bubble.left.and.bubble.right")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.accentAgent)

                Spacer()

                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            runMetaPillCloud([
                message.deliveryMode,
                message.lane,
                message.responseState,
                message.triageId.map { "triage \($0.prefix(8))" }
            ])

            Text(message.content)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(4)
        }
        .padding(8)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func traceEventRow(_ event: AgentRunTraceEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(event.source ?? event.eventType, systemImage: "text.bubble")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                Text(event.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            if !event.message.isEmpty {
                Text(event.message)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(4)
            }

            runMetaPillCloud([
                event.ticketId.map { "ticket \($0.prefix(8))" },
                event.lane
            ])
        }
        .padding(8)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func agentRunRow(_ run: AgentRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("\(run.runType.replacingOccurrences(of: "_", with: " ").capitalized) / \(run.status.label)", systemImage: run.status.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(run.status.color)

                Spacer()

                Text(run.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            runMetaPillCloud([
                run.runType,
                run.status.rawValue,
                run.operationalRouteLabel,
                run.computeTag ?? "no tag",
                run.caller,
                run.source,
                run.lane,
                run.workerLane.map { "worker: \($0)" },
                run.toolPolicy,
                run.backend,
                run.model,
                run.latencyMs.map { "\($0)ms" },
                run.tokenCount.map { "\($0)t" }
            ])

            if let sourceLabel = run.operationalSourceLabel {
                Label(sourceLabel, systemImage: "server.rack")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.accentElectric)
                    .fixedSize(horizontal: false, vertical: true)
            }

            runMetaPillCloud([
                "created \(run.createdAt.relativeTimeString)",
                run.startedAt.map { "started \($0.relativeTimeString)" },
                run.completedAt.map { "completed \($0.relativeTimeString)" },
                run.elapsedLabel,
                run.reviewStatus.map { "review: \($0)" },
                run.reviewedBy.map { "by \($0)" }
            ])

            if let traceId = run.traceId, !traceId.isEmpty {
                traceReferenceButton(label: "Trace", traceId: traceId)
            }

            if let outcome = run.outcome, !outcome.isEmpty {
                Text(outcome)
                    .font(.caption)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let summary = run.inputSummary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = run.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.accentDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reviewNote = run.reviewNote, !reviewNote.isEmpty {
                Label(reviewNote, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let artifacts = run.artifacts, !artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Label("Artifacts", systemImage: "paperclip")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(AppColors.accentElectric)

                        Spacer()

                        Button {
                            Task { await viewModel.loadArtifactSummary(runId: run.id) }
                        } label: {
                            if viewModel.isLoadingArtifactSummary(for: run.id) {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "shield.checkered")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(AppColors.accentElectric)
                        .disabled(viewModel.isLoadingArtifactSummary(for: run.id))
                        .accessibilityLabel("Verify artifacts")
                    }

                    ForEach(agentRunArtifactRows(artifacts).prefix(6), id: \.key) { row in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: row.icon)
                                .font(.caption2)
                                .foregroundColor(row.color)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(AppColors.textSecondary)
                                artifactValueView(row.value)
                            }

                            Spacer(minLength: 0)
                        }
                    }

                    if let summaries = viewModel.artifactSummaries(for: run.id) {
                        ForEach(summaries.prefix(4)) { summary in
                            artifactSummaryRow(summary)
                        }
                    } else if let error = viewModel.artifactSummaryError(for: run.id) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundColor(AppColors.accentWarning)
                    }
                }
                .padding(8)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let evidence = run.evidence, !evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Evidence", systemImage: "checkmark.seal")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.accentSuccess)
                    Text(evidence)
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func agentRunArtifactRows(_ artifacts: [String: AgentRunJSONValue]) -> [(key: String, label: String, value: String, icon: String, color: Color)] {
        let priority = [
            "mode",
            "worker",
            "script",
            "evidence_summary_compute_run_id",
            "evidence_summary_route",
            "evidence_summary_backend",
            "evidence_summary_model",
            "evidence_summary_fallback_used",
            "evidence_summary_error"
        ]
        let orderedKeys = priority.filter { artifacts[$0] != nil } + artifacts.keys.sorted().filter { !priority.contains($0) }

        return orderedKeys.map { key in
            let value = artifacts[key]?.displayValue ?? ""
            let lower = key.lowercased()
            let icon: String
            let color: Color
            if lower.contains("error") {
                icon = "exclamationmark.triangle"
                color = AppColors.accentWarning
            } else if lower.contains("script") || value.hasPrefix("/") {
                icon = "doc.text"
                color = AppColors.accentElectric
            } else if lower.contains("compute") || lower.contains("route") || lower.contains("backend") || lower.contains("model") {
                icon = "cpu"
                color = AppColors.accentAgent
            } else {
                icon = "tag"
                color = AppColors.textTertiary
            }
            return (
                key: key,
                label: key.replacingOccurrences(of: "_", with: " ").capitalized,
                value: value,
                icon: icon,
                color: color
            )
        }
    }

    private func runMetaPillCloud(_ values: [String?]) -> some View {
        let cleaned = values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(cleaned, id: \.self) { value in
                runMetaPill(value)
            }
        }
    }

    private func artifactSummaryRow(_ summary: AgentRunArtifactSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: summary.safeToPreview ? "doc.text.magnifyingglass" : "lock.shield")
                    .font(.caption2)
                    .foregroundColor(summary.safeToPreview ? AppColors.accentSuccess : AppColors.textTertiary)
                    .frame(width: 14)

                Text(summary.key)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                Text(summary.kind)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            Text(summary.value)
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(2)

            if let reason = summary.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            if let preview = summary.preview, !preview.isEmpty {
                Text(preview)
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(4)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.backgroundPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.top, 4)
    }

    private func runMetaPill(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.medium))
            .foregroundColor(AppColors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }

    private func evidenceRow(_ comment: TicketComment) -> some View {
        let category = evidenceCategory(for: comment)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(category.label, systemImage: category.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(category.color)

                Spacer()

                Text(comment.createdAt == Date.distantPast ? "Unknown time" : comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            Text(comment.message.isEmpty ? "(empty comment)" : comment.message)
                .font(.caption)
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let lane = comment.lane, !lane.isEmpty {
                    runMetaPill(lane)
                }
                if let source = comment.source, !source.isEmpty {
                    runMetaPill(source)
                }
                if let traceId = comment.traceId, !traceId.isEmpty {
                    traceReferenceButton(label: "Trace", traceId: traceId)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(category.color.opacity(0.16), lineWidth: 1)
        )
    }

    private func approvalRow(_ approval: TicketApprovalRecord) -> some View {
        let normalizedStatus = approval.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let authority = viewModel.approvalAuthoritySpec(for: approval.actionType)
        let color: Color
        switch normalizedStatus {
        case "approved":
            color = AppColors.accentSuccess
        case "rejected", "cancelled":
            color = AppColors.accentDanger
        default:
            color = Color.orange
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("Approval", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(color)

                Spacer()

                Text(approval.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }

            Text(approval.actionType.replacingOccurrences(of: "_", with: " "))
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.textPrimary)

            if let reason = approval.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                runMetaPill(approval.statusLabel)
                runMetaPill("confidence \(Int(approval.confidence))")
                runMetaPill(authority?.authorityLabel ?? "registry unknown")
                if let lane = approval.lane, !lane.isEmpty {
                    runMetaPill(lane)
                }
                if let source = approval.source, !source.isEmpty {
                    runMetaPill(source)
                }
            }

            if let traceId = approval.traceId, !traceId.isEmpty {
                traceReferenceButton(label: "Trace", traceId: traceId)
            }

            if let authority {
                Label(authority.authorityLabel, systemImage: authority.noCascade ? "lock.shield" : "person.2.badge.gearshape")
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let message = viewModel.approvalRegistryErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentWarning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Approval authority not loaded. ORCA still enforces the registry on resolution.", systemImage: "questionmark.shield")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if normalizedStatus == "pending" {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await viewModel.resolveApproval(
                                ticketId: ticket.id,
                                approvalId: approval.id,
                                approved: true,
                                reason: "Approved from Pod ticket evidence review."
                            )
                        }
                    } label: {
                        Label("Approve", systemImage: "checkmark.shield")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.accentSuccess)

                    Button(role: .destructive) {
                        Task {
                            await viewModel.resolveApproval(
                                ticketId: ticket.id,
                                approvalId: approval.id,
                                approved: false,
                                reason: "Rejected from Pod ticket evidence review."
                            )
                        }
                    } label: {
                        Label("Reject", systemImage: "xmark.shield")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)

                Text("Authority action: this requests ORCA to resolve the approval. ORCA checks the approval registry before accepting the decision.")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.16), lineWidth: 1)
        )
    }

    private func evidenceCategory(for comment: TicketComment) -> (label: String, icon: String, color: Color) {
        let text = "\(comment.eventType) \(comment.message) \(comment.lane ?? "")".lowercased()
        if text.contains("approval") || text.contains("waiting_for_human") || text.contains("needs human") || text.contains("protected") {
            return ("Approval", "person.crop.circle.badge.exclamationmark", Color.orange)
        }
        if text.contains("dispatch") || text.contains("schoolhouse") || text.contains("agent_run") {
            return ("Dispatch", "bolt.badge.clock", AppColors.accentAgent)
        }
        if text.contains("verify") || text.contains("verification") || text.contains("resolution") || text.contains("done means") {
            return ("Verification", "checkmark.seal", AppColors.accentSuccess)
        }
        return (comment.eventType.replacingOccurrences(of: "_", with: " ").capitalized, "quote.bubble", AppColors.accentElectric)
    }

    private var lifecycleAgents: [AgentDTO] {
        let filtered = agents.filter { AgentRosterPolicy.isActiveOrSupport($0.name) }
        return filtered.isEmpty ? agents : filtered
    }

    private var canDispatch: Bool {
        ticket.status != .closed && ticket.status != .cancelled
    }

    private var closureEvidenceReady: Bool {
        viewModel.evidenceSummary(for: ticket).finalVerification != "Pending"
            || !editedResolutionNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canCloseTicket: Bool {
        (ticket.status == .claimed || ticket.status == .inProgress)
            && !lifecycleAgentId.isEmpty
            && closureEvidenceReady
    }

    private var closeGateMessage: String? {
        guard ticket.status != .closed && ticket.status != .cancelled else { return nil }
        if ticket.status != .claimed && ticket.status != .inProgress {
            return "Claim or start the ticket before closing it."
        }
        if lifecycleAgentId.isEmpty {
            return "Choose a lifecycle agent before closing."
        }
        if !closureEvidenceReady {
            return "Add resolution notes or attach verification evidence before closing."
        }
        return nil
    }

    private var needsApproval: Bool {
        if hasClearedApproval {
            return false
        }
        let approvalState = normalizedApprovalState
        let context = viewModel.actionContext(for: ticket)
        let haystack = "\(ticket.title) \(ticket.description ?? "") \(approvalState) \(context.workerLane) \(context.toolPolicy)".lowercased()
        return approvalState.contains("approval")
            || approvalState.contains("waiting_for_human")
            || approvalState.contains("needs")
            || haystack.contains("waiting_for_human")
            || haystack.contains("needs human")
            || haystack.contains("protected-")
            || haystack.contains("forbidden-without-approval")
    }

    private var normalizedApprovalState: String {
        (ticket.approvalState ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var hasClearedApproval: Bool {
        Self.isClearedApprovalState(normalizedApprovalState)
    }

    private static func isClearedApprovalState(_ state: String) -> Bool {
        [
            "approved",
            "human_approved",
            "approved_by_human",
            "not_required",
            "not-required",
            "none",
            "cleared"
        ].contains(state)
    }

    private var cancellationReason: String {
        editedResolutionNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Cancelled from Pod"
            : editedResolutionNotes
    }

    private static func defaultAgentId(from agents: [AgentDTO]) -> String {
        let preferred = ["maui", "aloha", "chief", "rooster"]
        for name in preferred {
            if let agent = agents.first(where: { AgentRosterPolicy.normalizedName($0.name) == name }) {
                return agent.id
            }
        }
        return agents.first?.id ?? ""
    }

    private func lifecycleButton(
        _ title: String,
        icon: String,
        enabled: Bool,
        dismissOnCompletion: Bool = true,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
                if dismissOnCompletion {
                    dismiss()
                }
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(enabled && !lifecycleAgentId.isEmpty ? AppColors.accentElectric.opacity(0.16) : AppColors.backgroundTertiary)
                .foregroundColor(enabled && !lifecycleAgentId.isEmpty ? AppColors.accentElectric : AppColors.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!enabled || lifecycleAgentId.isEmpty)
    }

    private func saveChanges() async {
        let titleChanged = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines) != ticket.title
        let descriptionChanged = editedDescription != (ticket.description ?? "")
        let priorityChanged = editedPriority != ticket.priority
        let criteria = editedAcceptanceCriteria
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let criteriaChanged = criteria != (ticket.acceptanceCriteria ?? [])
        let desiredOutcome = editedDesiredOutcome.trimmingCharacters(in: .whitespacesAndNewlines)
        let desiredChanged = desiredOutcome != (ticket.desiredOutcome ?? "")
        let approvalChanged = editedApprovalState.trimmingCharacters(in: .whitespacesAndNewlines) != (ticket.approvalState ?? "not_required")
        let autonomyChanged = editedAutonomyLevel.trimmingCharacters(in: .whitespacesAndNewlines) != (ticket.autonomyLevel ?? "draft_only")
        let workerChanged = editedWorkerLane.trimmingCharacters(in: .whitespacesAndNewlines) != (ticket.workerLane ?? SchoolhouseTicketDispatchService.workerLane(for: ticket))
        let policyChanged = editedToolPolicy.trimmingCharacters(in: .whitespacesAndNewlines) != (ticket.toolPolicy ?? SchoolhouseTicketDispatchService.toolPolicy(for: ticket))

        if titleChanged || descriptionChanged || priorityChanged || criteriaChanged || desiredChanged || approvalChanged || autonomyChanged || workerChanged || policyChanged {
            await viewModel.updateTicket(
                ticketId: ticket.id,
                title: editedTitle,
                description: editedDescription,
                priority: editedPriority,
                acceptanceCriteria: criteria,
                desiredOutcome: desiredOutcome.isEmpty ? nil : desiredOutcome,
                approvalState: editedApprovalState.trimmingCharacters(in: .whitespacesAndNewlines),
                autonomyLevel: editedAutonomyLevel.trimmingCharacters(in: .whitespacesAndNewlines),
                workerLane: editedWorkerLane.trimmingCharacters(in: .whitespacesAndNewlines),
                toolPolicy: editedToolPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // Update status if changed
        if editedStatus != ticket.status {
            if editedStatus.isTerminal {
                if editedStatus == .closed {
                    if canCloseTicket {
                        pendingAction = .close
                    } else {
                        viewModel.errorMessage = closeGateMessage ?? "Add resolution notes or verification evidence before closing."
                    }
                } else {
                    pendingAction = .status(editedStatus)
                }
                return
            }
            await viewModel.updateStatus(ticketId: ticket.id, status: editedStatus)
        }

        // Update lessons learned if changed
        if editedLessonsLearned != (ticket.lessonsLearned ?? "") {
            await viewModel.updateLessonsLearned(ticketId: ticket.id, lessonsLearned: editedLessonsLearned)
        }

        dismiss()
    }

    @MainActor
    private func postSharedNote() async {
        let note = sharedNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }

        isPostingSharedNote = true
        sharedNoteStatus = nil
        defer { isPostingSharedNote = false }

        let posted = await viewModel.postTicketNote(ticketId: ticket.id, message: note)
        if posted {
            sharedNoteText = ""
            sharedNoteStatus = "Note added to the ticket thread."
        } else {
            sharedNoteStatus = "Couldn't add note. Try again."
        }
    }

    @MainActor
    private func postOrcaTicketNote() async {
        let title = orcaNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = orcaNoteBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else { return }

        isPostingOrcaNote = true
        orcaNoteStatus = nil
        defer { isPostingOrcaNote = false }

        let saved = await viewModel.createOrcaTicketNote(
            ticketId: ticket.id,
            title: title,
            body: body,
            noteType: orcaNoteType
        )
        if saved {
            orcaNoteTitle = ""
            orcaNoteBody = ""
            orcaNoteType = "note"
            orcaNoteStatus = "ORCA note saved."
        } else {
            orcaNoteStatus = "Couldn't save ORCA note."
        }
    }

    @MainActor
    private func confirm(_ action: PendingTicketAction) async {
        pendingAction = nil
        switch action {
        case .approve:
            await viewModel.approveTicket(ticket)
        case .dispatch:
            await viewModel.dispatchTicketToSchoolhouse(ticket)
        case .cancel:
            await viewModel.cancelTicket(ticketId: ticket.id, reason: cancellationReason)
            dismiss()
        case .close:
            await viewModel.completeTicket(
                ticketId: ticket.id,
                agentId: lifecycleAgentId,
                resolutionNotes: editedResolutionNotes
            )
            dismiss()
        case .status(let status):
            if status == .cancelled {
                await viewModel.cancelTicket(ticketId: ticket.id, reason: cancellationReason)
            } else {
                await viewModel.updateStatus(ticketId: ticket.id, status: status)
            }
            dismiss()
        }
    }
}

private enum PendingTicketAction: Identifiable {
    case approve
    case dispatch
    case cancel
    case close
    case status(TicketStatus)

    var id: String {
        switch self {
        case .approve: return "approve"
        case .dispatch: return "dispatch"
        case .cancel: return "cancel"
        case .close: return "close"
        case .status(let status): return "status-\(status.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .approve: return "Request Approval Review?"
        case .dispatch: return "Dispatch to Schoolhouse?"
        case .cancel: return "Cancel Ticket?"
        case .close: return "Close Ticket?"
        case .status(let status): return "Mark \(status.label)?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .approve: return "Request Review"
        case .dispatch: return "Dispatch"
        case .cancel: return "Cancel Ticket"
        case .close: return "Close Ticket"
        case .status(let status): return "Mark \(status.label)"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .approve, .dispatch: return nil
        case .cancel: return .destructive
        case .close: return nil
        case .status(let status): return status.isTerminal ? .destructive : nil
        }
    }

    func message(ticket: Ticket, context: TicketActionContext, cancellationReason: String, resolutionNotes: String) -> String {
        var lines = [
            ticket.title,
            "",
            "Owner: \(context.owner)",
            "Worker lane: \(context.workerLane)",
            "Tool policy: \(context.toolPolicy)",
            "Compute tag: \(context.computeTag)"
        ]
        switch self {
        case .cancel, .status(.cancelled):
            lines.append("Reason: \(cancellationReason)")
        case .approve:
            lines.append("This adds an approval-review evidence comment. It does not clear the ORCA approval gate.")
        case .close:
            let trimmed = resolutionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("Resolution: \(trimmed.isEmpty ? "No resolution note entered." : trimmed)")
            lines.append("This closes the ticket through ORCA lifecycle and records the resolution.")
        case .status(let status):
            lines.append("This changes the ticket to terminal status: \(status.label).")
        case .dispatch:
            break
        }
        return lines.joined(separator: "\n")
    }
}

private struct TicketControlSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String

    static func parse(_ markdown: String) -> [TicketControlSection] {
        let interesting = Set([
            "Request",
            "Desired Outcome",
            "Proposed Owner / Lane",
            "Approval / Guardrail Check",
            "Acceptance Criteria",
            "Done Means",
            "Source"
        ])
        var sections: [TicketControlSection] = []
        var currentTitle: String?
        var currentBody: [String] = []

        func flush() {
            guard let title = currentTitle, interesting.contains(title) else {
                currentBody.removeAll()
                return
            }
            let body = currentBody
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                sections.append(TicketControlSection(title: title, body: body))
            }
            currentBody.removeAll()
        }

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                flush()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if currentTitle != nil {
                currentBody.append(line)
            }
        }
        flush()
        return sections
    }
}
