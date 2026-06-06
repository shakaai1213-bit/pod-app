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
            await viewModel.loadAgentRegistry()
            await viewModel.loadSonarHealth()
            await viewModel.loadORCAChannelSummaries()
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
        .navigationTitle("Sonar")
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
                .accessibilityLabel("Open Sonar diagnostics")

                Button {
                    viewModel.refreshSonarSurface()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingRooms || viewModel.isLoadingSonarHealth)
                .accessibilityLabel("Refresh Sonar")
            }
        }
        .navigationDestination(for: AgentInfo.self) { agent in
            ConversationView(viewModel: viewModel, agent: agent)
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
                        Label("Refresh Sonar surface", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("Sonar Diagnostics")
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
                    Text("Sonar")
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
                    Text("Checking Sonar health")
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
        return "Sonar \(health.displayStatus)"
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
    @State private var isContextExpanded = false
    @State private var selectedEvidenceMessage: DMMessage?

    var body: some View {
        VStack(spacing: 0) {
            chatContextSurface
            if !viewModel.routeProgressSteps.isEmpty {
                RouteProgressStrip(steps: viewModel.routeProgressSteps)
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.currentMessages, id: \.id) { message in
                            DMBubble(
                                message: message,
                                agent: agent,
                                onRetry: { viewModel.retryMessage(message) }
                            )
                            .onTapGesture {
                                selectedEvidenceMessage = message
                            }
                            .id(message.id)
                            .accessibilityHint("Open Sonar evidence for this message.")
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
        }
    }

    @ViewBuilder
    private var chatContextSurface: some View {
        VStack(spacing: 0) {
            compactContextBar

            if isContextExpanded {
                ticketContextBar
                ticketContinuityBar
                workCockpitPanel
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
            let readiness = "\(viewModel.workCockpitReadinessPercent)% ready"
            return [run, readiness, viewModel.ticketLiveSummaryLabel]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        let channelText = viewModel.shortChannelId(for: agent).map { "ORCA channel \($0)" }
        return [deliveryTruthText, channelText, agent.boundaryText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var contextSummaryIcon: String {
        if viewModel.activeTicketId != nil { return "text.badge.checkmark" }
        return deliveryIcon(for: viewModel.selectedDeliveryMode)
    }

    private var contextSummaryColor: Color {
        if viewModel.activeTicketId != nil { return AppColors.accentSuccess }
        return routeDecisionColor
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
    private var workCockpitPanel: some View {
        if viewModel.activeTicketId != nil {
            VStack(alignment: .leading, spacing: 8) {
                // L6: toolbar overflow fix — status labels + Refresh inline;
                // Approval/Memory/Artifact/Tool collapsed into a single … Menu.
                HStack(spacing: 8) {
                    Label(awakeStateLabel, systemImage: awakeStateIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentAgent)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Label("\(viewModel.workCockpitReadinessPercent)%", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(readinessColor)

                    Button {
                        viewModel.refreshWorkCockpitFromChat()
                    } label: {
                        Image(systemName: viewModel.isRefreshingWorkCockpit ? "hourglass" : "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.accentElectric)
                            .frame(width: 28, height: 28)
                            .background(AppColors.accentElectric.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRefreshingWorkCockpit)
                    .accessibilityLabel(viewModel.isRefreshingWorkCockpit ? "Refreshing cockpit" : "Refresh cockpit")

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
                                viewModel.isSavingMemoryCandidate ? "Saving Memory…" : "Save Memory Candidate",
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
                            viewModel.requestWorkspaceToolFromChat()
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
                    .accessibilityLabel("Cockpit actions")
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
            .navigationTitle("Sonar Evidence")
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
            evidenceRow("Provenance", provenanceLabel)
            evidenceRow("Trace", short(message.traceId))
            evidenceRow("Message", short(message.remoteMessageId))
            evidenceRow("Compute run", short(message.computeRunId))
            evidenceRow("Channel", short(channelId))
            evidenceRow("Ticket", short(activeTicketId))
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
        Provenance: \(provenanceLabel)
        Trace: \(message.traceId ?? "not recorded")
        Compute run: \(message.computeRunId ?? "not recorded")
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

private struct SonarSurfaceEventRow: View {
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

private struct SonarComputeRunRow: View {
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

private struct SonarThreadMessageRow: View {
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

private struct SonarEvidencePacketDTO: Decodable {
    let generatedAt: Date
    let surfaceEvents: [SonarSurfaceEventDTO]
    let computeRuns: [SonarComputeRunDTO]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case surfaceEvents = "surface_events"
        case computeRuns = "compute_runs"
    }
}

private struct SonarThreadPacketDTO: Decodable {
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

private struct SonarThreadMessageDTO: Decodable {
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

private struct SonarSurfaceEventDTO: Decodable {
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

private struct SonarComputeRunDTO: Decodable {
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

                if !isUser {
                    MessageDeliveryLedger(message: message, agent: agent)
                }

                // Retry button for failed user messages
                if isUser,
                   DMUserMessageDeliveryState.parse(message.userDeliveryState) == .failed,
                   let retry = onRetry {
                    HStack(spacing: 8) {
                        Label("Failed", systemImage: "exclamationmark.triangle.fill")
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
        return deliveryState?.displayLabel ?? ""
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
        if agent.id == "aloha" {
            return "\(provider) draft in Aloha's voice — she's offline"
        }
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
        case .coordinationReview: return "person.2.wave.2"
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
        case .coordinationReview, .liveInbox, .compute:
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
        case .coordinationReview, .liveInbox, .compute:
            return AppColors.border
        case .agentRun:
            return AppColors.accentAgent.opacity(0.35)
        }
    }

    private var messageTextColor: Color {
        provenance == .fallback || provenance == .protected ? AppColors.accentWarning : AppColors.textPrimary
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
        let failed = deliveryState == .failed || deliveryState == .fallbackPresented
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

// MARK: - Preview

#Preview {
    DirectChatView(viewModel: DirectChatViewModel())
        .modelContainer(for: [DMConversation.self, DMMessage.self], inMemory: true)
}
