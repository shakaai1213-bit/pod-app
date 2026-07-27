import SwiftUI

struct ChatFileAttachmentChip: View {
    let attachment: ChatFileAttachment
    var compact = false

    @State private var didCopy = false

    var body: some View {
        Button {
            copyPath()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.text")
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(didCopy ? AppColors.accentSuccess : AppColors.accentElectric)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.displayName)
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(attachment.context ?? attachment.path)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 9 : 10)
            .padding(.vertical, compact ? 7 : 8)
            .background(AppColors.accentElectric.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppColors.accentElectric.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                copyPath()
            } label: {
                Label("Copy File Path", systemImage: "doc.on.doc")
            }
        }
        .accessibilityLabel("File attachment \(attachment.displayName)")
        .accessibilityHint("Copies the full file path")
    }

    private func copyPath() {
        UIPasteboard.general.string = attachment.path
        didCopy = true
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
