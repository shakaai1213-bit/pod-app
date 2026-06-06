import SwiftUI

// MARK: - Lifecycle Stage

enum ProjectLifecycleStage: String, CaseIterable {
    case assessment = "assessment"
    case definition = "definition"
    case blueprint = "blueprint"
    case scoping = "scoping"
    case active = "active"
    case inProgress = "in-progress"
    case handoff = "handoff"
    case live = "live"
    case closed = "closed"
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .assessment: return "Assessment"
        case .definition: return "Definition"
        case .blueprint: return "Blueprint"
        case .scoping: return "Scoping"
        case .active: return "Active"
        case .inProgress: return "In Progress"
        case .handoff: return "Handoff"
        case .live: return "Live"
        case .closed: return "Closed"
        case .cancelled: return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .assessment: return Color(hexString: "64748B")
        case .definition: return Color(hexString: "0EA5E9")
        case .blueprint: return Color(hexString: "3B82F6")
        case .scoping: return Color(hexString: "8B5CF6")
        case .active: return AppColors.accentSuccess
        case .inProgress: return Color(hexString: "F97316")
        case .handoff: return Color(hexString: "14B8A6")
        case .live: return AppColors.accentSuccess
        case .closed: return AppColors.textTertiary
        case .cancelled: return AppColors.accentDanger
        }
    }

    var icon: String {
        switch self {
        case .assessment: return "magnifyingglass"
        case .definition: return "text.page"
        case .blueprint: return "doc.text"
        case .scoping: return "scope"
        case .active: return "play.circle.fill"
        case .inProgress: return "hammer"
        case .handoff: return "arrowshape.turn.up.right.fill"
        case .live: return "bolt.fill"
        case .closed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

// MARK: - ORCA Projects View (Kanban)

struct ORCAProjectsView: View {
    @State private var viewModel = ORCAProjectsViewModel()
    @State private var showingNewProject = false
    @State private var selectedProject: ProjectDTO?
    @State private var selectedStage: ProjectLifecycleStage? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                if viewModel.isLoading && viewModel.projects.isEmpty {
                    loadingView
                } else {
                    VStack(spacing: 0) {
                        lifecycleFilterBar
                        kanbanContent
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewProject = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(AppColors.accentElectric)
                    }
                }
            }
            .refreshable {
                await viewModel.loadProjects()
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectSheet(viewModel: viewModel)
            }
            .sheet(item: $selectedProject) { project in
                ORCAProjectDetailView(project: project, viewModel: viewModel)
            }
            .task {
                await viewModel.loadProjects()
            }
        }
    }

    // MARK: - Lifecycle Filter Bar

    private var lifecycleFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.sm) {
                filterChip(label: "All", stage: nil)

                ForEach(ProjectLifecycleStage.allCases, id: \.self) { stage in
                    filterChip(label: stage.displayName, stage: stage)
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.sm)
        }
        .background(AppColors.backgroundPrimary)
    }

    private func filterChip(label: String, stage: ProjectLifecycleStage?) -> some View {
        let isSelected = selectedStage == stage
        let color = stage?.color ?? AppColors.accentElectric

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selectedStage == stage {
                    selectedStage = nil
                } else {
                    selectedStage = stage
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let stage = stage {
                    Image(systemName: stage.icon)
                        .font(.system(size: 10, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color : color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? color : color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - List Content (replaces 3-col kanban per Tony iPad review 2026-05-23)
    // Single vertical list sorted by priority (P1 → P5). Stage moved to card header.
    // [DUPLICATE — DEAD] / cancelled / done projects are hidden from default Active view.

    private var kanbanContent: some View {
        let visible = viewModel.projects
            .filter { p in
                // Hide cancelled and DUPLICATE-DEAD from default view
                let s = p.status.lowercased()
                if s == "cancelled" || s == "archived" { return false }
                if p.name.contains("[DUPLICATE") || p.name.contains("— DEAD") { return false }
                return true
            }
            .filter { p in
                guard let selectedStage else { return true }
                return p.stage == selectedStage.rawValue
            }
            .sorted { $0.priority < $1.priority }  // P1 first

        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                if visible.isEmpty {
                    listEmptyState
                        .padding(.top, 60)
                } else {
                    ForEach(visible) { project in
                        ORCAProjectCard(project: project)
                            .onTapGesture { selectedProject = project }
                    }
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.sm)
        }
    }

    private var listEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.textTertiary.opacity(0.5))
            Text("No active projects")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
            Text(selectedStage == nil ? "Tap + to start one" : "No projects in this stage")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textTertiary.opacity(0.7))
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .fill(AppColors.backgroundTertiary)
                    .frame(height: 88)
                    .shimmer()
            }
            Spacer()
        }
        .padding(.horizontal, Theme.md)
        .padding(.top, Theme.sm)
    }
}

// MARK: - Kanban Column

