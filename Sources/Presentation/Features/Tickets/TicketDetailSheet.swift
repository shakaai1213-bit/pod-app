// MARK: - Ticket Detail Sheet

struct TicketDetailSheet: View {
    let ticket: Ticket
    @Bindable var viewModel: TicketsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedTitle: String
    @State private var editedDescription: String
    @State private var editedStatus: TicketStatus
    @State private var editedPriority: TicketPriority
    @State private var editedLessonsLearned: String
    @State private var editedResolutionNotes: String
    @State private var showingStatusPicker = false

    init(ticket: Ticket, viewModel: TicketsViewModel) {
        self.ticket = ticket
        self.viewModel = viewModel
        _editedTitle = State(initialValue: ticket.title)
        _editedDescription = State(initialValue: ticket.description ?? "")
        _editedStatus = State(initialValue: ticket.status)
        _editedPriority = State(initialValue: ticket.priority)
        _editedLessonsLearned = State(initialValue: ticket.lessonsLearned ?? "")
        _editedResolutionNotes = State(initialValue: ticket.resolutionNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Title Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TITLE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.textTertiary)

                        TextField("Ticket title", text: $editedTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .padding(12)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Status & Priority Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STATUS & PRIORITY")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.textTertiary)

                        HStack(spacing: 12) {
                            // Status Button
                            Button {
                                showingStatusPicker = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: editedStatus.icon)
                                        .font(.system(size: 12))
                                    Text(editedStatus.label)
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(editedStatus.color)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(editedStatus.color.opacity(0.15))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            // Priority Picker
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
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.textTertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppColors.backgroundSecondary)
                                .clipShape(Capsule())
                            }
                        }
                    }

                    // Description Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("DESCRIPTION")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.textTertiary)

                            Spacer()

                            if !editedDescription.isEmpty {
                                Button("Clear") {
                                    editedDescription = ""
                                }
                                .font(.caption)
                                .foregroundColor(AppColors.accentElectric)
                            }
                        }

                        TextEditor(text: $editedDescription)
                            .font(.system(size: 15))
                            .foregroundColor(AppColors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Lessons Learned Section (POD-4)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("LESSONS LEARNED", systemImage: "lightbulb.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(Color.yellow)

                            Spacer()

                            if !editedLessonsLearned.isEmpty {
                                Button("Clear") {
                                    editedLessonsLearned = ""
                                }
                                .font(.caption)
                                .foregroundColor(AppColors.accentElectric)
                            }
                        }

                        TextEditor(text: $editedLessonsLearned)
                            .font(.system(size: 15))
                            .foregroundColor(AppColors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(Color.yellow.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                            )

                        Text("Capture insights from this ticket for future reference")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }

                    // Resolution Notes Section (for resolved/closed tickets)
                    if editedStatus == .resolved || editedStatus == .closed || !editedResolutionNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("RESOLUTION NOTES")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.textTertiary)

                                Spacer()

                                if !editedResolutionNotes.isEmpty {
                                    Button("Clear") {
                                        editedResolutionNotes = ""
                                    }
                                    .font(.caption)
                                    .foregroundColor(AppColors.accentElectric)
                                }
                            }

                            TextEditor(text: $editedResolutionNotes)
                                .font(.system(size: 15))
                                .foregroundColor(AppColors.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 80)
                                .padding(8)
                                .background(AppColors.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Metadata Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("METADATA")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.textTertiary)

                        VStack(alignment: .leading, spacing: 6) {
                            metadataRow(label: "ID", value: ticket.id.prefix(8) + "...")
                            metadataRow(label: "Created", value: ticket.createdAt.formatted(date: .abbreviated, time: .shortened))
                            metadataRow(label: "Updated", value: ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            if let agent = ticket.assigneeAgentName {
                                metadataRow(label: "Assignee", value: agent)
                            }
                            if let type = ticket.ticketType {
                                metadataRow(label: "Type", value: type)
                            }
                        }
                        .padding(12)
                        .background(AppColors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
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
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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

    private func saveChanges() async {
        // Update status if changed
        if editedStatus != ticket.status {
            await viewModel.updateStatus(ticketId: ticket.id, status: editedStatus)
        }

        // Update lessons learned if changed
        if editedLessonsLearned != (ticket.lessonsLearned ?? "") {
            await viewModel.updateLessonsLearned(ticketId: ticket.id, lessonsLearned: editedLessonsLearned)
        }

        dismiss()
    }
}
