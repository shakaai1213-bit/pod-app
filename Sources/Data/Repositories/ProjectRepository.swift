import Foundation

// MARK: - Project Update Request

struct ProjectUpdateRequest: Encodable {
    let name: String?
    let status: String?
    let priority: Int?
    let goal: String?
    let description: String?
    let dueDate: Date?

    enum CodingKeys: String, CodingKey {
        case name, status, priority, goal, description
        case dueDate = "due_date"
    }
}

// MARK: - Project Repository

actor ProjectRepository {
    private let api = APIClient.shared

    func listProjects(status: String? = nil) async throws -> [ProjectDTO] {
        var path = "/api/v1/projects/"
        if let status = status {
            path += "?status=\(status)"
        }
        return try await api.get(path: path)
    }

    func createProject(name: String, goal: String? = nil, priority: Int = 3, stage: String = "blueprint") async throws -> ProjectDTO {
        let body = ProjectCreateRequest(name: name, goal: goal, description: nil, priority: priority, stage: stage, dueDate: nil)
        return try await api.post(path: "/api/v1/projects/", body: body)
    }

    func getProject(_ id: UUID) async throws -> ProjectDTO {
        return try await api.get(path: "/api/v1/projects/\(id)")
    }

    func updateProject(_ id: UUID, status: String? = nil, priority: Int? = nil) async throws -> ProjectDTO {
        let body = ProjectUpdateRequest(name: nil, status: status, priority: priority, goal: nil, description: nil, dueDate: nil)
        return try await api.patch(path: "/api/v1/projects/\(id)", body: body)
    }

    func listTasks(projectId: UUID) async throws -> [ProjectTaskDTO] {
        return try await api.get(path: "/api/v1/projects/\(projectId)/tasks")
    }

    func listNotes(projectId: UUID) async throws -> [ProjectNoteDTO] {
        return try await api.get(path: "/api/v1/projects/\(projectId)/notes?limit=50")
    }

    func createNote(
        projectId: UUID,
        title: String,
        body: String,
        noteType: String,
        tags: [String] = ["pod", "project-note"]
    ) async throws -> ProjectNoteDTO {
        struct Body: Encodable {
            let targetType = "project"
            let targetId: String
            let noteType: String
            let title: String
            let body: String
            let tags: [String]
            let source = "pod.projects.notes"
            let traceId: String

            enum CodingKeys: String, CodingKey {
                case title, body, tags, source
                case targetType = "target_type"
                case targetId = "target_id"
                case noteType = "note_type"
                case traceId = "trace_id"
            }
        }

        return try await api.post(
            path: "/api/v1/projects/\(projectId)/notes",
            body: Body(
                targetId: projectId.uuidString,
                noteType: noteType,
                title: title,
                body: body,
                tags: tags,
                traceId: "pod-project-note-\(Int(Date().timeIntervalSince1970))"
            )
        )
    }

    func createTask(projectId: UUID, title: String, description: String? = nil, priority: Int = 3) async throws -> ProjectTaskDTO {
        struct Body: Encodable {
            let projectId: UUID
            let title: String
            let description: String?
            let priority: Int

            enum CodingKeys: String, CodingKey {
                case projectId = "project_id"
                case title, description, priority
            }
        }
        return try await api.post(
            path: "/api/v1/projects/\(projectId)/tasks",
            body: Body(projectId: projectId, title: title, description: description, priority: priority)
        )
    }

    func updateTask(projectId: UUID, taskId: UUID, status: String? = nil, priority: Int? = nil) async throws -> ProjectTaskDTO {
        let body = ProjectTaskUpdateRequest(
            title: nil,
            description: nil,
            status: status,
            priority: priority,
            dueDate: nil,
            assignedTo: nil,
            parentTaskId: nil
        )
        return try await api.patch(path: "/api/v1/projects/\(projectId)/tasks/\(taskId)", body: body)
    }
}
