import SwiftUI
import SwiftData
import UIKit

struct DirectChatView: View {
    @Bindable var viewModel: DirectChatViewModel
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var isShowingSonarDiagnostics = false
    @State private var isShowingVoiceRoom = false
    @State private var voiceViewModel = VoiceCompanionViewModel()

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            agentListSidebar
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
        .task {
            viewModel.startPresenceMonitoring()
            await viewModel.loadAgentRegistry()
            await viewModel.loadAgentPresence()
            await viewModel.loadSonarHealth()
            await viewModel.loadORCAChannelSummaries()
        }
        .onDisappear {
            viewModel.stopPresenceMonitoring()
        }
        .onChange(of: viewModel.navigationPath.count) { _, count in
            if count == 0 {
                viewModel.clearSelection()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .orcaAuthTokenInvalidated)) { _ in
            appState.logout()
        }
        .sheet(isPresented: $isShowingSonarDiagnostics) {
            SonarDiagnosticsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingVoiceRoom) {
            VoiceCompanionView(viewModel: voiceViewModel)
        }
    }

    // MARK: - Agent List Sidebar

    private var agentListSidebar: some View {
        List {
            Section {
                SonarSurfaceHeader(
                    health: viewModel.sonarHealth,
                    isLoading: viewModel.isLoadingSonarHealth,
                    roomCount: viewModel.sonarRooms.count,
                    pendingCount: totalPendingRooms,
                    unreadCount: totalUnreadRooms,
                    mentionCount: totalMentionRooms,
                    liveCount: totalLiveRooms,
                    selectedFilter: Binding(
                        get: { viewModel.selectedSonarRoomFilter },
                        set: { viewModel.selectedSonarRoomFilter = $0 }
                    ),
                    filterCounts: filterCounts
                )
            }
            .listRowBackground(Color.clear)

            roomSection("ATTENTION", rooms: attentionRooms)
            agentSection("CREW LANES", agents: primaryAgents)
            agentSection("PROTECTED LANES", agents: protectedAgents)
            agentSection("SUPPORT LANES", agents: supportAgents)

            roomSection("TICKET ROOMS", rooms: ticketRooms)
            roomSection("BOARD + PROJECT ROOMS", rooms: boardRooms)
            roomSection("SYSTEM + ALERTS", rooms: systemRooms)
            roomSection("GENERAL ROOMS", rooms: generalRooms)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Playground")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: Binding(
                get: { viewModel.sonarSearchText },
                set: { viewModel.sonarSearchText = $0 }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search team, rooms, tickets, boards"
        )
        .toolbarBackground(AppColors.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingVoiceRoom = true
                } label: {
                    Image(systemName: voiceViewModel.isRealtimeConnected ? "waveform.circle.fill" : "waveform.circle")
                        .foregroundStyle(voiceViewModel.isRealtimeConnected ? AppColors.accentSuccess : AppColors.accentElectric)
                }
                .accessibilityLabel(voiceViewModel.isRealtimeConnected ? "Open live Pod voice room" : "Open Pod voice room")

                Button {
                    isShowingSonarDiagnostics = true
                } label: {
                    Image(systemName: "waveform.path.ecg")
                }
                .accessibilityLabel("Open Playground diagnostics")

                Button {
                    viewModel.refreshSonarSurface()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingRooms || viewModel.isLoadingSonarHealth)
                .accessibilityLabel("Refresh Playground")
            }
        }
        .navigationDestination(for: AgentInfo.self) { agent in
            LockerChatView(viewModel: viewModel, agent: agent)
                .onAppear { viewModel.selectAgent(agent) }
        }
        .navigationDestination(for: SonarRoom.self) { room in
            SonarRoomConversationView(viewModel: viewModel, room: room)
                .onAppear { viewModel.selectRoom(room) }
        }
    }

    @ViewBuilder
    private func agentSection(_ title: String, agents: [AgentInfo]) -> some View {
        if !agents.isEmpty {
            Section(title) {
                ForEach(agents) { agent in
                    agentRow(agent)
                }
            }
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: AgentInfo) -> some View {
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

    @ViewBuilder
    private func roomSection(_ title: String, rooms: [SonarRoom]) -> some View {
        if viewModel.isLoadingRooms && viewModel.sonarRooms.isEmpty && title == "TICKET ROOMS" {
            Section("WORK ROOMS") {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading ORCA rooms")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .listRowBackground(Color.clear)
            }
        } else if viewModel.sonarRooms.isEmpty && title == "TICKET ROOMS" {
            Section("WORK ROOMS") {
                Text(viewModel.roomError ?? "No ORCA rooms yet.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .listRowBackground(Color.clear)
            }
        } else if viewModel.filteredSonarRooms.isEmpty && title == "TICKET ROOMS" {
            Section("WORK ROOMS") {
                Text("No matching ORCA rooms.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .listRowBackground(Color.clear)
            }
        } else if !rooms.isEmpty {
            Section(sectionTitle(title, count: rooms.count)) {
                ForEach(rooms) { room in
                    NavigationLink(value: room) {
                        SonarRoomRow(room: room)
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    private var visibleAgents: [AgentInfo] {
        viewModel.directChatAgents
    }

    private var primaryAgents: [AgentInfo] {
        visibleAgents.filter { $0.lane == .main && !isProtectedAgent($0) }
    }

    private var protectedAgents: [AgentInfo] {
        visibleAgents.filter { isProtectedAgent($0) }
    }

    private var supportAgents: [AgentInfo] {
        visibleAgents.filter { $0.lane == .supportRuntime && !isProtectedAgent($0) }
    }

    private var ticketRooms: [SonarRoom] {
        groupedRooms.filter { $0.roomGroup == .ticket }
    }

    private var boardRooms: [SonarRoom] {
        groupedRooms.filter { $0.roomGroup == .boardOrProject }
    }

    private var systemRooms: [SonarRoom] {
        groupedRooms.filter { $0.roomGroup == .system }
    }

    private var generalRooms: [SonarRoom] {
        groupedRooms.filter { $0.roomGroup == .general }
    }

    private var attentionRooms: [SonarRoom] {
        guard viewModel.selectedSonarRoomFilter == .all else { return [] }
        return viewModel.filteredSonarRooms.filter { isAttentionRoom($0) }
    }

    private var groupedRooms: [SonarRoom] {
        let attentionIds = Set(attentionRooms.map(\.id))
        return viewModel.filteredSonarRooms.filter { !attentionIds.contains($0.id) }
    }

    private var totalPendingRooms: Int {
        viewModel.sonarRooms.filter { $0.pendingCount > 0 }.count
    }

    private var totalUnreadRooms: Int {
        viewModel.sonarRooms.filter { $0.unreadCount > 0 }.count
    }

    private var totalMentionRooms: Int {
        viewModel.sonarRooms.filter { $0.mentionCount > 0 }.count
    }

    private var totalLiveRooms: Int {
        viewModel.sonarRooms.filter { $0.activeSSEClients > 0 }.count
    }

    private var filterCounts: [SonarRoomFilter: Int] {
        Dictionary(
            uniqueKeysWithValues: SonarRoomFilter.allCases.map { filter in
                (filter, viewModel.sonarRooms.filter { filter.includes($0) }.count)
            }
        )
    }

    private func isProtectedAgent(_ agent: AgentInfo) -> Bool {
        ["chief", "rooster", "reef"].contains(agent.id)
    }

    private func sectionTitle(_ title: String, count: Int) -> String {
        "\(title) · \(count)"
    }

    private func isAttentionRoom(_ room: SonarRoom) -> Bool {
        room.needsAttention
            || room.unreadCount > 0
            || room.mentionCount > 0
            || room.pendingCount > 0
            || room.notificationLevel == "urgent"
            || room.notificationLevel == "attention"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)
            Text("Select a lane to start chatting")
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
    }
}

private struct SonarDiagnosticsSheet: View {
    @Bindable var viewModel: DirectChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("STATUS") {
                    diagnosticRow("Health", value: viewModel.sonarHealth?.displayStatus ?? "Unknown")
                    diagnosticRow("Generated", value: viewModel.sonarHealth?.generatedAt.formatted(date: .abbreviated, time: .standard) ?? "Not recorded")
                    diagnosticRow("Contacts", value: viewModel.sonarContactsGeneratedAt?.formatted(date: .abbreviated, time: .standard) ?? "Fallback channel mode")
                    diagnosticRow("Rooms", value: "\(viewModel.sonarRooms.count)")
                    diagnosticRow("Direct lanes", value: "\(viewModel.orcaChannelIdByAgent.count)")
                    diagnosticRow("Unread rooms", value: "\(viewModel.sonarRooms.filter { $0.unreadCount > 0 }.count)")
                    diagnosticRow("Mention rooms", value: "\(viewModel.sonarRooms.filter { $0.mentionCount > 0 }.count)")
                    diagnosticRow("Protected rooms", value: "\(viewModel.sonarRooms.filter { $0.protectedLane }.count)")
                    diagnosticRow("Live rooms", value: "\(viewModel.sonarRooms.filter { $0.presence == "live" }.count)")
                }

                if let health = viewModel.sonarHealth {
                    Section("CHECKS") {
                        ForEach(health.checks) { check in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle()
                                        .fill(tint(for: check.status))
                                        .frame(width: 7, height: 7)
                                    Text(check.label)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(check.displayStatus)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(tint(for: check.status))
                                }
                                if let detail = check.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section("ACTIONS") {
                    Button {
                        viewModel.refreshSonarSurface()
                    } label: {
                        Label("Refresh Playground surface", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("Playground Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func diagnosticRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func tint(for status: String) -> Color {
        switch status.lowercased() {
        case "good": return AppColors.accentSuccess
        case "down": return AppColors.accentDanger
        default: return AppColors.accentWarning
        }
    }
}

private struct SonarSurfaceHeader: View {
    let health: SonarHealth?
    let isLoading: Bool
    let roomCount: Int
    let pendingCount: Int
    let unreadCount: Int
    let mentionCount: Int
    let liveCount: Int
    @Binding var selectedFilter: SonarRoomFilter
    let filterCounts: [SonarRoomFilter: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.accentElectric)
                    .frame(width: 34, height: 34)
                    .background(AppColors.accentElectric.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Playground")
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("ORCA-backed team chat")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SonarHeaderChip(title: healthTitle, icon: healthIcon, tint: healthTint)
                    SonarHeaderChip(title: "\(roomCount) rooms", icon: "number", tint: AppColors.textSecondary)
                    if unreadCount > 0 {
                        SonarHeaderChip(title: "\(unreadCount) unread", icon: "circle.fill", tint: AppColors.accentAgent)
                    }
                    if mentionCount > 0 {
                        SonarHeaderChip(title: "\(mentionCount) mentions", icon: "at", tint: AppColors.accentDanger)
                    }
                    if pendingCount > 0 {
                        SonarHeaderChip(title: "\(pendingCount) waiting", icon: "person.badge.clock", tint: AppColors.accentWarning)
                    }
                    if liveCount > 0 {
                        SonarHeaderChip(title: "\(liveCount) live", icon: "bolt.horizontal.circle", tint: AppColors.accentSuccess)
                    }
                    SonarHeaderChip(title: "Evidence on tap", icon: "point.topleft.down.curvedto.point.bottomright.up", tint: AppColors.accentElectric)
                }
            }
            .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SonarRoomFilter.allCases) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            Label(filterButtonTitle(for: filter), systemImage: filter.icon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(selectedFilter == filter ? .white : AppColors.textSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(selectedFilter == filter ? AppColors.accentElectric : AppColors.backgroundTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show \(filter.title) rooms")
                    }
                }
            }

            if let health {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(health.checks.prefix(4)) { check in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(tint(for: check.status))
                                .frame(width: 6, height: 6)
                            Text(check.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColors.textSecondary)
                            Text(check.displayStatus)
                                .font(.caption2)
                                .foregroundStyle(tint(for: check.status))
                            if let detail = check.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.70)
                    Text("Checking Playground health")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            Text("Use chat for triage and continuity. Use ORCA tickets, Agent Runs, and approvals for work that needs tools, files, memory, or mutation.")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
        .padding(.vertical, 6)
    }

    private var healthTitle: String {
        guard let health else {
            return isLoading ? "Checking health" : "Health unknown"
        }
        return "Playground \(health.displayStatus)"
    }

    private var healthIcon: String {
        switch health?.status.lowercased() {
        case "good": return "checkmark.shield"
        case "down": return "exclamationmark.octagon"
        case "degraded": return "exclamationmark.triangle"
        default: return "waveform.path.ecg"
        }
    }

    private var healthTint: Color {
        tint(for: health?.status ?? (isLoading ? "degraded" : "down"))
    }

    private func filterButtonTitle(for filter: SonarRoomFilter) -> String {
        let count = filterCounts[filter] ?? 0
        return filter == .all ? filter.title : "\(filter.title) \(count)"
    }

    private func tint(for status: String) -> Color {
        switch status.lowercased() {
        case "good": return AppColors.accentSuccess
        case "down": return AppColors.accentDanger
        default: return AppColors.accentWarning
        }
    }
}

private struct SonarHeaderChip: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }
}

struct TicketDraftReviewSheet: View {
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

struct AttachTicketSheet: View {
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

struct AttachableTicketRow: View {
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
                AgentPresenceDot(presence: viewModel.presence(for: agent))
                    .offset(x: 16, y: 16)
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

private struct AgentPresenceDot: View {
    let presence: AgentPresence

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.backgroundPrimary)
                .frame(width: 16, height: 16)
            Circle()
                .fill(presence.state.color)
                .frame(width: 10, height: 10)
            if presence.isWorking {
                Circle()
                    .strokeBorder(AppColors.accentElectric, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
            }
        }
        .accessibilityLabel("\(presence.state.label)\(presence.isWorking ? ", working" : "")")
    }
}

private struct SonarRoomRow: View {
    let room: SonarRoom

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(room.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(room.lastActivity, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }

                HStack(spacing: 6) {
                    Text(room.roomKindLabel)
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    if let ticketRef = short(room.linkedTicketId, prefix: "Ticket") {
                        pill(ticketRef, tint: AppColors.accentAgent)
                    }
                    if let boardRef = short(room.linkedBoardId, prefix: "Board") {
                        pill(boardRef, tint: AppColors.accentElectric)
                    }
                    if room.isSystemChannel {
                        pill("System", tint: AppColors.textSecondary)
                    }
                    if room.pendingCount > 0 {
                        pill("\(room.pendingCount) waiting", tint: AppColors.accentWarning)
                    }
                    if room.unreadCount > 0 {
                        pill("\(room.unreadCount) unread", tint: AppColors.accentAgent)
                    }
                    if room.mentionCount > 0 {
                        pill("@\(room.mentionCount)", tint: AppColors.accentDanger)
                    }
                    if room.activeSSEClients > 0 {
                        pill("Live", tint: AppColors.accentSuccess)
                    }
                    if room.protectedLane {
                        pill("Protected", tint: AppColors.accentWarning)
                    }
                    if room.notificationLevel == "urgent" {
                        pill("Urgent", tint: AppColors.accentDanger)
                    } else if room.notificationLevel == "attention" {
                        pill("Attention", tint: AppColors.accentWarning)
                    }
                    Spacer(minLength: 0)
                }

                Text(roomRowDetail)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var icon: String {
        if room.protectedLane { return "lock.shield" }
        if room.linkedTicketId != nil || room.channelPurpose == "service_request" {
            return "text.badge.checkmark"
        }
        if room.linkedBoardId != nil || room.channelPurpose == "board" {
            return "square.stack.3d.up"
        }
        let lower = room.name.lowercased()
        if lower.hasPrefix("ticket:") { return "text.badge.checkmark" }
        if lower.hasPrefix("board:") { return "square.stack.3d.up" }
        if lower.contains("project") { return "folder" }
        return "number"
    }

    private var tint: Color {
        if room.protectedLane { return AppColors.accentWarning }
        if room.linkedTicketId != nil || room.channelPurpose == "service_request" {
            return AppColors.accentAgent
        }
        if room.linkedBoardId != nil || room.channelPurpose == "board" {
            return AppColors.accentElectric
        }
        let lower = room.name.lowercased()
        if lower.hasPrefix("ticket:") { return AppColors.accentAgent }
        if lower.hasPrefix("board:") { return AppColors.accentElectric }
        return AppColors.textSecondary
    }

    private var roomRowDetail: String {
        let fallback = room.description?.isEmpty == false ? room.description! : "\(room.messageCount) messages"
        if let presence = room.presenceDetail, !presence.isEmpty {
            return "\(fallback) · \(presence)"
        }
        return "\(fallback) · \(room.presence.capitalized)"
    }

    private func pill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }

    private func short(_ value: String?, prefix: String) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let ref = value.count > 10 ? String(value.prefix(8)) : value
        return "\(prefix) \(ref)"
    }
}

private struct SonarRoomConversationView: View {
    let viewModel: DirectChatViewModel
    let room: SonarRoom

    @FocusState private var isFocused: Bool
    @State private var selectedEvidenceMessage: SonarRoomMessage?

    var body: some View {
        VStack(spacing: 0) {
            roomHeader

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.roomMessages) { message in
                            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                                SonarRoomMessageRow(message: message)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedEvidenceMessage = message
                                    }

                                SonarRoomMessageActionBar(
                                    message: message,
                                    canRequestWorkflow: room.canRequestWorkflow,
                                    onReply: {
                                        viewModel.replyToRoomMessage(message)
                                        isFocused = true
                                    },
                                    onCopy: {
                                        UIPasteboard.general.string = message.content
                                    },
                                    onEvidence: {
                                        selectedEvidenceMessage = message
                                    },
                                    onWorkRequest: { type in
                                        viewModel.prepareRoomWorkRequest(from: message, type: type)
                                        isFocused = true
                                    }
                                )
                            }
                            .contextMenu {
                                Button {
                                    viewModel.replyToRoomMessage(message)
                                    isFocused = true
                                } label: {
                                    Label("Reply in thread", systemImage: "arrowshape.turn.up.left")
                                }

                                Button {
                                    UIPasteboard.general.string = message.content
                                } label: {
                                    Label("Copy text", systemImage: "doc.on.doc")
                                }

                                Button {
                                    selectedEvidenceMessage = message
                                } label: {
                                    Label("Open evidence", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                                }

                                if room.canRequestWorkflow {
                                    Divider()
                                    Button {
                                        viewModel.prepareRoomWorkRequest(from: message, type: .agentRunRequest)
                                        isFocused = true
                                    } label: {
                                        Label("Request agent run", systemImage: "bolt.badge.clock")
                                    }
                                    Button {
                                        viewModel.prepareRoomWorkRequest(from: message, type: .approvalRequest)
                                        isFocused = true
                                    } label: {
                                        Label("Request approval", systemImage: "person.badge.key")
                                    }
                                    Button {
                                        viewModel.prepareRoomWorkRequest(from: message, type: .memoryCandidate)
                                        isFocused = true
                                    } label: {
                                        Label("Propose memory", systemImage: "brain.head.profile")
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                            .id(message.id)
                            .accessibilityHint("Tap for evidence. Use visible message actions for reply and work requests.")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: viewModel.roomMessages.count) { _, _ in
                    if let last = viewModel.roomMessages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(AppColors.backgroundPrimary)

            if let roomError = viewModel.roomError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(AppColors.accentWarning)
                    Text(roomError)
                        .font(.caption)
                        .foregroundStyle(AppColors.accentWarning)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.accentWarning.opacity(0.10))
            }

            if let roomActionMessage = viewModel.roomActionMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(AppColors.accentElectric)
                    Text(roomActionMessage)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.accentElectric.opacity(0.08))
            }

            roomComposeBar
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle(room.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.refreshSelectedRoom()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingRoomMessages)
                .accessibilityLabel("Refresh ORCA room")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { selectedEvidenceMessage != nil },
                set: { if !$0 { selectedEvidenceMessage = nil } }
            )
        ) {
            if let selectedEvidenceMessage {
                SonarRoomMessageEvidenceDrawer(message: selectedEvidenceMessage, room: room)
            }
        }
    }

    private var roomHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: roomHeaderIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(roomHeaderTint)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.roomKindLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(headerDetail)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if viewModel.isLoadingRoomMessages {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    roomChip(room.presence.capitalized, icon: "dot.radiowaves.left.and.right", tint: presenceTint)
                    if room.unreadCount > 0 {
                        roomChip("\(room.unreadCount) unread", icon: "circle.fill", tint: AppColors.accentAgent)
                    }
                    if room.mentionCount > 0 {
                        roomChip("@\(room.mentionCount)", icon: "at", tint: AppColors.accentDanger)
                    }
                    if room.pendingCount > 0 {
                        roomChip("\(room.pendingCount) waiting", icon: "person.badge.clock", tint: AppColors.accentWarning)
                    }
                    if room.protectedLane {
                        roomChip("Protected", icon: "lock.shield", tint: AppColors.accentWarning)
                    }
                    roomChip(room.canRequestWorkflow ? "Workflows allowed" : "Chat only", icon: room.canRequestWorkflow ? "checkmark.seal" : "text.bubble", tint: room.canRequestWorkflow ? AppColors.accentSuccess : AppColors.textSecondary)
                    if let owner = room.policyOwner, !owner.isEmpty {
                        roomChip(owner, icon: "person.crop.circle", tint: AppColors.textSecondary)
                    }
                }
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

    private var roomHeaderIcon: String {
        if room.protectedLane { return "lock.shield" }
        if room.linkedTicketId != nil || room.channelPurpose == "service_request" { return "text.badge.checkmark" }
        if room.linkedBoardId != nil || room.channelPurpose == "board" { return "square.stack.3d.up" }
        return "number"
    }

    private var roomHeaderTint: Color {
        if room.protectedLane { return AppColors.accentWarning }
        if room.linkedTicketId != nil || room.channelPurpose == "service_request" { return AppColors.accentAgent }
        if room.linkedBoardId != nil || room.channelPurpose == "board" { return AppColors.accentElectric }
        return AppColors.accentElectric
    }

    private var presenceTint: Color {
        switch room.presence.lowercased() {
        case "live": return AppColors.accentSuccess
        case "waiting", "active": return AppColors.accentWarning
        default: return AppColors.textSecondary
        }
    }

    private func roomChip(_ title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var headerDetail: String {
        var parts = ["ORCA channel \(String(room.id.prefix(8)))", "\(room.messageCount) messages"]
        if room.pendingCount > 0 {
            parts.append("\(room.pendingCount) waiting")
        }
        if room.activeSSEClients > 0 {
            parts.append("\(room.activeSSEClients) live listeners")
        }
        if room.unreadCount > 0 {
            parts.append("\(room.unreadCount) unread")
        }
        if room.mentionCount > 0 {
            parts.append("\(room.mentionCount) mentions")
        }
        if room.protectedLane {
            parts.append("protected")
        }
        if room.policyLaneType != "standard" {
            parts.append(room.policyLaneType.replacingOccurrences(of: "_", with: " "))
        }
        return parts.joined(separator: " · ")
    }

    private var roomComposeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyingTo = viewModel.replyingToRoomMessage {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .foregroundStyle(AppColors.accentElectric)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thread reply to \(replyingTo.displayName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(replyingTo.content.isEmpty ? "Empty message" : replyingTo.content)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        viewModel.cancelRoomReply()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel thread reply")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppColors.accentElectric.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                ForEach(SonarRoomMessageType.allCases) { type in
                    Button {
                        if canUseMessageType(type) {
                            viewModel.selectedRoomMessageType = type
                        }
                    } label: {
                        Image(systemName: type.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(buttonForeground(for: type))
                            .frame(width: 28, height: 28)
                            .background(buttonBackground(for: type))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canUseMessageType(type))
                    .accessibilityLabel(type.title)
                    .help(type.detail)
                }
                Spacer(minLength: 0)
                Label(viewModel.selectedRoomMessageType.detail, systemImage: viewModel.selectedRoomMessageType.icon)
                    .font(.caption2)
                    .foregroundStyle(canUseMessageType(viewModel.selectedRoomMessageType) ? AppColors.textTertiary : AppColors.accentWarning)
                    .lineLimit(1)
            }

            if room.protectedLane, let reason = room.protectionReason {
                Label(reason, systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(AppColors.accentWarning)
                    .lineLimit(2)
            }

            if !room.allowedActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(room.allowedActions.prefix(8), id: \.self) { action in
                            roomChip(action.replacingOccurrences(of: "_", with: " "), icon: actionIcon(action), tint: AppColors.textSecondary)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField(roomPrompt, text: Binding(
                    get: { viewModel.composedRoomMessage },
                    set: { viewModel.composedRoomMessage = $0 }
                ), axis: .vertical)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .lineLimit(1...5)

                Button {
                    viewModel.sendRoomMessage()
                } label: {
                    Image(systemName: viewModel.isSendingRoomMessage ? "hourglass.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? AppColors.accentElectric : AppColors.textTertiary)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send room message")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.backgroundSecondary)
    }

    private func canUseMessageType(_ type: SonarRoomMessageType) -> Bool {
        type == .text || room.canRequestWorkflow
    }

    private func buttonForeground(for type: SonarRoomMessageType) -> Color {
        if viewModel.selectedRoomMessageType == type { return .white }
        return canUseMessageType(type) ? AppColors.textSecondary : AppColors.textTertiary
    }

    private func buttonBackground(for type: SonarRoomMessageType) -> Color {
        if viewModel.selectedRoomMessageType == type { return AppColors.accentElectric }
        return canUseMessageType(type) ? AppColors.backgroundTertiary : AppColors.backgroundTertiary.opacity(0.45)
    }

    private var roomPrompt: String {
        switch viewModel.selectedRoomMessageType {
        case .text:
            return "Message \(room.displayName)..."
        case .toolRequest:
            return "Describe the tool request..."
        case .fileRequest:
            return "Describe the file context needed..."
        case .approvalRequest:
            return "Describe what needs sign/pass..."
        case .agentRunRequest:
            return "Describe the agent run request..."
        case .memoryCandidate:
            return "Describe the memory candidate..."
        }
    }

    private func actionIcon(_ action: String) -> String {
        switch action {
        case "post": return "paperplane"
        case "workflow": return "slider.horizontal.3"
        case "ticket": return "text.badge.checkmark"
        case "approval": return "person.badge.key"
        case "agent_run": return "bolt.badge.clock"
        case "file": return "doc"
        case "memory": return "brain.head.profile"
        default: return "checkmark.circle"
        }
    }

    private var canSend: Bool {
        !viewModel.isSendingRoomMessage
            && room.canPost
            && canUseMessageType(viewModel.selectedRoomMessageType)
            && !viewModel.composedRoomMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct SonarRoomMessageEvidenceDrawer: View {
    let message: SonarRoomMessage
    let room: SonarRoom

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var surfaceEvents: [SonarSurfaceEventDTO] = []
    @State private var computeRuns: [SonarComputeRunDTO] = []
    @State private var threadRoot: SonarThreadMessageDTO?
    @State private var threadReplies: [SonarThreadMessageDTO] = []
    @State private var didCopyEvidence = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    copyButton
                    threadSection
                    eventSection
                    computeSection
                }
                .padding(16)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Room Evidence")
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
            Label(room.displayName, systemImage: "number")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
            evidenceRow("Sender", message.displayName)
            evidenceRow("Delivery", message.statusLabel)
            evidenceRow("Trace", short(message.traceId))
            evidenceRow("Message", short(message.id))
            evidenceRow("Channel", short(room.id))
            evidenceRow("Source", message.source)
            evidenceRow("Lane", message.lane)
            evidenceRow("File", message.fileAttachment?.path)
            if message.isThreadReply {
                evidenceRow("Thread", "Reply")
            } else if !threadReplies.isEmpty {
                evidenceRow("Thread", "\(threadReplies.count) replies")
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

    @ViewBuilder
    private var threadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Thread", systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
            if isLoading {
                EmptyView()
            } else if threadRoot == nil && threadReplies.isEmpty {
                Text("No replies yet.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                if let threadRoot {
                    SonarThreadMessageRow(message: threadRoot, label: "Root")
                }
                ForEach(threadReplies, id: \.id) { reply in
                    SonarThreadMessageRow(message: reply, label: "Reply")
                }
            }
        }
    }

    @ViewBuilder
    private var eventSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ORCA surface events", systemImage: "rectangle.stack.badge.person.crop")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
            if isLoading {
                ProgressView("Loading evidence...")
                    .font(.caption)
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
            if !isLoading, computeRuns.isEmpty {
                Text("No compute record matched this message trace.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ForEach(computeRuns, id: \.id) { run in
                    SonarComputeRunRow(run: run)
                }
            }
        }
    }

    private func loadEvidence() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let packet: SonarEvidencePacketDTO = try await APIClient.shared.get(
                path: "/api/v1/sonar/evidence?message_id=\(urlQuery(message.id))&limit=20"
            )
            surfaceEvents = packet.surfaceEvents
            computeRuns = packet.computeRuns
            await loadThread()
        } catch let apiError as APIError {
            errorMessage = apiError.message
        } catch {
            errorMessage = "Evidence is unavailable right now."
        }
    }

    private func loadThread() async {
        do {
            let packet: SonarThreadPacketDTO = try await APIClient.shared.get(
                path: "/api/v1/sonar/messages/\(urlQuery(message.id))/thread?limit=50"
            )
            threadRoot = packet.root
            threadReplies = packet.replies
        } catch {
            threadRoot = nil
            threadReplies = []
        }
    }

    private func evidenceRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 72, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "Not recorded")
                .font(.caption)
                .foregroundStyle(value?.isEmpty == false ? AppColors.textPrimary : AppColors.textTertiary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func copyEvidencePacket() {
        UIPasteboard.general.string = evidencePacket
        didCopyEvidence = true
    }

    private var evidencePacket: String {
        """
        # Sonar Room Evidence
        Room: \(room.displayName)
        Room ID: \(room.id)
        Message ID: \(message.id)
        Sender: \(message.displayName)
        Message type: \(message.messageType)
        Delivery: \(message.statusLabel ?? "not recorded")
        Trace: \(message.traceId ?? "not recorded")
        Source: \(message.source ?? "not recorded")
        Lane: \(message.lane ?? "not recorded")
        File: \(message.fileAttachment?.path ?? "not recorded")
        Surface events: \(surfaceEvents.map(\.id).joined(separator: ", "))
        Compute runs: \(computeRuns.map(\.id).joined(separator: ", "))
        Thread replies: \(threadReplies.count)

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

private struct SonarRoomMessageRow: View {
    let message: SonarRoomMessage

    @ViewBuilder
    var body: some View {
        if message.isRequestCard {
            SonarRoomRequestCard(message: message)
        } else {
            HStack(alignment: .top, spacing: 10) {
                if message.isUser { Spacer(minLength: 50) }

                if !message.isUser {
                    avatar
                }

                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(message.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(message.isUser ? .white.opacity(0.85) : AppColors.textSecondary)
                        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(message.isUser ? .white.opacity(0.65) : AppColors.textTertiary)
                    }

                    Text(message.content.isEmpty ? "Empty message" : message.content)
                        .font(.body)
                        .foregroundStyle(message.isUser ? .white : AppColors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.isUser ? AppColors.accentElectric : AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(message.isUser ? Color.clear : AppColors.border, lineWidth: 1)
                        )

                    if let attachment = message.fileAttachment {
                        ChatFileAttachmentChip(attachment: attachment, compact: true)
                            .frame(maxWidth: 420)
                    }

                    if let status = message.statusLabel {
                        HStack(spacing: 6) {
                            Text(status)
                            if message.isThreadReply {
                                Text("Thread reply")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                    } else if message.isThreadReply {
                        Text("Thread reply")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                    }
                }

                if !message.isUser { Spacer(minLength: 50) }
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(AppColors.accentElectric.opacity(0.12))
                .frame(width: 30, height: 30)
            Text(message.senderEmoji ?? "A")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.accentElectric)
        }
    }
}

private struct SonarRoomMessageActionBar: View {
    let message: SonarRoomMessage
    let canRequestWorkflow: Bool
    let onReply: () -> Void
    let onCopy: () -> Void
    let onEvidence: () -> Void
    let onWorkRequest: (SonarRoomMessageType) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if message.isUser { Spacer(minLength: 34) }

            Button(action: onReply) {
                actionIcon("arrowshape.turn.up.left", label: "Reply")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reply in thread")

            Button(action: onEvidence) {
                actionIcon("point.topleft.down.curvedto.point.bottomright.up", label: "Evidence")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open evidence")

            Button(action: onCopy) {
                actionIcon("doc.on.doc", label: "Copy")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy message text")

            if canRequestWorkflow {
                Menu {
                    Button {
                        onWorkRequest(.agentRunRequest)
                    } label: {
                        Label("Request agent run", systemImage: "bolt.badge.clock")
                    }
                    Button {
                        onWorkRequest(.approvalRequest)
                    } label: {
                        Label("Request approval", systemImage: "person.badge.key")
                    }
                    Button {
                        onWorkRequest(.memoryCandidate)
                    } label: {
                        Label("Propose memory", systemImage: "brain.head.profile")
                    }
                } label: {
                    actionIcon("plus.circle", label: "Work")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Create work request from message")
            }

            if !message.isUser { Spacer(minLength: 34) }
        }
        .frame(maxWidth: 520, alignment: message.isUser ? .trailing : .leading)
        .padding(.horizontal, message.isUser ? 50 : 40)
    }

    private func actionIcon(_ icon: String, label: String) -> some View {
        Label(label, systemImage: icon)
            .labelStyle(.iconOnly)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColors.textTertiary)
            .frame(width: 28, height: 24)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppColors.border.opacity(0.8), lineWidth: 1)
            )
    }
}

private struct SonarRoomRequestCard: View {
    let message: SonarRoomMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isUser { Spacer(minLength: 34) }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(cardTint.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: message.cardIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(cardTint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(message.cardTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("\(message.displayName) · \(message.createdAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer(minLength: 0)
                }

                Text(message.content.isEmpty ? "No detail recorded." : message.content)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let attachment = message.fileAttachment {
                    ChatFileAttachmentChip(attachment: attachment, compact: true)
                }

                HStack(spacing: 8) {
                    if let status = message.statusLabel {
                        pill(status, tint: statusTint)
                    }
                    pill("ORCA routed", tint: AppColors.textSecondary)
                    Spacer(minLength: 0)
                    Text("Tap for evidence")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(12)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(cardTint.opacity(0.30), lineWidth: 1)
            )
            .frame(maxWidth: 520, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser { Spacer(minLength: 34) }
        }
    }

    private var cardTint: Color {
        switch message.messageType {
        case "approval_request": return AppColors.accentWarning
        case "agent_run_request", "tool_request": return AppColors.accentAgent
        case "memory_candidate": return AppColors.accentElectric
        case "system": return AppColors.textSecondary
        default: return AppColors.accentSuccess
        }
    }

    private var statusTint: Color {
        guard let responseState = message.responseState?.lowercased() else {
            return AppColors.textSecondary
        }
        if responseState.contains("failed") || responseState.contains("degraded") {
            return AppColors.accentDanger
        }
        if responseState.contains("waiting") || responseState.contains("pending") {
            return AppColors.accentWarning
        }
        return AppColors.accentSuccess
    }

    private func pill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }
}
// MARK: - Preview

#Preview {
    DirectChatView(viewModel: DirectChatViewModel())
        .modelContainer(for: [DMConversation.self, DMMessage.self], inMemory: true)
}
