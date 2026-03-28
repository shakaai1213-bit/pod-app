import Foundation

final class BoardRepository: Sendable {
    private let api = APIClient.shared

    var boards: [Board] = []
    private var tasksCache: [UUID: [ProjectTask]] = [:]
    var isLoading: Bool = false
    var lastError: Error?

    init() {}

    // MARK: - Load Boards

    func loadBoards() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let response: PaginatedResponse<BoardDTO> = try await api.get(path: Endpoint.boards.path)
            boards = response.items.map { dto -> Board in
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
        } catch {
            lastError = error
            boards = []
        }
    }

    // MARK: - Load Tasks for Board

    func loadTasks(boardId: UUID) async -> [ProjectTask] {
        if let cached = tasksCache[boardId], !cached.isEmpty {
            return cached
        }

        do {
            let response: PaginatedResponse<TaskDTO> = try await api.get(
                path: Endpoint.boardTasks(boardId: boardId.uuidString).path
            )
            let tasks = response.items.map { dto -> ProjectTask in
                ProjectTask(
                    id: UUID(uuidString: dto.id) ?? UUID(),
                    projectId: boardId,
                    title: dto.title,
                    description: dto.description ?? "",
                    status: mapTaskStatus(dto.status),
                    stage: mapTaskStage(dto.stage),
                    assigneeId: dto.assigneeId.flatMap { UUID(uuidString: $0) },
                    dueDate: dto.dueDate,
                    priority: mapPriority(dto.priority),
                    tags: dto.tags ?? []
                )
            }
            tasksCache[boardId] = tasks
            return tasks
        } catch {
            return []
        }
    }

    // MARK: - Mapping Helpers

    private func mapTaskStatus(_ status: String?) -> ProjectTaskStatus {
        switch status?.lowercased() {
        case "todo", "open":       return .todo
        case "in_progress":        return .inProgress
        case "review", "done":     return .review
        case "completed", "done":  return .done
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
}