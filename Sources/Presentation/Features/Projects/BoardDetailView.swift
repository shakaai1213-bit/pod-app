import SwiftUI

// MARK: - Board Detail View

struct BoardDetailView: View {

    let board: Board
    @Bindable var viewModel: ProjectsViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedStage: ProjectStage = .dev
    @State private var tasks: [Task] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var filterPriority: Priority?
    @State private var filterTag: String?
    @State private var showingNewTask = false
    @State private var draggingTask: Task?
    @State private var selectedTask: Task?
    @State private var collapsedStages: Set<ProjectStage> = []

    private var isIPad: Bool { horizontalSizeClass == .regular }

    // MARK: - Tasks by Stage

    private var tasksByStage: [ProjectStage: [Task]] {
        var grouped: [ProjectStage: [Task]] = [:]
        for stage in ProjectStage.allCases {
            grouped[stage] = tasksForDisplay.filter { $0.stage == stage }
        }
        return grouped
    }

    private var tasksForDisplay: [Task] {
        var result = tasks

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        if let priority = filterPriority {
            result = result.filter { $0.priority == priority }
        }

        if let tag = filterTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                if isIPad {
                    iPadKanbanLayout
                } else {
                    iPhoneKanbanLayout
                }
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle(board.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Theme.sm) {
                        Menu {
                            Button("All Stages") { selectedStage = .plan }
                            ForEach(ProjectStage.allCases, id: \.self) { stage in
                                Button(stage.displayName) { selectedStage = stage }
                            }
                        } label: {
                            Text(selectedStage.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.accentElectric)
                        }

                        Button { showingNewTask = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(AppColors.accentElectric)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewTask) {
                NewBoardTaskSheet(boardId: board.id, viewModel: viewModel) { newTask in
                    tasks.append(newTask)
                }
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailSheet(task: task, viewModel: viewModel) { updated in
                    if let idx = tasks.indices.first(where: { tasks[idx].id == updated.id }) {
                        tasks[idx] = updated
                    }
                }
            }
            .task {
                await loadTasks()
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: Theme.xs) {
            HStack(spacing: Theme.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)

                TextField("Search tasks", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textPrimary)

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Theme.sm)
            .padding(.vertical, Theme.xs)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.xs) {
                    filterChip("All", isSelected: filterPriority == nil) {
                        filterPriority = nil
                    }

                    ForEach(Priority.allCases, id: \.self) { priority in
                        filterChip(priority.displayName, isSelected: filterPriority == priority) {
                            filterPriority = priority
                        }
                    }

                    Divider()
                        .frame(height: 20)
                        .background(AppColors.border)

                    Button {
                        filterTag = nil
                    } label: {
                        if let tag = filterTag {
                            HStack(spacing: 4) {
                                Text(tag)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .tagPillStyle(color: AppColors.accentAgent)
                        } else {
                            Text("Tag")
                                .tagPillStyle(color: AppColors.backgroundTertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.sm)
        .background(AppColors.backgroundSecondary)
    }

    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                .padding(.horizontal, Theme.sm)
                .padding(.vertical, 5)
                .background(isSelected ? AppColors.accentElectric.opacity(0.2) : AppColors.backgroundTertiary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? AppColors.accentElectric.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        }
    }

    // MARK: - iPad Kanban Layout

    private var iPadKanbanLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.md) {
                ForEach(ProjectStage.allCases, id: \.self) { stage in
                    KanbanColumn(
                        stage: stage,
                        tasks: tasksByStage[stage] ?? [],
                        isCollapsed: collapsedStages.contains(stage),
                        onToggleCollapse: {
                            if collapsedStages.contains(stage) {
                                collapsedStages.remove(stage)
                            } else {
                                collapsedStages.insert(stage)
                            }
                        },
                        onTaskTap: { task in selectedTask = task },
                        onTaskDrop: { taskId in moveTask(taskId, to: stage) }
                    )
                    .frame(width: 280)
                }
            }
            .padding(Theme.md)
        }
    }

    // MARK: - iPhone Kanban Layout

    private var iPhoneKanbanLayout: some View {
        VStack(spacing: 0) {
            Picker("Stage", selection: $selectedStage) {
                ForEach(ProjectStage.allCases, id: \.self) { stage in
                    Text(stage.displayName)
                        .tag(stage)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.sm)

            let stageTasks = tasksByStage[selectedStage] ?? []
            ScrollView {
                KanbanColumn(
                    stage: selectedStage,
                    tasks: stageTasks,
                    isCollapsed: false,
                    onToggleCollapse: {},
                    onTaskTap: { task in selectedTask = task },
                    onTaskDrop: { _ in }
                )
                .frame(minHeight: 400)
                .padding(.horizontal, Theme.md)
                .padding(.bottom, 80) // space for FAB
            }

            // FAB
            Spacer()
            HStack {
                Spacer()
                Button { showingNewTask = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 56, height: 56)
                        .background(AppColors.accentElectric)
                        .clipShape(Circle())
                        .podShadow(Theme.Shadow.medium)
                }
                .padding(.trailing, Theme.lg)
                .padding(.bottom, Theme.lg)
            }
        }
    }

