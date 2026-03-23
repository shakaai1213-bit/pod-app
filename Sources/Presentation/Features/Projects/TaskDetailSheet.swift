import SwiftUI

// MARK: - Task Detail Sheet

struct TaskDetailSheet: View {

    let task: ProjectTask
    @Bindable var viewModel: ProjectsViewModel
    let onUpdate: (ProjectTask) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var editedTitle: String
    @State private var editedDescription: String
    @State private var editedStatus: ProjectTaskStatus
    @State private var editedStage: ProjectStage
    @State private var editedPriority: Priority
    @State private var editedDueDate: Date?
    @State private var editedTags: [String]
    @State private var editedAssigneeId: UUID?
    @State private var showingAssigneePicker = false
    @State private var showingDueDatePicker = false
    @State private var showingTagEditor = false
    @State private var showingDeleteConfirm = false
    @State private var newTagText = ""
    @State private var activityLog: [ActivityEntry] = []

    private let members = ProjectsViewModel.mockMembers

    init(task: ProjectTask, viewModel: ProjectsViewModel, onUpdate: @escaping (ProjectTask) -> Void) {
        self.task = task
        self.viewModel = viewModel
        self.onUpdate = onUpdate

        _editedTitle = State(initialValue: task.title)
        _editedDescription = State(initialValue: task.description)
        _editedStatus = State(initialValue: task.status)
        _editedStage = State(initialValue: task.stage)
        _editedPriority = State(initialValue: task.priority)
        _editedDueDate = State(initialValue: task.dueDate)
        _editedTags = State(initialValue: task.tags)
        _editedAssigneeId = State(initialValue: task.assigneeId)
        _activityLog = State(initialValue: Self.mockActivity(for: task))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    titleSection
                    statusSection
                    metadataSection
                    tagsSection
                    descriptionSection
                    activityLogSection
                    destructiveSection
                }
                .padding(Theme.md)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveChanges() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.accentElectric)
                }
            }
            .sheet(isPresented: $showingAssigneePicker) {
                AssigneePickerSheet(
                    members: members,
                    selectedId: $editedAssigneeId
                )
            }
            .sheet(isPresented: $showingTagEditor) {
                TagEditorSheet(tags: $editedTags)
            }
            .confirmationDialog(
                "Delete Task?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteTask(task.id)
                        dismiss()
                    }
                }
                Button("Archive") {
                    Task {
                        await viewModel.archiveTask(task.id)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            TextField("Task title", text: $editedTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("STATUS")
                .podTextStyle(.label, color: AppColors.textTertiary)

            VStack(spacing: Theme.sm) {
                // Task Status (Todo / In Progress / Review / Done)
                HStack(spacing: Theme.xs) {
                    ForEach(ProjectTaskStatus.allCases, id: \.self) { status in
                        Button {
                            editedStatus = status
                        } label: {
                            Text(status.displayName)
                                .font(.system(size: 13, weight: editedStatus == status ? .semibold : .regular))
                                .foregroundStyle(editedStatus == status ? AppColors.textPrimary : AppColors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.xs)
                                .background(
                                    editedStatus == status
                                        ? statusBackgroundColor(status)
                                        : AppColors.backgroundTertiary
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                        .strokeBorder(
                                            editedStatus == status
                                                ? statusBorderColor(status)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Stage (Plan / Dev / Verify / Test / Done)
                HStack(spacing: Theme.xs) {
                    ForEach(ProjectStage.allCases, id: \.self) { stage in
                        Button {
                            editedStage = stage
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(editedStage == stage ? stageColor(stage) : AppColors.textMuted)
                                    .frame(width: 6, height: 6)
                                Text(stage.displayName)
                            }
                            .font(.system(size: 11, weight: editedStage == stage ? .semibold : .regular))
                            .foregroundStyle(editedStage == stage ? AppColors.textPrimary : AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.xs)
                            .background(
                                editedStage == stage
                                    ? stageColor(stage).opacity(0.1)
                                    : AppColors.backgroundTertiary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(spacing: Theme.xs) {
            // Assignee
            metadataRow(
                icon: "person.circle",
                label: "Assignee",
                value: assigneeName,
                isPlaceholder: editedAssigneeId == nil,
                onTap: { showingAssigneePicker = true }
            )

            Divider().background(AppColors.border)

            // Due Date
            metadataRow(
                icon: "calendar",
                label: "Due Date",
                value: dueDateText,
                isPlaceholder: editedDueDate == nil,
                onTap: { showingDueDatePicker.toggle() }
            )

            if showingDueDatePicker {
                DatePicker(
                    "Due Date",
                    selection: Binding(
                        get: { editedDueDate ?? Date() },
                        set: { editedDueDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(AppColors.accentElectric)
                .padding(.horizontal, Theme.md)
            }

            Divider().background(AppColors.border)

            // Priority
            priorityRow
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    private func metadataRow(
        icon: String,
        label: String,
        value: String,
        isPlaceholder: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 24)

                Text(label)
                    .podTextStyle(.body, color: AppColors.textSecondary)

                Spacer(minLength: 0)

                Text(value.isEmpty ? "Not set" : value)
                    .podTextStyle(.body, color: isPlaceholder ? AppColors.textTertiary : AppColors.textPrimary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.vertical, Theme.xxs)
        }
        .buttonStyle(.plain)
    }

    private var priorityRow: some View {
        HStack {
            Image(systemName: "flag.circle")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 24)

            Text("Priority")
                .podTextStyle(.body, color: AppColors.textSecondary)

            Spacer(minLength: 0)

            Menu {
                ForEach(Priority.allCases, id: \.self) { p in
                    Button {
                        editedPriority = p
                    } label: {
                        HStack {
                            Circle()
                                .fill(priorityColor(p))
                                .frame(width: 8, height: 8)
                            Text(p.displayName)
                            if editedPriority == p {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(priorityColor(editedPriority))
                        .frame(width: 8, height: 8)
                    Text(editedPriority.displayName)
                        .podTextStyle(.body, color: AppColors.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(.vertical, Theme.xxs)
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Text("TAGS")
                    .podTextStyle(.label, color: AppColors.textTertiary)

                Spacer(minLength: 0)

                Button { showingTagEditor = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.accentElectric)
                }
            }

            if editedTags.isEmpty {
                Button { showingTagEditor = true } label: {
                    HStack(spacing: Theme.xs) {
                        Image(systemName: "tag")
                            .font(.system(size: 14))
                        Text("Add tags")
                    }
                    .podTextStyle(.body, color: AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }
                .buttonStyle(.plain)
            } else {
                TaskFlowLayout(spacing: Theme.xs) {
                    ForEach(editedTags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.accentAgent)

                            Button {
                                editedTags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(AppColors.accentAgent.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.accentAgent.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Text("DESCRIPTION")
                    .podTextStyle(.label, color: AppColors.textTertiary)

                Spacer(minLength: 0)

                if !editedDescription.isEmpty {
                    Button {
                        editedDescription = ""
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }

            TextEditor(text: $editedDescription)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )

            if !editedDescription.isEmpty {
                Text("Markdown supported")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Activity Log Section

    private var activityLogSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("ACTIVITY")
                .podTextStyle(.label, color: AppColors.textTertiary)

            VStack(spacing: 0) {
                ForEach(activityLog) { entry in
                    HStack(alignment: .top, spacing: Theme.sm) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                                .podTextStyle(.body, color: AppColors.textPrimary)
                                .lineLimit(3)

                            Text(entry.timestamp, style: .relative)
                                .podTextStyle(.caption, color: AppColors.textTertiary)
                        }
                    }
                    .padding(.vertical, Theme.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if entry.id != activityLog.last?.id {
                        Divider().background(AppColors.border)
                    }
                }
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Destructive Section

    private var destructiveSection: some View {
        VStack(spacing: Theme.xs) {
            Button {
                Task {
                    await viewModel.archiveTask(task.id)
                    dismiss()
                }
            } label: {
                HStack {
                    Image(systemName: "archivebox")
                    Text("Archive Task")
                }
                .podTextStyle(.body, color: AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Task")
                }
                .podTextStyle(.body, color: AppColors.accentDanger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.sm)
                .background(AppColors.accentDanger.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.md)
    }

    // MARK: - Helpers

    private var assigneeName: String {
        members.first { $0.id == editedAssigneeId }?.name ?? ""
    }

    private var dueDateText: String {
        guard let date = editedDueDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func priorityColor(_ p: Priority) -> Color {
        switch p {
        case .low:      return AppColors.accentSuccess
        case .medium:   return AppColors.accentWarning
        case .high:     return Color.orange
        case .critical: return AppColors.accentDanger
        }
    }

    private func stageColor(_ stage: ProjectStage) -> Color {
        switch stage {
        case .plan:   return AppColors.textTertiary
        case .dev:    return AppColors.accentElectric
        case .verify: return AppColors.accentWarning
        case .test:   return AppColors.accentAgent
        case .done:   return AppColors.accentSuccess
        }
    }

    private func statusBackgroundColor(_ status: ProjectTaskStatus) -> Color {
        switch status {
        case .todo:       return AppColors.backgroundTertiary
        case .inProgress: return AppColors.accentElectric.opacity(0.2)
        case .review:     return AppColors.accentWarning.opacity(0.2)
        case .done:       return AppColors.accentSuccess.opacity(0.2)
        }
    }

    private func statusBorderColor(_ status: ProjectTaskStatus) -> Color {
        switch status {
        case .todo:       return AppColors.border
        case .inProgress: return AppColors.accentElectric.opacity(0.4)
        case .review:     return AppColors.accentWarning.opacity(0.4)
        case .done:       return AppColors.accentSuccess.opacity(0.4)
        }
    }

    private func saveChanges() {
        var updated = task
        updated.title = editedTitle
        updated.description = editedDescription
        updated.status = editedStatus
        updated.stage = editedStage
        updated.priority = editedPriority
        updated.dueDate = editedDueDate
        updated.tags = editedTags
        updated.assigneeId = editedAssigneeId

        Task {
            await viewModel.updateTask(updated)
            onUpdate(updated)
            dismiss()
        }
    }

    private static func mockActivity(for task: ProjectTask) -> [ActivityEntry] {
        [
            ActivityEntry(
                id: UUID(),
                message: "Task created",
                timestamp: task.dueDate?.addingTimeInterval(-86400 * 3) ?? Date().addingTimeInterval(-86400 * 3),
                color: AppColors.textTertiary
            ),
            ActivityEntry(
                id: UUID(),
                message: "Assigned to \(ProjectsViewModel.mockMembers.first?.name ?? "Unknown")",
                timestamp: task.dueDate?.addingTimeInterval(-86400 * 2) ?? Date().addingTimeInterval(-86400 * 2),
                color: AppColors.accentElectric
            ),
            ActivityEntry(
                id: UUID(),
                message: "Priority changed to \(task.priority.displayName)",
                timestamp: task.dueDate?.addingTimeInterval(-86400) ?? Date().addingTimeInterval(-86400),
                color: AppColors.accentWarning
            ),
        ]
    }
}

// MARK: - Activity Entry

struct ActivityEntry: Identifiable {
    let id: UUID
    let message: String
    let timestamp: Date
    let color: Color
}

// MARK: - Assignee Picker Sheet

private struct AssigneePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let members: [TeamMember]
    @Binding var selectedId: UUID?

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedId = nil
                    dismiss()
                } label: {
                    HStack {
                        Circle()
                            .fill(AppColors.backgroundTertiary)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "person.slash")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.textTertiary)
                            )
                        Text("Unassigned")
                            .podTextStyle(.body, color: AppColors.textPrimary)
                        Spacer(minLength: 0)
                        if selectedId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.accentElectric)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(members) { member in
                    Button {
                        selectedId = member.id
                        dismiss()
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hexString: member.avatarColor ?? "#6B46C1"))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(member.name.prefix(1))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.white)
                                )
                            Text(member.name)
                                .podTextStyle(.body, color: AppColors.textPrimary)
                            Spacer(minLength: 0)
                            if selectedId == member.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.accentElectric)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Assign To")
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

// MARK: - Tag Editor Sheet

private struct TagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var tags: [String]
    @State private var newTagText = ""
    @State private var suggestions: [String] = ["backend", "frontend", "bug", "feature", "docs", "security", "performance", "testing", "ui", "api"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add a tag", text: $newTagText)
                            .textInputAutocapitalization(.never)

                        Button {
                            addTag()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(AppColors.accentElectric)
                        }
                        .disabled(newTagText.isEmpty || tags.contains(newTagText))
                    }
                }

                Section("Suggested") {
                    ForEach(suggestions.filter { !tags.contains($0) }, id: \.self) { suggestion in
                        Button {
                            tags.append(suggestion)
                        } label: {
                            HStack {
                                Text(suggestion)
                                    .podTextStyle(.body, color: AppColors.textPrimary)
                                Spacer(minLength: 0)
                                Image(systemName: "plus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.accentElectric)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Current Tags") {
                    ForEach(tags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                                .podTextStyle(.body, color: AppColors.textPrimary)
                            Spacer(minLength: 0)
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(AppColors.accentDanger)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTagText = ""
    }
}

// MARK: - Flow Layout

struct TaskFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }
            self.size.height = y + rowHeight
        }
    }
}
