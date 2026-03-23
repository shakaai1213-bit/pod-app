import SwiftUI

// MARK: - Projects View

struct ProjectsView: View {

    @State private var viewModel = ProjectsViewModel()
    @State private var selectedBoard: Board?
    @State private var showingFilters = false
    @State private var showingNewTask = false
    @State private var contextMenuTask: Any?
    @State private var quickActionBoard: Board?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    myTasksSection
                    boardGroupsSection
                    allBoardsSection
                }
                .padding(.horizontal, Theme.md)
                .padding(.bottom, Theme.xxl)
            }
            .background(AppColors.backgroundPrimary)
            .refreshable {
                await viewModel.loadBoards()
                await viewModel.loadMyTasks()
            }
            .searchable(
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ),
                prompt: "Search boards and tasks"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingFilters = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedBoard) { board in
                BoardDetailView(board: board, viewModel: viewModel)
            }
            .sheet(isPresented: $showingNewTask) {
                NewTaskSheet(viewModel: viewModel)
            }
            .task {
                await viewModel.loadBoards()
                await viewModel.loadMyTasks()
            }
        }
    }

    // MARK: - My Tasks Section

    private var myTasksSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                sectionLabel("My Tasks")
                if !viewModel.sortedMyTasks.isEmpty {
                    Text("\(viewModel.sortedMyTasks.count)")
                        .badgeStyle()
                }
                Spacer(minLength: 0)
            }

            if viewModel.isLoading && viewModel.myTasks.isEmpty {
                myTasksSkeleton
            } else if viewModel.sortedMyTasks.isEmpty {
                myTasksEmpty
            } else {
                VStack(spacing: Theme.xs) {
                    ForEach(viewModel.sortedMyTasks.prefix(5)) { task in
                        MyTaskRow(task: task, members: ProjectsViewModel.mockMembers) {
                            contextMenuTask = task
                        }
                    }

                    if viewModel.sortedMyTasks.count > 5 {
                        Button {
                            // TODO: Navigate to full my tasks view
                        } label: {
                            Text("View all \(viewModel.sortedMyTasks.count) tasks")
                                .podTextStyle(.caption, color: AppColors.accentElectric)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.xs)
                        }
                    }
                }
                .podCard()
            }
        }
        .padding(.top, Theme.sm)
    }

    // MARK: - Board Groups Section

    private var boardGroupsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionLabel("Board Groups")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.sm) {
                    ForEach(viewModel.boardGroups) { group in
                        BoardGroupCard(group: group)
                            .onTapGesture {
                                // Could expand/collapse or navigate to group detail
                            }
                    }
                }
            }

            if viewModel.isLoading && viewModel.boardGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.sm) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                .fill(AppColors.backgroundTertiary)
                                .frame(width: 200, height: 90)
                                .shimmer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - All Boards Section

    private var allBoardsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                sectionLabel("All Boards")
                Spacer(minLength: 0)
            }

            if viewModel.isLoading && viewModel.allBoards.isEmpty {
                VStack(spacing: Theme.xs) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .fill(AppColors.backgroundTertiary)
                            .frame(height: 72)
                            .shimmer()
                    }
                }
                .podCard()
            } else if viewModel.filteredBoards.isEmpty {
                emptyBoardsView
            } else {
                ForEach(viewModel.boardGroups) { group in
                    let boards = filteredBoardsForGroup(group)
                    if !boards.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            Text(group.name.uppercased())
                                .podTextStyle(.label, color: AppColors.textTertiary)
                                .padding(.horizontal, Theme.xxs)

                            VStack(spacing: Theme.xs) {
                                ForEach(boards) { board in
                                    BoardRow(board: board)
                                        .onTapGesture {
                                            selectedBoard = board
                                        }
                                        .contextMenu {
                                            boardContextMenu(for: board)
                                        }
                                }
                            }
                            .podCard()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func filteredBoardsForGroup(_ group: BoardGroup) -> [Board] {
        viewModel.filteredBoards.filter { board in
            group.boards.contains { $0.id == board.id }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .podTextStyle(.label, color: AppColors.textTertiary)
    }

    private var myTasksEmpty: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(AppColors.accentSuccess)

            Text("No tasks assigned to you. Nice!")
                .podTextStyle(.body, color: AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.md)
        .podCard()
    }

    private var myTasksSkeleton: some View {
        VStack(spacing: Theme.xs) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: Theme.sm) {
                    Circle()
                        .fill(AppColors.backgroundTertiary)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.backgroundTertiary)
                            .frame(height: 14)
                            .frame(maxWidth: 200)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.backgroundTertiary)
                            .frame(height: 12)
                            .frame(maxWidth: 100)
                    }
                    Spacer()
                }
                .padding(Theme.sm)
            }
        }
        .podCard()
    }

    private var emptyBoardsView: some View {
        VStack(spacing: Theme.sm) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.textTertiary)

            Text("No boards found")
                .podTextStyle(.headline, color: AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.xxl)
        .podCard()
    }

    @ViewBuilder
    private func boardContextMenu(for board: Board) -> some View {
        Button {
            selectedBoard = board
        } label: {
            Label("Open Board", systemImage: "arrow.up.right.square")
        }

        Button {
            quickActionBoard = board
        } label: {
            Label("Add Task", systemImage: "plus")
        }

        Divider()

        Button(role: .destructive) {
            // Archive board
        } label: {
            Label("Archive Board", systemImage: "archivebox")
        }
    }
}

