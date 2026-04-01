import SwiftUI

// MARK: - ORCA Projects View (Kanban)

struct ORCAProjectsView: View {
    @State private var viewModel = ORCAProjectsViewModel()
    @State private var showingNewProject = false
    @State private var selectedProject: ProjectDTO?

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                if viewModel.isLoading && viewModel.projects.isEmpty {
                    loadingView
                } else {
                    kanbanContent
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

    // MARK: - Kanban Content

    private var kanbanContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.md) {
                ForEach(ORCAProjectsViewModel.KanbanStatus.allCases, id: \.self) { status in
                    ORCAKanbanColumn(
                        status: status,
                        projects: viewModel.projectsByStatus(status.rawValue),
                        onProjectTap: { project in selectedProject = project },
                        onStatusChange: { projectId, newStatus in
                            Task {
                                await viewModel.moveProject(projectId, toStatus: newStatus)
                            }
                        }
                    )
                    .frame(width: 300)
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.sm)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        HStack(spacing: Theme.sm) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(AppColors.backgroundTertiary)
                    .frame(width: 280, height: 400)
                    .shimmer()
            }
        }
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
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.textTertiary)
            Text("No projects")
                .podTextStyle(.caption, color: AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.xl)
    }
}

// MARK: - Project Card

private struct ORCAProjectCard: View {
    let project: ProjectDTO

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            // Priority indicator
            HStack(spacing: Theme.xs) {
                priorityDot
                Spacer(minLength: 0)
                priorityLabel
            }

            // Name
            Text(project.name)
                .podTextStyle(.headline, color: AppColors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Goal
            if let goal = project.goal, !goal.isEmpty {
                Text(goal)
                    .podTextStyle(.body, color: AppColors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            // Meta info
            HStack(spacing: Theme.xs) {
                if let dueDate = project.dueDate {
                    dueDateView(dueDate)
                }

                if let projected = project.projectedCost {
                    Text("$\(Int(projected))")
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                }
            }
        }
        .padding(Theme.md)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var priorityDot: some View {
        Circle()
            .fill(priorityColor)
            .frame(width: 8, height: 8)
    }

    private var priorityColor: Color {
        switch project.priority {
        case 1: return AppColors.accentDanger
        case 2: return Color.orange
        case 3: return AppColors.accentWarning
        case 4: return Color.blue
        default: return AppColors.textTertiary
        }
    }

    private var priorityLabel: some View {
        Text("P\(project.priority)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(priorityColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private func dueDateView(_ date: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let isOverdue = date < Date()
        return HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.system(size: 10))
            Text(formatter.string(from: date))
        }
        .podTextStyle(.caption, color: isOverdue ? AppColors.accentDanger : AppColors.textSecondary)
    }
}

// MARK: - New Project Sheet

private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ORCAProjectsViewModel

    @State private var name = ""
    @State private var goal = ""
    @State private var priority = 3
    @State private var selectedStatus: ORCAProjectsViewModel.KanbanStatus = .backlog

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

                Picker("Status", selection: $selectedStatus) {
                    ForEach(ORCAProjectsViewModel.KanbanStatus.allCases, id: \.self) { s in
                        Text(s.displayName).tag(s)
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
                                goal: goal.isEmpty ? nil : goal
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func priorityColor(_ p: Int) -> Color {
        switch p {
        case 1: return AppColors.accentDanger
        case 2: return Color.orange
        case 3: return AppColors.accentWarning
        case 4: return Color.blue
        default: return AppColors.textTertiary
        }
    }
}

// MARK: - Project Detail View

private struct ORCAProjectDetailView: View {
    let project: ProjectDTO
    @Bindable var viewModel: ORCAProjectsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var tasks: [ProjectTaskDTO] = []
    @State private var isLoading = false
    @State private var showingNewTask = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    projectInfo
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
            .task {
                await loadTasks()
            }
        }
    }

    private var projectInfo: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            if let goal = project.goal, !goal.isEmpty {
                Text(goal)
                    .podTextStyle(.body, color: AppColors.textSecondary)
            }

            HStack(spacing: Theme.md) {
                metaPill(icon: "flag.fill", text: "P\(project.priority)", color: priorityColor)
                if let dueDate = project.dueDate {
                    metaPill(icon: "calendar", text: formatDate(dueDate), color: AppColors.textSecondary)
                }
                if let projected = project.projectedCost {
                    metaPill(icon: "dollarsign.circle", text: "$\(Int(projected))", color: AppColors.textSecondary)
                }
            }
        }
        .padding(Theme.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
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
        switch project.priority {
        case 1: return AppColors.accentDanger
        case 2: return Color.orange
        case 3: return AppColors.accentWarning
        default: return AppColors.textTertiary
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func loadTasks() async {
        isLoading = true
        await viewModel.loadTasks(projectId: project.id)
        tasks = viewModel.tasks
        isLoading = false
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
    @State private var selectedStatus: ORCAProjectsViewModel.KanbanStatus = .backlog

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

                Picker("Status", selection: $selectedStatus) {
                    ForEach(ORCAProjectsViewModel.KanbanStatus.allCases, id: \.self) { s in
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
                            do {
                                let task = try await ProjectRepository().createTask(
                                    projectId: projectId,
                                    title: title,
                                    status: selectedStatus.rawValue,
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
