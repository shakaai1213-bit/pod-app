import Foundation
import SwiftUI

// MARK: - Projects ViewModel

@Observable
final class ProjectsViewModel {

    // MARK: - Published State

    var boardGroups: [BoardGroup] = []
    var myTasks: [ProjectTask] = []
    var teamMembers: [TeamMember] = []
    var selectedBoard: Board?
    var isLoading: Bool = false
    var errorMessage: String?

    var filterAssignee: UUID?
    var filterTag: String?
    var searchText: String = ""

    // MARK: - Private

    private let apiClient = APIClient.shared

    // MARK: - Computed

    var filteredBoards: [Board] {
        guard !searchText.isEmpty else { return allBoards }
        return allBoards.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var allBoards: [Board] {
        boardGroups.flatMap { $0.boards }
    }

    // MARK: - My Tasks Sorting

    var sortedMyTasks: [ProjectTask] {
        let now = Date()
        let calendar = Calendar.current

        return myTasks.sorted { a, b in
            let dateA = a.dueDate ?? .distantFuture
            let dateB = b.dueDate ?? .distantFuture

            let isOverdueA = a.dueDate.map { calendar.isDateInToday($0) == false && $0 < now } ?? false
            let isOverdueB = b.dueDate.map { calendar.isDateInToday($0) == false && $0 < now } ?? false

            if isOverdueA != isOverdueB { return isOverdueA }
            if a.dueDate == nil && b.dueDate != nil { return false }
            if a.dueDate != nil && b.dueDate == nil { return true }

            if let dA = a.dueDate, let dB = b.dueDate {
                let isTodayA = calendar.isDateInToday(dA)
                let isTodayB = calendar.isDateInToday(dB)
                if isTodayA != isTodayB { return isTodayA }
            }

            return dateA < dateB
        }
    }

    // MARK: - Loading

    func loadBoards() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        // Try /api/v1/boards first (paginated). Falls back to /api/v1/projects/ (flat array) if it 500s.
        var boards: [Board] = []

        if let response = try? await apiClient.get(path: "/api/v1/boards") as PaginatedResponse<BoardDTO> {
            boards = response.items.map { dto in
                Board(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    description: dto.description ?? "",
                    stageCounts: [:],
                    taskCount: dto.taskCount,
                    completedTaskCount: dto.completedTaskCount,
                    lastActivity: dto.updatedAt
                )
            }
        }

        // Boards endpoint broken (500) — fall back to /api/v1/projects/
        if boards.isEmpty, let projects = try? await ProjectRepository().listProjects() {
            boards = projects.map { dto in
                Board(
                    id: dto.id,
                    name: dto.name,
                    description: dto.description ?? dto.goal ?? "",
                    stageCounts: [:],
                    taskCount: 0,
                    completedTaskCount: 0,
                    lastActivity: dto.updatedAt
                )
            }
        }

        let loadedBoards = boards
        await MainActor.run {
            if !loadedBoards.isEmpty {
                let group = BoardGroup(
                    id: UUID(),
                    name: "All Projects",
                    boards: loadedBoards,
                    taskCount: loadedBoards.reduce(0) { $0 + $1.taskCount },
                    completedTaskCount: loadedBoards.reduce(0) { $0 + $1.completedTaskCount }
                )
                self.boardGroups = [group]
            } else {
                self.boardGroups = []
                self.errorMessage = "ORCA boards/projects unavailable. Legacy Projects no longer falls back to mock boards."
            }
            self.isLoading = false
        }
    }

    func loadTeamMembers() async {
        do {
            let response: PaginatedResponse<AgentDTO> = try await apiClient.get(path: "/api/v1/agents?status=active,support&limit=100")
            let members = response.items.map { dto in
                TeamMember(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    name: dto.name,
                    avatarColor: dto.avatarColor ?? "#3B82F6"
                )
            }
            await MainActor.run {
                self.teamMembers = members
            }
        } catch {
            await MainActor.run {
                self.teamMembers = []
            }
        }
    }

    func boardTasks(boardId: UUID) async -> [ProjectTask] {
        do {
            let response: PaginatedResponse<TaskDTO> = try await apiClient.get(path: "/api/v1/boards/\(boardId)/tasks")
            return response.items.map { dto -> ProjectTask in
                ProjectTask(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    projectId: boardId,
                    title: dto.title,
                    description: dto.description ?? "",
                    status: mapTaskStatus(dto.status),
                    stage: mapTaskStage(dto.stage),
                    assigneeId: (dto.assignedAgentId ?? dto.assigneeId).flatMap { UUID(uuidString: $0) },
                    dueDate: dto.dueAt ?? dto.dueDate,
                    priority: mapPriority(dto.priority),
                    tags: dto.tags ?? []
                )
            }
        } catch {
            return []
        }
    }

    func loadTasks(boardId: UUID) async {
        do {
            let response: PaginatedResponse<TaskDTO> = try await apiClient.get(path: "/api/v1/boards/\(boardId)/tasks")
            let tasks = response.items.map { dto -> ProjectTask in
                ProjectTask(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    projectId: boardId,
                    title: dto.title,
                    description: dto.description ?? "",
                    status: mapTaskStatus(dto.status),
                    stage: mapTaskStage(dto.stage),
                    assigneeId: (dto.assignedAgentId ?? dto.assigneeId).flatMap { UUID(uuidString: $0) },
                    dueDate: dto.dueAt ?? dto.dueDate,
                    priority: mapPriority(dto.priority),
                    tags: dto.tags ?? []
                )
            }
            await MainActor.run {
                self.myTasks = tasks
            }
        } catch {
            // Leave empty on error
        }
    }

