import SwiftUI

// MARK: - Agent Detail Sheet

struct AgentDetailSheet: View {

    let agent: Agent
    var onViewLogs: (() -> Void)?
    var onStatusChanged: ((AgentState) -> Void)?
    var onPause: (() -> Void)?
    var onRestart: (() -> Void)?
    var onStartChat: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: AgentState
    @State private var showingPauseConfirmation = false
    @State private var showingRestartConfirmation = false
    @State private var showingConfigureSheet = false
    @State private var showingSendMessage = false
    @State private var workNoteText = ""
    @State private var workNotes: [AgentWorkNoteDTO] = []
    @State private var isLoadingWorkNotes = false
    @State private var isPostingWorkNote = false
    @State private var workNoteError: String?
    @State private var responsibility: AgentResponsibilityDetailDTO?
    @State private var isLoadingResponsibility = false
    @State private var responsibilityError: String?
    @State private var activationContext: AgentActivationContextDTO?
    @State private var isLoadingActivationContext = false
    @State private var activationContextError: String?

    // POD-5 (c797ada1): non-destructive inbox tail, fetched on appear.
    @State private var inboxTail: InboxTailDTO?

    init(
        agent: Agent,
        onViewLogs: (() -> Void)? = nil,
        onStatusChanged: ((AgentState) -> Void)? = nil,
        onPause: (() -> Void)? = nil,
        onRestart: (() -> Void)? = nil,
        onStartChat: (() -> Void)? = nil
    ) {
        self.agent = agent
        self.onViewLogs = onViewLogs
        self.onStatusChanged = onStatusChanged
        self.onPause = onPause
        self.onRestart = onRestart
        self.onStartChat = onStartChat
        _selectedStatus = State(initialValue: agent.status)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    headerSection
                    rosterPolicySection
                    responsibilitySection
                    activationContextSection
                    workNotesSection
                    inboxSection                  // POD-5 (c797ada1)
                    statusSection
                    currentTaskSection
                    skillsSection
                    actionsSection
                }
                .padding(.horizontal, Theme.md)
                .padding(.bottom, Theme.xxl)
                .task {
                    await loadInboxTail()
                    await loadResponsibility()
                    await loadActivationContext()
                    await loadWorkNotes()
                }
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle(agent.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.accentElectric)
                }
            }
            .confirmationDialog(
                "Pause Agent",
                isPresented: $showingPauseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Pause \(agent.name)", role: .destructive) {
                    onPause?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(agent.name) will stop processing tasks until manually resumed.")
            }
            .confirmationDialog(
                "Restart Agent",
                isPresented: $showingRestartConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restart \(agent.name)", role: .destructive) {
                    onRestart?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will terminate the current session and start a fresh instance.")
            }
            .sheet(isPresented: $showingConfigureSheet) {
                AgentConfigureSheet(agent: agent)
            }
            .sheet(isPresented: $showingSendMessage) {
                ComposeMessageSheet(recipientName: agent.name)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: Theme.md) {
            // Large avatar with status ring
            ZStack {
                Circle()
                    .fill(agent.status.color.opacity(0.15))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(agent.status.color)
                    .frame(width: 92, height: 92)

                Circle()
                    .fill(Color(hexString: agent.avatarColor ?? "3B82F6"))
                    .frame(width: 88, height: 88)

                Text(agent.name.prefix(1).uppercased())
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                // Status ring indicator
                Circle()
                    .strokeBorder(agent.status.color, lineWidth: 3)
                    .frame(width: 100, height: 100)
            }

            VStack(spacing: Theme.xxs) {
                Text(agent.name)
                    .podTextStyle(.title1, color: AppColors.textPrimary)

                Text(agent.role)
                    .podTextStyle(.body, color: AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.md)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Status")

            VStack(spacing: 0) {
                ForEach(AgentState.allCases, id: \.self) { status in
                    statusRow(status)

                    if status != AgentState.allCases.last {
                        Divider()
                            .background(AppColors.border)
                    }
                }
            }
            .podCard()
        }
        .disabled(AgentRosterPolicy.isDormantOrArchived(agent))
        .opacity(AgentRosterPolicy.isDormantOrArchived(agent) ? 0.55 : 1)
    }

    private func statusRow(_ status: AgentState) -> some View {
        HStack {
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)

            Text(status.displayName)
                .podTextStyle(.body, color: AppColors.textPrimary)

            Spacer()

            if selectedStatus == status {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentElectric)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedStatus = status
            onStatusChanged?(status)
        }
        .padding(Theme.md)
    }

    // MARK: - Current Task Section

    private var currentTaskSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Current Task")

            if let task = agent.currentTask {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.accentWarning)

                    Text(task)
                        .podTextStyle(.body, color: AppColors.textPrimary)

                    Spacer()
                }
                .padding(Theme.md)
                .podCard()
            } else {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.accentSuccess)

                    Text("No active task")
                        .podTextStyle(.body, color: AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.md)
                .podCard()
            }
        }
    }

    // MARK: - Skills Section

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Skills", count: agent.skills.count)

            if agent.skills.isEmpty {
                Text("No skills configured")
                    .podTextStyle(.body, color: AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.md)
                    .podCard()
            } else {
                AgentDetailFlowLayout(spacing: Theme.xs) {
                    ForEach(agent.skills, id: \.self) { skill in
                        Text(skill)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.accentAgent)
                            .padding(.horizontal, Theme.sm)
                            .padding(.vertical, Theme.xxs)
                            .background(AppColors.accentAgent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(Theme.md)
                .podCard()
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: Theme.sm) {
            // Primary actions
            if AgentRosterPolicy.isDormantOrArchived(agent) {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(AppColors.accentWarning)
                    Text("Archived agents are inspectable here, but new chat and runtime control are routed through active owners.")
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                    Spacer()
                }
                .padding(Theme.md)
                .background(AppColors.accentWarning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else {
                actionButton(
                    icon: "bubble.left.fill",
                    label: "Chat",
                    color: AppColors.accentElectric
                ) {
                    dismiss()
                    onStartChat?()
                }
            }

            actionButton(
                icon: "doc.text.fill",
                label: "View Logs",
                color: AppColors.textSecondary
            ) {
                onViewLogs?()
            }

            Divider()
                .background(AppColors.border)

            // Status control actions
            if !AgentRosterPolicy.isDormantOrArchived(agent) {
                HStack(spacing: Theme.sm) {
                    actionButton(
                        icon: "pause.circle.fill",
                        label: "Pause Agent",
                        color: AppColors.accentWarning,
                        isDestructive: true
                    ) {
                        showingPauseConfirmation = true
                    }

                    actionButton(
                        icon: "arrow.clockwise.circle.fill",
                        label: "Restart Agent",
                        color: AppColors.accentDanger,
                        isDestructive: true
                    ) {
                        showingRestartConfirmation = true
                    }
                }

                actionButton(
                    icon: "gearshape.fill",
                    label: "Configure",
                    color: AppColors.textSecondary
                ) {
                    showingConfigureSheet = true
                }
            }
        }
    }

    private var rosterPolicySection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Roster")

            VStack(alignment: .leading, spacing: Theme.sm) {
                HStack(spacing: Theme.xs) {
                    Label(agent.rosterLane.label, systemImage: AgentRosterPolicy.isDormantOrArchived(agent) ? "archivebox.fill" : "person.crop.circle.badge.checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AgentRosterPolicy.isDormantOrArchived(agent) ? AppColors.accentWarning : AppColors.accentSuccess)

                    Spacer()

                    Text(agent.isDefaultRoutingEnabled ? "Routing on" : "Routing off")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(agent.isDefaultRoutingEnabled ? AppColors.accentSuccess : AppColors.accentWarning)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((agent.isDefaultRoutingEnabled ? AppColors.accentSuccess : AppColors.accentWarning).opacity(0.12))
                        .clipShape(Capsule())
                }

                if let state = agent.quarantineState, !state.isEmpty {
                    Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                }

                if let note = agent.rosterNote, !note.isEmpty {
                    Text(note)
                        .podTextStyle(.body, color: AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.md)
            .podCard()
        }
    }

    private var workNotesSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Work Notes", count: workNotes.count)

            VStack(alignment: .leading, spacing: Theme.sm) {
                TextEditor(text: $workNoteText)
                    .frame(minHeight: 88)
                    .scrollContentBackground(.hidden)
                    .background(AppColors.backgroundPrimary)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(Theme.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .strokeBorder(AppColors.border, lineWidth: 1)
                    )

                if let workNoteError {
                    Text(workNoteError)
                        .podTextStyle(.caption, color: AppColors.accentDanger)
                }

                Button {
                    Task { await postWorkNote() }
                } label: {
                    HStack(spacing: Theme.xs) {
                        if isPostingWorkNote {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text("Add Note")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.sm)
                    .foregroundStyle(.white)
                    .background(canPostWorkNote ? AppColors.accentElectric : AppColors.textMuted)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
                .disabled(!canPostWorkNote || isPostingWorkNote)

                if isLoadingWorkNotes && workNotes.isEmpty {
                    HStack(spacing: Theme.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading notes…")
                            .podTextStyle(.body, color: AppColors.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, Theme.xs)
                } else if workNotes.isEmpty {
                    Text("No work notes")
                        .podTextStyle(.body, color: AppColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.xs)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(workNotes.prefix(5).enumerated()), id: \.element.id) { index, note in
                            workNoteRow(note)
                            if index < min(workNotes.count, 5) - 1 {
                                Divider().background(AppColors.border)
                            }
                        }
                    }
                }
            }
            .padding(Theme.md)
            .podCard()
        }
    }

    private var responsibilitySection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Direction")

            VStack(alignment: .leading, spacing: Theme.sm) {
                if isLoadingResponsibility && responsibility == nil {
                    HStack(spacing: Theme.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading ORCA direction…")
                            .podTextStyle(.body, color: AppColors.textTertiary)
                        Spacer()
                    }
                } else if let responsibility {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        HStack(spacing: Theme.xs) {
                            Label(responsibility.profile.title ?? agent.role, systemImage: "signpost.right.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.accentElectric)
                            Spacer()
                            if let worker = responsibility.profile.defaultWorkerLane, !worker.isEmpty {
                                Text("Worker: \(worker)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppColors.accentAgent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(AppColors.accentAgent.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        if let summary = responsibility.profile.summary, !summary.isEmpty {
                            Text(summary)
                                .podTextStyle(.body, color: AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !responsibility.profile.owns.isEmpty {
                            AgentDetailFlowLayout(spacing: Theme.xs) {
                                ForEach(responsibility.profile.owns.prefix(8), id: \.self) { domain in
                                    Text(domain.replacingOccurrences(of: "_", with: " "))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .padding(.horizontal, Theme.sm)
                                        .padding(.vertical, Theme.xxs)
                                        .background(AppColors.backgroundTertiary)
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        if !responsibility.domains.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.xs) {
                                Text("Domain routes")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.textTertiary)

                                ForEach(responsibility.sortedDomainRoutes.prefix(5)) { route in
                                    AgentResponsibilityRouteRow(route: route)
                                }
                            }
                            .padding(.top, Theme.xs)
                        }

                        if !responsibility.profile.protectedDomains.isEmpty {
                            Label("Protected: \(responsibility.profile.protectedDomains.joined(separator: ", "))", systemImage: "lock.shield.fill")
                                .font(.caption)
                                .foregroundStyle(AppColors.accentWarning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let note = responsibility.profile.approvalNotes.first, !note.isEmpty {
                            Text(note)
                                .podTextStyle(.caption, color: AppColors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text(responsibilityError ?? "No ORCA direction profile")
                        .podTextStyle(.body, color: AppColors.textTertiary)
                }
            }
            .padding(Theme.md)
            .podCard()
        }
    }

    private var canPostWorkNote: Bool {
        !workNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activationContextSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Activation Context", count: activationContext?.packet.contextVersion)

            VStack(alignment: .leading, spacing: Theme.sm) {
                if isLoadingActivationContext && activationContext == nil {
                    HStack(spacing: Theme.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading wake packet…")
                            .podTextStyle(.body, color: AppColors.textTertiary)
                        Spacer()
                    }
                } else if let context = activationContext {
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        HStack(spacing: Theme.sm) {
                            activationMetric(
                                "Tickets",
                                value: "\(context.work.assignedTicketCount)",
                                icon: "ticket.fill",
                                color: AppColors.accentElectric
                            )
                            activationMetric(
                                "Review",
                                value: "\(context.reviewQueues.agentReviewRequiredCount)/\(context.reviewQueues.globalReviewRequiredCount)",
                                icon: "checklist.checked",
                                color: context.reviewQueues.globalReviewRequiredCount > 0 ? AppColors.accentWarning : AppColors.accentSuccess
                            )
                            activationMetric(
                                "Notes",
                                value: "\(context.notes.recentWorkNotes.count)",
                                icon: "note.text",
                                color: AppColors.accentAgent
                            )
                        }

                        activationList(
                            title: "Start Docs",
                            icon: "doc.text.magnifyingglass",
                            items: context.startHere.docs,
                            limit: 3
                        )

                        activationList(
                            title: "Manual Checks",
                            icon: "list.bullet.clipboard",
                            items: context.startHere.manualChecks,
                            limit: 3
                        )

                        if context.packet.computePolicy != nil || context.startHere.intelligenceEndpoints?.isEmpty == false {
                            activationIntelligenceSection(context)
                        }

                        if !context.guardrails.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.xs) {
                                Text("Guardrails")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.textTertiary)

                                ForEach(Array(context.guardrails.prefix(4)), id: \.self) { guardrail in
                                    Label(guardrail, systemImage: "lock.shield.fill")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.top, Theme.xs)
                        }

                        if let source = context.packet.source {
                            Text(source)
                                .podTextStyle(.label, color: AppColors.textTertiary)
                        }
                    }
                } else {
                    Text(activationContextError ?? "Activation context unavailable")
                        .podTextStyle(.body, color: AppColors.textTertiary)
                }
            }
            .padding(Theme.md)
            .podCard()
        }
    }

    private func activationMetric(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.xxs) {
            Label(label, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func activationIntelligenceSection(_ context: AgentActivationContextDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Label("Compute & Intelligence", systemImage: "cpu.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)

            if let policy = context.packet.computePolicy {
                VStack(alignment: .leading, spacing: 3) {
                    activationMetadataRow("Default tag", value: policy.defaultTag)
                    activationMetadataRow("Path", value: policy.workflowComputePath ?? policy.path ?? policy.daemonComputePath)
                    activationMetadataRow("Intel", value: policy.intelligencePath)
                    activationMetadataRow("Policy", value: policy.source ?? policy.caller ?? policy.lane)
                }
                .padding(Theme.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            if let endpoints = context.startHere.intelligenceEndpoints, !endpoints.isEmpty {
                AgentDetailFlowLayout(spacing: Theme.xs) {
                    ForEach(Array(endpoints.prefix(6))) { endpoint in
                        Text(endpoint.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.accentAgent)
                            .lineLimit(1)
                            .padding(.horizontal, Theme.sm)
                            .padding(.vertical, Theme.xxs)
                            .background(AppColors.accentAgent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.top, Theme.xs)
    }

    private func activationMetadataRow(_ label: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.xs) {
            Text(label)
                .podTextStyle(.label, color: AppColors.textTertiary)
                .frame(width: 72, alignment: .leading)

            Text(activationMetadataValue(value))
                .podTextStyle(.caption, color: value?.isEmpty == false ? AppColors.textSecondary : AppColors.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private func activationMetadataValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "Not listed" }
        return value
    }

    private func activationList(title: String, icon: String, items: [String], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)

            if items.isEmpty {
                Text("None listed")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
            } else {
                ForEach(Array(items.prefix(limit)), id: \.self) { item in
                    Text(item)
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func workNoteRow(_ note: AgentWorkNoteDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.xxs) {
            HStack(spacing: Theme.xs) {
                Text(note.source ?? "orca.notes.agent")
                    .podTextStyle(.label, color: AppColors.textTertiary)
                Spacer()
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .podTextStyle(.label, color: AppColors.textTertiary)
            }

            Text(note.title)
                .podTextStyle(.caption, color: AppColors.textPrimary)
                .fontWeight(.semibold)

            Text(note.message)
                .podTextStyle(.body, color: AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if note.signState?.isEmpty == false || note.owner?.isEmpty == false || note.reviewer?.isEmpty == false || note.traceId?.isEmpty == false {
                HStack(spacing: Theme.xs) {
                    if let signState = note.signState, !signState.isEmpty {
                        workNoteChip(signState.replacingOccurrences(of: "_", with: " "), icon: "signature")
                    }

                    if let owner = note.owner, !owner.isEmpty {
                        workNoteChip(owner, icon: "person.crop.circle")
                    }

                    if let reviewer = note.reviewer, !reviewer.isEmpty {
                        workNoteChip(reviewer, icon: "person.crop.circle.badge.checkmark")
                    }

                    if let traceId = note.traceId, !traceId.isEmpty {
                        workNoteChip(traceId, icon: "point.3.connected.trianglepath.dotted")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.sm)
    }

    private func workNoteChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }

    private func actionButton(
        icon: String,
        label: String,
        color: Color,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)

                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isDestructive ? color : AppColors.textPrimary)

                Spacer()

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .padding(Theme.md)
            .background(isDestructive ? color.opacity(0.08) : AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(isDestructive ? color.opacity(0.2) : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inbox Section (POD-5 / M-042 W21)
    //
    // Renders the agent's NATS inbox tail via the live backend contract
    // (GET /api/v1/agents/{name}/inbox-tail?limit=N — M-036 + M-042 backend).
    // Fetched once on appear via .task; non-destructive read.

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Inbox", count: inboxTail?.unreadEntries)

            if let tail = inboxTail {
                VStack(spacing: 0) {
                    if tail.recent.isEmpty {
                        Text(tail.exists ? "No messages" : "Inbox not yet present")
                            .podTextStyle(.body, color: AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.md)
                    } else {
                        let rows = Array(tail.recent.reversed().prefix(5))
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, entry in
                            inboxEntryRow(entry)
                            if idx < rows.count - 1 {
                                Divider().background(AppColors.border)
                            }
                        }
                    }
                }
                .podCard()
            } else {
                HStack(spacing: Theme.sm) {
                    ProgressView().controlSize(.small)
                    Text("Loading inbox…")
                        .podTextStyle(.body, color: AppColors.textTertiary)
                    Spacer()
                }
                .padding(Theme.md)
                .podCard()
            }
        }
    }

    private func inboxEntryRow(_ entry: InboxTailEntryDTO) -> some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            Circle()
                .fill(entry.isUnread ? AppColors.accentElectric : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.from)
                        .podTextStyle(.label, color: AppColors.textPrimary)
                    Spacer()
                    Text(entry.type)
                        .podTextStyle(.label, color: AppColors.textTertiary)
                }
                Text(entry.displayTitle)
                    .podTextStyle(.body, color: AppColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(Theme.md)
    }

    // MARK: - Data Loading

    private func loadInboxTail() async {
        let name = agent.name.lowercased()
        do {
            let dto: InboxTailDTO = try await APIClient.shared.request(
                .agentInboxTail(name: name, limit: 20)
            )
            await MainActor.run { self.inboxTail = dto }
        } catch {
            // Soft-fail (mirrors AgentsViewModel.loadInboxTail): inbox may not
            // be present yet or backend unreachable. UI shows the
            // "Inbox not yet present" / loading branch — no user-surfaced error.
        }
    }

    private func loadWorkNotes() async {
        await MainActor.run {
            isLoadingWorkNotes = true
            workNoteError = nil
        }
        do {
            let notes: [AgentWorkNoteDTO] = try await APIClient.shared.get(
                path: "/api/v1/notes/agents/\(agent.apiPathComponent)?limit=20"
            )
            await MainActor.run {
                self.workNotes = notes
                self.isLoadingWorkNotes = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingWorkNotes = false
                self.workNoteError = "Notes unavailable"
            }
        }
    }

    private func loadResponsibility() async {
        await MainActor.run {
            isLoadingResponsibility = true
            responsibilityError = nil
        }
        do {
            let dto: AgentResponsibilityDetailDTO = try await APIClient.shared.get(
                path: "/api/v1/agent-responsibilities/agents/\(agent.apiPathComponent)"
            )
            await MainActor.run {
                self.responsibility = dto
                self.isLoadingResponsibility = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingResponsibility = false
                self.responsibilityError = "ORCA direction unavailable"
            }
        }
    }

    private func loadActivationContext() async {
        await MainActor.run {
            isLoadingActivationContext = true
            activationContextError = nil
        }
        do {
            let dto: AgentActivationContextDTO = try await APIClient.shared.request(
                .agentActivationContext(name: agent.apiPathComponent, limit: 10)
            )
            await MainActor.run {
                self.activationContext = dto
                self.isLoadingActivationContext = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingActivationContext = false
                self.activationContextError = "Activation context unavailable"
            }
        }
    }

    private func postWorkNote() async {
        let note = workNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }
        await MainActor.run {
            isPostingWorkNote = true
            workNoteError = nil
        }

        do {
            let body = AgentWorkNoteCreateBody(
                targetType: "agent",
                targetId: nil,
                noteType: "work_note",
                title: "Pod work note",
                body: note,
                tags: ["pod", "agent-work-note", AgentRosterPolicy.normalizedName(agent.name)],
                traceId: "pod-agent-note-\(agent.name.lowercased())-\(Int(Date().timeIntervalSince1970))",
                source: "pod.agents.work_note",
                owner: AgentRosterPolicy.normalizedName(agent.name),
                reviewer: "aloha",
                signState: "draft"
            )
            let created: AgentWorkNoteDTO = try await APIClient.shared.post(
                path: "/api/v1/notes/agents/\(agent.apiPathComponent)",
                body: body
            )
            await MainActor.run {
                self.workNotes.insert(created, at: 0)
                self.workNoteText = ""
                self.isPostingWorkNote = false
            }
        } catch {
            await MainActor.run {
                self.workNoteError = "Couldn't save note"
                self.isPostingWorkNote = false
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

}

private struct AgentWorkNoteDTO: Identifiable, Decodable {
    let id: String
    let targetType: String
    let targetId: String?
    let noteType: String
    let title: String
    let body: String
    let tags: [String]?
    let createdBy: String?
    let traceId: String?
    let source: String?
    let owner: String?
    let reviewer: String?
    let signState: String?
    let createdAt: Date
    let updatedAt: Date

    var message: String { body }

    enum CodingKeys: String, CodingKey {
        case id, title, body, tags, source, owner, reviewer
        case targetType = "target_type"
        case targetId = "target_id"
        case noteType = "note_type"
        case createdBy = "created_by"
        case traceId = "trace_id"
        case signState = "sign_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct AgentWorkNoteCreateBody: Encodable {
    let targetType: String
    let targetId: String?
    let noteType: String
    let title: String
    let body: String
    let tags: [String]
    let traceId: String
    let source: String
    let owner: String
    let reviewer: String
    let signState: String

    enum CodingKeys: String, CodingKey {
        case title, body, tags, source, owner, reviewer
        case targetType = "target_type"
        case targetId = "target_id"
        case noteType = "note_type"
        case traceId = "trace_id"
        case signState = "sign_state"
    }
}

private struct AgentResponsibilityDetailDTO: Decodable {
    let agent: String
    let profile: AgentResponsibilityProfileDTO
    let domains: [String: AgentResponsibilityDomainDTO]

    var sortedDomainRoutes: [AgentResponsibilityRoute] {
        domains
            .map {
                AgentResponsibilityRoute(
                    domain: $0.key,
                    primary: $0.value.primary,
                    fallback: $0.value.fallback,
                    scope: $0.value.scope,
                    note: $0.value.note
                )
            }
            .sorted { $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending }
    }
}

private struct AgentResponsibilityRoute: Identifiable, Hashable {
    let domain: String
    let primary: String?
    let fallback: String?
    let scope: String?
    let note: String?

    var id: String { domain }
}

private struct AgentResponsibilityRouteRow: View {
    let route: AgentResponsibilityRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.xs) {
                Text(route.domain.replacingOccurrences(of: "_", with: " "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: Theme.xs)

                if let primary = route.primary, !primary.isEmpty {
                    Text(primary)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentElectric)
                        .lineLimit(1)
                }
            }

            if let scope = route.scope, !scope.isEmpty {
                Text(scope)
                    .podTextStyle(.caption, color: AppColors.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: Theme.xs) {
                if let fallback = route.fallback, !fallback.isEmpty {
                    Label(fallback, systemImage: "arrow.triangle.2.circlepath")
                }
                if let note = route.note, !note.isEmpty {
                    Label(note, systemImage: "info.circle")
                }
            }
            .font(.caption2)
            .foregroundStyle(AppColors.textTertiary)
            .lineLimit(1)
        }
        .padding(Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

private struct AgentResponsibilityProfileDTO: Decodable {
    let rosterLane: String?
    let defaultRoutingEnabled: Bool?
    let title: String?
    let summary: String?
    let owns: [String]
    let defaultWorkerLane: String?
    let protectedDomains: [String]
    let approvalNotes: [String]

    enum CodingKeys: String, CodingKey {
        case rosterLane = "roster_lane"
        case defaultRoutingEnabled = "default_routing_enabled"
        case title
        case summary
        case owns
        case defaultWorkerLane = "default_worker_lane"
        case protectedDomains = "protected_domains"
        case approvalNotes = "approval_notes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rosterLane = try container.decodeIfPresent(String.self, forKey: .rosterLane)
        defaultRoutingEnabled = try container.decodeIfPresent(Bool.self, forKey: .defaultRoutingEnabled)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        owns = try container.decodeIfPresent([String].self, forKey: .owns) ?? []
        defaultWorkerLane = try container.decodeIfPresent(String.self, forKey: .defaultWorkerLane)
        protectedDomains = try container.decodeIfPresent([String].self, forKey: .protectedDomains) ?? []
        approvalNotes = try container.decodeIfPresent([String].self, forKey: .approvalNotes) ?? []
    }
}

private struct AgentResponsibilityDomainDTO: Decodable {
    let primary: String?
    let fallback: String?
    let scope: String?
    let note: String?
}

private extension Agent {
    var apiPathComponent: String {
        name
            .lowercased()
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name.lowercased()
    }
}

// MARK: - Flow Layout

struct AgentDetailFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Agent Configure Sheet

struct AgentConfigureSheet: View {
    let agent: Agent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    LabeledContent("Name", value: agent.name)
                    LabeledContent("Role", value: agent.role)
                    LabeledContent("Model", value: "gpt-4o")
                }

                Section("Capabilities") {
                    ForEach(agent.skills, id: \.self) { skill in
                        Text(skill)
                    }
                }
            }
            .navigationTitle("Configure \(agent.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Compose Message Sheet

struct ComposeMessageSheet: View {
    let recipientName: String
    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: Theme.sm) {
                    Text("To:")
                        .podTextStyle(.body, color: AppColors.textSecondary)
                    Text(recipientName)
                        .podTextStyle(.body, color: AppColors.textPrimary)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.md)
                .background(AppColors.backgroundSecondary)

                TextEditor(text: $messageText)
                    .scrollContentBackground(.hidden)
                    .background(AppColors.backgroundPrimary)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(Theme.md)

                Spacer()
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        // TODO: Send via API
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.accentElectric)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
