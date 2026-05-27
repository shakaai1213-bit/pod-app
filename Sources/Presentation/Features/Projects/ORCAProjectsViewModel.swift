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
    var boardOptions: [ProjectBoardOption] = []
    var isLoadingBoardOptions = false
    var boardOptionsMessage: String?

    private let repo = ProjectRepository()

    // MARK: - Kanban Columns

    enum KanbanStatus: String, CaseIterable {
        case active
        case backlog
        case inProgress = "in-progress"
        case done
        case archived

        var displayName: String {
            switch self {
            case .active:      return "Active"
            case .backlog:    return "Backlog"
            case .inProgress: return "In Progress"
            case .done:       return "Done"
            case .archived:    return "Archived"
            }
        }

        var color: Color {
            switch self {
            case .active:      return AppColors.accentElectric
            case .backlog:    return AppColors.textTertiary
            case .inProgress: return AppColors.accentElectric
            case .done:       return AppColors.accentSuccess
            case .archived:    return AppColors.textTertiary
            }
        }
    }

    // MARK: - Computed

    func projectsByStatus(_ status: String) -> [ProjectDTO] {
        projects.filter { statusBucket($0.status) == status }
    }

    var activeProjects: [ProjectDTO] { projectsByStatus(KanbanStatus.active.rawValue) }
    var backlogProjects: [ProjectDTO] { projectsByStatus(KanbanStatus.backlog.rawValue) }
    var inProgressProjects: [ProjectDTO] { projectsByStatus(KanbanStatus.inProgress.rawValue) }
    var doneProjects: [ProjectDTO] { projectsByStatus(KanbanStatus.done.rawValue) }

    func statusBucket(_ status: String) -> String {
        switch status.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "in-progress":
            return KanbanStatus.inProgress.rawValue
        case "done", "completed", "closed":
            return KanbanStatus.done.rawValue
        case "archived":
            return KanbanStatus.archived.rawValue
        case "backlog":
            return KanbanStatus.backlog.rawValue
        default:
            return KanbanStatus.active.rawValue
        }
    }

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

    func loadBoardOptions() async {
        if isLoadingBoardOptions { return }
        isLoadingBoardOptions = true
        boardOptionsMessage = nil
        defer { isLoadingBoardOptions = false }

        do {
            let response: ProjectBoardListResponse = try await APIClient.shared.get(path: "/api/v1/boards")
            boardOptions = response.items
                .map(\.option)
                .sorted { lhs, rhs in
                    let lhsIndex = ProjectBoardOption.preferredSlugs.firstIndex(of: lhs.slug) ?? Int.max
                    let rhsIndex = ProjectBoardOption.preferredSlugs.firstIndex(of: rhs.slug) ?? Int.max
                    if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                    return lhs.displayName < rhs.displayName
                }
            if boardOptions.isEmpty {
                boardOptionsMessage = "ORCA returned no boards."
            }
        } catch {
            boardOptions = []
            boardOptionsMessage = "ORCA boards unavailable."
        }
    }

    func loadTasks(projectId: UUID) async {
        do {
            tasks = try await repo.listTasks(projectId: projectId)
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }

    func loadNotes(projectId: UUID) async -> [ProjectNoteDTO] {
        do {
            return try await repo.listNotes(projectId: projectId)
        } catch {
            print("Failed to load project notes: \(error)")
            return []
        }
    }

    func createNote(projectId: UUID, title: String, body: String, noteType: String) async -> ProjectNoteDTO? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanBody.isEmpty else { return nil }

        do {
            return try await repo.createNote(
                projectId: projectId,
                title: cleanTitle,
                body: cleanBody,
                noteType: noteType
            )
        } catch {
            print("Failed to create project note: \(error)")
            return nil
        }
    }

    // MARK: - Mutations

    func createProject(name: String, goal: String? = nil, priority: Int = 3, stage: String = "blueprint", boardId: String? = nil) async {
        do {
            let new = try await repo.createProject(name: name, goal: goal, priority: priority, stage: stage, boardId: boardId)
            projects.insert(new, at: 0)
        } catch {
            print("Failed to create project: \(error)")
        }
    }

    func moveProject(_ projectId: UUID, toStatus: String) async {
        // Optimistic update
        if let idx = projects.firstIndex(where: { $0.id == projectId }) {
            let old = projects[idx]
            var updated = ProjectDTO(
                id: old.id, boardId: old.boardId, boardIds: old.boardIds,
                name: old.name, goal: old.goal,
                description: old.description, status: toStatus,
                priority: old.priority, projectedCost: old.projectedCost,
                actualCost: old.actualCost, createdBy: old.createdBy,
                assignedTo: old.assignedTo, createdAt: old.createdAt,
                updatedAt: Date(), startedAt: toStatus == KanbanStatus.inProgress.rawValue ? Date() : old.startedAt,
                completedAt: toStatus == KanbanStatus.done.rawValue ? Date() : nil,
                dueDate: old.dueDate, stage: old.stage
            )
            updated.automationEnabled = old.automationEnabled
            updated.proposedMilestones = old.proposedMilestones
            updated.milestones = old.milestones
            updated.lastGenerationRunId = old.lastGenerationRunId
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

    func generateMilestones(projectId: UUID, note: String? = nil) async throws -> ProjectDTO {
        let updated = try await repo.generateMilestones(projectId: projectId, note: note)
        replaceProject(updated)
        return updated
    }

    func acceptMilestone(projectId: UUID, milestoneId: String, edits: ProjectMilestoneEdits? = nil) async throws -> ProjectDTO {
        let updated = try await repo.acceptMilestone(projectId: projectId, milestoneId: milestoneId, edits: edits)
        replaceProject(updated)
        return updated
    }

    func dropMilestone(projectId: UUID, milestoneId: String, reason: String = "Dropped from Pod Projects review.") async throws -> ProjectDTO {
        let updated = try await repo.dropMilestone(projectId: projectId, milestoneId: milestoneId, reason: reason)
        replaceProject(updated)
        return updated
    }

    func addMilestone(projectId: UUID, title: String, description: String?) async throws -> ProjectDTO {
        let updated = try await repo.addMilestone(projectId: projectId, title: title, description: description)
        replaceProject(updated)
        return updated
    }

    func advanceToScoping(projectId: UUID) async throws -> ProjectDTO {
        let updated = try await repo.advanceToScoping(projectId: projectId)
        replaceProject(updated)
        return updated
    }

    private func replaceProject(_ updated: ProjectDTO) {
        if let idx = projects.firstIndex(where: { $0.id == updated.id }) {
            projects[idx] = updated
        } else {
            projects.insert(updated, at: 0)
        }
    }

    func moveTask(taskId: UUID, toStatus: String) async {
        guard let task = tasks.first(where: { $0.id == taskId }) else {
            errorMessage = "Project task not loaded."
            return
        }

        let oldTasks = tasks
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            let old = tasks[idx]
            tasks[idx] = ProjectTaskDTO(
                id: old.id,
                projectId: old.projectId,
                title: old.title,
                description: old.description,
                status: toStatus,
                priority: old.priority,
                parentTaskId: old.parentTaskId,
                createdBy: old.createdBy,
                assignedTo: old.assignedTo,
                createdAt: old.createdAt,
                updatedAt: Date(),
                dueDate: old.dueDate
            )
        }

        do {
            let updated = try await repo.updateTask(projectId: task.projectId, taskId: taskId, status: toStatus)
            if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[idx] = updated
            }
            errorMessage = nil
        } catch {
            tasks = oldTasks
            errorMessage = "Failed to move project task: \(error.localizedDescription)"
        }
    }
}

