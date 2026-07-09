import SwiftUI
import SwiftData
import UIKit

// MARK: - LockerChat Module
// 1:1 DM conversation surface for agent lanes.
// Evidence drawer accessible via long-press context menu (not primary tap).



// MARK: - Conversation View

struct LockerChatView: View {
    let viewModel: DirectChatViewModel
    let agent: AgentInfo

    @EnvironmentObject private var voiceCoordinator: VoiceCoordinator
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var isTextFieldFocused: Bool
    @State private var tabBarPadding: CGFloat = 83
    @State private var showingTicketConfirmation = false
    @State private var showingAttachTicketSheet = false
    @State private var showingTriageSheet = false
    @State private var showingToolRequestComposer = false
    @State private var toolRequestName = "agent_workspace_task"
    @State private var toolRequestInstruction = ""
    @State private var toolRequestReason = ""
    @State private var isContextExpanded = false
    @State private var areOlderMessagesExpanded = false
    @State private var selectedEvidenceMessage: DMMessage?
    @State private var selectedAgentPacketProject: AgentChatService.LockerWorkSpineProject?
    @State private var isShowingVoiceRoom = false

    private static let recentMessageLimit = 40

    var body: some View {
        VStack(spacing: 0) {
            chatContextSurface
            if !viewModel.routeProgressSteps.isEmpty {
                RouteProgressStrip(steps: viewModel.routeProgressSteps)
            }

            // Voice active banner
            if voiceCoordinator.isActive {
                HStack(spacing: 8) {
                    Circle()
                        .fill(lockerVoiceColor)
                        .frame(width: 7, height: 7)
                    Text(lockerVoiceStatusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(lockerVoiceColor)
                    Spacer()
                    Button(lockerVoiceActionText) {
                        if voiceCoordinator.activeAgentSlug == agent.id {
                            isShowingVoiceRoom = true
                        } else {
                            Task {
                                await voiceCoordinator.connect(agentSlug: agent.id)
                                isShowingVoiceRoom = true
                            }
                        }
                    }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentElectric)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(lockerVoiceColor.opacity(0.10))
                .overlay(Rectangle().fill(AppColors.border).frame(height: 0.5), alignment: .bottom)
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if shouldCompactMessages {
                            PlaygroundHistoryToggle(
                                hiddenCount: hiddenMessageCount,
                                isExpanded: areOlderMessagesExpanded,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        areOlderMessagesExpanded.toggle()
                                    }
                                    if !areOlderMessagesExpanded {
                                        scrollToLatestMessage(proxy, animated: false)
                                    }
                                }
                            )
                        }

                        ForEach(displayedMessages, id: \.id) { message in
                            messageBubble(message, agent: agent)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    scrollToLatestMessage(proxy, animated: false)
                }
                .onChange(of: viewModel.currentMessages.count) { _, _ in
                    scrollToLatestMessage(proxy, animated: true)
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    scrollToLatestMessage(proxy, animated: false)
                }
            }
            .background(AppColors.backgroundPrimary)

            // Error bar
            if let error = viewModel.error {
                HStack {
                    Image(systemName: viewModel.errorIsDestructive ? "exclamationmark.triangle.fill" : "bolt.horizontal.circle.fill")
                        .foregroundColor(viewModel.errorIsDestructive ? AppColors.accentDanger : AppColors.accentAgent)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(viewModel.errorIsDestructive ? AppColors.accentDanger : AppColors.accentAgent)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background((viewModel.errorIsDestructive ? AppColors.accentDanger : AppColors.accentAgent).opacity(0.1))
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.errorIsDestructive {
                        viewModel.retryLastFailedMessage()
                    }
                }
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
        .sheet(isPresented: $showingToolRequestComposer) {
            LockerToolRequestComposerSheet(
                ticketTitle: viewModel.activeTicketTitle ?? viewModel.activeTicketContinuity?.ticket.title ?? "Attached ticket",
                capabilities: viewModel.agentToolsProjection?.capabilities ?? [],
                selectedToolName: $toolRequestName,
                instruction: $toolRequestInstruction,
                reason: $toolRequestReason,
                isSubmitting: viewModel.isRequestingWorkspaceTool,
                onSubmit: {
                    viewModel.requestWorkspaceToolFromChat(
                        toolName: toolRequestName,
                        instruction: toolRequestInstruction,
                        reason: toolRequestReason
                    )
                    showingToolRequestComposer = false
                },
                onCancel: {
                    showingToolRequestComposer = false
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedAgentPacketProject) { project in
            let endpoint = trimmedAgentPacketEndpoint(for: project) ?? ""
            ProjectAgentPacketSheet(
                project: project,
                brief: endpoint.isEmpty ? nil : viewModel.agentPacketBriefByEndpoint[endpoint],
                isLoading: viewModel.isLoadingAgentPacket,
                errorMessage: viewModel.agentPacketError,
                onRetry: {
                    guard !endpoint.isEmpty else { return }
                    Task {
                        await viewModel.loadAgentPacket(endpoint: endpoint, for: agent)
                    }
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { selectedEvidenceMessage != nil },
                set: { if !$0 { selectedEvidenceMessage = nil } }
            )
        ) {
            if let message = selectedEvidenceMessage {
                SonarEvidenceDrawer(
                    message: message,
                    agent: agent,
                    channelId: viewModel.currentChannelId(for: agent),
                    activeTicketId: viewModel.activeTicketId
                )
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if voiceCoordinator.isActive && voiceCoordinator.activeAgentSlug == agent.id {
                        isShowingVoiceRoom = true
                    } else {
                        Task {
                            await voiceCoordinator.connect(agentSlug: agent.id)
                            isShowingVoiceRoom = true
                        }
                    }
                } label: {
                    Image(systemName: voiceCoordinator.isActive && voiceCoordinator.activeAgentSlug == agent.id
                          ? "phone.fill" : "phone")
                        .foregroundStyle(voiceCoordinator.isActive && voiceCoordinator.activeAgentSlug == agent.id
                                         ? AppColors.accentSuccess : AppColors.accentElectric)
                }
                .accessibilityLabel(lockerVoiceAccessibilityLabel)
            }
        }
        .sheet(isPresented: $isShowingVoiceRoom) {
            VoiceCompanionView(viewModel: voiceCoordinator.viewModel)
        }
    }

    private var shouldCompactMessages: Bool {
        viewModel.currentMessages.count > Self.recentMessageLimit
    }

    private var hiddenMessageCount: Int {
        max(0, viewModel.currentMessages.count - Self.recentMessageLimit)
    }

    private var displayedMessages: [DMMessage] {
        guard shouldCompactMessages, !areOlderMessagesExpanded else {
            return viewModel.currentMessages
        }
        return Array(viewModel.currentMessages.suffix(Self.recentMessageLimit))
    }

    private func scrollToLatestMessage(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = viewModel.currentMessages.last else { return }
        let scroll = {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    scroll()
                }
            } else {
                scroll()
            }
        }
    }

    private var lockerVoiceColor: Color {
        voiceCoordinator.activeAgentSlug == agent.id ? AppColors.accentSuccess : AppColors.accentWarning
    }

    private var lockerVoiceStatusText: String {
        if voiceCoordinator.activeAgentSlug == agent.id {
            return "Voice active — talking with \(voiceCoordinator.activeAgentDisplayName)"
        }
        return "Voice active with \(voiceCoordinator.activeAgentDisplayName) — tap to switch"
    }

    private var lockerVoiceActionText: String {
        voiceCoordinator.activeAgentSlug == agent.id ? "Open" : "Switch"
    }

    private var lockerVoiceAccessibilityLabel: String {
        if voiceCoordinator.isActive && voiceCoordinator.activeAgentSlug == agent.id {
            return "Voice call active with \(agent.name) — open"
        }
        if voiceCoordinator.isActive {
            return "Voice active with \(voiceCoordinator.activeAgentDisplayName) — tap to switch"
        }
        return "Call \(agent.name)"
    }

    @ViewBuilder
    private func messageBubble(_ message: DMMessage, agent: AgentInfo) -> some View {
        DMBubble(message: message, agent: agent, onRetry: { viewModel.retryMessage(message) })
            .contextMenu {
                Button {
                    selectedEvidenceMessage = message
                } label: {
                    Label("Show Evidence", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Label("Copy Message", systemImage: "doc.on.doc")
                }
            }
    }

    private var chatContextSurface: some View {
        VStack(spacing: 0) {
            compactContextBar

            if isContextExpanded {
                ticketContextBar
                ticketContinuityBar
                lockerCockpitPanel
                workClassroomPanel
                routeDecisionBar
            }
        }
    }

    private var compactContextBar: some View {
        HStack(spacing: 10) {
            Image(systemName: contextSummaryIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(contextSummaryColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(contextSummaryTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(contextSummaryDetail)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let summary = lockerSummary {
                lockerPolicyBadge(summary)
            } else if viewModel.isLoadingAgentLocker {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppColors.accentElectric)
            }

            Menu {
                ForEach(viewModel.availableDeliveryModes(for: agent), id: \.rawValue) { mode in
                    Button {
                        viewModel.selectedDeliveryMode = mode
                    } label: {
                        Label(deliveryLabel(for: mode), systemImage: deliveryIcon(for: mode))
                    }
                }
            } label: {
                Label(deliveryLabel(for: viewModel.selectedDeliveryMode), systemImage: deliveryIcon(for: viewModel.selectedDeliveryMode))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
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

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isContextExpanded.toggle()
                }
            } label: {
                Image(systemName: isContextExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.accentElectric)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isContextExpanded ? "Hide chat context" : "Show chat context")
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

    private var contextSummaryTitle: String {
        if let ticketId = viewModel.activeTicketId {
            return "ORCA ticket \(String(ticketId.prefix(8)))"
        }
        return "\(agent.name) lane"
    }

    private var contextSummaryDetail: String {
        if viewModel.activeTicketId != nil {
            let run = viewModel.activeTicketContinuity?.latestRunLabel
            let readiness = "\(viewModel.workClassroomReadinessPercent)% ready"
            return [run, readiness, viewModel.ticketLiveSummaryLabel]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        let channelText = viewModel.shortChannelId(for: agent).map { "ORCA channel \($0)" }
        let lockerText = lockerSummary.map { "Locker \($0.reportCardScore)%" }
        return [deliveryTruthText, channelText, lockerText, agent.boundaryText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var lockerSummary: AgentChatService.LockerSummary? {
        viewModel.agentLockerSummaryByAgent[agent.id]
    }

    private var contextSummaryIcon: String {
        if viewModel.activeTicketId != nil { return "text.badge.checkmark" }
        return deliveryIcon(for: viewModel.selectedDeliveryMode)
    }

    private var contextSummaryColor: Color {
        if viewModel.activeTicketId != nil { return AppColors.accentSuccess }
        return routeDecisionColor
    }

    @ViewBuilder
    private func lockerPolicyBadge(_ summary: AgentChatService.LockerSummary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: lockerPolicyIcon(summary))
                .font(.system(size: 10, weight: .semibold))
            Text(lockerPolicyText(summary))
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(lockerPolicyColor(summary))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(lockerPolicyColor(summary).opacity(0.10))
        .clipShape(Capsule())
        .accessibilityLabel("Locker policy \(lockerPolicyText(summary))")
    }

    @ViewBuilder
    private var lockerCockpitPanel: some View {
        if let summary = lockerSummary {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("Locker cockpit", systemImage: "rectangle.3.group.bubble.left")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentElectric)

                    Spacer(minLength: 0)

                    lockerPolicyBadge(summary)
                }

                if let headline = summary.startHereHeadline, !headline.isEmpty {
                    Text(headline)
                        .font(.caption)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                }

                if let division = summary.divisionName, !division.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(division)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        if let role = summary.divisionRole, !role.isEmpty {
                            Text(role)
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary)
                                .lineLimit(2)
                        }
                        if !summary.divisionLoopLabels.isEmpty {
                            FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                                ForEach(summary.divisionLoopLabels.prefix(5), id: \.self) { label in
                                    lockerMetricChip(label, color: AppColors.accentElectric)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text(summary.chatChannelName ?? "direct:\(agent.id)")
                    Text("\(summary.chatMessageCount) msg")
                    if summary.chatPendingCount > 0 {
                        Text("\(summary.chatPendingCount) pending")
                    }
                    if let status = summary.reportCardStatus, !status.isEmpty {
                        Text(status)
                    }
                }
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)

                HStack(spacing: 6) {
                    lockerCapabilityChip("Post", enabled: summary.chatCanPost)
                    lockerCapabilityChip("Ticket", enabled: summary.chatAllowedActions.contains("ticket"))
                    lockerCapabilityChip("Research", enabled: summary.chatAllowedActions.contains("research"))
                    lockerCapabilityChip("Run", enabled: summary.chatCanRun)
                }

                lockerWorkSpineRows(summary.workSpine)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(AppColors.backgroundSecondary.opacity(0.9))
            .overlay(
                Rectangle()
                    .fill(AppColors.border.opacity(0.7))
                    .frame(height: 0.5),
                alignment: .bottom
            )
        } else if viewModel.isLoadingAgentLocker {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text("Loading locker cockpit")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(AppColors.backgroundSecondary.opacity(0.9))
        } else if let error = viewModel.agentLockerError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.accentWarning)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(AppColors.backgroundSecondary.opacity(0.9))
        }
    }

    private func lockerCapabilityChip(_ label: String, enabled: Bool) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(enabled ? AppColors.accentSuccess : AppColors.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((enabled ? AppColors.accentSuccess : AppColors.textTertiary).opacity(0.10))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func lockerWorkSpineRows(_ workSpine: AgentChatService.LockerWorkSpineSummary) -> some View {
        if workSpine.hasWork {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Label("Work spine", systemImage: "rectangle.stack.badge.person.crop")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentAgent)

                    Spacer(minLength: 0)

                    lockerMetricChip("\(workSpine.projectCount) project", color: AppColors.accentElectric)
                    lockerMetricChip("\(workSpine.ticketCount) ticket", color: AppColors.accentSuccess)
                    lockerMetricChip("\(workSpine.taskCount) task", color: AppColors.accentAgent)
                    if workSpine.blockedCount > 0 {
                        lockerMetricChip("\(workSpine.blockedCount) blocked", color: AppColors.accentWarning)
                    }
                }

                if let project = workSpine.projects.first {
                    lockerWorkSpineProjectRow(project)
                }

                ForEach(Array((workSpine.tickets + workSpine.tasks).prefix(3))) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.kind == "task" ? "checklist" : "text.badge.checkmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(item.kind == "task" ? AppColors.accentAgent : AppColors.accentSuccess)
                        Text(item.title)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let status = item.status, !status.isEmpty {
                            Text(status.replacingOccurrences(of: "_", with: " "))
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary)
                                .lineLimit(1)
                        }
                        if let ref = shortWorkRef(item) {
                            Text(ref)
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                if let source = workSpine.source, !source.isEmpty {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func lockerWorkSpineProjectRow(_ project: AgentChatService.LockerWorkSpineProject) -> some View {
        if let endpoint = trimmedAgentPacketEndpoint(for: project) {
            Button {
                openAgentPacket(project, endpoint: endpoint)
            } label: {
                lockerWorkSpineProjectRowContent(project, isTappable: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open project agent packet for \(project.name)")
        } else {
            lockerWorkSpineProjectRowContent(project, isTappable: false)
        }
    }

    private func lockerWorkSpineProjectRowContent(
        _ project: AgentChatService.LockerWorkSpineProject,
        isTappable: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColors.accentElectric)
            Text(project.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
            Text([project.stage, project.status].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isTappable {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func trimmedAgentPacketEndpoint(for project: AgentChatService.LockerWorkSpineProject) -> String? {
        guard let endpoint = project.agentPacketEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !endpoint.isEmpty else {
            return nil
        }
        return endpoint
    }

    private func openAgentPacket(_ project: AgentChatService.LockerWorkSpineProject, endpoint: String) {
        selectedAgentPacketProject = project
        Task {
            await viewModel.loadAgentPacket(endpoint: endpoint, for: agent)
        }
    }

    private func lockerMetricChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func shortWorkRef(_ item: AgentChatService.LockerWorkSpineItem) -> String? {
        if let projectId = item.projectId, !projectId.isEmpty {
            return "P \(String(projectId.prefix(8)))"
        }
        if let sourceTicketId = item.sourceTicketId, !sourceTicketId.isEmpty {
            return "T \(String(sourceTicketId.prefix(8)))"
        }
        if let boardId = item.boardId, !boardId.isEmpty {
            return "B \(String(boardId.prefix(8)))"
        }
        return nil
    }

    private func lockerPolicyText(_ summary: AgentChatService.LockerSummary) -> String {
        switch summary.chatPolicyState {
        case "ticket_required":
            return "Ticket gate"
        case "protected":
            return "Protected"
        case "open":
            return "Open"
        default:
            if let lane = summary.chatPolicyLane, !lane.isEmpty {
                return lane.capitalized
            }
            return "Locker"
        }
    }

    private func lockerPolicyIcon(_ summary: AgentChatService.LockerSummary) -> String {
        switch summary.chatPolicyState {
        case "ticket_required":
            return "text.badge.checkmark"
        case "protected":
            return "lock.fill"
        case "open":
            return "checkmark.circle.fill"
        default:
            return "rectangle.3.group.bubble.left"
        }
    }

    private func lockerPolicyColor(_ summary: AgentChatService.LockerSummary) -> Color {
        switch summary.chatPolicyState {
        case "ticket_required":
            return AppColors.accentWarning
        case "protected":
            return AppColors.accentDanger
        case "open":
            return AppColors.accentSuccess
        default:
            return AppColors.accentElectric
        }
    }

    private var deliveryTruthText: String {
        switch viewModel.selectedDeliveryMode {
        case .compute:
            return "Helper draft for \(agent.name), not live runtime"
        case .liveInbox:
            return "Send to \(agent.name)'s inbox and wait for reply"
        case .agentRun:
            return "Agent Run requires attached ticket"
        case .auto:
            return "Merman/Schoolhouse auto route"
        case .fallback:
            return "Local guardrail fallback"
        case .system:
            return "System status"
        case .ticket:
            return "Ticket evidence"
        }
    }

    @ViewBuilder
    private var workClassroomPanel: some View {
        if viewModel.activeTicketId != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(awakeStateLabel, systemImage: awakeStateIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentAgent)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Label("\(viewModel.workClassroomReadinessPercent)%", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(readinessColor)

                    Button {
                        viewModel.refreshWorkClassroomFromChat()
                    } label: {
                        Image(systemName: viewModel.isRefreshingWorkClassroom ? "hourglass" : "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.accentElectric)
                            .frame(width: 28, height: 28)
                            .background(AppColors.accentElectric.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRefreshingWorkClassroom)
                    .accessibilityLabel(viewModel.isRefreshingWorkClassroom ? "Refreshing classroom" : "Refresh classroom")

                    // Overflow menu — Approval / Memory / Artifact / Tool
                    Menu {
                        Button {
                            viewModel.requestApprovalFromChat()
                        } label: {
                            Label(
                                viewModel.isRequestingTicketApproval ? "Requesting Approval…" : "Request Approval",
                                systemImage: "person.badge.key"
                            )
                        }
                        .disabled(viewModel.isRequestingTicketApproval)

                        Button {
                            viewModel.saveMemoryCandidateFromChat()
                        } label: {
                            Label(
                                viewModel.isSavingMemoryCandidate ? "Saving Lesson…" : "Learn from Chat",
                                systemImage: "brain.head.profile"
                            )
                        }
                        .disabled(viewModel.isSavingMemoryCandidate)

                        Button {
                            viewModel.saveWorkspaceArtifactFromChat()
                        } label: {
                            Label(
                                viewModel.isSavingWorkspaceArtifact ? "Saving Artifact…" : "Save Workspace Artifact",
                                systemImage: "doc.badge.plus"
                            )
                        }
                        .disabled(viewModel.isSavingWorkspaceArtifact)

                        Button {
                            openToolRequestComposer()
                        } label: {
                            Label(
                                viewModel.isRequestingWorkspaceTool ? "Requesting Tool…" : "Request Workspace Tool",
                                systemImage: "hammer"
                            )
                        }
                        .disabled(viewModel.isRequestingWorkspaceTool)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.accentElectric)
                            .frame(width: 28, height: 28)
                            .background(AppColors.accentElectric.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Classroom actions")
                }

                classroomToolRail
                agentToolProjectionRows
                runtimeProvenanceRows

                HStack(spacing: 8) {
                    Text(viewModel.workClassroomRefreshLabel)
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
                classroomGapRows
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

    private var classroomToolRail: some View {
        HStack(spacing: 8) {
            Text("TOOLS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 38, alignment: .leading)

            classroomActionButton(
                icon: "person.badge.key",
                label: viewModel.isRequestingTicketApproval ? "Requesting approval" : "Request approval",
                tint: AppColors.accentWarning,
                isBusy: viewModel.isRequestingTicketApproval
            ) {
                viewModel.requestApprovalFromChat()
            }

            classroomActionButton(
                icon: "hammer",
                label: viewModel.isRequestingWorkspaceTool ? "Requesting tool" : "Request workspace tool",
                tint: AppColors.accentElectric,
                isBusy: viewModel.isRequestingWorkspaceTool
            ) {
                openToolRequestComposer()
            }

            classroomActionButton(
                icon: "doc.badge.plus",
                label: viewModel.isSavingWorkspaceArtifact ? "Saving artifact" : "Save workspace artifact",
                tint: AppColors.accentSuccess,
                isBusy: viewModel.isSavingWorkspaceArtifact
            ) {
                viewModel.saveWorkspaceArtifactFromChat()
            }

            classroomActionButton(
                icon: "brain.head.profile",
                label: viewModel.isSavingMemoryCandidate ? "Saving lesson" : "Learn from chat",
                tint: AppColors.accentAgent,
                isBusy: viewModel.isSavingMemoryCandidate
            ) {
                viewModel.saveMemoryCandidateFromChat()
            }

            Spacer(minLength: 0)
        }
    }

    private func classroomActionButton(
        icon: String,
        label: String,
        tint: Color,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: isBusy ? "hourglass" : icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(label)
        .help(label)
    }

    private func openToolRequestComposer() {
        let typedInstruction = viewModel.composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackInstruction = viewModel.activeTicketContinuity?.nextActionLabel
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedCapability = viewModel.agentToolsProjection?.capabilities.first { capability in
            capability.id == "workspace_artifact" && capability.normalizedStatus == "available"
        }

        toolRequestName = selectedCapability?.id ?? "agent_workspace_task"
        toolRequestInstruction = typedInstruction.isEmpty ? fallbackInstruction : typedInstruction
        toolRequestReason = "Owner-approved observe-only request from \(agent.name) chat."
        showingToolRequestComposer = true
    }

    @ViewBuilder
    private var agentToolProjectionRows: some View {
        if viewModel.isLoadingAgentTools {
            Label("Loading ORCA tool projection", systemImage: "wrench.and.screwdriver")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        } else if let projection = viewModel.agentToolsProjection {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Label("ORCA tools", systemImage: "wrench.and.screwdriver.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentElectric)

                    Spacer(minLength: 0)

                    Text(projection.protectedLevel.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(projection.protectedLevel == "open" ? AppColors.accentSuccess : AppColors.accentWarning)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background((projection.protectedLevel == "open" ? AppColors.accentSuccess : AppColors.accentWarning).opacity(0.10))
                        .clipShape(Capsule())
                }

                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(projection.capabilities.prefix(7)) { capability in
                        agentToolCapabilityChip(capability)
                    }
                }

                Text("\(projection.availableCapabilities.count) available · \(projection.disabledCapabilities.count) held · \(projection.provenanceSourceLabel)")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(2)

                if !projection.gaps.isEmpty {
                    Text(projection.gaps.prefix(2).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(AppColors.accentWarning)
                        .lineLimit(2)
                } else {
                    Text(projection.richToolsPolicy.replacingOccurrences(of: "_", with: " "))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
        } else if let error = viewModel.agentToolsError {
            Label(error, systemImage: "wrench.adjustable")
                .font(.caption2)
                .foregroundStyle(AppColors.accentWarning)
                .lineLimit(2)
        }
    }

    private func agentToolCapabilityChip(_ capability: WorkbenchAgentToolCapability) -> some View {
        let color = agentToolCapabilityColor(capability)
        return HStack(spacing: 4) {
            Image(systemName: agentToolCapabilityIcon(capability))
                .font(.system(size: 9, weight: .semibold))
            Text(capability.label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            if capability.requiresApproval {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
        .accessibilityLabel("\(capability.label) \(capability.status)")
        .help(capability.blockedReasons.first ?? capability.mode ?? capability.status)
    }

    private func agentToolCapabilityColor(_ capability: WorkbenchAgentToolCapability) -> Color {
        switch capability.normalizedStatus {
        case "available":
            return capability.requiresApproval ? AppColors.accentWarning : AppColors.accentSuccess
        case "disabled", "blocked":
            return AppColors.textTertiary
        default:
            return AppColors.accentElectric
        }
    }

    private func agentToolCapabilityIcon(_ capability: WorkbenchAgentToolCapability) -> String {
        switch capability.toolClass {
        case "read_context":
            return "book"
        case "preview":
            return "eye"
        case "workspace_artifact":
            return "folder.badge.gearshape"
        case "agent_action":
            return "paperplane"
        case "compute":
            return "cpu"
        case "external_or_desktop":
            return "desktopcomputer"
        case "protected":
            return "lock.shield"
        default:
            return capability.requiresApproval ? "checkmark.shield" : "wrench.and.screwdriver"
        }
    }

    @ViewBuilder
    private var runtimeProvenanceRows: some View {
        if let run = viewModel.activeTicketContinuity?.latestRun {
            VStack(alignment: .leading, spacing: 6) {
                Label("Runtime provenance", systemImage: "cpu")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)

                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    provenancePill("run", value: shortRef(run.id), color: AppColors.accentElectric)
                    provenancePill("trace", value: shortRef(run.traceId), color: AppColors.accentElectric)
                    provenancePill("backend", value: run.backend, color: AppColors.accentSuccess)
                    provenancePill("model", value: run.model, color: AppColors.accentAgent)
                    provenancePill("tier", value: run.tier, color: AppColors.textSecondary)
                    provenancePill("route", value: run.operationalRouteLabel, color: AppColors.textSecondary)
                    provenancePill("policy", value: run.toolPolicy, color: AppColors.accentWarning)
                }

                if let label = run.operationalSourceLabel {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
        } else if viewModel.activeTicketId != nil {
            Label("Runtime provenance will appear after an Agent Run attaches.", systemImage: "cpu")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    @ViewBuilder
    private func provenancePill(_ label: String, value: String?, color: Color) -> some View {
        if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            Text("\(label) \(value)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(color.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    private func shortRef(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        guard value.count > 16 else { return value }
        return "\(value.prefix(8))...\(value.suffix(4))"
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
    private var classroomGapRows: some View {
        let gaps = viewModel.workClassroomGapLabels
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
        let percent = viewModel.workClassroomReadinessPercent
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
                    PodReviewCard(
                        item: workspaceToolReviewItem(for: request),
                        isBusy: viewModel.executingWorkspaceToolRunIds.contains(request.runId),
                        onAction: { action in
                            if action.id == "execute" {
                                viewModel.executeWorkspaceToolRequestFromChat(request)
                            }
                        }
                    )
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

    private func workspaceToolReviewItem(for request: DirectChatWorkspaceToolRequest) -> PodReviewItem {
        let normalizedStatus = request.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let canExecute = normalizedStatus == "waiting_for_human" || normalizedStatus == "queued"
        let statusLabel = normalizedStatus.replacingOccurrences(of: "_", with: " ").capitalized
        var provenance = [
            request.toolName,
            request.createdAt.formatted(date: .abbreviated, time: .shortened)
        ]
        if let reason = request.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            provenance.append(reason)
        }

        return PodReviewItem(
            id: request.runId,
            eyebrow: "Workspace tool request",
            title: request.instructionPreview.isEmpty ? request.toolName : request.instructionPreview,
            detail: canExecute
                ? "Owner approval materializes this as a bounded ORCA workspace artifact."
                : "Recorded in ORCA for ticket workspace review.",
            status: statusLabel.isEmpty ? "Unknown" : statusLabel,
            statusColor: workspaceToolStatusColor(normalizedStatus),
            provenance: provenance,
            traceId: request.runId,
            actions: canExecute
                ? [PodReviewAction(id: "execute", title: "Execute", systemImage: "checkmark.shield", style: .success)]
                : []
        )
    }

    private func workspaceToolStatusColor(_ status: String) -> Color {
        switch status {
        case "succeeded", "complete", "completed":
            return AppColors.accentSuccess
        case "failed", "error", "cancelled":
            return AppColors.accentDanger
        case "waiting_for_human", "queued":
            return AppColors.accentWarning
        default:
            return AppColors.accentElectric
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
                        Label(deliveryLabel(for: mode), systemImage: deliveryIcon(for: mode))
                    }
                }
            } label: {
                Label(deliveryLabel(for: viewModel.selectedDeliveryMode), systemImage: deliveryIcon(for: viewModel.selectedDeliveryMode))
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

                        agentRunClassroom(for: continuity)
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

    private func agentRunClassroom(for continuity: DirectChatTicketContinuity) -> some View {
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
            return "Helper draft for \(agent.name)"
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

    private func deliveryLabel(for mode: DMDeliveryMode) -> String {
        switch mode {
        case .compute:
            return "Helper draft"
        case .liveInbox:
            return "\(agent.name) inbox"
        case .agentRun:
            return "ORCA Agent Run"
        case .auto:
            return "Auto route"
        case .fallback:
            return "Local fallback"
        case .system:
            return "System"
        case .ticket:
            return "Ticket"
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

            TextField("Message \(agent.name) lane...", text: Binding(
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

private struct ProjectAgentPacketSheet: View {
    let project: AgentChatService.LockerWorkSpineProject
    let brief: AgentChatService.ProjectAgentPacketBrief?
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Project") {
                    labeledValue("Name", brief?.projectName ?? project.name)
                    if let status = cleaned(brief?.projectStatus) ?? cleaned(project.status) {
                        labeledValue("Status", formatted(status))
                    }
                    if let stage = cleaned(brief?.projectStage) ?? cleaned(project.stage) {
                        labeledValue("Stage", formatted(stage))
                    }
                    if let brief {
                        labeledValue("Boards", "\(brief.boardIds.count)")
                    }
                }

                if isLoading {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(AppColors.accentElectric)
                            Text("Loading project brief")
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer(minLength: 0)
                        }
                    }
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Section {
                        ErrorBannerView(message: errorMessage, retryTitle: "Retry", retry: onRetry)
                    }
                }

                if let brief {
                    Section("Tickets (\(brief.ticketCount))") {
                        if brief.tickets.isEmpty {
                            emptyRow("No tickets in this packet")
                        } else {
                            ForEach(brief.tickets) { ticket in
                                ticketRow(ticket)
                            }
                        }
                    }

                    Section("Work tasks (\(brief.workTaskCount))") {
                        if brief.workTasks.isEmpty {
                            emptyRow("No work tasks in this packet")
                        } else {
                            ForEach(brief.workTasks) { task in
                                taskRow(task)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Agent Packet")
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

    private func ticketRow(_ ticket: AgentChatService.ProjectAgentPacketTicket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ticket.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if let status = cleaned(ticket.status) {
                    packetChip(formatted(status), color: AppColors.accentSuccess)
                }
                if let priority = cleaned(ticket.priority) {
                    packetChip(formatted(priority), color: AppColors.accentWarning)
                }
                if let ticketType = cleaned(ticket.ticketType) {
                    packetChip(formatted(ticketType), color: AppColors.accentElectric)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func taskRow(_ task: AgentChatService.ProjectAgentPacketTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if let status = cleaned(task.status) {
                    packetChip(formatted(status), color: AppColors.accentAgent)
                }
                if let stage = cleaned(task.stage) {
                    packetChip(formatted(stage), color: AppColors.accentElectric)
                }
                if let priority = cleaned(task.priority) {
                    packetChip(formatted(priority), color: AppColors.accentWarning)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppColors.textTertiary)
    }

    private func packetChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func formatted(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
    }
}

private struct ErrorBannerView: View {
    let message: String
    let retryTitle: String?
    let retry: (() -> Void)?

    init(message: String, retryTitle: String? = nil, retry: (() -> Void)? = nil) {
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.accentWarning)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retryTitle, let retry {
                Button(retryTitle, action: retry)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)
            }
        }
        .padding(12)
        .background(AppColors.accentWarning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

struct PlaygroundHistoryToggle: View {
    let hiddenCount: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(isExpanded ? "Hide earlier messages" : "\(hiddenCount) earlier messages")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(isExpanded ? "Collapse" : "Show")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .foregroundStyle(AppColors.accentElectric)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.accentElectric.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppColors.accentElectric.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide earlier messages" : "Show \(hiddenCount) earlier messages")
    }
}

private struct LockerToolRequestComposerSheet: View {
    let ticketTitle: String
    let capabilities: [WorkbenchAgentToolCapability]
    @Binding var selectedToolName: String
    @Binding var instruction: String
    @Binding var reason: String
    let isSubmitting: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    private let options = LockerToolRequestOption.defaults

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    toolPicker
                    instructionEditor
                    reasonEditor
                    policyStrip
                }
                .padding(16)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Tool Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSubmit()
                    } label: {
                        Label(isSubmitting ? "Submitting" : "Submit", systemImage: isSubmitting ? "hourglass" : "checkmark.shield")
                    }
                    .disabled(isSubmitting || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if !options.contains(where: { $0.id == selectedToolName }) {
                    selectedToolName = "agent_workspace_task"
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(ticketTitle.prefix(96)), systemImage: "ticket")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Text("SEC-010 observe-only broker")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColors.accentWarning)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.accentWarning.opacity(0.10))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var toolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tool Kind")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)

            Picker("Tool Kind", selection: $selectedToolName) {
                ForEach(options) { option in
                    Label(option.label, systemImage: option.icon)
                        .tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .tint(AppColors.accentElectric)

            if let selected = options.first(where: { $0.id == selectedToolName }) {
                Label(selected.detail, systemImage: selected.icon)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var instructionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instruction")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)

            TextEditor(text: $instruction)
                .font(.body)
                .foregroundStyle(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 118)
                .padding(8)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var reasonEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reason")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)

            TextField("Why this tool request is needed", text: $reason, axis: .vertical)
                .font(.body)
                .lineLimit(2...4)
                .padding(10)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var policyStrip: some View {
        if !capabilities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Policy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)

                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(capabilities.prefix(7)) { capability in
                        capabilityPill(capability)
                    }
                }
            }
            .padding(12)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func capabilityPill(_ capability: WorkbenchAgentToolCapability) -> some View {
        let color: Color = capability.normalizedStatus == "available"
            ? (capability.requiresApproval ? AppColors.accentWarning : AppColors.accentSuccess)
            : AppColors.textTertiary
        return Label(capability.label, systemImage: capability.requiresApproval ? "checkmark.shield" : "wrench.and.screwdriver")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }
}

private struct LockerToolRequestOption: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let detail: String

    static let defaults: [LockerToolRequestOption] = [
        LockerToolRequestOption(
            id: "agent_workspace_task",
            label: "Workspace Task",
            icon: "hammer",
            detail: "Records a bounded request for owner-reviewed workspace follow-up."
        ),
        LockerToolRequestOption(
            id: "workspace_artifact",
            label: "Workspace Artifact",
            icon: "doc.badge.plus",
            detail: "Creates an observe-only artifact request tied to this ticket."
        ),
        LockerToolRequestOption(
            id: "evidence_pack",
            label: "Evidence Pack",
            icon: "point.topleft.down.curvedto.point.bottomright.up",
            detail: "Asks ORCA to assemble trace, file, and run evidence."
        ),
        LockerToolRequestOption(
            id: "code_review_packet",
            label: "Code Review Packet",
            icon: "curlybraces.square",
            detail: "Prepares a review packet for changed files and residual risk."
        ),
        LockerToolRequestOption(
            id: "research_packet",
            label: "Research Packet",
            icon: "magnifyingglass",
            detail: "Stages a research handoff without running external tools."
        ),
        LockerToolRequestOption(
            id: "runtime_probe_plan",
            label: "Runtime Probe Plan",
            icon: "stethoscope",
            detail: "Captures a bounded diagnostic plan for later approved execution."
        )
    ]
}

private struct SonarEvidenceDrawer: View {
    let message: DMMessage
    let agent: AgentInfo
    let channelId: String?
    let activeTicketId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var surfaceEvents: [SonarSurfaceEventDTO] = []
    @State private var computeRuns: [SonarComputeRunDTO] = []
    @State private var didCopyEvidence = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    copyButton
                    eventSection
                    computeSection
                }
                .padding(16)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Playground Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        copyEvidencePacket()
                    } label: {
                        Label(didCopyEvidence ? "Copied" : "Copy", systemImage: didCopyEvidence ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: message.id) {
                await loadEvidence()
            }
            .refreshable {
                await loadEvidence()
            }
        }
    }

    private var copyButton: some View {
        Button {
            copyEvidencePacket()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: didCopyEvidence ? "checkmark.circle.fill" : "doc.on.doc")
                Text(didCopyEvidence ? "Evidence packet copied" : "Copy evidence packet")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(didCopyEvidence ? AppColors.accentSuccess : AppColors.accentElectric)
            .padding(12)
            .background((didCopyEvidence ? AppColors.accentSuccess : AppColors.accentElectric).opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(AppColors.accentElectric)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agent.name) message proof")
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                Spacer()
            }

            evidenceRow("Delivery", DMDeliveryState.parse(message.deliveryState)?.displayLabel ?? "Unknown")
            evidenceRow("Reason", message.deliveryError)
            evidenceRow("Failed hop", message.deliveryFailedHop)
            evidenceRow("Evidence", message.deliveryEvidence)
            evidenceRow("Provenance", provenanceLabel)
            evidenceRow("Trace", short(message.traceId))
            evidenceRow("Message", short(message.remoteMessageId))
            evidenceRow("Compute run", short(message.computeRunId))
            evidenceRow("Channel", short(channelId))
            evidenceRow("Ticket", short(activeTicketId))
            evidenceRow("File", message.fileAttachment?.path)
            evidenceRow("Model", message.modelUsed?.isEmpty == false ? message.modelUsed : nil)
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var eventSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ORCA surface events", systemImage: "rectangle.stack.badge.person.crop")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)

            if isLoading {
                ProgressView("Loading ORCA evidence...")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AppColors.accentWarning)
            } else if surfaceEvents.isEmpty {
                Text("No matching surface events found yet.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ForEach(surfaceEvents, id: \.id) { event in
                    SonarSurfaceEventRow(event: event)
                }
            }
        }
    }

    @ViewBuilder
    private var computeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Compute records", systemImage: "cpu")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)

            if isLoading {
                EmptyView()
            } else if computeRuns.isEmpty {
                Text("No compute run matched this trace.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ForEach(computeRuns, id: \.id) { run in
                    SonarComputeRunRow(run: run)
                }
            }
        }
    }

    private var provenanceLabel: String {
        (DMResponseProvenance.parse(message.provenance)
            ?? DMResponseProvenance(deliveryMode: message.deliveryMode, source: message.source, lane: message.lane))
            .displayLabel
    }

    private func evidenceRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 86, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "Not recorded")
                .font(.caption)
                .foregroundStyle(value?.isEmpty == false ? AppColors.textPrimary : AppColors.textTertiary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func loadEvidence() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let packet: SonarEvidencePacketDTO = try await APIClient.shared.get(
                path: evidencePath
            )
            surfaceEvents = packet.surfaceEvents
            computeRuns = packet.computeRuns
        } catch let apiError as APIError {
            errorMessage = apiError.message
        } catch {
            errorMessage = "Evidence is unavailable right now."
        }
    }

    private var evidencePath: String {
        if let remoteMessageId = clean(message.remoteMessageId) {
            return "/api/v1/sonar/evidence?message_id=\(urlQuery(remoteMessageId))&limit=20"
        }
        if let traceId = clean(message.traceId) {
            return "/api/v1/sonar/evidence?trace_id=\(urlQuery(traceId))&limit=20"
        }
        return "/api/v1/sonar/evidence?source_event_id=\(urlQuery(message.id.uuidString))&limit=20"
    }

    private func copyEvidencePacket() {
        UIPasteboard.general.string = evidencePacket
        didCopyEvidence = true
    }

    private var evidencePacket: String {
        """
        # Sonar Evidence
        Agent: \(agent.name)
        Message ID: \(message.remoteMessageId ?? message.id.uuidString)
        Channel ID: \(channelId ?? "not recorded")
        Ticket ID: \(activeTicketId ?? "not recorded")
        Delivery: \(DMDeliveryState.parse(message.deliveryState)?.displayLabel ?? "unknown")
        Reason: \(message.deliveryError ?? "not recorded")
        Failed hop: \(message.deliveryFailedHop ?? "not recorded")
        Evidence: \(message.deliveryEvidence ?? "not recorded")
        Provenance: \(provenanceLabel)
        Trace: \(message.traceId ?? "not recorded")
        Compute run: \(message.computeRunId ?? "not recorded")
        File: \(message.fileAttachment?.path ?? "not recorded")
        Model: \(message.modelUsed ?? "not recorded")
        Surface events: \(surfaceEvents.map(\.id).joined(separator: ", "))
        Compute runs: \(computeRuns.map(\.id).joined(separator: ", "))

        Content:
        \(message.content)
        """
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func short(_ value: String?) -> String? {
        guard let value = clean(value) else { return nil }
        guard value.count > 18 else { return value }
        return "\(value.prefix(10))...\(value.suffix(6))"
    }

    private func urlQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

struct SonarSurfaceEventRow: View {
    let event: SonarSurfaceEventDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(event.status, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(event.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
            Text(event.summary ?? event.textPreview ?? "Surface event recorded.")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(3)
            Text(event.provenanceLine)
                .font(.caption2)
                .foregroundStyle(event.isComputeDraft ? AppColors.accentWarning : AppColors.textTertiary)
                .lineLimit(1)
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var icon: String {
        if event.isComputeDraft { return "cpu" }
        return event.status.lowercased().contains("fail") ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var tint: Color {
        if event.isComputeDraft { return AppColors.accentWarning }
        return event.status.lowercased().contains("fail") ? AppColors.accentWarning : AppColors.accentSuccess
    }
}

struct SonarComputeRunRow: View {
    let run: SonarComputeRunDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(run.status, systemImage: run.fallbackUsed ? "exclamationmark.triangle" : "cpu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(run.fallbackUsed ? AppColors.accentWarning : AppColors.accentElectric)
                Spacer()
                Text(run.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
            Text([run.taskHint, run.route, run.actualBackend ?? run.backend, run.model].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
            if let latency = run.latencyMs {
                Text("\(latency)ms")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
            if let error = run.error, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(AppColors.accentWarning)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SonarThreadMessageRow: View {
    let message: SonarThreadMessageDTO
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(label, systemImage: message.isThreadReply ? "arrow.turn.down.right" : "bubble.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.isThreadReply ? AppColors.accentElectric : AppColors.textSecondary)
                Spacer()
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
            Text(message.senderName ?? "Unknown")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
            Text(message.content)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(4)
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SonarEvidencePacketDTO: Decodable {
    let generatedAt: Date
    let surfaceEvents: [SonarSurfaceEventDTO]
    let computeRuns: [SonarComputeRunDTO]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case surfaceEvents = "surface_events"
        case computeRuns = "compute_runs"
    }
}

struct SonarThreadPacketDTO: Decodable {
    let generatedAt: Date
    let root: SonarThreadMessageDTO?
    let replies: [SonarThreadMessageDTO]
    let replyCount: Int

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case root, replies
        case replyCount = "reply_count"
    }
}

struct SonarThreadMessageDTO: Decodable {
    let id: String
    let channelId: String
    let senderName: String?
    let senderType: String?
    let senderEmoji: String?
    let content: String
    let messageType: String
    let replyToId: String?
    let isThreadReply: Bool
    let traceId: String?
    let source: String?
    let lane: String?
    let deliveryMode: String?
    let provenance: String?
    let responseState: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content, source, lane, provenance
        case channelId = "channel_id"
        case senderName = "sender_name"
        case senderType = "sender_type"
        case senderEmoji = "sender_emoji"
        case messageType = "message_type"
        case replyToId = "reply_to_id"
        case isThreadReply = "is_thread_reply"
        case traceId = "trace_id"
        case deliveryMode = "delivery_mode"
        case responseState = "response_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SonarSurfaceEventDTO: Decodable {
    let id: String
    let direction: String
    let eventType: String
    let actorKind: String
    let actorId: String?
    let traceId: String?
    let threadId: String?
    let chatChannelId: String?
    let chatMessageId: String?
    let ticketId: String?
    let computeRunId: String?
    let provider: String?
    let model: String?
    let provenance: String?
    let status: String
    let summary: String?
    let textPreview: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, direction, status, summary, model, provider, provenance
        case eventType = "event_type"
        case actorKind = "actor_kind"
        case actorId = "actor_id"
        case traceId = "trace_id"
        case threadId = "thread_id"
        case chatChannelId = "chat_channel_id"
        case chatMessageId = "chat_message_id"
        case ticketId = "ticket_id"
        case computeRunId = "compute_run_id"
        case textPreview = "text_preview"
        case createdAt = "created_at"
    }

    var isComputeDraft: Bool {
        ["spark", "kimi", "openclaw"].contains((provider ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    var provenanceLine: String {
        var parts: [String] = [direction, actorKind]
        if let actorId, !actorId.isEmpty {
            parts.append(actorId)
        }
        if isComputeDraft {
            parts.append("\((provider ?? "compute").capitalized) helper draft")
        } else if let provenance, !provenance.isEmpty {
            parts.append(provenance.replacingOccurrences(of: "_", with: " "))
        }
        if let model, !model.isEmpty {
            parts.append(model)
        }
        return parts.joined(separator: " · ")
    }
}

struct SonarComputeRunDTO: Decodable {
    let id: String
    let traceId: String?
    let surface: String
    let taskHint: String
    let route: String
    let requestedRoute: String?
    let requestedComputeTag: String?
    let actualTier: String?
    let actualBackend: String?
    let model: String?
    let backend: String?
    let status: String
    let fallbackUsed: Bool
    let latencyMs: Int?
    let error: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, surface, route, model, backend, status, error
        case traceId = "trace_id"
        case taskHint = "task_hint"
        case requestedRoute = "requested_route"
        case requestedComputeTag = "requested_compute_tag"
        case actualTier = "actual_tier"
        case actualBackend = "actual_backend"
        case fallbackUsed = "fallback_used"
        case latencyMs = "latency_ms"
        case createdAt = "created_at"
    }
}

// MARK: - Message Bubble

struct DMBubble: View {
    let message: DMMessage
    let agent: AgentInfo
    var onRetry: (() -> Void)? = nil

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

                if let attachment = message.fileAttachment {
                    ChatFileAttachmentChip(attachment: attachment, compact: true)
                        .frame(maxWidth: 420)
                }

                if !isUser {
                    MessageDeliveryLedger(message: message, agent: agent)
                }

                if isUser {
                    userDeliveryChip
                        .padding(.top, 2)
                }

                // Retry button for failed user messages
                if isUser,
                   isRetryableUserDelivery,
                   let retry = onRetry {
                    HStack(spacing: 8) {
                        Label(userDeliveryFailureLabel, systemImage: userDeliveryFailureIcon)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.accentDanger)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColors.accentDanger.opacity(0.12))
                            .clipShape(Capsule())

                        Button(action: retry) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.medium))
                                .foregroundColor(AppColors.accentDanger)
                        }
                    }
                    .padding(.top, 2)
                }

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
            parts.append(Self.deliveryLabel(deliveryMode, agent: agent))
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
            return "Waiting for the helper draft..."
        case .agentRunQueued:
            return "Agent Run queued in ORCA..."
        case .agentRunRunning:
            return "Agent Run is running in ORCA..."
        case .waitingForLiveAgent:
            return "Waiting for the live inbox reply..."
        case .deliveryNatsFailed:
            return "Not delivered - NATS transport failed"
        case .agentUnresponsive:
            return "Not delivered - agent unresponsive"
        default:
            return message.isStreaming ? "Routing through ORCA..." : ""
        }
    }

    private var streamingStatusText: String {
        switch deliveryState {
        case .computeRunning:
            return "Compute helper accepted."
        case .agentRunQueued:
            return "Agent Run queued."
        case .agentRunRunning:
            return "Agent Run running."
        case .waitingForLiveAgent:
            return "Live inbox acknowledged."
        case .deliveryNatsFailed:
            return "Transport failed."
        case .agentUnresponsive:
            return "Delivery failed."
        default:
            return message.content.isEmpty ? "Routing through ORCA." : "Receiving..."
        }
    }

    private static func shortTraceLabel(_ traceId: String) -> String {
        let trimmed = traceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 18 else { return trimmed }
        return "\(trimmed.prefix(10))...\(trimmed.suffix(6))"
    }

    private static func deliveryLabel(_ mode: DMDeliveryMode, agent: AgentInfo) -> String {
        switch mode {
        case .compute:
            return "Helper draft"
        case .liveInbox:
            return "\(agent.name) inbox"
        case .agentRun:
            return "ORCA Agent Run"
        case .auto:
            return "Auto route"
        case .fallback:
            return "Local fallback"
        case .system:
            return "Pod system"
        case .ticket:
            return "ORCA ticket"
        }
    }

    @ViewBuilder
    private var provenanceLabel: some View {
        Label(visibleProvenanceLabel, systemImage: provenanceIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(provenanceColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(provenanceColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Response provenance: \(visibleProvenanceLabel)")
    }

    private var provenance: DMResponseProvenance {
        if hasComputeAttribution {
            return .compute
        }
        if let value = DMResponseProvenance.parse(message.provenance) {
            return value
        }
        return DMResponseProvenance(deliveryMode: message.deliveryMode, source: message.source, lane: message.lane)
    }

    private var visibleProvenanceLabel: String {
        if let computeDraftLabel {
            return computeDraftLabel
        }
        if provenance == .liveInbox, deliveryState == .responseReceived {
            return "\(agent.name) replied"
        }
        return provenance.displayLabel
    }

    @ViewBuilder
    private var deliveryStateLabel: some View {
        if deliveryState != nil {
            Label(visibleDeliveryStateLabel, systemImage: deliveryStateIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(deliveryStateColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(deliveryStateColor.opacity(0.12))
                .clipShape(Capsule())
                .accessibilityLabel("Delivery state: \(visibleDeliveryStateLabel)")
        }
    }

    private var deliveryState: DMDeliveryState? {
        DMDeliveryState.parse(message.deliveryState)
    }

    private var visibleDeliveryStateLabel: String {
        if deliveryState == .waitingForLiveAgent {
            return "Waiting for \(agent.name)"
        }
        if deliveryState == .deliveryNatsFailed {
            return "Not delivered - NATS failed"
        }
        if deliveryState == .agentUnresponsive {
            return "Agent unresponsive"
        }
        return deliveryState?.displayLabel ?? ""
    }

    @ViewBuilder
    private var userDeliveryChip: some View {
        switch userDeliveryState {
        case .sending:
            userDeliveryLabel("Sending", icon: "paperplane", tint: AppColors.textTertiary)
        case .accepted:
            userDeliveryLabel("Recorded - awaiting confirmation", icon: "tray.and.arrow.down", tint: AppColors.accentElectric)
        case .sent:
            userDeliveryLabel("Confirmed", icon: "checkmark.circle", tint: AppColors.accentSuccess)
        case .transportFailed:
            userDeliveryLabel("Transport failed", icon: "antenna.radiowaves.left.and.right.slash", tint: AppColors.accentDanger)
        case .agentUnresponsive:
            userDeliveryLabel("Agent unresponsive", icon: "person.crop.circle.badge.exclamationmark", tint: AppColors.accentWarning)
        case .failed:
            userDeliveryLabel("Failed", icon: "exclamationmark.triangle.fill", tint: AppColors.accentDanger)
        case nil:
            EmptyView()
        }
    }

    private var userDeliveryState: DMUserMessageDeliveryState? {
        DMUserMessageDeliveryState.parse(message.userDeliveryState)
    }

    private var isRetryableUserDelivery: Bool {
        switch userDeliveryState {
        case .failed, .transportFailed, .agentUnresponsive:
            return true
        default:
            return false
        }
    }

    private var userDeliveryFailureLabel: String {
        switch userDeliveryState {
        case .transportFailed:
            return "Transport failed"
        case .agentUnresponsive:
            return "Agent unresponsive"
        default:
            return "Failed"
        }
    }

    private var userDeliveryFailureIcon: String {
        switch userDeliveryState {
        case .transportFailed:
            return "antenna.radiowaves.left.and.right.slash"
        case .agentUnresponsive:
            return "person.crop.circle.badge.exclamationmark"
        default:
            return "exclamationmark.triangle.fill"
        }
    }

    private func userDeliveryLabel(_ title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("User message delivery: \(title)")
    }

    private var hasComputeAttribution: Bool {
        guard let model = message.modelUsed?.lowercased(), !model.isEmpty else { return false }
        return model.contains("spark")
            || model.contains("kimi")
            || model.contains("openclaw")
            || model.contains("qwen")
    }

    private var computeDraftLabel: String? {
        guard hasComputeAttribution else { return nil }
        let provider = computeProviderName
        return "\(provider) draft in \(agent.name)'s voice — live agent offline"
    }

    private var computeProviderName: String {
        let model = message.modelUsed?.lowercased() ?? ""
        if model.contains("spark") || model.contains("qwen") { return "Spark" }
        if model.contains("kimi") { return "Kimi" }
        if model.contains("openclaw") { return "OpenClaw" }
        return "Compute"
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
        case .deliveryNatsFailed: return "antenna.radiowaves.left.and.right.slash"
        case .agentUnresponsive: return "person.crop.circle.badge.exclamationmark"
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
        case .deliveryNatsFailed, .agentUnresponsive, .failed, .fallbackPresented, .timedOut:
            return AppColors.accentWarning
        case nil:
            return AppColors.textTertiary
        }
    }

    private var provenanceIcon: String {
        switch provenance {
        case .coordinationReview: return "person.2.wave.2"
        case .timeoutFallback: return "clock.badge.exclamationmark"
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
        case .coordinationReview: return AppColors.accentSuccess
        case .timeoutFallback: return AppColors.accentWarning
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
        case .fallback, .timeoutFallback:
            return AppColors.accentWarning.opacity(0.10)
        case .ticket:
            return AppColors.accentAgent.opacity(0.10)
        case .system:
            return AppColors.backgroundSecondary
        case .protected:
            return AppColors.accentWarning.opacity(0.10)
        case .coordinationReview, .liveInbox, .compute:
            return AppColors.backgroundTertiary
        case .agentRun:
            return AppColors.accentAgent.opacity(0.10)
        }
    }

    private var bubbleBorderColor: Color {
        switch provenance {
        case .fallback, .timeoutFallback:
            return AppColors.accentWarning.opacity(0.45)
        case .ticket:
            return AppColors.accentAgent.opacity(0.35)
        case .system:
            return AppColors.borderActive
        case .protected:
            return AppColors.accentWarning.opacity(0.45)
        case .coordinationReview, .liveInbox, .compute:
            return AppColors.border
        case .agentRun:
            return AppColors.accentAgent.opacity(0.35)
        }
    }

    private var messageTextColor: Color {
        provenance == .fallback || provenance == .timeoutFallback || provenance == .protected ? AppColors.accentWarning : AppColors.textPrimary
    }
}

private struct MessageDeliveryLedger: View {
    let message: DMMessage
    let agent: AgentInfo

    private enum StepState: Equatable {
        case done
        case current
        case pending
        case failed
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(steps, id: \.title) { step in
                Label(step.title, systemImage: step.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color(for: step.state))
                    .labelStyle(.iconOnly)
                    .frame(width: 18, height: 18)
                    .background(color(for: step.state).opacity(step.state == .pending ? 0.06 : 0.13))
                    .clipShape(Circle())
                    .accessibilityLabel("\(step.title): \(accessibilityState(step.state))")
            }

            Text(ledgerText)
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
        }
    }

    private var deliveryState: DMDeliveryState? {
        DMDeliveryState.parse(message.deliveryState)
    }

    private var deliveryMode: DMDeliveryMode {
        DMDeliveryMode.parse(message.deliveryMode) ?? .compute
    }

    private var steps: [(title: String, icon: String, state: StepState)] {
        let failed = deliveryState == .failed
            || deliveryState == .deliveryNatsFailed
            || deliveryState == .agentUnresponsive
            || deliveryState == .fallbackPresented
        let timedOut = deliveryState == .timedOut
        let finalDone = deliveryState == .responseReceived
        let waiting = deliveryState == .computeRunning
            || deliveryState == .waitingForLiveAgent
            || deliveryState == .agentRunQueued
            || deliveryState == .agentRunRunning
            || deliveryState == .claimedByAgent
        let handlerTitle: String
        let handlerIcon: String
        switch deliveryMode {
        case .liveInbox:
            handlerTitle = "\(agent.name) inbox"
            handlerIcon = "tray.full"
        case .agentRun:
            handlerTitle = "Agent Run"
            handlerIcon = "bolt.badge.clock"
        case .ticket:
            handlerTitle = "Ticket"
            handlerIcon = "text.badge.checkmark"
        case .fallback:
            handlerTitle = "Fallback"
            handlerIcon = "exclamationmark.triangle"
        case .system:
            handlerTitle = "System"
            handlerIcon = "gearshape"
        case .auto:
            handlerTitle = "Route"
            handlerIcon = "arrow.triangle.branch"
        case .compute:
            handlerTitle = "Helper draft"
            handlerIcon = "cpu"
        }

        return [
            (
                "Sent",
                "paperplane",
                failed ? .done : .done
            ),
            (
                "ORCA accepted",
                "checkmark.circle",
                failed ? .failed : .done
            ),
            (
                handlerTitle,
                handlerIcon,
                failed ? .failed : (waiting || timedOut ? .current : (finalDone ? .done : .pending))
            ),
            (
                "Reply",
                finalDone ? "checkmark.seal" : "hourglass",
                failed ? .failed : (finalDone ? .done : (timedOut ? .failed : .pending))
            ),
        ]
    }

    private var ledgerText: String {
        switch deliveryState {
        case .routing:
            return "Routing through ORCA"
        case .computeRunning:
            return "Helper draft accepted; waiting"
        case .waitingForLiveAgent:
            return "\(agent.name) inbox accepted; waiting"
        case .claimedByAgent:
            return "\(agent.name) claimed the inbox"
        case .agentRunQueued:
            return "Agent Run queued"
        case .agentRunRunning:
            return "Agent Run running"
        case .responseReceived:
            return "Reply/evidence received"
        case .deliveryNatsFailed:
            return "Not delivered - NATS failed"
        case .agentUnresponsive:
            return "Not delivered - agent unreachable"
        case .fallbackPresented:
            return "Local fallback, not agent reply"
        case .failed:
            return "Route failed"
        case .timedOut:
            return "Still waiting; refresh can check ORCA"
        case .sending:
            return "Sending"
        case nil:
            return provenanceText
        }
    }

    private var provenanceText: String {
        switch DMResponseProvenance.parse(message.provenance)
            ?? DMResponseProvenance(deliveryMode: message.deliveryMode, source: message.source, lane: message.lane) {
        case .coordinationReview:
            return "\(agent.name) coordination review"
        case .timeoutFallback:
            return "Compute fallback after timeout"
        case .compute:
            return "Helper draft"
        case .liveInbox:
            return "\(agent.name) live inbox"
        case .agentRun:
            return "ORCA Agent Run"
        case .ticket:
            return "ORCA ticket evidence"
        case .fallback:
            return "Local fallback"
        case .system:
            return "Pod system"
        case .protected:
            return "Protected guardrail"
        }
    }

    private func color(for state: StepState) -> Color {
        switch state {
        case .done:
            return AppColors.accentSuccess
        case .current:
            return AppColors.accentElectric
        case .pending:
            return AppColors.textTertiary
        case .failed:
            return AppColors.accentWarning
        }
    }

    private func accessibilityState(_ state: StepState) -> String {
        switch state {
        case .done: return "done"
        case .current: return "current"
        case .pending: return "pending"
        case .failed: return "needs attention"
        }
    }
}