private struct ORCAKanbanColumn: View {
    let status: ORCAProjectsViewModel.KanbanStatus
    let projects: [ProjectDTO]
    let onProjectTap: (ProjectDTO) -> Void
    let onStatusChange: (UUID, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Column Header
            columnHeader

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Theme.sm) {
                    ForEach(projects) { project in
                        ORCAProjectCard(project: project)
                            .onTapGesture {
                                onProjectTap(project)
                            }
                            .draggable(project.id.uuidString) {
                                ORCAProjectCard(project: project)
                                    .frame(width: 280)
                                    .opacity(0.8)
                            }
                    }

                    if projects.isEmpty {
                        emptyColumn
                    }
                }
                .padding(.horizontal, Theme.xs)
                .padding(.bottom, Theme.md)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let idString = items.first,
                      let projectId = UUID(uuidString: idString) else { return false }
                onStatusChange(projectId, status.rawValue)
                return true
            }
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(status.color.opacity(0.2), lineWidth: 1)
        )
    }

    private var columnHeader: some View {
        HStack(spacing: Theme.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            Text(status.displayName.uppercased())
                .podTextStyle(.label, color: AppColors.textSecondary)

            Text("\(projects.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.backgroundTertiary)
                .clipShape(Capsule())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.sm)
        .padding(.vertical, Theme.sm)
        .background(status.color.opacity(0.05))
    }

    private var emptyColumn: some View {
        VStack(spacing: Theme.sm) {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(AppColors.textTertiary.opacity(0.4))
                .frame(height: 80)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "tray")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColors.textTertiary.opacity(0.6))
                        Text("No projects")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary.opacity(0.6))
                    }
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.md)
    }
}

// MARK: - Project Card

private struct ORCAProjectCard: View {
    let project: ProjectDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // HEADER ROW per Tony iPad review 2026-05-23:
            // short_id | STAGE | priority | owner | last-activity Δ
            HStack(spacing: 8) {
                shortIdChip
                stageBadge
                priorityChip
                Spacer(minLength: 4)
                if project.assignedTo != nil {
                    assignedAgentView
                }
                activityDelta
            }