struct ProjectBoardOption: Identifiable, Sendable, Hashable {
    let id: String
    let slug: String
    let name: String
    let layer: String?
    let component: String?

    var displayName: String { component?.isEmpty == false ? component! : name }
    var detail: String {
        [slug, layer]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    static let preferredSlugs = [
        "north-star", "pod", "surfaces", "orca", "memory", "compute", "nerve",
        "governance", "jarvis", "schoolhouse", "fund", "products", "tools"
    ]
}

private struct ProjectBoardListResponse: Decodable {
    let items: [ProjectBoardDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [ProjectBoardDTO] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(ProjectBoardDTO.self))
            }
            items = values
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([ProjectBoardDTO].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey { case items }
}

private struct ProjectBoardDTO: Decodable {
    let id: String
    let slug: String
    let name: String
    let layer: String?
    let component: String?

    var option: ProjectBoardOption {
        ProjectBoardOption(id: id, slug: slug, name: name, layer: layer, component: component)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeProjectFlexibleString(forKey: .id)
        slug = try container.decodeProjectFlexibleStringIfPresent(forKey: .slug) ?? id
        name = try container.decodeProjectFlexibleStringIfPresent(forKey: .name) ?? slug
        layer = try container.decodeProjectFlexibleStringIfPresent(forKey: .layer)
        component = try container.decodeProjectFlexibleStringIfPresent(forKey: .component)
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, layer, component
    }
}

private extension KeyedDecodingContainer {
    func decodeProjectFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return "\(value)"
        }
        if let value = try? decode(UUID.self, forKey: key) {
            return value.uuidString
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected string-compatible value")
        )
    }

    func decodeProjectFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if !contains(key) || (try? decodeNil(forKey: key)) == true {
            return nil
        }
        return try decodeProjectFlexibleString(forKey: key)
    }
}
