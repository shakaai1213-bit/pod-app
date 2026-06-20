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
    @State private var lockerData: AgentLockerDTO?
    @State private var isLoadingLocker = false
    @State private var lockerError: String?
    @State private var plannerNewTitle = ""
    @State private var plannerNewBody = ""
    @State private var plannerNewLane = "now"
    @State private var plannerNewPriority = "medium"
    @State private var plannerWriteItemId: String?
    @State private var plannerWriteError: String?
    @State private var plannerEditDraft: PlannerItemEditDraft?
    @State private var lockerFeedbackText = ""
    @State private var lockerFeedbackRating: String? = nil
    @State private var lockerFeedbackPanel: String = "classroom"
    @State private var lockerFeedbackAttachSnapshot: Bool = false
    @State private var isPostingLockerFeedback = false
    @State private var lockerFeedbackMessage: String?
    @State private var selectedLockerTab: AgentLockerTab = .card
    @State private var memoryCandidateNote = ""
    @State private var isPostingMemoryCandidate = false
    @State private var memoryCandidateMessage: String?
    @State private var isRuntimeExpanded = false

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
                    lockerSection
                    responsibilitySection
                    activationContextSection
                    runtimeSection
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
                    await loadLocker()
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
                ComposeMessageSheet(agent: agent.directChatAgentInfo)
            }
            .sheet(item: $plannerEditDraft) { draft in
                plannerEditSheet(draft)
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
                HStack(spacing: Theme.sm) {
                    actionButton(
                        icon: "bubble.left.fill",
                        label: "Chat",
                        color: AppColors.accentElectric
                    ) {
                        dismiss()
                        onStartChat?()
                    }

                    actionButton(
                        icon: "tray.and.arrow.down.fill",
                        label: "Message",
                        color: AppColors.accentAgent
                    ) {
                        showingSendMessage = true
                    }
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

    private var canPostLockerFeedback: Bool {
        !lockerFeedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lockerSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Locker", count: lockerData?.planner.counts.now)

            VStack(alignment: .leading, spacing: Theme.sm) {
                if isLoadingLocker && lockerData == nil {
                    HStack(spacing: Theme.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading locker…")
                            .podTextStyle(.body, color: AppColors.textTertiary)
                        Spacer()
                    }
                } else if let locker = lockerData {
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        agentStatusBand(locker)
                        lockerCockpitTabs

                        switch selectedLockerTab {
                        case .card:
                            lockerCardTab(locker)
                        case .dashboard:
                            lockerRoleDashboardTab(locker)
                        case .classroom:
                            lockerClassroomTab(locker)
                        case .planner:
                            lockerPlannerTab(locker)
                        case .inbox:
                            lockerInboxTab(locker)
                        case .chat:
                            lockerChatTab(locker)
                        case .memory:
                            lockerMemoryTab(locker)
                        case .research:
                            lockerResearchTab(locker)
                        case .feedback:
                            lockerFeedbackTabView(locker)
                        case .library:
                            lockerLibraryTab(locker)
                        case .escalation:
                            lockerEscalationTab(locker)
                        case .preferences:
                            lockerPreferencesTab(locker)
                        }

                        if let source = locker.source {
                            Text(source)
                                .podTextStyle(.label, color: AppColors.textTertiary)
                        }
                    }
                } else {
                    Text(lockerError ?? "Locker unavailable")
                        .podTextStyle(.body, color: AppColors.textTertiary)
                }
            }
            .padding(Theme.md)
            .podCard()
        }
    }

    private func agentStatusBand(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .top, spacing: Theme.sm) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color(hexString: agent.avatarColor ?? "3B82F6"))
                        .frame(width: 40, height: 40)

                    Text(agent.name.prefix(1).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Circle()
                        .fill(agentStatusDotColor(locker))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(AppColors.backgroundSecondary, lineWidth: 2))
                }

                VStack(alignment: .leading, spacing: Theme.xxs) {
                    HStack(spacing: Theme.xs) {
                        Text(agent.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)

                        Text(agentStatusLaneLabel(locker))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.accentAgent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.accentAgent.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(agent.role)
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                        .lineLimit(1)

                    Text("Last seen \(agentLastSeenLabel(locker))")
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Theme.xxs) {
                    Text(agentStatusLabel(locker))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(agentStatusDotColor(locker))
                    Text("\(lockerAttentionCount(locker)) needs attention")
                        .podTextStyle(.label, color: AppColors.textTertiary)
                }
            }

            HStack(spacing: Theme.sm) {
                activationMetric("Now", value: "\(locker.planner.counts.now)", icon: "bolt.fill", color: locker.planner.counts.now > 0 ? AppColors.accentWarning : AppColors.accentSuccess)
                activationMetric("Blocked", value: "\(locker.planner.counts.blocked)", icon: "lock.fill", color: locker.planner.counts.blocked > 0 ? AppColors.accentWarning : AppColors.textTertiary)
                activationMetric("Inbox", value: "\(locker.inbox.actionCount)", icon: "tray.full.fill", color: locker.inbox.actionCount > 0 ? AppColors.accentElectric : AppColors.textTertiary)
            }
        }
    }

    private var lockerCockpitTabs: some View {
        HStack(spacing: 4) {
            ForEach(AgentLockerTab.primaryTabs) { tab in
                lockerCockpitTabButton(tab)
            }

            Menu {
                ForEach(AgentLockerTab.secondaryTabs) { tab in
                    Button {
                        selectedLockerTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                    }
                }
            } label: {
                lockerCockpitTabLabel(
                    title: "More",
                    systemImage: "ellipsis.circle",
                    isSelected: AgentLockerTab.secondaryTabs.contains(selectedLockerTab)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func lockerCockpitTabButton(_ tab: AgentLockerTab) -> some View {
        Button {
            selectedLockerTab = tab
        } label: {
            lockerCockpitTabLabel(
                title: tab.shortTitle,
                systemImage: tab.systemImage,
                isSelected: selectedLockerTab == tab
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }

    private func lockerCockpitTabLabel(title: String, systemImage: String, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Capsule()
                .fill(isSelected ? AppColors.accentElectric : Color.clear)
                .frame(height: 3)
        }
        .foregroundStyle(isSelected ? AppColors.accentElectric : AppColors.textTertiary)
        .frame(maxWidth: .infinity, minHeight: 46)
        .contentShape(Rectangle())
    }

    private func agentStatusLaneLabel(_ locker: AgentLockerDTO) -> String {
        let lane = locker.agentProfile?.rosterLane?.nilIfBlank ?? agent.rosterLane.rawValue
        return lane.replacingOccurrences(of: "_", with: " ")
    }

    private func agentStatusLabel(_ locker: AgentLockerDTO) -> String {
        if let status = locker.heartbeat.status?.nilIfBlank {
            return status.replacingOccurrences(of: "_", with: " ")
        }
        return agent.status.displayName
    }

    private func agentStatusDotColor(_ locker: AgentLockerDTO) -> Color {
        switch locker.heartbeat.status?.nilIfBlank ?? agent.status.rawValue {
        case "awake", "online", "busy":
            return AppColors.accentSuccess
        case "idle":
            return AppColors.accentWarning
        case "offline", "sleeping", "asleep":
            return AppColors.textTertiary
        default:
            return agent.status.color
        }
    }

    private func agentLastSeenLabel(_ locker: AgentLockerDTO) -> String {
        if let date = parseLockerDate(locker.heartbeat.lastHeartbeatAt) ?? agent.lastActivity ?? agent.lastAwakeProofAt {
            return date.relativeFormatted
        }
        return "unknown"
    }

    private func parseLockerDate(_ value: String?) -> Date? {
        guard let value = value?.nilIfBlank else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: value)
    }

    // MARK: - Report Card Tab (M1 — SPEC-AGENT-LOCKER-REPORT-CARD)

    private func lockerCardTab(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            if locker.reportCard.source != nil || !locker.reportCard.sections.isEmpty {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    HStack(alignment: .center, spacing: Theme.sm) {
                        ZStack {
                            Circle()
                                .stroke(reportCardStatusColor(locker.reportCard.status).opacity(0.22), lineWidth: 7)
                                .frame(width: 58, height: 58)
                            Text("\(locker.reportCard.score)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(reportCardStatusColor(locker.reportCard.status))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(locker.reportCard.status?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Report Card")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(reportCardStatusColor(locker.reportCard.status))
                            Text(locker.reportCard.headline ?? "Evidence-derived Locker readiness.")
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }

                    ForEach(locker.reportCard.sections.prefix(7)) { section in
                        reportCardSectionRow(section)
                    }

                    if let policyNote = locker.reportCard.agentUpdatePolicy.note {
                        Label(policyNote, systemImage: "pencil.and.list.clipboard")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            let coreFiles = locker.reportCard.sections.first(where: { $0.key == "core_files" })?.details.files ?? []
            if !coreFiles.isEmpty {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("Core Files")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)

                    AgentDetailFlowLayout(spacing: Theme.xs) {
                        ForEach(coreFiles) { file in
                            Label(file.key.replacingOccurrences(of: "_", with: " "), systemImage: file.safeToPreview ? "doc.text.fill" : "doc.badge.exclamationmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(file.safeToPreview ? AppColors.textPrimary : AppColors.accentWarning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(file.safeToPreview ? AppColors.backgroundSecondary : AppColors.accentWarning.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            // Identity
            if let profile = locker.agentProfile {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("Identity")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)

                    HStack(spacing: Theme.xs) {
                        Label(profile.title ?? agent.role, systemImage: "person.crop.circle.badge.checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.accentElectric)
                        Spacer()
                        let lane = profile.rosterLane?.replacingOccurrences(of: "_", with: " ") ?? "unknown"
                        Text(lane)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.accentAgent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.accentAgent.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !profile.owns.isEmpty {
                        AgentDetailFlowLayout(spacing: Theme.xs) {
                            ForEach(profile.owns, id: \.self) { domain in
                                Text(domain.replacingOccurrences(of: "_", with: " "))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.backgroundTertiary)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if !profile.protectedDomains.isEmpty {
                        Label("Protected: \(profile.protectedDomains.joined(separator: ", "))", systemImage: "lock.shield.fill")
                            .font(.caption2)
                            .foregroundStyle(AppColors.accentWarning)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            // Tools
            if let tools = locker.tools, !tools.available.isEmpty {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("Tools")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)

                    ForEach(tools.available.prefix(8)) { tool in
                        HStack(spacing: Theme.xs) {
                            Image(systemName: toolModeIcon(tool.mode))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(toolModeColor(tool.mode))
                                .frame(width: 16)
                            Text(tool.label ?? tool.endpoint ?? "tool")
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            if let mode = tool.mode?.replacingOccurrences(of: "_", with: " ") {
                                Text(mode)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            // Compliance / Guardrails
            if !locker.guardrails.isEmpty {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("Compliance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)

                    ForEach(locker.guardrails.prefix(5), id: \.self) { g in
                        Label(g, systemImage: "lock.shield.fill")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            // How I'm doing
            VStack(alignment: .leading, spacing: Theme.xs) {
                Text("How I'm Doing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)

                let now = locker.planner.counts.now
                let blocked = locker.planner.counts.blocked
                let review = locker.planner.counts.review
                let inbox = locker.inbox.actionCount

                HStack(spacing: Theme.xs) {
                    reportCardMetric("Now", value: now, warn: now > 0)
                    reportCardMetric("Blocked", value: blocked, warn: blocked > 0)
                    reportCardMetric("Review", value: review, warn: review > 0)
                    reportCardMetric("Inbox", value: inbox, warn: inbox > 0)
                }

                if let currentWork = locker.heartbeat.currentWork, !currentWork.isEmpty {
                    Text(currentWork)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            // Gaps
            if !locker.gaps.isEmpty {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Label("Gaps (\(locker.gaps.count))", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.accentWarning)

                    ForEach(locker.gaps.prefix(4), id: \.self) { gap in
                        Text(gap)
                            .font(.caption2)
                            .foregroundStyle(AppColors.accentWarning.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.accentWarning.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
    }

    private func reportCardMetric(_ label: String, value: Int, warn: Bool) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(warn ? AppColors.accentWarning : AppColors.accentSuccess)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.xxs)
    }

    private func reportCardSectionRow(_ section: AgentLockerDTO.ReportCard.Section) -> some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: reportCardSectionIcon(section.status))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(reportCardStatusColor(section.status))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(section.label ?? section.key.replacingOccurrences(of: "_", with: " "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                if let summary = section.summary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text("\(section.score)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportCardStatusColor(section.status))
        }
        .padding(.vertical, 2)
    }

    private func reportCardSectionIcon(_ status: String?) -> String {
        switch status {
        case "ready":
            return "checkmark.circle.fill"
        case "dormant_archive":
            return "archivebox.fill"
        case "attention":
            return "exclamationmark.triangle.fill"
        default:
            return "circle.dotted"
        }
    }

    private func reportCardStatusColor(_ status: String?) -> Color {
        switch status {
        case "ready":
            return AppColors.accentSuccess
        case "dormant_archive":
            return AppColors.textTertiary
        case "attention":
            return AppColors.accentWarning
        default:
            return AppColors.accentAgent
        }
    }

    private func toolModeIcon(_ mode: String?) -> String {
        switch mode {
        case "read_only": return "eye.fill"
        case "explicit_mutation_required": return "pencil.circle.fill"
        case "protected": return "lock.fill"
        default: return "wrench.fill"
        }
    }

    private func toolModeColor(_ mode: String?) -> Color {
        switch mode {
        case "read_only": return AppColors.accentSuccess
        case "explicit_mutation_required": return AppColors.accentElectric
        case "protected": return AppColors.accentWarning
        default: return AppColors.textTertiary
        }
    }

    private func lockerClassroomTab(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .top, spacing: Theme.sm) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(priorityColor(locker.startHere.priority))

                VStack(alignment: .leading, spacing: Theme.xxs) {
                    Text(locker.startHere.headline ?? "No urgent action")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    lockerText(locker.startHere.reason, fallback: "No priority reason returned.")
                    lockerText(locker.startHere.primaryAction, fallback: "No primary action returned.")

                    if let blockedBy = locker.startHere.blockedBy, !blockedBy.isEmpty {
                        Label(blockedBy, systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.accentWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !locker.dashboards.isEmpty {
                lockerDashboardList(locker.dashboards)
            }
        }
    }

    private func lockerPlannerTab(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            plannerCreateRow
            lockerLane("Now", items: locker.planner.lanes.now, emptyReason: locker.planner.emptyReasons["now"] ?? nil)
            lockerLane("Next", items: locker.planner.lanes.next, emptyReason: locker.planner.emptyReasons["next"] ?? nil)
            lockerLane("Waiting", items: locker.planner.lanes.waiting, emptyReason: locker.planner.emptyReasons["waiting"] ?? nil)
            lockerLane("Blocked", items: locker.planner.lanes.blocked, emptyReason: locker.planner.emptyReasons["blocked"] ?? nil)
            lockerLane("Review", items: locker.planner.lanes.review, emptyReason: locker.planner.emptyReasons["review"] ?? nil)
            lockerLane("Done", items: locker.planner.lanes.done, emptyReason: locker.planner.emptyReasons["done"] ?? nil)
            lockerLane("Assigned ORCA Tasks", items: locker.orcaTasks.assigned, emptyReason: locker.orcaTasks.emptyReasons["assigned"] ?? nil)
            lockerLane("Active Runs", items: locker.orcaTasks.activeRuns, emptyReason: locker.orcaTasks.emptyReasons["active_runs"] ?? nil)
        }
    }

    private var plannerCreateRow: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            TextField("Add a task...", text: $plannerNewTitle)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .font(.caption)
                .padding(.horizontal, Theme.sm)
                .padding(.vertical, 8)
                .background(AppColors.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
                .onSubmit {
                    Task { await createPlannerItem() }
                }

            TextField("Notes", text: $plannerNewBody, axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .lineLimit(1...3)
                .font(.caption)
                .padding(.horizontal, Theme.sm)
                .padding(.vertical, 8)
                .background(AppColors.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )

            HStack(spacing: Theme.xs) {
                Picker("Lane", selection: $plannerNewLane) {
                    ForEach(plannerWritableLanes, id: \.self) { lane in
                        Text(lane).tag(lane)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Priority", selection: $plannerNewPriority) {
                    ForEach(plannerPriorities, id: \.self) { priority in
                        Text(priority).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    Task { await createPlannerItem() }
                } label: {
                    plannerIcon(systemName: "plus")
                }
                .buttonStyle(.plain)
                .disabled(plannerNewTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plannerWriteItemId != nil)
                .accessibilityLabel("Add planner item")
            }
        }
        .padding(Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(alignment: .bottomLeading) {
            if let plannerWriteError {
                Text(plannerWriteError)
                    .font(.caption2)
                    .foregroundStyle(AppColors.accentDanger)
                    .padding(.top, 2)
                    .offset(y: Theme.md)
            }
        }
        .padding(.bottom, plannerWriteError == nil ? 0 : Theme.md)
    }

    private func lockerInboxTab(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: Theme.sm) {
                Label("\(locker.inbox.actionCount) need action", systemImage: "tray.full.fill")
                    .font(.caption)
                    .foregroundStyle(locker.inbox.actionCount > 0 ? AppColors.accentWarning : AppColors.textSecondary)
                Label("\(locker.inbox.staleCount) stale", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(locker.inbox.staleCount > 0 ? AppColors.accentWarning : AppColors.textTertiary)
                Spacer()
                Text("metadata only")
                    .podTextStyle(.label, color: AppColors.textMuted)
            }

            if locker.inbox.threads.isEmpty {
                lockerEmptyText(locker.inbox.emptyReason ?? locker.inbox.gap ?? "No inbox threads returned.")
            } else {
                ForEach(Array(locker.inbox.threads.enumerated()), id: \.offset) { _, thread in
                    lockerThreadRow(thread)
                }
            }
        }
    }

    private func lockerChatTab(_ locker: AgentLockerDTO) -> some View {
        let chat = locker.chat
        return VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .top, spacing: Theme.sm) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(lockerChatStatusColor(chat.policyState))
                    .frame(width: 34, height: 34)
                    .background(lockerChatStatusColor(chat.policyState).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

                VStack(alignment: .leading, spacing: 4) {
                    Text(chat.channelName ?? "direct:\(agent.name.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(lockerChatStatusText(chat))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    onStartChat?()
                    dismiss()
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accentElectric)
                .disabled(onStartChat == nil)
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            HStack(spacing: Theme.xs) {
                reportCardMetric("Messages", value: chat.messageCount, warn: false)
                reportCardMetric("Pending", value: chat.pendingCount, warn: chat.pendingCount > 0)
                reportCardMetric("Unread", value: chat.unreadCount, warn: chat.unreadCount > 0)
                if let continuityScore = chat.continuityInputsScore {
                    reportCardMetric(
                        "Context",
                        value: Int((continuityScore * 100).rounded()),
                        warn: continuityScore < 0.5
                    )
                }
            }

            if let preview = chat.latestMessagePreview?.nilIfBlank {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("Latest")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            VStack(alignment: .leading, spacing: Theme.xs) {
                Text("Policy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)

                AgentDetailFlowLayout(spacing: Theme.xs) {
                    lockerPolicyChip(chat.policyState ?? "open", color: lockerChatStatusColor(chat.policyState))
                    if let lane = chat.policyLane?.nilIfBlank {
                        lockerPolicyChip(lane, color: AppColors.accentAgent)
                    }
                    ForEach(chat.policyAllowedActions.prefix(6), id: \.self) { action in
                        lockerPolicyChip(action, color: AppColors.textTertiary)
                    }
                }

                if let reason = chat.policyReason?.nilIfBlank {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            VStack(alignment: .leading, spacing: Theme.xs) {
                Text("Promotions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)

                AgentDetailFlowLayout(spacing: Theme.xs) {
                    lockerPromotionChip("Ticket", enabled: chat.canCreateTicket, icon: "ticket.fill")
                    lockerPromotionChip("Research", enabled: chat.canRequestResearch, icon: "doc.badge.plus")
                    lockerPromotionChip("Run", enabled: chat.canDispatchSchoolhouseRun, icon: "play.circle.fill")
                    lockerPromotionChip("Feedback", enabled: chat.canLeaveFeedback, icon: "quote.bubble.fill")
                }
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            if let ticketId = chat.activeTicketId?.nilIfBlank {
                lockerMetadataRow("Attached ticket", value: ticketId)
            }

            if let continuityEventId = chat.continuityEventId?.nilIfBlank {
                lockerMetadataRow("Continuity evidence", value: continuityEventId)
            }

            if let note = chat.note?.nilIfBlank {
                lockerEmptyText(note)
            }
        }
    }

    private func lockerChatStatusText(_ chat: AgentLockerDTO.LockerChat) -> String {
        let state = (chat.policyState ?? "open").replacingOccurrences(of: "_", with: " ")
        if chat.exists {
            return "Playground thread ready • \(state)"
        }
        return "Playground will open this 1:1 thread • \(state)"
    }

    private func lockerChatStatusColor(_ status: String?) -> Color {
        switch status?.lowercased() {
        case "open":
            return AppColors.accentSuccess
        case "dormant_archive":
            return AppColors.textTertiary
        case "ticket_required", "protected", "redacted_summary_available":
            return AppColors.accentWarning
        default:
            return AppColors.accentElectric
        }
    }

    private func lockerPolicyChip(_ text: String, color: Color) -> some View {
        Text(text.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func lockerPromotionChip(_ label: String, enabled: Bool, icon: String) -> some View {
        Label(label, systemImage: enabled ? icon : "lock.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(enabled ? AppColors.textPrimary : AppColors.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(enabled ? AppColors.backgroundSecondary : AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }

    private func lockerMemoryTab(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            lockerMetadataRow("Session", value: locker.heartbeat.currentSessionId)
            lockerMetadataRow("Awake", value: locker.heartbeat.awakeAt)
            lockerMetadataRow("Heartbeat", value: locker.heartbeat.lastHeartbeatAt)
            lockerMetadataRow("Sleep", value: locker.heartbeat.lastSleepProof ?? locker.heartbeat.sleepAt)
            lockerMetadataRow("Current work", value: locker.heartbeat.currentWork)
            lockerMetadataRow("Next checkpoint", value: locker.heartbeat.nextCheckpoint)
            lockerMetadataRow("Blocker", value: locker.heartbeat.blocker)

            Divider().background(AppColors.border)

            lockerText(locker.lockerMemory.lastSessionSummary, fallback: locker.lockerMemory.emptyReason ?? "No last session summary returned.")
            lockerMetadataRow("Daily log", value: locker.lockerMemory.dailyLogRef)
            lockerStringList("Open Loops", items: locker.lockerMemory.openLoops)
            lockerStringList("Commitments", items: locker.lockerMemory.commitments)
            lockerStringList("Unresolved Blockers", items: locker.lockerMemory.unresolvedBlockers)
        }
    }

    private func lockerResearchTab(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: Theme.sm) {
                activationMetric("Requests", value: "\(locker.researchRail.counts.activeRequests)", icon: "doc.badge.plus", color: locker.researchRail.counts.activeRequests > 0 ? AppColors.accentElectric : AppColors.textTertiary)
                activationMetric("Review", value: "\(locker.researchRail.counts.awaitingReview)", icon: "checklist.checked", color: locker.researchRail.counts.awaitingReview > 0 ? AppColors.accentWarning : AppColors.accentSuccess)
                activationMetric("Reviewed", value: "\(locker.researchRail.counts.reviewedRelevant)", icon: "doc.text.magnifyingglass", color: AppColors.accentAgent)
            }

            lockerResearchLane("Research Requests", packets: locker.researchRail.activeRequests, emptyReason: locker.researchRail.emptyReason)
            lockerResearchLane("Active Packets", packets: locker.researchRail.activePackets, emptyReason: "No in-progress research packets returned.")
            lockerResearchLane("Awaiting Review", packets: locker.researchRail.awaitingReview, emptyReason: "No Research Rail packets are waiting on this agent.")
            lockerResearchLane("Reviewed Relevant", packets: locker.researchRail.reviewedRelevant, emptyReason: "No reviewed packets returned for this agent.")

            if let source = locker.researchRail.source {
                Text(source)
                    .podTextStyle(.label, color: AppColors.textTertiary)
            }
        }
    }

    private func lockerResearchLane(_ title: String, packets: [AgentLockerDTO.ResearchPacket], emptyReason: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            HStack(spacing: Theme.xs) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)
                if !packets.isEmpty {
                    Text("\(packets.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppColors.accentElectric)
                        .clipShape(Capsule())
                }
            }
            if packets.isEmpty {
                Text(emptyReason ?? "No items.")
                    .podTextStyle(.caption, color: AppColors.textMuted)
                    .padding(.vertical, Theme.xxs)
            } else {
                ForEach(packets, id: \.stableId) { packet in
                    VStack(alignment: .leading, spacing: Theme.xxs) {
                        Text(packet.title ?? "Untitled request")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Theme.xs) {
                            if let domain = packet.domain, !domain.isEmpty {
                                Text(domain)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppColors.accentAgent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(AppColors.accentAgent.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            if let status = packet.status, !status.isEmpty {
                                let sColor = researchStatusColor(status)
                                Text(status.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(sColor)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(sColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        if let req = packet.requestedBy, let asgn = packet.assignedTo {
                            Text("\(req) → \(asgn)")
                                .podTextStyle(.label, color: AppColors.textTertiary)
                        } else if let req = packet.requestedBy {
                            Text("Requested by \(req)")
                                .podTextStyle(.label, color: AppColors.textTertiary)
                        }
                        if let next = packet.nextAction, !next.isEmpty {
                            Text(next)
                                .podTextStyle(.label, color: AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(Theme.xs)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }
            }
        }
    }

    private func researchStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "assigned": return AppColors.accentElectric
        case "in_progress", "active": return AppColors.accentWarning
        case "awaiting_review", "review": return AppColors.accentElectric
        case "reviewed", "complete", "done": return AppColors.accentSuccess
        case "blocked", "failed": return AppColors.accentDanger
        default: return AppColors.textTertiary
        }
    }

    private func lockerFeedbackTabView(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            if locker.feedback.endpoint == nil {
                lockerEmptyText("Feedback endpoint was not returned by ORCA.")
            } else {
                // Rating chips
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("How useful was this wake?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                    let ratings = locker.feedback.ratings.isEmpty
                        ? ["useful", "missing_context", "wrong_priority", "confusing", "unsafe_preview", "other"]
                        : locker.feedback.ratings
                    AgentDetailFlowLayout(spacing: Theme.xs) {
                        ForEach(ratings, id: \.self) { rating in
                            let isSelected = lockerFeedbackRating == rating
                            Button {
                                lockerFeedbackRating = isSelected ? nil : rating
                            } label: {
                                Text(rating.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .white : AppColors.textSecondary)
                                    .padding(.horizontal, Theme.sm)
                                    .padding(.vertical, Theme.xxs)
                                    .background(isSelected ? AppColors.accentElectric : AppColors.backgroundSecondary)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(isSelected ? Color.clear : AppColors.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Panel selector
                VStack(alignment: .leading, spacing: Theme.xxs) {
                    Text("Which panel?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                    Picker("Panel", selection: $lockerFeedbackPanel) {
                        ForEach(["classroom", "planner", "inbox", "memory", "research", "feedback", "library", "escalation"], id: \.self) { panel in
                            Text(panel.capitalized).tag(panel)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.accentElectric)
                }

                // Free text
                TextEditor(text: $lockerFeedbackText)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .background(AppColors.backgroundPrimary)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(Theme.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .strokeBorder(AppColors.border, lineWidth: 1)
                    )

                // Snapshot toggle
                Toggle(isOn: $lockerFeedbackAttachSnapshot) {
                    Text("Attach redacted locker snapshot")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .toggleStyle(SwitchToggleStyle(tint: AppColors.accentElectric))

                // Send button
                HStack(spacing: Theme.sm) {
                    Button {
                        Task { await postLockerFeedback() }
                    } label: {
                        HStack(spacing: Theme.xs) {
                            if isPostingLockerFeedback {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text("Send Feedback")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, Theme.md)
                        .padding(.vertical, Theme.xs)
                        .foregroundStyle(.white)
                        .background(lockerFeedbackRating != nil ? AppColors.accentElectric : AppColors.textMuted)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                    .buttonStyle(.plain)
                    .disabled(lockerFeedbackRating == nil || isPostingLockerFeedback)

                    if let lockerFeedbackMessage {
                        Text(lockerFeedbackMessage)
                            .podTextStyle(.caption, color: lockerFeedbackMessage == "Feedback saved" ? AppColors.accentSuccess : AppColors.accentDanger)
                            .lineLimit(2)
                    }
                    Spacer()
                }
            }
        }
    }

    private func lockerAttentionCount(_ locker: AgentLockerDTO) -> Int {
        locker.planner.counts.now + locker.planner.counts.blocked + locker.planner.counts.review + locker.inbox.actionCount
    }

    private func lockerRoleDashboardTab(_ locker: AgentLockerDTO) -> some View {
        let activeDashboards = locker.dashboards.filter { $0.status != "approval_required" }
        let protectedDashboards = locker.dashboards.filter { $0.status == "approval_required" }
        return VStack(alignment: .leading, spacing: Theme.md) {
            if activeDashboards.isEmpty && protectedDashboards.isEmpty {
                lockerEmptyText("No role dashboards registered for this agent.")
            }
            ForEach(activeDashboards) { dash in
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack(spacing: Theme.xs) {
                        Image(systemName: "rectangle.3.group.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.accentAgent)
                        Text(dash.title ?? dash.id)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("WIRED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.accentSuccess)
                            .tracking(0.5)
                    }
                    if let summary = dash.summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    if !dash.cards.isEmpty {
                        VStack(spacing: Theme.xxs) {
                            ForEach(dash.cards) { card in
                                roleDashboardCardRow(card)
                            }
                        }
                    } else {
                        Text("No active items.")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                            .italic()
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(AppColors.border, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
            ForEach(protectedDashboards) { dash in
                HStack(spacing: Theme.xs) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.accentWarning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dash.title ?? dash.id)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Requires Rooster review")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer()
                    Text("PROTECTED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.accentWarning)
                        .tracking(0.5)
                }
                .padding(Theme.sm)
                .background(AppColors.accentWarning.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(AppColors.accentWarning.opacity(0.3), lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
    }

    @ViewBuilder
    private func roleDashboardCardRow(_ card: AgentLockerDTO.DashboardCard) -> some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: statusIcon(card.status ?? "open"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor(card.status ?? "open"))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title ?? card.id)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                if let priority = card.priority {
                    Text(priority.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(priorityColor(priority))
                }
            }
            Spacer(minLength: Theme.xs)
            if let status = card.status {
                Text(status.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor(status))
                    .tracking(0.3)
            }
        }
        .padding(.horizontal, Theme.sm)
        .padding(.vertical, Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "open": return "circle"
        case "in_progress": return "arrow.trianglehead.clockwise"
        case "claimed": return "hand.raised.fill"
        case "blocked": return "exclamationmark.triangle.fill"
        case "closed": return "checkmark.circle.fill"
        default: return "circle.dotted"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "open": return AppColors.textTertiary
        case "in_progress", "claimed": return AppColors.accentWarning
        case "closed": return AppColors.accentSuccess
        case "blocked": return AppColors.accentDanger
        default: return AppColors.textTertiary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": return AppColors.accentDanger
        case "high": return AppColors.accentWarning
        case "medium": return AppColors.accentElectric
        default: return AppColors.textTertiary
        }
    }

    private func lockerDashboardList(_ dashboards: [AgentLockerDTO.Dashboard]) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text("Dashboards")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)

            ForEach(dashboards) { dashboard in
                VStack(alignment: .leading, spacing: Theme.xxs) {
                    HStack(spacing: Theme.xs) {
                        Image(systemName: dashboard.visibility == "protected" ? "lock.shield.fill" : "rectangle.3.group.fill")
                            .font(.caption)
                            .foregroundStyle(dashboard.visibility == "protected" ? AppColors.accentWarning : AppColors.accentAgent)
                        Text(dashboard.title ?? dashboard.id)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        if let status = dashboard.status {
                            Text(status.replacingOccurrences(of: "_", with: " "))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        Spacer()
                    }

                    lockerText(dashboard.summary, fallback: "Dashboard registered without a preview summary.")
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
    }

    private func lockerLane(_ title: String, items: [AgentLockerDTO.WorkItem], emptyReason: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)

            if items.isEmpty {
                lockerEmptyText(emptyReason ?? "No \(title.lowercased()) items returned.")
            } else {
                ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, item in
                    lockerWorkItemRow(item)
                }
            }
        }
    }

    private func lockerWorkItemRow(_ item: AgentLockerDTO.WorkItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.xxs) {
            HStack(alignment: .top, spacing: Theme.xs) {
                Text(item.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if item.isPlannerItem {
                    plannerItemControls(item)
                } else if let priority = item.priority, !priority.isEmpty {
                    Text(priority)
                        .podTextStyle(.label, color: priorityColor(priority))
                }
            }

            if let body = item.body?.nilIfBlank, item.isPlannerItem {
                Text(body)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.isPlannerItem, let ticketId = item.ticketId ?? item.id, !ticketId.isEmpty {
                Text(String(ticketId.prefix(8)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textMuted)
            }

            if !item.isPlannerItem || (item.nextAction?.nilIfBlank != nil || item.whyShown?.nilIfBlank != nil) {
                lockerText(item.nextAction ?? item.whyShown, fallback: "No next action returned.")
            }

            HStack(spacing: Theme.xs) {
                if let state = item.displayState, !state.isEmpty {
                    workNoteChip(state.replacingOccurrences(of: "_", with: " "), icon: "circle.dashed")
                }
                if let priority = item.priority, item.isPlannerItem, !priority.isEmpty {
                    workNoteChip(priority, icon: "flag.fill")
                }
                if let source = item.source ?? item.sourceType, !source.isEmpty {
                    workNoteChip(source, icon: "link")
                }
                if let sourceRef = item.sourceRef, !sourceRef.isEmpty {
                    workNoteChip(String(sourceRef.prefix(10)), icon: "number")
                }
                if let blockedOn = item.blockedOn, !blockedOn.isEmpty {
                    workNoteChip(blockedOn, icon: "lock.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func plannerItemControls(_ item: AgentLockerDTO.WorkItem) -> some View {
        HStack(spacing: 4) {
            Button {
                Task { await updatePlannerItem(item, status: "done") }
            } label: {
                plannerIcon(systemName: item.status == "done" ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            .disabled(plannerWriteItemId == item.id)
            .accessibilityLabel("Mark done")

            Menu {
                ForEach(plannerWritableLanes, id: \.self) { lane in
                    Button {
                        Task { await updatePlannerItem(item, lane: lane) }
                    } label: {
                        Label(lane, systemImage: item.lane == lane ? "checkmark" : "arrow.right")
                    }
                }
            } label: {
                plannerIcon(systemName: "arrow.left.arrow.right")
            }
            .disabled(plannerWriteItemId == item.id)

            Button {
                plannerEditDraft = PlannerItemEditDraft(item: item)
            } label: {
                plannerIcon(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit planner item")

            Button(role: .destructive) {
                Task { await retirePlannerItem(item) }
            } label: {
                plannerIcon(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(plannerWriteItemId == item.id)
            .accessibilityLabel("Retire planner item")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func plannerIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.accentElectric)
            .frame(width: 26, height: 26)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var plannerWritableLanes: [String] {
        ["now", "next", "waiting"]
    }

    private var plannerPriorities: [String] {
        ["low", "medium", "high"]
    }

    private func plannerEditSheet(_ draft: PlannerItemEditDraft) -> some View {
        PlannerItemEditSheet(draft: draft) { updated in
            Task { await savePlannerItemEdit(updated) }
        }
        .presentationDetents([.medium])
    }

    private func createPlannerItem() async {
        let title = plannerNewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        await MainActor.run {
            plannerWriteItemId = "new"
            plannerWriteError = nil
        }

        do {
            let body = PlannerItemCreateRequest(
                title: title,
                body: plannerNewBody.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                lane: plannerNewLane,
                priority: plannerNewPriority
            )
            let _: EmptyResponse = try await APIClient.shared.request(
                .createPlannerItem(agentId: agent.id, body),
                body: body
            )
            await MainActor.run {
                self.plannerNewTitle = ""
                self.plannerNewBody = ""
                self.plannerNewPriority = "medium"
                self.plannerWriteItemId = nil
            }
            await loadLocker()
        } catch {
            await MainActor.run {
                self.plannerWriteError = "Planner write failed"
                self.plannerWriteItemId = nil
            }
        }
    }

    private func updatePlannerItem(
        _ item: AgentLockerDTO.WorkItem,
        title: String? = nil,
        body: String? = nil,
        lane: String? = nil,
        priority: String? = nil,
        status: String? = nil
    ) async {
        guard item.isPlannerItem, let itemId = item.id?.nilIfBlank else { return }
        await MainActor.run {
            plannerWriteItemId = itemId
            plannerWriteError = nil
        }

        do {
            let request = PlannerItemUpdateRequest(
                title: title,
                body: body,
                lane: lane,
                priority: priority,
                status: status
            )
            let _: EmptyResponse = try await APIClient.shared.request(
                .updatePlannerItem(agentId: agent.id, itemId: itemId, request),
                body: request
            )
            await MainActor.run {
                self.plannerWriteItemId = nil
            }
            await loadLocker()
        } catch {
            await MainActor.run {
                self.plannerWriteError = "Planner write failed"
                self.plannerWriteItemId = nil
            }
        }
    }

    private func savePlannerItemEdit(_ draft: PlannerItemEditDraft) async {
        guard let item = draft.item else { return }
        await updatePlannerItem(
            item,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            lane: draft.lane,
            priority: draft.priority
        )
        await MainActor.run {
            self.plannerEditDraft = nil
        }
    }

    private func retirePlannerItem(_ item: AgentLockerDTO.WorkItem) async {
        guard item.isPlannerItem, let itemId = item.id?.nilIfBlank else { return }
        await MainActor.run {
            plannerWriteItemId = itemId
            plannerWriteError = nil
        }

        do {
            let _: EmptyResponse = try await APIClient.shared.request(
                .deletePlannerItem(agentId: agent.id, itemId: itemId)
            )
            await MainActor.run {
                self.plannerWriteItemId = nil
            }
            await loadLocker()
        } catch {
            await MainActor.run {
                self.plannerWriteError = "Planner retire failed"
                self.plannerWriteItemId = nil
            }
        }
    }

    private func lockerThreadRow(_ thread: AgentLockerDTO.Inbox.Thread) -> some View {
        VStack(alignment: .leading, spacing: Theme.xxs) {
            HStack(spacing: Theme.xs) {
                if thread.actionRequired == true {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.accentWarning)
                }
                Text(thread.sender ?? "Unknown sender")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                if let classification = thread.classification {
                    Text(classification.replacingOccurrences(of: "_", with: " "))
                        .podTextStyle(.label, color: AppColors.textTertiary)
                }
            }

            HStack(spacing: Theme.xs) {
                if let source = thread.source {
                    workNoteChip(source, icon: "tray.full")
                }
                if let timestamp = thread.timestamp {
                    workNoteChip(timestamp, icon: "clock")
                }
                if thread.stale == true {
                    workNoteChip("stale", icon: "timer")
                }
                if thread.handled == true {
                    workNoteChip("handled", icon: "checkmark.circle")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func lockerMetadataRow(_ label: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.xs) {
            Text(label)
                .podTextStyle(.label, color: AppColors.textTertiary)
                .frame(width: 104, alignment: .leading)
            Text(value?.nilIfBlank ?? "Not returned")
                .podTextStyle(.caption, color: value?.nilIfBlank == nil ? AppColors.textTertiary : AppColors.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func lockerStringList(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
            if items.isEmpty {
                lockerEmptyText("No \(title.lowercased()) returned.")
            } else {
                ForEach(items.prefix(4), id: \.self) { item in
                    Text(item)
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func lockerText(_ text: String?, fallback: String) -> some View {
        Text(text?.nilIfBlank ?? fallback)
            .podTextStyle(.caption, color: text?.nilIfBlank == nil ? AppColors.textTertiary : AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lockerEmptyText(_ text: String) -> some View {
        Text(text)
            .podTextStyle(.caption, color: AppColors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
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

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            sectionHeader("Runtime")

            DisclosureGroup(isExpanded: $isRuntimeExpanded) {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack(spacing: Theme.sm) {
                        Text("Support")
                            .podTextStyle(.label, color: AppColors.textTertiary)
                        Spacer()
                        runtimeBadge(
                            runtimeDisplay(agent.supportRuntime),
                            color: supportRuntimeColor(agent.supportRuntime)
                        )
                    }

                    HStack(spacing: Theme.sm) {
                        Label(agent.runtimeHost?.nilIfBlank ?? "Unknown", systemImage: "server.rack")
                            .podTextStyle(.body, color: AppColors.textPrimary)
                        Spacer()
                    }

                    HStack(spacing: Theme.sm) {
                        Text("Drift")
                            .podTextStyle(.label, color: AppColors.textTertiary)
                        Spacer()
                        runtimeBadge(
                            runtimeDisplay(agent.driftState),
                            color: driftStateColor(agent.driftState)
                        )
                    }

                    HStack(spacing: Theme.sm) {
                        Label(lastAwakeLabel, systemImage: "bolt.circle")
                            .podTextStyle(.body, color: AppColors.textSecondary)
                        Spacer()
                    }

                    if let tokenProfile = agent.tokenProfile?.nilIfBlank {
                        Text(tokenProfile)
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, Theme.sm)
            } label: {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accentElectric)
                    Text("Runtime")
                        .podTextStyle(.body, color: AppColors.textPrimary)
                    Spacer()
                    if let driftState = agent.driftState?.nilIfBlank, driftState != "ok" {
                        runtimeBadge(runtimeDisplay(driftState), color: driftStateColor(driftState))
                    }
                }
            }
            .tint(AppColors.textSecondary)
            .padding(Theme.md)
            .podCard()
        }
    }

    private var lastAwakeLabel: String {
        guard let lastAwakeProofAt = agent.lastAwakeProofAt else { return "Never" }
        return "Active \(lastAwakeProofAt.relativeFormatted)"
    }

    private func runtimeBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func runtimeDisplay(_ rawValue: String?) -> String {
        rawValue?.nilIfBlank?.replacingOccurrences(of: "_", with: " ") ?? "unknown"
    }

    private func supportRuntimeColor(_ value: String?) -> Color {
        switch value?.nilIfBlank {
        case "codex_support":
            return AppColors.accentElectric
        case "claude_judgment":
            return AppColors.accentAgent
        case "dormant_archive":
            return AppColors.textTertiary
        case "pending":
            return AppColors.accentCaptain
        default:
            return AppColors.textTertiary
        }
    }

    private func driftStateColor(_ value: String?) -> Color {
        switch value?.nilIfBlank {
        case "ok":
            return AppColors.accentSuccess
        case "archive_drift", "protected_violation":
            return AppColors.accentDanger
        case "stale_doc", "missing_runtime", "unexpected_live_runtime":
            return AppColors.accentWarning
        default:
            return AppColors.textTertiary
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

    private func priorityColor(_ priority: String?) -> Color {
        switch priority?.lowercased() {
        case "urgent", "critical":
            return AppColors.accentDanger
        case "high":
            return AppColors.accentWarning
        case "medium":
            return AppColors.accentElectric
        case "low":
            return AppColors.textTertiary
        default:
            return AppColors.accentAgent
        }
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
                if let fileName = entry.fileDisplayName {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.accentElectric)
                        Text(fileName)
                            .podTextStyle(.caption, color: AppColors.accentElectric)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .accessibilityLabel("File drop \(fileName)")
                }
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

    private func loadLocker() async {
        await MainActor.run {
            isLoadingLocker = true
            lockerError = nil
        }
        do {
            let dto: AgentLockerDTO = try await APIClient.shared.request(
                .agentLocker(name: agent.apiPathComponent, limit: 10)
            )
            await MainActor.run {
                self.lockerData = dto
                self.isLoadingLocker = false
            }
        } catch {
            let errorMessage: String
            #if DEBUG
            errorMessage = "Locker unavailable\n\(Self.describeLockerLoadError(error))"
            print("Locker load failed for \(agent.apiPathComponent): \(Self.describeLockerLoadError(error))")
            #else
            errorMessage = "Locker unavailable"
            #endif
            await MainActor.run {
                self.isLoadingLocker = false
                self.lockerError = errorMessage
            }
        }
    }

    private static func describeLockerLoadError(_ error: Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "DecodingError.keyNotFound(\(key.stringValue)) at \(codingPathDescription(context.codingPath + [key])): \(context.debugDescription)"
        case let DecodingError.typeMismatch(type, context):
            return "DecodingError.typeMismatch(\(type)) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let DecodingError.valueNotFound(type, context):
            return "DecodingError.valueNotFound(\(type)) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case let DecodingError.dataCorrupted(context):
            return "DecodingError.dataCorrupted at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        default:
            return String(describing: error)
        }
    }

    private static func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "<root>" : path
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

    private func lockerLibraryTab(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            let lib = locker.library
            if lib.documents.isEmpty && lib.doctrineBundle == nil {
                lockerEmptyText("No library documents returned by ORCA.")
            } else {
                if let label = lib.label {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                if let bundle = lib.doctrineBundle {
                    HStack(spacing: Theme.xs) {
                        Image(systemName: "book.closed.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.accentAgent)
                        Text(bundle)
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(.bottom, Theme.xxs)
                }
                ForEach(lib.documents) { doc in
                    HStack(spacing: Theme.xs) {
                        Image(systemName: doc.exists ? "doc.fill" : "doc.badge.ellipsis")
                            .font(.caption)
                            .foregroundStyle(doc.exists ? AppColors.accentSuccess : AppColors.textMuted)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(doc.key)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            if let path = doc.path {
                                Text(path)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textMuted)
                                    .lineLimit(1)
                            }
                            if let reason = doc.reason {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if doc.safeToPreview == false {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(AppColors.textMuted)
                        }
                    }
                    .padding(.vertical, Theme.xxs)
                }
                if let source = lib.source {
                    Text(source)
                        .podTextStyle(.label, color: AppColors.textMuted)
                        .padding(.top, Theme.xxs)
                }
            }
        }
    }

    private func lockerEscalationTab(_ locker: AgentLockerDTO) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            let esc = locker.escalation
            if esc.actions.isEmpty {
                lockerEmptyText("No escalation actions returned by ORCA.")
            } else {
                Text("Escalation Actions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)

                ForEach(esc.actions) { action in
                    HStack(spacing: Theme.xs) {
                        Image(systemName: action.mode == "non_protected_only" ? "arrow.up.message.fill" : "bolt.shield.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.accentWarning)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppColors.textPrimary)
                            if let mode = action.mode {
                                Text(mode.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, Theme.xxs)
                }
            }

            Divider().padding(.vertical, Theme.xxs)

            Text("Promote to Memory Candidate")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)

            TextEditor(text: $memoryCandidateNote)
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .background(AppColors.backgroundPrimary)
                .foregroundStyle(AppColors.textPrimary)
                .padding(Theme.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )

            HStack(spacing: Theme.sm) {
                Button {
                    Task { await postMemoryCandidate(locker: locker) }
                } label: {
                    HStack(spacing: Theme.xs) {
                        if isPostingMemoryCandidate {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text("Promote")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.xs)
                    .foregroundStyle(.white)
                    .background(!memoryCandidateNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.accentElectric : AppColors.textMuted)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }
                .buttonStyle(.plain)
                .disabled(memoryCandidateNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPostingMemoryCandidate)

                if let memoryCandidateMessage {
                    Text(memoryCandidateMessage)
                        .podTextStyle(.caption, color: memoryCandidateMessage == "Candidate saved" ? AppColors.accentSuccess : AppColors.accentDanger)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private func postMemoryCandidate(locker: AgentLockerDTO) async {
        let note = memoryCandidateNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }
        await MainActor.run {
            isPostingMemoryCandidate = true
            memoryCandidateMessage = nil
        }
        do {
            struct MemoryCandidateBody: Encodable {
                let note: String
                let source: String
                let tags: [String]
            }
            let body = MemoryCandidateBody(note: note, source: "pod_locker_escalation", tags: [])
            let _: AgentLockerActionResultDTO = try await APIClient.shared.post(
                path: "/api/v1/agents/\(agent.apiPathComponent)/locker-actions/memory-candidate",
                body: body
            )
            await MainActor.run {
                self.memoryCandidateNote = ""
                self.memoryCandidateMessage = "Candidate saved"
                self.isPostingMemoryCandidate = false
            }
        } catch {
            await MainActor.run {
                self.memoryCandidateMessage = "Couldn't save candidate"
                self.isPostingMemoryCandidate = false
            }
        }
    }

    private func postLockerFeedback() async {
        let note = lockerFeedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rating = lockerFeedbackRating ?? "other"
        await MainActor.run {
            isPostingLockerFeedback = true
            lockerFeedbackMessage = nil
        }

        do {
            let body = AgentLockerFeedbackCreateBody(
                rating: rating,
                note: note,
                panel: lockerFeedbackPanel,
                attachSnapshot: lockerFeedbackAttachSnapshot,
                snapshot: [
                    "agent": AgentRosterPolicy.normalizedName(agent.name),
                    "section": lockerFeedbackPanel,
                    "source": "pod"
                ],
                traceId: "pod-locker-feedback-\(agent.name.lowercased())-\(Int(Date().timeIntervalSince1970))",
                source: "pod.agent_locker"
            )
            let _: AgentLockerActionResultDTO = try await APIClient.shared.post(
                path: "/api/v1/agents/\(agent.apiPathComponent)/locker-feedback",
                body: body
            )
            await MainActor.run {
                self.lockerFeedbackText = ""
                self.lockerFeedbackRating = nil
                self.lockerFeedbackPanel = "classroom"
                self.lockerFeedbackAttachSnapshot = false
                self.lockerFeedbackMessage = "Feedback saved"
                self.isPostingLockerFeedback = false
            }
        } catch {
            await MainActor.run {
                self.lockerFeedbackMessage = "Couldn't save feedback"
                self.isPostingLockerFeedback = false
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

    // MARK: - M3 Preferences Tab

    @State private var preferencesSaving: Bool = false
    @State private var preferencesError: String? = nil

    private func lockerPreferencesTab(_ locker: AgentLockerDTO) -> some View {
        let prefs = locker.preferences
        let allTabs = AgentLockerTab.allCases.filter { $0 != .preferences }.map(\.rawValue)
        let allTools: [String] = locker.tools?.available.compactMap { $0.label ?? $0.endpoint } ?? []
        return VStack(alignment: .leading, spacing: Theme.md) {
            if let err = preferencesError {
                Text(err).foregroundColor(AppColors.accentWarning).font(.caption)
            }
            // Pinned Tabs
            VStack(alignment: .leading, spacing: Theme.sm) {
                Text("Pinned Tabs")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                ForEach(allTabs, id: \.self) { tabName in
                    let isPinned = prefs.pinnedTabs.contains(tabName)
                    Button {
                        togglePin(agent: locker.agentProfile?.name ?? "", tab: tabName, pinned: isPinned, prefs: prefs)
                    } label: {
                        HStack {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .foregroundColor(isPinned ? AppColors.accentElectric : AppColors.textTertiary)
                                .frame(width: 18)
                            Text(tabName)
                                .foregroundColor(AppColors.textPrimary)
                                .font(.subheadline)
                            Spacer()
                            if isPinned {
                                Text("PINNED")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(AppColors.accentElectric)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            // Pinned Tools
            if !allTools.isEmpty {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    Text("Pinned Tools")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                    ForEach(allTools, id: \.self) { toolName in
                        let isPinned = prefs.pinnedTools.contains(toolName)
                        Button {
                            togglePinTool(agent: locker.agentProfile?.name ?? "", tool: toolName, pinned: isPinned, prefs: prefs)
                        } label: {
                            HStack {
                                Image(systemName: isPinned ? "wrench.fill" : "wrench")
                                    .foregroundColor(isPinned ? AppColors.accentElectric : AppColors.textTertiary)
                                    .frame(width: 18)
                                Text(toolName)
                                    .foregroundColor(AppColors.textPrimary)
                                    .font(.subheadline)
                                Spacer()
                                if isPinned {
                                    Text("PINNED")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(AppColors.accentElectric)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            if preferencesSaving {
                HStack { Spacer(); ProgressView().scaleEffect(0.7); Spacer() }
            }
        }
        .padding(Theme.md)
    }

    private func togglePin(agent: String, tab: String, pinned: Bool, prefs: AgentLockerPreferences) {
        var tabs = prefs.pinnedTabs
        if pinned { tabs.removeAll { $0 == tab } } else { tabs.append(tab) }
        savePreferences(agent: agent, newPrefs: AgentLockerPreferences(pinnedTabs: tabs, pinnedTools: prefs.pinnedTools))
    }

    private func togglePinTool(agent: String, tool: String, pinned: Bool, prefs: AgentLockerPreferences) {
        var tools = prefs.pinnedTools
        if pinned { tools.removeAll { $0 == tool } } else { tools.append(tool) }
        savePreferences(agent: agent, newPrefs: AgentLockerPreferences(pinnedTabs: prefs.pinnedTabs, pinnedTools: tools))
    }

    private func savePreferences(agent: String, newPrefs: AgentLockerPreferences) {
        guard !agent.isEmpty else { return }
        preferencesSaving = true
        preferencesError = nil
        Task {
            defer { preferencesSaving = false }
            do {
                struct PrefsBody: Encodable {
                    let pinnedTabs: [String]
                    let pinnedTools: [String]
                    enum CodingKeys: String, CodingKey {
                        case pinnedTabs = "pinned_tabs"
                        case pinnedTools = "pinned_tools"
                    }
                }
                let body = PrefsBody(pinnedTabs: newPrefs.pinnedTabs, pinnedTools: newPrefs.pinnedTools)
                let _: [String: String] = try await APIClient.shared.put(
                    path: "/api/v1/agents/\(agent)/locker-cockpit/preferences",
                    body: body
                )
                await MainActor.run { self.refreshLocker() }
            } catch {
                await MainActor.run { preferencesError = "Save failed: \(error.localizedDescription)" }
            }
        }
    }

    private func refreshLocker() {
        // Trigger a locker reload by resetting selectedAgent briefly — triggers .task in parent
        // Simpler: post a notification the sheet's parent observes, or use a @State refresh ID.
        // For M3, we rely on the existing sheet reload on re-open; a manual reload would need
        // parent ViewModel cooperation. Acceptable for M3 — full live-refresh is M4 scope.
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

private struct AgentLockerFeedbackCreateBody: Encodable {
    let rating: String
    let note: String
    let panel: String
    let attachSnapshot: Bool
    let snapshot: [String: String]
    let traceId: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case rating, note, panel, snapshot, source
        case attachSnapshot = "attach_snapshot"
        case traceId = "trace_id"
    }
}

private struct AgentLockerActionResultDTO: Decodable {
    let ok: Bool
    let action: String
    let agent: String
    let id: String?
    let status: String?
    let detail: String?
}

private enum AgentLockerTab: String, CaseIterable, Identifiable {
    case card = "Card"
    case dashboard = "Dashboard"
    case classroom = "Classroom"
    case planner = "Planner"
    case inbox = "Inbox"
    case chat = "Chat"
    case memory = "Memory"
    case research = "Research"
    case feedback = "Feedback"
    case library = "Library"
    case escalation = "Escalation"
    case preferences = "Preferences"

    var id: String { rawValue }

    static let primaryTabs: [AgentLockerTab] = [
        .card,
        .planner,
        .inbox,
        .chat,
        .classroom,
        .memory
    ]

    static let secondaryTabs: [AgentLockerTab] = [
        .dashboard,
        .research,
        .feedback,
        .library,
        .escalation,
        .preferences
    ]

    var shortTitle: String {
        switch self {
        case .classroom:
            return "Tickets"
        default:
            return rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .card:
            return "person.text.rectangle"
        case .dashboard:
            return "chart.bar.doc.horizontal"
        case .classroom:
            return "ticket.fill"
        case .planner:
            return "calendar"
        case .inbox:
            return "tray.full.fill"
        case .chat:
            return "bubble.left.and.bubble.right.fill"
        case .memory:
            return "brain.head.profile"
        case .research:
            return "sparkle.magnifyingglass"
        case .feedback:
            return "quote.bubble.fill"
        case .library:
            return "books.vertical.fill"
        case .escalation:
            return "exclamationmark.triangle.fill"
        case .preferences:
            return "slider.horizontal.3"
        }
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

private struct PlannerItemEditDraft: Identifiable {
    let id: String
    let item: AgentLockerDTO.WorkItem?
    var title: String
    var body: String
    var lane: String
    var priority: String

    init(item: AgentLockerDTO.WorkItem) {
        self.id = item.id ?? item.stableId
        self.item = item
        self.title = item.title ?? item.summary ?? ""
        self.body = item.body ?? ""
        self.lane = item.lane?.nilIfBlank ?? "now"
        self.priority = item.priority?.nilIfBlank ?? "medium"
    }
}

private struct PlannerItemEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlannerItemEditDraft
    let onSave: (PlannerItemEditDraft) -> Void

    init(draft: PlannerItemEditDraft, onSave: @escaping (PlannerItemEditDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.md) {
                TextField("Title", text: $draft.title)
                    .textInputAutocapitalization(.sentences)
                    .font(.body)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

                TextEditor(text: $draft.body)
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.xs)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

                Picker("Priority", selection: $draft.priority) {
                    ForEach(["low", "medium", "high"], id: \.self) { priority in
                        Text(priority).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Lane", selection: $draft.lane) {
                    ForEach(["now", "next", "waiting"], id: \.self) { lane in
                        Text(lane).tag(lane)
                    }
                }
                .pickerStyle(.segmented)

                Spacer(minLength: 0)
            }
            .padding(Theme.md)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private extension Agent {
    var apiPathComponent: String {
        name
            .lowercased()
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name.lowercased()
    }

    var directChatAgentInfo: AgentInfo {
        let normalizedName = AgentRosterPolicy.normalizedName(name)
        if let knownAgent = AgentInfo.find(normalizedName) {
            return AgentInfo(
                id: knownAgent.id,
                name: knownAgent.name,
                role: knownAgent.role,
                icon: knownAgent.icon,
                color: knownAgent.color,
                endpoint: knownAgent.endpoint,
                isReachable: knownAgent.isReachable,
                lane: knownAgent.lane,
                guardrail: knownAgent.guardrail,
                supportRuntime: supportRuntime,
                allowedRuntimes: allowedRuntimes,
                runtimeHost: runtimeHost,
                lastAwakeProofAt: lastAwakeProofAt,
                lastSleepProofAt: lastSleepProofAt,
                driftState: driftState,
                tokenProfile: tokenProfile
            )
        }

        return AgentInfo(
            id: normalizedName,
            name: name,
            role: role,
            icon: "person.crop.circle",
            color: avatarColor?.replacingOccurrences(of: "#", with: "") ?? "3B82F6",
            endpoint: .init(baseURL: AppConfig.computeURL, authToken: ""),
            isReachable: isDefaultRoutingEnabled,
            lane: directChatLane,
            guardrail: rosterNote ?? "Keep responses grounded in ORCA direct chat. Do not claim live runtime access or completed actions unless ORCA confirms them.",
            supportRuntime: supportRuntime,
            allowedRuntimes: allowedRuntimes,
            runtimeHost: runtimeHost,
            lastAwakeProofAt: lastAwakeProofAt,
            lastSleepProofAt: lastSleepProofAt,
            driftState: driftState,
            tokenProfile: tokenProfile
        )
    }

    private var directChatLane: AgentInfo.Lane {
        switch rosterLane {
        case .activeMain:
            return .main
        case .supportRuntime:
            return .supportRuntime
        case .dormantArchive, .unknown:
            return .dormantAdvisor
        }
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
    let agent: AgentInfo
    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: Theme.sm) {
                    Text("To:")
                        .podTextStyle(.body, color: AppColors.textSecondary)
                    Text(agent.name)
                        .podTextStyle(.body, color: AppColors.textPrimary)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.md)
                .background(AppColors.backgroundSecondary)

                if let errorMessage {
                    HStack(spacing: Theme.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.accentDanger)
                        Text(errorMessage)
                            .podTextStyle(.caption, color: AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.sm)
                    .background(AppColors.accentDanger.opacity(0.12))
                }

                if isSending {
                    HStack(spacing: Theme.sm) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.accentElectric)
                        Text("Sending...")
                            .podTextStyle(.caption, color: AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.sm)
                    .background(AppColors.backgroundSecondary.opacity(0.7))
                }

                TextEditor(text: $messageText)
                    .scrollContentBackground(.hidden)
                    .background(AppColors.backgroundPrimary)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(Theme.md)
                    .disabled(isSending)

                Spacer()
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                        .disabled(isSending)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.accentElectric)
                    } else {
                        Button("Send") {
                            sendMessage()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.accentElectric)
                        .disabled(trimmedMessage.isEmpty)
                    }
                }
            }
        }
    }

    private var trimmedMessage: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendMessage() {
        let text = trimmedMessage
        guard !text.isEmpty, !isSending else { return }

        isSending = true
        errorMessage = nil

        Task {
            do {
                let service = AgentChatService(agent: agent)
                let stream = await service.send(message: text)
                for try await _ in stream {}

                await MainActor.run {
                    messageText = ""
                    isSending = false
                    dismiss()
                }
            } catch let apiError as APIError {
                await MainActor.run {
                    errorMessage = apiError.message
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