    private func mapTaskStatus(_ status: String?) -> ProjectTaskStatus {
        switch status?.lowercased() {
        case "todo", "open", "inbox":  return .todo
        case "in_progress":        return .inProgress
        case "review", "done":    return .review
        case "completed":          return .done
        default:                   return .todo
        }
    }

    private func mapTaskStage(_ stage: String?) -> ProjectStage {
        switch stage?.lowercased() {
        case "plan":    return .plan
        case "dev":     return .dev
        case "verify":  return .verify
        case "test":    return .test
        case "done":    return .done
        default:        return .plan
        }
    }

    private func mapPriority(_ priority: String?) -> Priority {
        switch priority?.lowercased() {
        case "low":      return .low
        case "medium":   return .medium
        case "high":     return .high
        case "critical": return .critical
        default:        return .medium
        }
    }

    func loadMyTasks() async {
        do {
            let tasks: [ProjectTask] = try await apiClient.get(path: "/api/v1/tasks/me")
            await MainActor.run { self.myTasks = tasks }
        } catch {
            await MainActor.run {
                self.myTasks = []
                self.errorMessage = "ORCA task list unavailable. Legacy Projects no longer falls back to mock tasks."
            }
        }
    }

    // MARK: - Mutations

    func createTask(boardId: UUID, title: String, description: String) async {
        do {
            let body = CreateTaskRequest(title: title, description: description)
            let dto: TaskDTO = try await apiClient.post(path: "/api/v1/boards/\(boardId)/tasks", body: body)
            let task = ProjectTask(
                id: UUID(uuidString: dto.id) ?? UUID(),
                projectId: boardId,
                title: dto.title,
                description: dto.description ?? "",
                status: mapTaskStatus(dto.status),
                stage: mapTaskStage(dto.stage),
                assigneeId: (dto.assignedAgentId ?? dto.assigneeId).flatMap { UUID(uuidString: $0) },
                dueDate: dto.dueAt ?? dto.dueDate,
                priority: mapPriority(dto.priority),
                tags: dto.tags ?? []
            )
            await MainActor.run {
                self.myTasks.append(task)
            }
        } catch {
            // Handle error
        }
    }

    func updateTask(_ task: ProjectTask) async {
        do {
            let updated: ProjectTask = try await apiClient.put(
                path: "/api/v1/tasks/\(task.id)",
                body: task
            )
            await MainActor.run {
                if let index = self.myTasks.firstIndex(where: { $0.id == task.id }) {
                    self.myTasks[index] = updated
                }
            }
        } catch {
            // Handle error
        }
    }

    func moveTask(_ taskId: UUID, toStage: ProjectStage) async {
        do {
            let body = MoveTaskRequest(stage: toStage.rawValue)
            let _: ProjectTask = try await apiClient.patch(
                path: "/api/v1/tasks/\(taskId)/move",
                body: body
            )
        } catch {
            // Handle error
        }
    }

    func deleteTask(_ taskId: UUID) async {
        do {
            try await apiClient.delete(path: "/api/v1/tasks/\(taskId)")
            await MainActor.run {
                self.myTasks.removeAll { $0.id == taskId }
            }
        } catch {
            // Handle error
        }
    }

    func archiveTask(_ taskId: UUID) async {
        do {
            try await apiClient.postVoid(path: "/api/v1/tasks/\(taskId)/archive", body: EmptyBody())
        } catch {
            // Handle error
        }
    }

}

// MARK: - Board Group

struct BoardGroup: Identifiable, Codable {
    let id: UUID
    let name: String
    var boards: [Board]
    var taskCount: Int
    var completedTaskCount: Int

    init(id: UUID, name: String, boards: [Board], taskCount: Int, completedTaskCount: Int) {
        self.id = id
        self.name = name
        self.boards = boards
        self.taskCount = taskCount
        self.completedTaskCount = completedTaskCount
    }

    var completionPercentage: Double {
        guard taskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(taskCount) * 100
    }
}

// MARK: - Board

struct Board: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var stageCounts: [ProjectStage: Int]
    var taskCount: Int
    var completedTaskCount: Int
    var lastActivity: Date

    init(id: UUID, name: String, description: String, stageCounts: [ProjectStage: Int], taskCount: Int, completedTaskCount: Int, lastActivity: Date) {
        self.id = id
        self.name = name
        self.description = description
        self.stageCounts = stageCounts
        self.taskCount = taskCount
        self.completedTaskCount = completedTaskCount
        self.lastActivity = lastActivity
    }

    var completionPercentage: Double {
        guard taskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(taskCount) * 100
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, taskCount, completedTaskCount, lastActivity
        case stageCounts = "stage_counts"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        taskCount = try container.decodeIfPresent(Int.self, forKey: .taskCount) ?? 0
        completedTaskCount = try container.decodeIfPresent(Int.self, forKey: .completedTaskCount) ?? 0
        lastActivity = try container.decodeIfPresent(Date.self, forKey: .lastActivity) ?? Date()
        stageCounts = [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(taskCount, forKey: .taskCount)
        try container.encode(completedTaskCount, forKey: .completedTaskCount)
        try container.encode(lastActivity, forKey: .lastActivity)
    }
}

// MARK: - Request / Response Types

struct CreateTaskRequest: Encodable {
    let title: String
    let description: String
}

struct MoveTaskRequest: Encodable {
    let stage: String
}

struct EmptyBody: Encodable {}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