// MARK: - My ProjectTask Row

private struct MyTaskRow: View {
    let task: ProjectTask
    let members: [TeamMember]
    let onTap: () -> Void

    private var assignee: TeamMember? {
        members.first { $0.id == task.assigneeId }
    }

    private var isOverdue: Bool {
        guard let due = task.dueDate else { return false }
        return due < Date() && !Calendar.current.isDateInToday(due)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.sm) {
                Circle()
                    .fill(priorityColor(for: task.priority))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .podTextStyle(.headline, color: AppColors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: Theme.xs) {
                        if let assignee = assignee {
                            Text(assignee.name)
                                .podTextStyle(.caption, color: AppColors.textSecondary)
                        }

                        if let due = task.dueDate {
                            Text("•")
                                .foregroundStyle(AppColors.textTertiary)
                            dueDateText(due)
                        }
                    }
                }

                Spacer(minLength: 0)

                stagePill(for: task.stage)
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
    }

    private func dueDateText(_ date: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = isOverdue ? "'Overdue' MMM d" : "MMM d"
        return Text(formatter.string(from: date))
            .podTextStyle(.caption, color: isOverdue ? AppColors.accentDanger : AppColors.textSecondary)
    }

    private func stagePill(for stage: ProjectStage) -> some View {
        Text(stage.displayName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppColors.backgroundSecondary)
            .clipShape(Capsule())
    }

    private func priorityColor(for priority: Priority) -> Color {
        switch priority {
        case .low:      return AppColors.accentSuccess
        case .medium:   return AppColors.accentWarning
        case .high:     return Color.orange
        case .critical: return AppColors.accentDanger
        }
    }
}

// MARK: - Board Group Card

private struct BoardGroupCard: View {
    let group: BoardGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(group.name)
                .podTextStyle(.headline, color: AppColors.textPrimary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.backgroundTertiary)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.accentElectric)
                        .frame(width: geo.size.width * group.completionPercentage / 100, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(group.taskCount) tasks")
                    .podTextStyle(.caption, color: AppColors.textSecondary)
                Spacer(minLength: 0)
                Text("\(Int(group.completionPercentage))%")
                    .podTextStyle(.caption, color: AppColors.accentElectric)
            }
        }
        .padding(Theme.md)
        .frame(width: 200)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }
}

// MARK: - Board Row

private struct BoardRow: View {
    let board: Board

    var body: some View {
        HStack(spacing: Theme.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(board.name)
                    .podTextStyle(.headline, color: AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    stageDots
                    Text("•")
                        .foregroundStyle(AppColors.textTertiary)
                    Text("\(board.taskCount) tasks")
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                    Text("•")
                        .foregroundStyle(AppColors.textTertiary)
                    Text(board.lastActivity, style: .relative)
                        .podTextStyle(.caption, color: AppColors.textTertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(Theme.md)
    }

    private var stageDots: some View {
        HStack(spacing: 3) {
            ForEach(ProjectStage.allCases, id: \.self) { stage in
                let count = board.stageCounts[stage] ?? 0
                Circle()
                    .fill(count > 0 ? stageColor(stage) : AppColors.textMuted)
                    .frame(width: 6, height: 6)
            }
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
}

// MARK: - Badge Style Modifier

private extension Text {
    func badgeStyle() -> some View {
        self
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }
}

// MARK: - New ProjectTask Sheet

private struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProjectsViewModel

    @State private var title = ""
    @State private var description = ""
    @State private var selectedBoard: Board?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task title", text: $title)
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(3...6)

                Picker("Board", selection: $selectedBoard) {
                    Text("Select a board").tag(nil as Board?)
                    ForEach(viewModel.allBoards) { board in
                        Text(board.name).tag(board as Board?)
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
                    Button {
                        guard let board = selectedBoard, !title.isEmpty else { return }
                        Task {
                            await viewModel.createTask(boardId: board.id, title: title, description: description)
                            dismiss()
                        }
                    } label: {
                        Text("Create")
                    }
                    .disabled(title.isEmpty || selectedBoard == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