    // MARK: - Data Loading

    private func loadTasks() async {
        isLoading = true
        // Load tasks for this board from API
        // For now, use filtered mock tasks
        tasks = Self.mockTasksForBoard(boardId: board.id)
        isLoading = false
    }

    private func moveTask(_ taskId: UUID, to stage: ProjectStage) {
        if let idx = tasks.indices.first(where: { tasks[idx].id == taskId }) {
            tasks[idx].stage = stage
            Task {
                await viewModel.moveTask(taskId, toStage: stage)
            }
        }
    }

    private static func mockTasksForBoard(boardId: UUID) -> [Task] {
        let members = ProjectsViewModel.mockMembers
        return ProjectStage.allCases.flatMap { stage in
            let count = Int.random(in: 2...5)
            return (0..<count).map { i in
                Task(
                    id: UUID(),
                    projectId: boardId,
                    title: "\(stage.displayName) task \(i + 1)",
                    description: "Description for \(stage.displayName) task \(i + 1)",
                    status: stage == .done ? .done : .todo,
                    stage: stage,
                    assigneeId: members.randomElement()?.id,
                    dueDate: Bool.random() ? Date().addingTimeInterval(Double.random(in: -86400...604800)) : nil,
                    priority: Priority.allCases.randomElement()!,
                    tags: Array(["backend", "frontend", "bug", "feature", "docs"].shuffled().prefix(2))
                )
            }
        }
    }
}

// MARK: - Kanban Column

private struct KanbanColumn: View {
    let stage: ProjectStage
    let tasks: [Task]
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onTaskTap: (Task) -> Void
    let onTaskDrop: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Column Header
            columnHeader

            if !isCollapsed {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: Theme.xs) {
                        ForEach(tasks) { task in
                            TaskCardView(task: task, members: ProjectsViewModel.mockMembers)
                                .onTapGesture {
                                    onTaskTap(task)
                                }
                                .draggable(task.id.uuidString) {
                                    TaskCardView(task: task, members: ProjectsViewModel.mockMembers)
                                        .frame(width: 256)
                                        .opacity(0.8)
                                }
                        }
                    }
                    .padding(.horizontal, Theme.xs)
                    .padding(.bottom, Theme.md)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let idString = items.first,
                          let taskId = UUID(uuidString: idString) else { return false }
                    onTaskDrop(taskId)
                    return true
                }
            }
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(stageBorderColor, lineWidth: 1)
        )
    }

    private var columnHeader: some View {
        HStack(spacing: Theme.xs) {
            Circle()
                .fill(stageColor)
                .frame(width: 8, height: 8)

            Text(stage.displayName.uppercased())
                .podTextStyle(.label, color: AppColors.textSecondary)

            Text("\(tasks.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.backgroundTertiary)
                .clipShape(Capsule())

            Spacer(minLength: 0)

            Button(action: onToggleCollapse) {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, Theme.sm)
        .padding(.vertical, Theme.sm)
        .background(stageColor.opacity(0.05))
    }

    private var stageColor: Color {
        switch stage {
        case .plan:   return AppColors.textTertiary
        case .dev:    return AppColors.accentElectric
        case .verify: return AppColors.accentWarning
        case .test:   return AppColors.accentAgent
        case .done:   return AppColors.accentSuccess
        }
    }

    private var stageBorderColor: Color {
        stageColor.opacity(0.2)
    }
}

// MARK: - Tag Pill Style Modifier

private extension View {
    func tagPillStyle(color: Color) -> some View {
        self
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - New Board Task Sheet

private struct NewBoardTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let boardId: UUID
    let viewModel: ProjectsViewModel
    let onCreated: (Task) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var selectedPriority: Priority = .medium
    @State private var selectedStage: ProjectStage = .dev

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task title", text: $title)

                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(3...8)

                Picker("Priority", selection: $selectedPriority) {
                    ForEach(Priority.allCases, id: \.self) { p in
                        HStack {
                            Circle()
                                .fill(priorityColor(p))
                                .frame(width: 8, height: 8)
                            Text(p.displayName)
                        }
                        .tag(p)
                    }
                }

                Picker("Stage", selection: $selectedStage) {
                    ForEach(ProjectStage.allCases, id: \.self) { s in
                        Text(s.displayName).tag(s)
                    }
                }
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
                            await viewModel.createTask(
                                boardId: boardId,
                                title: title,
                                description: description
                            )
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func priorityColor(_ p: Priority) -> Color {
        switch p {
        case .low:      return AppColors.accentSuccess
        case .medium:   return AppColors.accentWarning
        case .high:     return Color.orange
        case .critical: return AppColors.accentDanger
        }
    }
}
