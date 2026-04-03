import Foundation
import SwiftUI

// MARK: - ORCA Projects ViewModel

@MainActor
@Observable
final class ORCAProjectsViewModel {
    var projects: [ProjectDTO] = []
    var isLoading = false
    var selectedProject: ProjectDTO?
    var tasks: [ProjectTaskDTO] = []
    var errorMessage: String?

    private let repo = ProjectRepository()

    // MARK: - Kanban Columns

    enum KanbanStatus: String, CaseIterable {
        case backlog
        case inProgress = "in-progress"
        case done

        var displayName: String {
            switch self {
            case .backlog:    return "Backlog"
            case .inProgress: return "In Progress"
            case .done:       return "Done"
            }
        }

        var color: Color {
            switch self {
            case .backlog:    return AppColors.textTertiary
            case .inProgress: return AppColors.accentElectric
            case .done:       return AppColors.accentSuccess
            }
        }
    }

    // MARK: - Computed

    func projectsByStatus(_ status: String) -> [ProjectDTO] {
        projects.filter { $0.status == status }
    }

    var backlogProjects: [ProjectDTO] { projectsByStatus(KanbanStatus.backlog.rawValue) }
    var inProgressProjects: [ProjectDTO] { projectsByStatus(KanbanStatus.inProgress.rawValue) }
    var doneProjects: [ProjectDTO] { projectsByStatus(KanbanStatus.done.rawValue) }

    // MARK: - Loading

    func loadProjects() async {
        isLoading = true
        errorMessage = nil
        do {
            projects = try await repo.listProjects()
        } catch {
            errorMessage = "Failed to load projects: \(error.localizedDescription)"
            print("Failed to load projects: \(error)")
        }
        isLoading = false
    }

    func loadTasks(projectId: UUID) async {
        do {
            tasks = try await repo.listTasks(projectId: projectId)
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }

    // MARK: - Mutations

    func createProject(name: String, goal: String? = nil, priority: Int = 3) async {
        do {
            let new = try await repo.createProject(name: name, goal: goal, priority: priority)
            projects.insert(new, at: 0)
        } catch {
            print("Failed to create project: \(error)")
        }
    }

    func moveProject(_ projectId: UUID, toStatus: String) async {
        // Optimistic update
        if let idx = projects.firstIndex(where: { $0.id == projectId }) {
            let old = projects[idx]
            let updated = ProjectDTO(
                id: old.id, name: old.name, goal: old.goal,
                description: old.description, status: toStatus,
                priority: old.priority, projectedCost: old.projectedCost,
                actualCost: old.actualCost, createdBy: old.createdBy,
                assignedTo: old.assignedTo, createdAt: old.createdAt,
                updatedAt: Date(), startedAt: toStatus == KanbanStatus.inProgress.rawValue ? Date() : old.startedAt,
                completedAt: toStatus == KanbanStatus.done.rawValue ? Date() : nil,
                dueDate: old.dueDate, stage: old.stage
            )
            projects[idx] = updated
        }

        // Persist
        do {
            _ = try await repo.updateProject(projectId, status: toStatus)
        } catch {
            print("Failed to move project: \(error)")
            // Reload to restore correct state
            await loadProjects()
        }
    }

    func moveTask(taskId: UUID, toStatus: String) async {
        // Optimistic update
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            let task = tasks[idx]
            tasks[idx] = ProjectTaskDTO(
                id: task.id, projectId: task.projectId, title: task.title,
                description: task.description, status: toStatus, priority: task.priority,
                parentTaskId: task.parentTaskId, createdBy: task.createdBy,
                assignedTo: task.assignedTo, createdAt: task.createdAt,
                updatedAt: Date(), dueDate: task.dueDate
            )
        }

        // Persist via project update endpoint (ORCA MC uses project-level status update)
        if let task = tasks.first(where: { $0.id == taskId }) {
            do {
                _ = try await repo.updateProject(task.projectId, status: toStatus)
            } catch {
                print("Failed to move task: \(error)")
            }
        }
    }
}
