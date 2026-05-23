import SwiftUI
import SwiftData

struct DirectChatView: View {
    @Bindable var viewModel: DirectChatViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            agentListSidebar
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
        .task {
            await viewModel.loadAgentRegistry()
            await viewModel.loadORCAChannelSummaries()
        }
        .onChange(of: viewModel.navigationPath.count) { _, count in
            if count == 0 {
                viewModel.clearSelection()
            }
        }
    }

    // MARK: - Agent List Sidebar

    private var agentListSidebar: some View {
        List(viewModel.directChatAgents) { agent in
            // Pod chat shows active and support-runtime lanes. Dormant/advisor
            // agents stay preserved in the model, but do not present as working
            // chat targets.
            if viewModel.canStartChat(with: agent) {
                NavigationLink(value: agent) {
                    AgentRowView(agent: agent, viewModel: viewModel)
                }
                .listRowBackground(
                    viewModel.selectedAgent?.id == agent.id
                    ? AppColors.accentElectric.opacity(0.15)
                    : Color.clear
                )
            } else {
                AgentRowView(agent: agent, viewModel: viewModel)
                    .opacity(0.45)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("\(agent.name) - \(viewModel.rosterBadgeText(for: agent))")
                    .accessibilityHint("Create or route an ORCA ticket before assigning this lane.")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: AgentInfo.self) { agent in
            ConversationView(viewModel: viewModel, agent: agent)
                .onAppear { viewModel.selectAgent(agent) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)
            Text("Select an agent to start chatting")
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
    }
}

private struct TicketDraftReviewSheet: View {
    let draft: DirectChatTicketDraft
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: (DirectChatTicketDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var priority: String
    @State private var ticketType: String
    @State private var computeTag: String
    @State private var workerLane: String
    @State private var toolPolicy: String
    @State private var autonomyLevel: String
    @State private var approvalState: String
    @State private var desiredOutcome: String
    @State private var acceptanceCriteriaText: String
    @State private var tagsText: String

    init(
        draft: DirectChatTicketDraft,
        isSubmitting: Bool,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (DirectChatTicketDraft) -> Void
    ) {
        self.draft = draft
        self.isSubmitting = isSubmitting
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        _title = State(initialValue: draft.title)
        _description = State(initialValue: draft.description)
        _priority = State(initialValue: draft.priority)
        _ticketType = State(initialValue: draft.ticketType)
        _computeTag = State(initialValue: draft.computeTag)
        _workerLane = State(initialValue: draft.workerLane)
        _toolPolicy = State(initialValue: draft.toolPolicy)
        _autonomyLevel = State(initialValue: draft.autonomyLevel)
        _approvalState = State(initialValue: draft.approvalState)
        _desiredOutcome = State(initialValue: draft.desiredOutcome)
        _acceptanceCriteriaText = State(initialValue: draft.acceptanceCriteria.joined(separator: "\n"))
        _tagsText = State(initialValue: draft.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Ticket") {
                    TextField("Title", text: $title, axis: .vertical)
                    TextField("Description", text: $description, axis: .vertical)
                    TextField("Priority", text: $priority)
                        .textInputAutocapitalization(.never)
                    TextField("Type", text: $ticketType)
                        .textInputAutocapitalization(.never)
                    TextField("Tags", text: $tagsText)
                        .textInputAutocapitalization(.never)
                    labeledValue("Owner", draft.ownerSlug.capitalized)
                }

                Section("Work Control") {
                    TextField("Worker lane", text: $workerLane)
                        .textInputAutocapitalization(.never)
                    TextField("Tool policy", text: $toolPolicy)
                        .textInputAutocapitalization(.never)
                    TextField("Approval", text: $approvalState)
                        .textInputAutocapitalization(.never)
                    TextField("Autonomy", text: $autonomyLevel)
                        .textInputAutocapitalization(.never)
                    TextField("Compute tag", text: $computeTag)
                        .textInputAutocapitalization(.never)
                    TextField("Outcome", text: $desiredOutcome, axis: .vertical)
                }

                Section("Acceptance Criteria") {
                    TextEditor(text: $acceptanceCriteriaText)
                        .frame(minHeight: 110)
                        .font(.caption)
                }

                Section("Merman Triage") {
                    Text(draft.triageSummary)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Intake") {
                    Text(draft.intake)
                        .font(.caption)
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Review Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Creating" : "Create") {
                        onSubmit(editedDraft)
                    }
                    .disabled(isSubmitting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var editedDraft: DirectChatTicketDraft {
        draft.withEdits(
            title: title,
            description: description,
            priority: priority,
            ticketType: ticketType,
            tags: tagsText
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            computeTag: computeTag,
            approvalState: approvalState,
            autonomyLevel: autonomyLevel,
            workerLane: workerLane,
            toolPolicy: toolPolicy,
            desiredOutcome: desiredOutcome,
            acceptanceCriteria: acceptanceCriteriaText
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundColor(AppColors.textTertiary)
            Text(value.isEmpty ? "None" : value)
                .font(.caption)
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AttachTicketSheet: View {
    let tickets: [DirectChatAttachableTicket]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void
    let onAttach: (DirectChatAttachableTicket) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredTickets: [DirectChatAttachableTicket] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tickets }
        return tickets.filter { ticket in
            [
                ticket.id,
                ticket.title,
                ticket.status,
                ticket.priority,
                ticket.workerLane ?? "",
                ticket.approvalState ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading && tickets.isEmpty {
                    Section {
                        HStack(spacing: Theme.xs) {
                            ProgressView()
                                .scaleEffect(0.75)
                            Text("Loading ORCA tickets...")
                                .font(.caption)
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                } else if let errorMessage, tickets.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(AppColors.accentWarning)
                    }
                } else if tickets.isEmpty {
                    Section {
                        Text("No active ORCA tickets are available to attach.")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }
                } else if filteredTickets.isEmpty {
                    Section {
                        Text("No tickets match that filter.")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }
                } else {
                    Section("Active Tickets") {
                        ForEach(filteredTickets) { ticket in
                            Button {
                                onAttach(ticket)
                            } label: {
                                AttachableTicketRow(ticket: ticket)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.backgroundPrimary)
            .searchable(text: $searchText, prompt: "Search title, id, lane, status")
            .navigationTitle("Attach Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct AttachableTicketRow: View {
    let ticket: DirectChatAttachableTicket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.xs) {
                Text(ticket.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: Theme.xs)

                Text(ticket.priority.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(priorityColor)
                    .lineLimit(1)
            }

            HStack(spacing: Theme.xs) {
                Label(ticket.status.replacingOccurrences(of: "_", with: " "), systemImage: "circle.dotted")
                if let workerLane = ticket.workerLane, !workerLane.isEmpty {
                    Label(workerLane, systemImage: "hammer")
                }
                if let approvalState = ticket.approvalState, !approvalState.isEmpty {
                    Label(approvalState.replacingOccurrences(of: "_", with: " "), systemImage: "person.badge.key")
                }
            }
            .font(.caption2)
            .foregroundColor(AppColors.textTertiary)
            .lineLimit(1)

            Text(ticket.id)
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
        }
        .padding(.vertical, Theme.xs)
    }

    private var priorityColor: Color {
        switch ticket.priority.lowercased() {
        case "critical", "urgent":
            return AppColors.accentDanger
        case "high":
            return AppColors.accentWarning
        default:
            return AppColors.textTertiary
        }
    }
}

// MARK: - Agent Row

struct AgentRowView: View {
    let agent: AgentInfo
    let viewModel: DirectChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Agent avatar
            ZStack {
                Circle()
                    .fill(Color(hexString: agent.color).opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: agent.icon)
                    .font(.system(size: 18))
                    .foregroundColor(Color(hexString: agent.color))
            }

            // Name + last message
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(agent.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    if let date = viewModel.lastMessagePreview(for: agent).date {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                HStack {
                    Text(viewModel.rosterBadgeText(for: agent))
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    let unread = viewModel.unreadCount(for: agent)
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.accentElectric)
                            .clipShape(Capsule())
                    }
                }

                if agent.isReachable {
                    Text(rowPreviewText)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)

                    if !capabilityChips.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(capabilityChips, id: \.self) { chip in
                                Text(chip)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(AppColors.accentElectric)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.accentElectric.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                } else {
                    Text(agent.availabilityText)
                        .font(.caption.italic())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var rowPreviewText: String {
        let preview = viewModel.lastMessagePreview(for: agent).text
        if preview != "No messages yet" { return preview }
        return viewModel.serverChannelStatusText(for: agent) ?? viewModel.rosterDetailText(for: agent)
    }

    private var capabilityChips: [String] {
        guard let registryAgent = viewModel.registryAgent(for: agent) else {
            return [agent.defaultDeliveryMode.displayLabel]
        }
        var chips = [
            registryAgent.status.displayName,
            registryAgent.rosterLane.label
        ]
        chips += registryAgent.skills
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
        return Array(chips.prefix(4))
    }
}

// MARK: - Conversation View

struct ConversationView: View {
    let viewModel: DirectChatViewModel
    let agent: AgentInfo

    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var isTextFieldFocused: Bool
    // Padding to keep compose bar above the floating tab bar on iPhone.
    // Cleared when keyboard appears (tab bar also hides at that point).
    @State private var tabBarPadding: CGFloat = 83
    @State private var showingTicketConfirmation = false
    @State private var showingAttachTicketSheet = false
    @State private var showingTriageSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ticketContextBar
            ticketContinuityBar
            workCockpitPanel
            routeDecisionBar
            if !viewModel.routeProgressSteps.isEmpty {
                RouteProgressStrip(steps: viewModel.routeProgressSteps)
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.currentMessages, id: \.id) { message in
                            DMBubble(message: message, agent: agent)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.currentMessages.count) { _, _ in
                    if let last = viewModel.currentMessages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    if let last = viewModel.currentMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(AppColors.backgroundPrimary)

            // Error bar
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundColor(AppColors.accentAgent)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppColors.accentAgent)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.accentAgent.opacity(0.1))
            }

            if let message = viewModel.ticketActionMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.accentSuccess)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(AppColors.accentSuccess)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.accentSuccess.opacity(0.1))
            }

            if viewModel.liveChatStatus != nil {
                liveStatusBar
            }

            if viewModel.ticketLiveStatus != nil {
                ticketLiveStatusBar
            }

            // Compose bar
            composeBar
        }
        .padding(.bottom, tabBarPadding)
        .background(AppColors.backgroundPrimary)
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { tabBarPadding = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { tabBarPadding = 83 }
        }
        .toolbarBackground(AppColors.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog(
            "Create ORCA ticket?",
            isPresented: $showingTicketConfirmation,
            titleVisibility: .visible
        ) {
            Button("Review Draft") {
                viewModel.createTicketFromChat()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pod will ask Merman for triage, then show the ORCA ticket draft before creating it.")
        }
        .sheet(item: Binding(
            get: { viewModel.pendingTicketDraft },
            set: { if $0 == nil { viewModel.cancelPendingTicketDraft() } }
        )) { draft in
            TicketDraftReviewSheet(
                draft: draft,
                isSubmitting: viewModel.isCreatingTicket,
                onCancel: { viewModel.cancelPendingTicketDraft() },
                onSubmit: { viewModel.submitPendingTicketDraft($0) }
            )
        }
        .sheet(isPresented: $showingAttachTicketSheet) {
            AttachTicketSheet(
                tickets: viewModel.attachableTickets,
                isLoading: viewModel.isLoadingAttachableTickets,
                errorMessage: viewModel.attachTicketError,
                onRefresh: { Task { await viewModel.loadAttachableTickets() } },
                onAttach: { ticket in
                    viewModel.attachTicket(ticket)
                    showingAttachTicketSheet = false
                }
            )
            .task {
                await viewModel.loadAttachableTickets()
            }
        }
        .sheet(isPresented: $showingTriageSheet) {
            if let preview = viewModel.latestTriagePreview {
                TriagePreviewSheet(preview: preview)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: agent.icon)
                        .foregroundColor(Color(hexString: agent.color))
                    Text(agent.name)
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                    Text(agent.role)
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var workCockpitPanel: some View {
        if viewModel.activeTicketId != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(awakeStateLabel, systemImage: awakeStateIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentAgent)

                    Spacer()

                    Label("\(viewModel.workCockpitReadinessPercent)%", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(readinessColor)

                    Button {
                        viewModel.refreshWorkCockpitFromChat()
                    } label: {
                        Label(viewModel.isRefreshingWorkCockpit ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(viewModel.isRefreshingWorkCockpit)

                    Button {
                        viewModel.requestApprovalFromChat()
                    } label: {
                        Label(viewModel.isRequestingTicketApproval ? "Requesting" : "Approval", systemImage: "person.badge.key")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(viewModel.isRequestingTicketApproval)

                    Button {
                        viewModel.saveMemoryCandidateFromChat()
                    } label: {
                        Label(viewModel.isSavingMemoryCandidate ? "Saving" : "Memory", systemImage: "brain.head.profile")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(viewModel.isSavingMemoryCandidate)

                    Button {
                        viewModel.saveWorkspaceArtifactFromChat()
                    } label: {
                        Label(viewModel.isSavingWorkspaceArtifact ? "Saving" : "Artifact", systemImage: "doc.badge.plus")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(viewModel.isSavingWorkspaceArtifact)

                    Button {
                        viewModel.requestWorkspaceToolFromChat()
                    } label: {
                        Label(viewModel.isRequestingWorkspaceTool ? "Requesting" : "Tool", systemImage: "hammer")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(viewModel.isRequestingWorkspaceTool)
                }

                HStack(spacing: 8) {
                    Text(viewModel.workCockpitRefreshLabel)
                    Text(viewModel.ticketLiveSummaryLabel)
                    if let ticketId = viewModel.activeTicketId {
                        Text("Ticket \(String(ticketId.prefix(8)))")
                    }
                    if let traceId = viewModel.agentRunTrace?.traceId {
                        Text("Trace \(String(traceId.prefix(8)))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)

                if let message = viewModel.approvalActionMessage ?? viewModel.memoryCandidateMessage ?? viewModel.workspaceArtifactMessage ?? viewModel.workspaceToolMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(message.lowercased().contains("couldn't") ? AppColors.accentWarning : AppColors.accentSuccess)
                        .lineLimit(2)
                }

                routePacketRows
                approvalRows
                traceTimeline
                artifactRows
                workspaceRows
                cockpitGapRows
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(AppColors.backgroundSecondary.opacity(0.82))
            .overlay(
                Rectangle()
                    .fill(AppColors.border.opacity(0.7))
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }
    }

    @ViewBuilder
    private var routePacketRows: some View {
        if let continuity = viewModel.activeTicketContinuity {
            VStack(alignment: .leading, spacing: 5) {
                Label("Route packet", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)

                Text(continuity.routePacketLabel ?? "No route packet recorded yet")
                    .font(.caption2)
                    .foregroundStyle(continuity.routePacketLabel == nil ? AppColors.textTertiary : AppColors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("Next: \(continuity.nextActionLabel)")
                    if let approval = continuity.approvalLabel {
                        Text("Approval: \(approval)")
                    }
                    if let worker = continuity.latestRun?.workerLane, !worker.isEmpty {
                        Text("Worker: \(worker)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var cockpitGapRows: some View {
        let gaps = viewModel.workCockpitGapLabels
        if !gaps.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Label("Readiness gaps", systemImage: "list.bullet.clipboard")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentWarning)
                ForEach(gaps, id: \.self) { gap in
                    Text(gap)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var readinessColor: Color {
        let percent = viewModel.workCockpitReadinessPercent
        if percent >= 80 { return AppColors.accentSuccess }
        if percent >= 55 { return AppColors.accentAgent }
        return AppColors.accentWarning
    }

    private var awakeStateLabel: String {
        guard let run = viewModel.activeTicketContinuity?.latestRun else {
            return "No Agent Run yet"
        }
        switch run.status {
        case .queued:
            return "Agent Run queued"
        case .running, .retrying:
            return "\(run.workerLane ?? agent.id) awake on run"
        case .waitingForHuman:
            return "Waiting approval"
        case .succeeded:
            return "Run evidence ready"
        case .failed, .blocked:
            return "Run needs review"
        case .cancelled:
            return "Run cancelled"
        }
    }

    private var awakeStateIcon: String {
        guard let status = viewModel.activeTicketContinuity?.latestRun?.status else {
            return "moon.zzz"
        }
        switch status {
        case .queued: return "clock"
        case .running, .retrying: return "bolt.circle.fill"
        case .waitingForHuman: return "person.crop.circle.badge.exclamationmark"
        case .succeeded: return "checkmark.seal"
        case .failed, .blocked: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        }
    }

    @ViewBuilder
    private var approvalRows: some View {
        if viewModel.isLoadingTicketApprovals {
            Label("Loading approvals", systemImage: "hourglass")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        } else if !viewModel.ticketApprovals.isEmpty {
            VStack(spacing: 5) {
                ForEach(viewModel.ticketApprovals.prefix(2)) { approval in
                    HStack(spacing: 8) {
                        Label("\(approval.actionType.replacingOccurrences(of: "_", with: " ")) · \(approval.statusLabel)", systemImage: approval.status == "approved" ? "checkmark.shield" : "person.badge.key")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(approval.status == "approved" ? AppColors.accentSuccess : AppColors.accentWarning)
                            .lineLimit(1)

                        Spacer()

                        if approval.resolvedAt == nil {
                            if viewModel.resolvingApprovalIds.contains(approval.id) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.62)
                                    .tint(AppColors.accentAgent)
                            } else {
                                Button("Approve") {
                                    viewModel.resolveApprovalFromChat(approval, approved: true)
                                }
                                .font(.caption2.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)

                                Button("Reject") {
                                    viewModel.resolveApprovalFromChat(approval, approved: false)
                                }
                                .font(.caption2.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .tint(AppColors.accentWarning)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var traceTimeline: some View {
        if viewModel.isLoadingAgentRunTrace {
            Label("Loading Agent Run trace", systemImage: "hourglass")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        } else if let trace = viewModel.agentRunTrace {
            VStack(alignment: .leading, spacing: 5) {
                Label("Trace \(String(trace.traceId.prefix(8))) · \(trace.events.count) events · \(trace.computeRuns.count) compute · \(trace.chatMessages.count) chat", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)

                ForEach(traceTimelineItems(trace).prefix(4), id: \.self) { item in
                    Text(item)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }
        } else if let error = viewModel.agentRunTraceError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(AppColors.accentWarning)
        }
    }

    private func traceTimelineItems(_ trace: AgentRunTrace) -> [String] {
        var items: [String] = []
        items.append(contentsOf: trace.agentRuns.suffix(2).map { "Run \($0.runType): \($0.status.label)" })
        items.append(contentsOf: trace.events.suffix(2).map { "\($0.eventType): \($0.message)" })
        items.append(contentsOf: trace.computeRuns.suffix(2).map { "Compute \($0.taskHint): \($0.status)" })
        items.append(contentsOf: trace.chatMessages.suffix(1).map { "Chat: \($0.content)" })
        return items.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @ViewBuilder
    private var artifactRows: some View {
        let summaries = viewModel.artifactSummariesByRunId.values.flatMap { $0 }
        if !summaries.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Label("Artifacts", systemImage: "paperclip")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentSuccess)
                ForEach(summaries.prefix(4)) { artifact in
                    Text("\(artifact.kind): \(artifact.value)")
                        .font(.caption2)
                        .foregroundStyle(artifact.safeToPreview ? AppColors.textSecondary : AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
        } else if let error = viewModel.artifactSummaryErrorsByRunId.values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            Label(error, systemImage: "paperclip.badge.ellipsis")
                .font(.caption2)
                .foregroundStyle(AppColors.accentWarning)
        }
    }

    @ViewBuilder
    private var workspaceRows: some View {
        if viewModel.isLoadingWorkspaceContext {
            Label("Loading workspace context", systemImage: "folder.badge.gearshape")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        } else if let context = viewModel.workspaceContext {
            VStack(alignment: .leading, spacing: 5) {
                Label("Workspace \(String(context.workspaceId.suffix(8))) · \(context.files.count) file\(context.files.count == 1 ? "" : "s") · \(context.mode.replacingOccurrences(of: "_", with: " "))", systemImage: "folder.badge.gearshape")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentSuccess)
                    .lineLimit(2)

                Text(context.storagePolicy)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(2)

                ForEach(context.files.prefix(3)) { file in
                    HStack(spacing: 6) {
                        Image(systemName: file.kind == "directory" ? "folder" : "doc.text")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(file.safeToPreview ? AppColors.accentElectric : AppColors.textTertiary)

                        Text("\(file.key): \(file.displayName)")
                            .font(.caption2)
                            .foregroundStyle(file.safeToPreview ? AppColors.textSecondary : AppColors.textTertiary)
                            .lineLimit(1)

                        if let reason = file.reason, !reason.isEmpty {
                            Text(reason)
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                ForEach(context.toolRequests.prefix(2)) { request in
                    HStack(spacing: 6) {
                        Image(systemName: "hammer")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.accentWarning)

                        Text("\(request.toolName): \(request.status.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)

                        Text(request.instructionPreview)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)

                        if request.status == "waiting_for_human" || request.status == "queued" {
                            if viewModel.executingWorkspaceToolRunIds.contains(request.runId) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.6)
                                    .tint(AppColors.accentAgent)
                            } else {
                                Button("Execute") {
                                    viewModel.executeWorkspaceToolRequestFromChat(request)
                                }
                                .font(.caption2.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                }

                if context.files.isEmpty, let gap = context.gaps.first {
                    Text(gap)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
        } else if let error = viewModel.workspaceContextError {
            Label(error, systemImage: "folder.badge.questionmark")
                .font(.caption2)
                .foregroundStyle(AppColors.accentWarning)
        }
    }

    // MARK: - Compose Bar

    private var liveStatusBar: some View {
        let status = viewModel.liveChatStatus ?? ""
        return HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundColor(AppColors.accentElectric)
            Text(status)
                .font(.caption)
                .foregroundColor(AppColors.accentElectric)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.accentElectric.opacity(0.1))
    }

    private var ticketLiveStatusBar: some View {
        let status = viewModel.ticketLiveStatus ?? ""
        return HStack {
            Image(systemName: "text.badge.checkmark")
                .foregroundColor(AppColors.accentAgent)
            Text(status)
                .font(.caption)
                .foregroundColor(AppColors.accentAgent)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.accentAgent.opacity(0.1))
    }

    @ViewBuilder
    private var ticketContextBar: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.activeTicketId == nil ? "lock.open.display" : "checkmark.seal.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(viewModel.activeTicketId == nil ? AppColors.textTertiary : AppColors.accentSuccess)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.activeTicketId == nil ? viewModel.rosterBadgeText(for: agent) : "Attached to ORCA")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(ticketContextText)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Menu {
                ForEach(viewModel.availableDeliveryModes(for: agent), id: \.rawValue) { mode in
                    Button {
                        viewModel.selectedDeliveryMode = mode
                    } label: {
                        Label(mode.displayLabel, systemImage: deliveryIcon(for: mode))
                    }
                }
            } label: {
                Label(viewModel.selectedDeliveryMode.displayLabel, systemImage: deliveryIcon(for: viewModel.selectedDeliveryMode))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppColors.accentElectric.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chat delivery mode")

            if viewModel.currentChannelId(for: agent) != nil {
                Button {
                    viewModel.refreshCurrentChannel()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.accentElectric)
                        .frame(width: 28, height: 28)
                        .background(AppColors.accentElectric.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh ORCA chat channel")
            }

            if viewModel.activeTicketId != nil {
                Button {
                    viewModel.clearTicketContext()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Detach ORCA ticket")
            } else {
                Button {
                    showingAttachTicketSheet = true
                } label: {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach existing ORCA ticket")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(AppColors.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var ticketContextText: String {
        let channelText = viewModel.shortChannelId(for: agent).map { "ORCA channel \($0)" }
        if let id = viewModel.activeTicketId {
            if let title = viewModel.activeTicketTitle, !title.isEmpty {
                return [id, title, channelText].compactMap { $0 }.joined(separator: " · ")
            }
            return [id, channelText].compactMap { $0 }.joined(separator: " · ")
        }
        return [viewModel.rosterDetailText(for: agent), channelText, agent.boundaryText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var ticketContinuityBar: some View {
        if viewModel.activeTicketId != nil {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.accentAgent)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 5) {
                    if let continuity = viewModel.activeTicketContinuity {
                        HStack(spacing: 6) {
                            Text(continuity.statusLabel)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(continuity.ticket.status.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(continuity.ticket.status.color.opacity(0.10))
                                .clipShape(Capsule())

                            Text(continuity.priorityLabel)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(continuity.ticket.priority.color)

                            Text(continuity.evidenceLabel)
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary)

                            Spacer(minLength: 0)
                        }

                        Text(continuity.latestRunLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)

                        Text(continuity.latestActivityLabel)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)

                        Text(continuity.nextActionLabel)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)

                        agentRunCockpit(for: continuity)
                    } else if viewModel.isLoadingTicketContinuity {
                        HStack(spacing: Theme.xs) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading ORCA ticket continuity...")
                                .font(.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    } else {
                        Text(viewModel.ticketContinuityError ?? "ORCA ticket continuity has not loaded yet.")
                            .font(.caption)
                            .foregroundStyle(viewModel.ticketContinuityError == nil ? AppColors.textTertiary : AppColors.accentWarning)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    Task { await viewModel.refreshAttachedTicketContinuity() }
                } label: {
                    Image(systemName: viewModel.isLoadingTicketContinuity ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.accentAgent)
                        .frame(width: 28, height: 28)
                        .background(AppColors.accentAgent.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingTicketContinuity)
                .accessibilityLabel("Refresh attached ticket continuity")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(AppColors.backgroundPrimary)
            .overlay(
                Rectangle()
                    .fill(AppColors.border.opacity(0.7))
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }
    }

    private func agentRunCockpit(for continuity: DirectChatTicketContinuity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("\(continuity.sortedRuns.count) runs", systemImage: "bolt.badge.clock")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentAgent)

                if let approval = continuity.approvalLabel {
                    Label(approval, systemImage: approval.lowercased().contains("waiting") ? "person.badge.key" : "checkmark.seal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(approval.lowercased().contains("waiting") ? AppColors.accentWarning : AppColors.accentSuccess)
                }

                if let route = continuity.routePacketLabel, !route.isEmpty {
                    Label(route, systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            if continuity.sortedRuns.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("Attach an instruction, choose Agent Run, then send to dispatch this ticket.")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                }
            } else {
                VStack(spacing: 5) {
                    ForEach(continuity.sortedRuns.prefix(3)) { run in
                        agentRunMiniRow(run)
                    }
                }
            }
        }
        .padding(.top, 3)
    }

    private func agentRunMiniRow(_ run: AgentRun) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: run.status.icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(run.status.color)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(agentRunTitle(run))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if let detail = agentRunDetail(run) {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func agentRunTitle(_ run: AgentRun) -> String {
        let type = run.runType.replacingOccurrences(of: "_", with: " ").capitalized
        let worker = run.workerLane.map { " · \($0)" } ?? ""
        return "\(type) · \(run.status.label)\(worker)"
    }

    private func agentRunDetail(_ run: AgentRun) -> String? {
        let evidence = run.outcome?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? run.evidence?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? run.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let evidence, !evidence.isEmpty {
            return evidence
                .split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(2)
                .joined(separator: " ")
        }
        var parts: [String] = []
        if let policy = run.toolPolicy, !policy.isEmpty { parts.append(policy) }
        if let source = run.operationalSourceLabel { parts.append(source) }
        if let trace = run.traceId, !trace.isEmpty { parts.append("trace \(String(trace.prefix(8)))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var routeDecisionBar: some View {
        HStack(spacing: 8) {
            Label(routeDecisionTitle, systemImage: routeDecisionIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(routeDecisionColor)
                .lineLimit(1)

            Text(routeDecisionDetail)
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let preview = viewModel.latestTriagePreview {
                Button {
                    showingTriageSheet = true
                } label: {
                    Label(preview.riskLabel, systemImage: preview.needsApproval ? "person.badge.key" : "list.bullet.clipboard")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(preview.needsApproval ? AppColors.accentWarning : AppColors.accentAgent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((preview.needsApproval ? AppColors.accentWarning : AppColors.accentAgent).opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show Merman triage preview")
            }

            Button {
                viewModel.previewMermanTriage()
            } label: {
                Label("Merman", systemImage: viewModel.isPreviewingTriage ? "hourglass" : "scope")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.accentElectric.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPreviewingTriage)
            .accessibilityLabel("Preview Merman route")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(AppColors.backgroundPrimary)
        .overlay(
            Rectangle()
                .fill(AppColors.border.opacity(0.7))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var routeDecisionTitle: String {
        if let preview = viewModel.latestTriagePreview {
            return "Merman: \(preview.intentLabel)"
        }
        if agent.id == "chief" {
            return "Protected Chief lane"
        }
        switch viewModel.selectedDeliveryMode {
        case .compute:
            return "\(agent.name) compute persona"
        case .agentRun:
            return "ORCA Agent Run"
        case .liveInbox:
            return "\(agent.name) live inbox"
        case .auto:
            return "Schoolhouse auto route"
        case .fallback:
            return "Local guardrail fallback"
        case .system:
            return "System status"
        case .ticket:
            return "Ticket evidence"
        }
    }

    private var routeDecisionDetail: String {
        if let preview = viewModel.latestTriagePreview {
            let worker = preview.suggestedWorker.map { " · worker \($0)" } ?? ""
            return "\(preview.suggestedOwner) · \(preview.deliveryLabel) · \(preview.nextActionLabel)\(worker)"
        }
        if let triagePreviewError = viewModel.triagePreviewError {
            return triagePreviewError
        }
        if agent.id == "chief" {
            return "Read-only chat; Fund/trading changes require an ORCA ticket and approval."
        }
        switch viewModel.selectedDeliveryMode {
        case .compute:
            return "Fast compute-backed answer; not the live runtime or tool access."
        case .agentRun:
            return viewModel.activeTicketId == nil
                ? "Attach an ORCA ticket before starting a real Agent Run."
                : "Dispatches the attached ticket into Schoolhouse Agent Runs."
        case .liveInbox:
            return "Records in ORCA and waits for a live inbox reply."
        case .auto:
            return "Merman/Schoolhouse may choose compute, inbox, ticket, or protected review."
        case .fallback:
            return "Local guardrails only; not a real agent reply."
        case .system:
            return "Displays ORCA or Schoolhouse state."
        case .ticket:
            return "Adds durable context to the attached ORCA ticket."
        }
    }

    private var routeDecisionIcon: String {
        if let preview = viewModel.latestTriagePreview {
            if preview.needsApproval { return "person.badge.key" }
            if preview.needsTicket { return "text.badge.checkmark" }
            return "scope"
        }
        if agent.id == "chief" { return "lock.shield" }
        return deliveryIcon(for: viewModel.selectedDeliveryMode)
    }

    private var routeDecisionColor: Color {
        if let preview = viewModel.latestTriagePreview {
            if preview.needsApproval || preview.riskLevel.lowercased() == "protected" {
                return AppColors.accentWarning
            }
            if preview.needsTicket {
                return AppColors.accentAgent
            }
            return AppColors.accentElectric
        }
        if agent.id == "chief" { return AppColors.accentWarning }
        switch viewModel.selectedDeliveryMode {
        case .liveInbox, .ticket:
            return AppColors.accentSuccess
        case .agentRun:
            return AppColors.accentAgent
        case .compute, .auto, .system:
            return AppColors.accentElectric
        case .fallback:
            return AppColors.accentWarning
        }
    }

    private func deliveryIcon(for mode: DMDeliveryMode) -> String {
        switch mode {
        case .auto: return "arrow.triangle.branch"
        case .liveInbox: return "tray.full"
        case .compute: return "cpu"
        case .agentRun: return "bolt.badge.clock"
        case .fallback: return "exclamationmark.triangle"
        case .system: return "gearshape"
        case .ticket: return "text.badge.checkmark"
        }
    }

    private var composeBar: some View {
        HStack(spacing: 10) {
            Button {
                if viewModel.activeTicketId == nil {
                    showingTicketConfirmation = true
                } else {
                    viewModel.createTicketFromChat()
                }
            } label: {
                Image(systemName: viewModel.isCreatingTicket ? "hourglass.circle" : "text.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AppColors.accentAgent)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .disabled(viewModel.isCreatingTicket || viewModel.isStreaming)
            .accessibilityLabel(viewModel.activeTicketId == nil ? "Create ORCA ticket" : "Add ORCA ticket comment")

            TextField("Message \(agent.name)...", text: Binding(
                get: { viewModel.composedMessage },
                set: {
                    viewModel.composedMessage = $0
                    viewModel.latestTriagePreview = nil
                    viewModel.triagePreviewError = nil
                }
            ), axis: .vertical)
                .focused($isTextFieldFocused)
                .textFieldStyle(.plain)
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppColors.backgroundTertiary)
                .cornerRadius(20)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit {
                    viewModel.sendMessage()
                }

            Button {
                viewModel.sendMessage()
            } label: {
                Image(systemName: viewModel.isStreaming ? "hourglass.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(
                        viewModel.composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming
                        ? AppColors.textTertiary
                        : AppColors.accentElectric
                    )
            }
            .disabled(viewModel.isStreaming || !viewModel.canStartChat(with: agent) || viewModel.composedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

private struct TriagePreviewSheet: View {
    let preview: DirectChatTriagePreview

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Decision") {
                    labeledValue("Intent", preview.intentLabel)
                    labeledValue("Next action", preview.nextActionLabel)
                    labeledValue("Reason", preview.reason)
                }

                Section("Route") {
                    labeledValue("Owner", preview.suggestedOwner.capitalized)
                    labeledValue("Lane", preview.recommendedLane.capitalized)
                    labeledValue("Worker", preview.suggestedWorker ?? "None")
                    labeledValue("Delivery", preview.deliveryLabel)
                    labeledValue("Compute", preview.suggestedComputeRoute)
                }

                Section("Control") {
                    labeledValue("Risk", preview.riskLabel)
                    labeledValue("Needs ticket", preview.needsTicket ? "Yes" : "No")
                    labeledValue("Needs approval", preview.needsApproval ? "Yes" : "No")
                    labeledValue("Autonomy", preview.autonomyLevel)
                    if let approvalGate = preview.approvalGate, !approvalGate.isEmpty {
                        labeledValue("Approval gate", approvalGate)
                    }
                }

                if !preview.tags.isEmpty {
                    Section("Tags") {
                        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(preview.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppColors.accentElectric)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppColors.accentElectric.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let traceId = preview.traceId {
                    Section("Trace") {
                        Text(traceId)
                            .font(.caption2.monospaced())
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Merman Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppColors.textTertiary)
            Text(value.isEmpty ? "None" : value)
                .font(.caption)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RouteProgressStrip: View {
    let steps: [DirectChatProgressStep]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(steps) { step in
                    Label(step.title, systemImage: step.icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color(for: step.state))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(color(for: step.state).opacity(step.state == .pending ? 0.06 : 0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(color(for: step.state).opacity(step.state == .current ? 0.45 : 0.18), lineWidth: 1)
                        )
                        .accessibilityLabel("\(step.title): \(step.state.rawValue)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
        .background(AppColors.backgroundSecondary.opacity(0.7))
    }

    private func color(for state: DirectChatProgressStep.State) -> Color {
        switch state {
        case .pending:
            return AppColors.textTertiary
        case .current:
            return AppColors.accentElectric
        case .done:
            return AppColors.accentSuccess
        case .failed:
            return AppColors.accentWarning
        }
    }
}

// MARK: - Message Bubble

struct DMBubble: View {
    let message: DMMessage
    let agent: AgentInfo

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                // Agent avatar
                ZStack {
                    Circle()
                        .fill(Color(hexString: agent.color).opacity(0.2))
                        .frame(width: 30, height: 30)
                    Image(systemName: agent.icon)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hexString: agent.color))
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    HStack(spacing: 6) {
                        provenanceLabel
                        deliveryStateLabel
                    }
                }

                // Message content
                Text(displayContent)
                    .font(.body)
                    .foregroundColor(isUser ? .white : messageTextColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(bubbleBorderColor, lineWidth: isUser ? 0 : 1)
                    )
                    .opacity(message.isStreaming && message.content.isEmpty ? 0.6 : 1)

                // Streaming indicator
                if message.isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text(streamingStatusText)
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                // Metadata
                if !message.isStreaming, let metadataText {
                    Text(metadataText)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }

                if !message.isStreaming, let traceId = message.traceId, !traceId.isEmpty {
                    Label(Self.shortTraceLabel(traceId), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                        .accessibilityLabel("Trace \(traceId)")
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var metadataText: String? {
        var parts: [String] = []
        if let model = message.modelUsed, !model.isEmpty {
            parts.append(model)
        }
        if let deliveryMode = DMDeliveryMode.parse(message.deliveryMode) {
            parts.append(deliveryMode.displayLabel)
        }
        if let lane = message.lane, !lane.isEmpty {
            parts.append(lane)
        }
        if let ms = message.latencyMs {
            parts.append("\(ms)ms")
        }
        if let tokens = message.tokenCount {
            parts.append("\(tokens)t")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var displayContent: String {
        if !message.content.isEmpty { return message.content }
        switch deliveryState {
        case .computeRunning:
            return "Waiting for the compute persona answer..."
        case .agentRunQueued:
            return "Agent Run queued in ORCA..."
        case .agentRunRunning:
            return "Agent Run is running in ORCA..."
        case .waitingForLiveAgent:
            return "Waiting for the live inbox reply..."
        default:
            return message.isStreaming ? "Routing through ORCA..." : ""
        }
    }

    private var streamingStatusText: String {
        switch deliveryState {
        case .computeRunning:
            return "Compute persona accepted."
        case .agentRunQueued:
            return "Agent Run queued."
        case .agentRunRunning:
            return "Agent Run running."
        case .waitingForLiveAgent:
            return "Live inbox acknowledged."
        default:
            return message.content.isEmpty ? "Routing through ORCA." : "Receiving..."
        }
    }

    private static func shortTraceLabel(_ traceId: String) -> String {
        let trimmed = traceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 18 else { return trimmed }
        return "\(trimmed.prefix(10))...\(trimmed.suffix(6))"
    }

    @ViewBuilder
    private var provenanceLabel: some View {
        Label(provenance.displayLabel, systemImage: provenanceIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(provenanceColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(provenanceColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Response provenance: \(provenance.displayLabel)")
    }

    private var provenance: DMResponseProvenance {
        if let value = DMResponseProvenance.parse(message.provenance) {
            return value
        }
        return DMResponseProvenance(deliveryMode: message.deliveryMode, source: message.source, lane: message.lane)
    }

    @ViewBuilder
    private var deliveryStateLabel: some View {
        if let deliveryState {
            Label(deliveryState.displayLabel, systemImage: deliveryStateIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(deliveryStateColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(deliveryStateColor.opacity(0.12))
                .clipShape(Capsule())
                .accessibilityLabel("Delivery state: \(deliveryState.displayLabel)")
        }
    }

    private var deliveryState: DMDeliveryState? {
        DMDeliveryState.parse(message.deliveryState)
    }

    private var deliveryStateIcon: String {
        switch deliveryState {
        case .sending: return "paperplane"
        case .routing: return "arrow.triangle.branch"
        case .computeRunning: return "cpu"
        case .agentRunQueued: return "bolt.badge.clock"
        case .agentRunRunning: return "bolt.circle.fill"
        case .waitingForLiveAgent: return "hourglass"
        case .claimedByAgent: return "hand.raised"
        case .responseReceived: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .fallbackPresented: return "exclamationmark.triangle"
        case .timedOut: return "clock.badge.exclamationmark"
        case nil: return "circle"
        }
    }

    private var deliveryStateColor: Color {
        switch deliveryState {
        case .sending, .routing, .computeRunning, .agentRunQueued, .agentRunRunning, .waitingForLiveAgent, .claimedByAgent:
            return AppColors.accentElectric
        case .responseReceived:
            return AppColors.accentSuccess
        case .failed, .fallbackPresented, .timedOut:
            return AppColors.accentWarning
        case nil:
            return AppColors.textTertiary
        }
    }

    private var provenanceIcon: String {
        switch provenance {
        case .liveInbox: return "tray.full"
        case .compute: return "cpu"
        case .agentRun: return "bolt.badge.clock"
        case .fallback: return "exclamationmark.triangle"
        case .system: return "gearshape"
        case .ticket: return "text.badge.checkmark"
        case .protected: return "lock.shield"
        }
    }

    private var provenanceColor: Color {
        switch provenance {
        case .liveInbox: return AppColors.accentSuccess
        case .compute: return AppColors.accentElectric
        case .agentRun: return AppColors.accentAgent
        case .fallback: return AppColors.accentWarning
        case .system: return AppColors.textTertiary
        case .ticket: return AppColors.accentAgent
        case .protected: return AppColors.accentWarning
        }
    }

    private var bubbleBackground: Color {
        if isUser { return AppColors.accentElectric }
        switch provenance {
        case .fallback:
            return AppColors.accentWarning.opacity(0.10)
        case .ticket:
            return AppColors.accentAgent.opacity(0.10)
        case .system:
            return AppColors.backgroundSecondary
        case .protected:
            return AppColors.accentWarning.opacity(0.10)
        case .liveInbox, .compute:
            return AppColors.backgroundTertiary
        case .agentRun:
            return AppColors.accentAgent.opacity(0.10)
        }
    }

    private var bubbleBorderColor: Color {
        switch provenance {
        case .fallback:
            return AppColors.accentWarning.opacity(0.45)
        case .ticket:
            return AppColors.accentAgent.opacity(0.35)
        case .system:
            return AppColors.borderActive
        case .protected:
            return AppColors.accentWarning.opacity(0.45)
        case .liveInbox, .compute:
            return AppColors.border
        case .agentRun:
            return AppColors.accentAgent.opacity(0.35)
        }
    }

    private var messageTextColor: Color {
        provenance == .fallback || provenance == .protected ? AppColors.accentWarning : AppColors.textPrimary
    }
}

// MARK: - Preview

#Preview {
    DirectChatView(viewModel: DirectChatViewModel())
        .modelContainer(for: [DMConversation.self, DMMessage.self], inMemory: true)
}
