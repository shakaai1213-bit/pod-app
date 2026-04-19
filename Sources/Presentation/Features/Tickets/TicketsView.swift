import SwiftUI

// MARK: - Tickets View

struct TicketsView: View {
    @State private var viewModel = TicketsViewModel()
    @State private var agents: [AgentDTO] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status filter bar
                statusFilterBar

                Divider().background(AppColors.border)

                if viewModel.isLoading && viewModel.tickets.isEmpty {
                    loadingView
                } else if viewModel.filtered.isEmpty {
                    emptyView
                } else {
                    ticketList
                }
            }
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
            }
            .sheet(isPresented: $viewModel.showCreateSheet) {
                CreateTicketSheet(viewModel: viewModel, agents: agents)
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
                filterChip(label: "In Progress", status: .inProgress)
                filterChip(label: "Resolved", status: .resolved)
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

    // MARK: - Ticket List

    // MARK: - Ticket List (POD-4: tree view)

    private var ticketList: some View {
        List {
            ForEach(viewModel.rootTickets) { ticket in
                TicketTreeNode(
                    ticket: ticket,
                    depth: 0,
                    onStatusChange: { newStatus in
                        Task { await viewModel.updateStatus(ticketId: ticket.id, status: newStatus) }
                    },
                    subtasksProvider: { viewModel.subtasks(of: $0) }
                )
                .listRowBackground(AppColors.backgroundSecondary)
                .listRowSeparatorTint(AppColors.border)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
        .listStyle(.plain)
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
            Text(viewModel.selectedStatus == nil ? "No tickets yet" : "No \(viewModel.selectedStatus!.label.lowercased()) tickets")
                .font(.headline)
                .foregroundColor(AppColors.textSecondary)
            Text("Create a ticket to assign work to an agent")
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
        } catch {}
    }
}

// MARK: - Ticket Row

struct TicketRowView: View {
    let ticket: Ticket
    let onStatusChange: (TicketStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: priority + title
            HStack(alignment: .top, spacing: 8) {
                // Priority indicator
                Image(systemName: ticket.priority.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ticket.priority.color)
                    .frame(width: 16)

                Text(ticket.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)

                Spacer()

                // Status badge
                statusBadge
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
                if status != ticket.status {
                    Button {
                        onStatusChange(status)
                    } label: {
                        Label("Mark \(status.label)", systemImage: status.icon)
                    }
                }
            }
        }
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
}

// MARK: - Ticket Tree Node (POD-4: subtask hierarchy)

struct TicketTreeNode: View {
    let ticket: Ticket
    let depth: Int
    let onStatusChange: (TicketStatus) -> Void
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

                TicketRowView(ticket: ticket, onStatusChange: onStatusChange)
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
                        depth: depth + 1,
                        onStatusChange: onStatusChange,
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
                Section("Details") {
                    TextField("Title", text: $viewModel.newTitle)
                        .foregroundColor(AppColors.textPrimary)

                    TextField("Description (optional)", text: $viewModel.newDescription, axis: .vertical)
                        .lineLimit(3...6)
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