            // TITLE
            Text(project.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // DESCRIPTION (NEW — every card; description first, fall back to goal)
            if let body = descriptionLine, !body.isEmpty {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            // FOOTER: due date + cost (ticket counts deferred to slice 2 — tickets don't carry project_id yet)
            if project.dueDate != nil || project.projectedCost != nil {
                HStack(spacing: 10) {
                    if let dueDate = project.dueDate {
                        dueDateView(dueDate)
                    }
                    if let projected = project.projectedCost {
                        Text("$\(Int(projected))")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    // First line of description, else goal
    private var descriptionLine: String? {
        if let d = project.description, !d.isEmpty {
            return d.components(separatedBy: .newlines).first
        }
        return project.goal
    }

    // MARK: - Header chips

    // short_id chip — bumped contrast + size per Tony 2026-05-23 (was illegible)
    private var shortIdChip: some View {
        Text(String(project.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(AppColors.textPrimary.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(hexString: "1a1a1f"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(AppColors.border.opacity(0.8), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var stageBadge: some View {
        if let stage = project.stage {
            let lifecycleStage = ProjectLifecycleStage(rawValue: stage)
            let badgeColor = lifecycleStage?.color ?? AppColors.textTertiary
            HStack(spacing: 3) {
                Image(systemName: lifecycleStage?.icon ?? "tag.fill")
                    .font(.system(size: 9, weight: .medium))
                Text((lifecycleStage?.displayName ?? stage.replacingOccurrences(of: "_", with: " ")).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.3)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeColor)
            .clipShape(Capsule())
        }
    }

    private var priorityChip: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(priorityColor)
                .frame(width: 6, height: 6)
            Text("P\(project.priority)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(priorityColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(priorityColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var assignedAgentView: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 10))
            Text(agentShortId)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(AppColors.accentAgent)
    }

    private var agentShortId: String {
        guard let assignedTo = project.assignedTo else { return "" }
        return String(assignedTo.uuidString.prefix(4)).lowercased()
    }

    // Last-activity Δ (uses updatedAt)
    private var activityDelta: some View {
        Text(relativeShort(project.updatedAt))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppColors.textTertiary)
    }

    private func relativeShort(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(secs/60)m" }
        if secs < 86400 { return "\(secs/3600)h" }
        if secs < 86400 * 7 { return "\(secs/86400)d" }
        return "\(secs/(86400 * 7))w"
    }

    private var priorityColor: Color {
        switch project.priority {
        case 1: return AppColors.accentDanger
        case 2: return Color(hexString: "F97316")  // orange
        case 3: return AppColors.accentWarning
        case 4: return Color(hexString: "3B82F6")  // blue
        default: return AppColors.textTertiary
        }
    }

    // MARK: - Due Date

    private func dueDateView(_ date: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let now = Date()
        let isOverdue = date < now
        let daysUntilDue = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
        let isSoon = !isOverdue && daysUntilDue <= 3

        let color: Color = isOverdue
            ? AppColors.accentDanger
            : (isSoon ? Color(hexString: "F97316") : AppColors.textSecondary)

        return HStack(spacing: 3) {
            Image(systemName: isOverdue ? "calendar.badge.exclamationmark" : "calendar")
                .font(.system(size: 10))
            Text(formatter.string(from: date))
                .font(.system(size: 11))
        }
        .foregroundStyle(color)
    }
}

// MARK: - New Project Sheet

private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ORCAProjectsViewModel

    @State private var name = ""
    @State private var goal = ""
    @State private var priority = 3
    @State private var selectedStage: ProjectLifecycleStage = .assessment
    @State private var selectedBoardId = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $name)

                TextField("Goal (optional)", text: $goal, axis: .vertical)
                    .lineLimit(2...4)

                Picker("Priority", selection: $priority) {
                    ForEach(1...5, id: \.self) { p in
                        HStack {
                            Circle()
                                .fill(priorityColor(p))
                                .frame(width: 8, height: 8)
                            Text("P\(p)")
                        }
                        .tag(p)
                    }
                }

                Picker("Milestone", selection: $selectedStage) {
                    ForEach(ProjectLifecycleStage.allCases, id: \.self) { stage in
                        Text(stage.displayName).tag(stage)
                    }
                }

                Section("Board") {
                    Picker("Board", selection: $selectedBoardId) {
                        if viewModel.boardOptions.isEmpty {
                            Text("Select after ORCA loads").tag("")
                        }
                        ForEach(viewModel.boardOptions) { board in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(board.displayName)
                                if !board.detail.isEmpty {
                                    Text(board.detail)
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                            .tag(board.id)
                        }
                    }
                    .disabled(viewModel.isLoadingBoardOptions || viewModel.boardOptions.isEmpty)

                    if viewModel.isLoadingBoardOptions {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading live ORCA boards")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    } else if let message = viewModel.boardOptionsMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    } else {
                        Text("Board is saved to ORCA as this project's primary board and is required on create.")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await viewModel.createProject(
                                name: name,
                                goal: goal.isEmpty ? nil : goal,
                                priority: priority,
                                stage: selectedStage.rawValue,
                                boardId: selectedBoardId.isEmpty ? nil : selectedBoardId
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || selectedBoardId.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            await viewModel.loadBoardOptions()
            if selectedBoardId.isEmpty {
                selectedBoardId = viewModel.boardOptions.first(where: { $0.slug == "pod" })?.id ?? viewModel.boardOptions.first?.id ?? ""
            }
        }
    }

    private func priorityColor(_ p: Int) -> Color {
        switch p {
        case 1: return AppColors.accentDanger
        case 2: return Color(hexString: "F97316")
        case 3: return AppColors.accentWarning
        case 4: return Color(hexString: "3B82F6")
        default: return AppColors.textTertiary
        }
    }
}

// MARK: - Project Detail View

private struct ORCAProjectDetailView: View {
    let project: ProjectDTO
    @Bindable var viewModel: ORCAProjectsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var workingProject: ProjectDTO?
    @State private var tasks: [ProjectTaskDTO] = []
    @State private var notes: [ProjectNoteDTO] = []
    @State private var isLoading = false
    @State private var showingNewTask = false
    @State private var newNoteTitle = ""
    @State private var newNoteBody = ""
    @State private var newNoteType = "decision"
    @State private var isSavingNote = false
    @State private var noteStatus: String?
    @State private var automationStatus: String?
    @State private var automationBusyAction: String?
    @State private var generationNote = ""
    @State private var showingMilestoneEditor = false
    @State private var milestoneEditorTitle = ""
    @State private var milestoneEditorDescription = ""
    @State private var editingMilestoneId: String?

    private var activeProject: ProjectDTO {
        workingProject ?? project
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    projectInfo
                    commandRoomSection
                    decisionQueueSection
                    workSummarySection
                    agentSupportSection
                    proposedMilestonesSection
                    notesSection
                    tasksSection
                }
                .padding(.horizontal, Theme.md)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewTask = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColors.accentElectric)
                    }
                }
            }
            .sheet(isPresented: $showingNewTask) {
                NewORCATaskSheet(projectId: project.id, viewModel: viewModel) { newTask in
                    tasks.append(newTask)
                }
            }
            .sheet(isPresented: $showingMilestoneEditor) {
                ProjectMilestoneEditorSheet(
                    titleText: $milestoneEditorTitle,
                    descriptionText: $milestoneEditorDescription,
                    isEditingProposal: editingMilestoneId != nil,
                    isSaving: automationBusyAction == "milestone-editor"
                ) { title, description in
                    Task { await submitMilestoneEditor(title: title, description: description) }
                }
            }
            .task {
                workingProject = project
                await loadTasks()
            }
        }
    }

    private var projectInfo: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .top, spacing: Theme.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROJECT COMMAND ROOM")
                        .podTextStyle(.label, color: AppColors.textTertiary)

                    Text(activeProject.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.sm)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(activeProject.status.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())

                    Text("ORCA truth")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            if let goal = activeProject.goal, !goal.isEmpty {
                Text(goal)
                    .podTextStyle(.body, color: AppColors.textSecondary)
            }

            FlowLayout(horizontalSpacing: Theme.xs, verticalSpacing: Theme.xs) {
                if let stage = activeProject.stage, !stage.isEmpty {
                    metaPill(icon: "square.stack.3d.up", text: stage.replacingOccurrences(of: "-", with: " "), color: AppColors.accentElectric)
                }
                metaPill(icon: "flag.fill", text: "P\(activeProject.priority)", color: priorityColor)
                metaPill(icon: "rectangle.3.group", text: boardLabel, color: AppColors.accentAgent)
                if let dueDate = activeProject.dueDate {
                    metaPill(icon: "calendar", text: formatDate(dueDate), color: AppColors.textSecondary)
                }
                if let projected = activeProject.projectedCost {
                    metaPill(icon: "dollarsign.circle", text: "$\(Int(projected))", color: AppColors.textSecondary)
                }
                if activeProject.automationEnabled == true {
                    metaPill(icon: "sparkles", text: "automation", color: AppColors.accentAgent)
                }
            }
        }
        .padding(Theme.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }

    private var commandRoomSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionHeader("COMMAND", count: nil)

            HStack(alignment: .top, spacing: Theme.sm) {
                commandMetric(title: "Open tasks", value: "\(openTasks.count)", color: openTasks.isEmpty ? AppColors.accentSuccess : AppColors.accentWarning)
                commandMetric(title: "Decisions", value: "\(decisionNotes.count)", color: decisionNotes.isEmpty ? AppColors.textTertiary : AppColors.accentElectric)
                commandMetric(title: "Milestones", value: "\(acceptedMilestones.count)", color: acceptedMilestones.isEmpty ? AppColors.textTertiary : AppColors.accentAgent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(nextAction.title, systemImage: nextAction.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(nextAction.color)

                Text(nextAction.detail)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(nextAction.color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            Text("Updated \(relativeDate(activeProject.updatedAt)) from ORCA project, task, note, and milestone records.")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private var decisionQueueSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionHeader("DECISION QUEUE", count: pendingDecisions.count)

            if pendingDecisions.isEmpty {
                Text("No Tony decisions waiting on this project.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            } else {
                VStack(spacing: Theme.xs) {
                    ForEach(Array(pendingDecisions.prefix(4)), id: \.id) { item in
                        HStack(alignment: .top, spacing: Theme.sm) {
                            Image(systemName: item.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.color)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(2)

                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(Theme.sm)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                }
            }
        }
    }

    private var workSummarySection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionHeader("WORKFLOW", count: timelineRows.count)

            if timelineRows.isEmpty {
                Text("No project activity loaded yet.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            } else {
                ProjectWorkflowPreview(rows: timelinePreviewRows)
            }
        }
    }

    private var agentSupportSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionHeader("AGENT SUPPORT", count: nil)

            VStack(alignment: .leading, spacing: Theme.xs) {
                agentSupportRow(
                    icon: "checkmark.seal",
                    title: "Ready now",
                    detail: "Agents can read the project goal, tasks, notes, milestone proposals, and accepted milestones through ORCA.",
                    color: AppColors.accentSuccess
                )
                agentSupportRow(
                    icon: "link",
                    title: "Contract gap",
                    detail: "Linked tickets should become a first-class ORCA project relation instead of a Pod-side guess.",
                    color: AppColors.accentWarning
                )
                agentSupportRow(
                    icon: "doc.text.magnifyingglass",
                    title: "Next contract",
                    detail: "Add `/api/v1/projects/{id}/agent-packet` so Maui, Merman, and workers wake with one canonical project brief.",
                    color: AppColors.accentElectric
                )
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
    }

    private var proposedMilestonesSection: some View {
        let proposals = activeProject.proposedMilestones ?? []
        let durable = activeProject.milestones ?? []
        let canAdvance = proposals.isEmpty && !durable.isEmpty

        return VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: Theme.xs) {
                Text("PROPOSED MILESTONES")
                    .podTextStyle(.label, color: AppColors.textTertiary)

                if !proposals.isEmpty {
                    Text("\(proposals.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentAgent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColors.accentAgent.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                Button {
                    openMilestoneEditor(for: nil)
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(AppColors.accentSuccess)
                .disabled(automationBusyAction != nil)

                Button {
                    Task { await generateMilestones() }
                } label: {
                    Label(automationBusyAction == "generate" ? "Generating" : "Generate", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(AppColors.accentElectric)
                .disabled(automationBusyAction != nil)
            }

            TextField("Optional generation note", text: $generationNote, axis: .vertical)
                .font(.caption)
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .padding(Theme.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            if let runId = activeProject.lastGenerationRunId, !runId.isEmpty {
                Label("Last generation \(runId)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let automationStatus {
                Text(automationStatus)
                    .font(.caption2)
                    .foregroundStyle(automationStatus.localizedCaseInsensitiveContains("couldn't") ? AppColors.accentDanger : AppColors.textTertiary)
            }

            if proposals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(durable.isEmpty ? "No proposed milestones yet." : "\(durable.count) durable milestone\(durable.count == 1 ? "" : "s") accepted.")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)

                    if canAdvance {
                        Button {
                            Task { await advanceToScoping() }
                        } label: {
                            Label(automationBusyAction == "advance" ? "Advancing" : "Advance to Scoping", systemImage: "arrow.right.circle")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(AppColors.accentSuccess)
                        .disabled(automationBusyAction != nil)
                    }
                }
                .padding(Theme.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            } else {
                VStack(spacing: Theme.xs) {
                    ForEach(proposals) { proposal in
                        PodReviewCard(
                            item: milestoneReviewItem(for: proposal),
                            isBusy: automationBusyAction?.hasSuffix(proposal.id) == true,
	                            onAction: { action in
	                                switch action.id {
                                case "edit":
                                    openMilestoneEditor(for: proposal)
	                                case "accept":
	                                    Task { await acceptMilestone(proposal.id) }
	                                case "drop":
	                                    Task { await dropMilestone(proposal.id) }
	                                default:
	                                    break
	                                }
                            }
	                        )
	                    }
	                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("TASKS")
                .podTextStyle(.label, color: AppColors.textTertiary)

            if isLoading {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .fill(AppColors.backgroundTertiary)
                        .frame(height: 60)
                        .shimmer()
                }
            } else if tasks.isEmpty {
                Text("No tasks yet")
                    .podTextStyle(.body, color: AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.lg)
            } else {
                ForEach(tasks) { task in
                    ORCATaskRow(task: task)
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: Theme.xs) {
                Text("NOTES & DECISIONS")
                    .podTextStyle(.label, color: AppColors.textTertiary)

                Spacer(minLength: 0)

                if !notes.isEmpty {
                    Text("\(notes.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.accentElectric)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColors.accentElectric.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: Theme.xs) {
                HStack(spacing: Theme.xs) {
                    TextField("Note title", text: $newNoteTitle)
                        .font(.caption.weight(.semibold))
                        .textInputAutocapitalization(.sentences)

                    Picker("Type", selection: $newNoteType) {
                        Text("Decision").tag("decision")
                        Text("Note").tag("note")
                        Text("Handoff").tag("handoff")
                        Text("Finding").tag("finding")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.caption)
                }

                TextField("Project note", text: $newNoteBody, axis: .vertical)
                    .font(.caption)
                    .lineLimit(2...6)

                Button {
                    Task { await createProjectNote() }
                } label: {
                    HStack(spacing: Theme.xs) {
                        if isSavingNote {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.pencil")
                        }
                        Text(isSavingNote ? "Saving" : "Save ORCA Note")
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .disabled(!canSaveProjectNote || isSavingNote)

                if let noteStatus {
                    Text(noteStatus)
                        .font(.caption2)
                        .foregroundStyle(noteStatus.localizedCaseInsensitiveContains("couldn't") ? AppColors.accentDanger : AppColors.textTertiary)
                }
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            if isLoading && notes.isEmpty {
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .fill(AppColors.backgroundTertiary)
                    .frame(height: 72)
                    .shimmer()
            } else if notes.isEmpty {
                Text("No ORCA project notes yet")
                    .podTextStyle(.body, color: AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.md)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            } else {
                VStack(spacing: Theme.xs) {
                    ForEach(notes.prefix(6)) { note in
                        ORCAProjectNoteRow(note: note)
                    }
                }
            }
        }
    }

    private var canSaveProjectNote: Bool {
        !newNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !newNoteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var openTasks: [ProjectTaskDTO] {
        tasks.filter { !closedStatuses.contains($0.status.lowercased()) }
    }

    private var blockedTasks: [ProjectTaskDTO] {
        tasks.filter { $0.status.lowercased() == "blocked" }
    }

    private var decisionNotes: [ProjectNoteDTO] {
        notes.filter { $0.noteType.lowercased() == "decision" || $0.signState?.lowercased() == "pending" }
    }

    private var pendingProposals: [ProjectMilestoneProposalDTO] {
        activeProject.proposedMilestones ?? []
    }

    private var acceptedMilestones: [ProjectMilestoneDTO] {
        activeProject.milestones ?? []
    }

    private var pendingDecisions: [ProjectCommandDecision] {
        var items = pendingProposals.map {
            ProjectCommandDecision(
                title: $0.title,
                detail: $0.description ?? "Milestone proposal awaiting accept, edit, or drop.",
                icon: "sparkles",
                color: AppColors.accentAgent
            )
        }

        items.append(contentsOf: decisionNotes.prefix(3).map {
            ProjectCommandDecision(
                title: $0.title,
                detail: $0.body,
                icon: "signature",
                color: AppColors.accentElectric
            )
        })

        return items
    }

    private var timelineRows: [ProjectCommandTimelineRow] {
        var rows: [ProjectCommandTimelineRow] = [
            ProjectCommandTimelineRow(
                title: "Project record updated",
                subtitle: "\(activeProject.status.capitalized) · \(activeProject.stage ?? "stage unknown")",
                date: activeProject.updatedAt,
                icon: "folder",
                color: statusColor
            )
        ]

        rows.append(contentsOf: tasks.map {
            ProjectCommandTimelineRow(
                title: $0.title,
                subtitle: "Task · \($0.status.replacingOccurrences(of: "-", with: " "))",
                date: $0.updatedAt,
                icon: "checklist",
                color: taskColor($0)
            )
        })

        rows.append(contentsOf: notes.map {
            ProjectCommandTimelineRow(
                title: $0.title,
                subtitle: "\($0.typeLabel) · \($0.source ?? "ORCA note")",
                date: $0.updatedAt,
                icon: "note.text",
                color: AppColors.accentElectric
            )
        })

        rows.append(contentsOf: acceptedMilestones.compactMap {
            guard let acceptedAt = $0.acceptedAt else { return nil }
            return ProjectCommandTimelineRow(
                title: $0.title,
                subtitle: "Accepted milestone",
                date: acceptedAt,
                icon: "flag.checkered",
                color: AppColors.accentSuccess
            )
        })

        return rows.sorted { $0.date > $1.date }
    }

    private var timelinePreviewRows: [ProjectCommandTimelineRow] {
        Array(timelineRows.prefix(6))
    }

    private var nextAction: ProjectCommandAction {
        if !pendingProposals.isEmpty {
            return ProjectCommandAction(
                title: "Review milestone proposals",
                detail: "\(pendingProposals.count) generated milestone\(pendingProposals.count == 1 ? "" : "s") need accept, edit, or drop before the project is cleanly plannable.",
                icon: "sparkles",
                color: AppColors.accentAgent
            )
        }

        if !blockedTasks.isEmpty {
            return ProjectCommandAction(
                title: "Clear blockers",
                detail: "\(blockedTasks.count) task\(blockedTasks.count == 1 ? "" : "s") marked blocked. Add a note or split work into tickets before dispatch.",
                icon: "exclamationmark.triangle",
                color: AppColors.accentWarning
            )
        }

        if !openTasks.isEmpty {
            return ProjectCommandAction(
                title: "Work open tasks",
                detail: "\(openTasks.count) open task\(openTasks.count == 1 ? "" : "s") can be used as the next agent handoff surface.",
                icon: "checklist",
                color: AppColors.accentElectric
            )
        }

        if notes.isEmpty {
            return ProjectCommandAction(
                title: "Add project context",
                detail: "The project has no notes yet. Add a decision, handoff, or finding so agents inherit the why, not only the task list.",
                icon: "square.and.pencil",
                color: AppColors.accentWarning
            )
        }

        return ProjectCommandAction(
            title: "Project is tidy",
            detail: "No pending milestone proposals or open tasks are loaded from ORCA. Keep notes current as the project moves.",
            icon: "checkmark.circle",
            color: AppColors.accentSuccess
        )
    }

    private var closedStatuses: Set<String> {
        ["done", "completed", "closed", "archived", "cancelled", "canceled"]
    }

    private var boardLabel: String {
        if let boardId = activeProject.boardId {
            return "board \(shortUUID(boardId))"
        }
        if let boardIds = activeProject.boardIds, !boardIds.isEmpty {
            return "\(boardIds.count) boards"
        }
        return "needs home"
    }

    @MainActor
    private func createProjectNote() async {
        guard canSaveProjectNote else { return }
        isSavingNote = true
        noteStatus = nil
        defer { isSavingNote = false }

        if let note = await viewModel.createNote(
            projectId: project.id,
            title: newNoteTitle,
            body: newNoteBody,
            noteType: newNoteType
        ) {
            notes.insert(note, at: 0)
            newNoteTitle = ""
            newNoteBody = ""
            newNoteType = "decision"
            noteStatus = "ORCA note saved."
        } else {
            noteStatus = "Couldn't save ORCA note."
        }
    }

    private func metaPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, Theme.sm)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var priorityColor: Color {
        switch activeProject.priority {
        case 1: return AppColors.accentDanger
        case 2: return Color(hexString: "F97316")
        case 3: return AppColors.accentWarning
        default: return AppColors.textTertiary
        }
    }

    private var statusColor: Color {
        switch activeProject.status.lowercased() {
        case "done", "completed", "shipped":
            return AppColors.accentSuccess
        case "blocked":
            return AppColors.accentDanger
        case "in-progress", "in_progress", "active", "live":
            return AppColors.accentElectric
        case "backlog", "scoping":
            return AppColors.accentWarning
        default:
            return AppColors.textTertiary
        }
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack(spacing: Theme.xs) {
            Text(title)
                .podTextStyle(.label, color: AppColors.textTertiary)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.accentElectric)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.accentElectric.opacity(0.12))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)
        }
    }

    private func commandMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func agentSupportRow(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func taskColor(_ task: ProjectTaskDTO) -> Color {
        switch task.status.lowercased() {
        case "done", "completed", "closed":
            return AppColors.accentSuccess
        case "blocked":
            return AppColors.accentDanger
        case "in-progress", "in_progress", "active":
            return AppColors.accentElectric
        default:
            return AppColors.textTertiary
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func shortUUID(_ uuid: UUID) -> String {
        String(uuid.uuidString.prefix(8)).lowercased()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func loadTasks() async {
        isLoading = true
        async let taskLoad: Void = viewModel.loadTasks(projectId: project.id)
        async let notesLoad = viewModel.loadNotes(projectId: project.id)
        _ = await taskLoad
        tasks = viewModel.tasks
        notes = await notesLoad
        isLoading = false
    }

    private func milestoneReviewItem(for proposal: ProjectMilestoneProposalDTO) -> PodReviewItem {
        var provenance: [String] = []
        if let route = proposal.route, !route.isEmpty { provenance.append(route) }
        if let model = proposal.model, !model.isEmpty { provenance.append(model) }
        if let runId = proposal.runId, !runId.isEmpty { provenance.append("run \(String(runId.prefix(8)))") }
        if let count = proposal.dependencies?.count, count > 0 { provenance.append("\(count) deps") }
        if let createdAt = proposal.createdAt {
            provenance.append(createdAt.formatted(date: .abbreviated, time: .shortened))
        }

        return PodReviewItem(
            id: proposal.id,
            eyebrow: "Milestone proposal",
            title: proposal.title,
            detail: proposal.description,
            status: (proposal.status ?? "proposed").replacingOccurrences(of: "_", with: " ").capitalized,
            statusColor: AppColors.accentAgent,
            provenance: provenance,
            traceId: proposal.runId ?? activeProject.lastGenerationRunId,
            artifactHash: proposal.artifactHash,
	            actions: [
                PodReviewAction(id: "edit", title: "Edit", systemImage: "pencil", style: .primary),
	                PodReviewAction(id: "accept", title: "Accept", systemImage: "checkmark", style: .success),
	                PodReviewAction(id: "drop", title: "Drop", systemImage: "xmark", style: .destructive)
	            ]
        )
    }

    @MainActor
    private func generateMilestones() async {
        automationBusyAction = "generate"
        automationStatus = nil
        defer { automationBusyAction = nil }
	        do {
	            workingProject = try await viewModel.generateMilestones(projectId: activeProject.id, note: generationNote)
	            let usedNote = !generationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	            generationNote = ""
	            automationStatus = usedNote ? "Milestone regeneration requested with Pod note." : "Milestone generation requested through ORCA."
	        } catch {
	            automationStatus = "Couldn't generate milestones: \(error.localizedDescription)"
	        }
	    }

    @MainActor
    private func acceptMilestone(_ milestoneId: String) async {
        automationBusyAction = "accept:\(milestoneId)"
        automationStatus = nil
        defer { automationBusyAction = nil }
        do {
            workingProject = try await viewModel.acceptMilestone(projectId: activeProject.id, milestoneId: milestoneId)
            automationStatus = "Milestone accepted into ORCA."
        } catch {
            automationStatus = "Couldn't accept milestone: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func dropMilestone(_ milestoneId: String) async {
        automationBusyAction = "drop:\(milestoneId)"
        automationStatus = nil
        defer { automationBusyAction = nil }
        do {
            workingProject = try await viewModel.dropMilestone(projectId: activeProject.id, milestoneId: milestoneId)
            automationStatus = "Milestone dropped with ORCA audit trail."
        } catch {
            automationStatus = "Couldn't drop milestone: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func advanceToScoping() async {
        automationBusyAction = "advance"
        automationStatus = nil
        defer { automationBusyAction = nil }
        do {
            workingProject = try await viewModel.advanceToScoping(projectId: activeProject.id)
            automationStatus = "Project advanced to Scoping."
        } catch {
	            automationStatus = "Couldn't advance to Scoping: \(error.localizedDescription)"
	        }
	    }

    private func openMilestoneEditor(for proposal: ProjectMilestoneProposalDTO?) {
        editingMilestoneId = proposal?.id
        milestoneEditorTitle = proposal?.title ?? ""
        milestoneEditorDescription = proposal?.description ?? ""
        showingMilestoneEditor = true
    }

    @MainActor
    private func submitMilestoneEditor(title: String, description: String) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        automationBusyAction = "milestone-editor"
        automationStatus = nil
        defer { automationBusyAction = nil }

        do {
            if let editingMilestoneId {
                workingProject = try await viewModel.acceptMilestone(
                    projectId: activeProject.id,
                    milestoneId: editingMilestoneId,
                    edits: ProjectMilestoneEdits(
                        title: cleanTitle,
                        outcome: cleanDescription.isEmpty ? nil : cleanDescription
                    )
                )
                automationStatus = "Edited milestone accepted into ORCA."
            } else {
                workingProject = try await viewModel.addMilestone(
                    projectId: activeProject.id,
                    title: cleanTitle,
                    description: cleanDescription.isEmpty ? nil : cleanDescription
                )
                automationStatus = "Manual milestone added to ORCA."
            }
            showingMilestoneEditor = false
            self.editingMilestoneId = nil
            milestoneEditorTitle = ""
            milestoneEditorDescription = ""
        } catch {
            automationStatus = "Couldn't save milestone: \(error.localizedDescription)"
        }
    }
	}

private struct ProjectCommandAction {
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

private struct ProjectCommandDecision: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

private struct ProjectCommandTimelineRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let date: Date
    let icon: String
    let color: Color
}

private struct ProjectWorkflowPreview: View {
    let rows: [ProjectCommandTimelineRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .top, spacing: Theme.sm) {
                    Image(systemName: row.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.color)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)

                        Text(row.subtitle)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Text(relativeDate(row.date))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
                .padding(.vertical, Theme.xs)

                if index < rows.count - 1 {
                    Divider().overlay(AppColors.border)
                }
            }
        }
        .padding(.horizontal, Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct ProjectMilestoneEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var titleText: String
    @Binding var descriptionText: String
    let isEditingProposal: Bool
    let isSaving: Bool
    let onSubmit: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Milestone title", text: $titleText)
                TextField("Description", text: $descriptionText, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle(isEditingProposal ? "Edit Milestone" : "Add Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditingProposal ? "Accept" : "Add") {
                        onSubmit(titleText, descriptionText)
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ORCAProjectNoteRow: View {
    let note: ProjectNoteDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.xs) {
                Image(systemName: iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                Text(note.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: Theme.xs)

                Text(note.typeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .lineLimit(1)
            }

            Text(note.body)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.xs) {
                if let source = note.source, !source.isEmpty {
                    noteChip(text: source, icon: "tray")
                }

                if let signState = note.signState, !signState.isEmpty {
                    noteChip(text: signState.replacingOccurrences(of: "_", with: " "), icon: "signature")
                }

                if let traceId = note.traceId, !traceId.isEmpty {
                    noteChip(text: traceId, icon: "point.3.connected.trianglepath.dotted")
                }

                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            if note.owner?.isEmpty == false || note.reviewer?.isEmpty == false {
                HStack(spacing: Theme.xs) {
                    if let owner = note.owner, !owner.isEmpty {
                        noteChip(text: owner, icon: "person.crop.circle")
                    }

                    if let reviewer = note.reviewer, !reviewer.isEmpty {
                        noteChip(text: reviewer, icon: "person.crop.circle.badge.checkmark")
                    }
                }
            }

            if let tags = note.tags, !tags.isEmpty {
                HStack(spacing: Theme.xs) {
                    ForEach(tags.prefix(4), id: \.self) { tag in
                        noteChip(text: tag, icon: "tag")
                    }
                }
            }
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var iconName: String {
        switch note.noteType {
        case "decision": return "checkmark.seal.fill"
        case "handoff": return "arrow.left.arrow.right.circle.fill"
        case "risk": return "exclamationmark.triangle.fill"
        default: return "note.text"
        }
    }

    private var iconColor: Color {
        switch note.noteType {
        case "decision": return AppColors.accentSuccess
        case "risk": return AppColors.accentWarning
        default: return AppColors.accentElectric
        }
    }

    private func noteChip(text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppColors.backgroundSecondary)
            .clipShape(Capsule())
    }
}

// MARK: - Task Row

private struct ORCATaskRow: View {
    let task: ProjectTaskDTO

    var body: some View {
        HStack(spacing: Theme.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .podTextStyle(.headline, color: AppColors.textPrimary)
                    .lineLimit(2)

                if let desc = task.description, !desc.isEmpty {
                    Text(desc)
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            statusPill
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var statusColor: Color {
        switch task.status {
        case "done":       return AppColors.accentSuccess
        case "in-progress": return AppColors.accentElectric
        case "blocked":    return AppColors.accentDanger
        case "cancelled":  return AppColors.textTertiary
        default:           return AppColors.textTertiary
        }
    }

    private var statusPill: some View {
        Text(task.status.replacingOccurrences(of: "-", with: " ").capitalized)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - New Task Sheet

private struct NewORCATaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let viewModel: ORCAProjectsViewModel
    let onCreated: (ProjectTaskDTO) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var priority = 3

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task title", text: $title)

                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(3...6)

                Picker("Priority", selection: $priority) {
                    ForEach(1...5, id: \.self) { p in
                        Text("P\(p)").tag(p)
                    }
                }

                Text("New tasks start in ORCA's default project-task state.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            do {
                                let task = try await ProjectRepository().createTask(
                                    projectId: projectId,
                                    title: title,
                                    description: description.isEmpty ? nil : description,
                                    priority: priority
                                )
                                onCreated(task)
                                dismiss()
                            } catch {
                                print("Failed to create task: \(error)")
                            }
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
