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

struct ProjectMilestoneEdits: Encodable {
    let title: String?
    let outcome: String?
}

// MARK: - Project Repository

actor ProjectRepository {
    private let api = APIClient.shared

    func listProjects(status: String? = nil) async throws -> [ProjectDTO] {
        var path = "/api/v1/projects/?limit=200"
        if let status = status {
            path += "&status=\(status)"
        }
        let response: ProjectListResponse = try await api.get(path: path)
        return response.items
    }

    func createProject(name: String, goal: String? = nil, priority: Int = 3, stage: String = "blueprint", boardId: String? = nil) async throws -> ProjectDTO {
        let body = ProjectCreateRequest(name: name, goal: goal, description: nil, priority: priority, stage: stage, dueDate: nil, boardId: boardId)
        return try await api.post(path: "/api/v1/projects/", body: body)
    }

    func getProject(_ id: UUID) async throws -> ProjectDTO {
        return try await api.get(path: "/api/v1/projects/\(id)")
    }

    func updateProject(_ id: UUID, status: String? = nil, priority: Int? = nil) async throws -> ProjectDTO {
        let body = ProjectUpdateRequest(name: nil, status: status, priority: priority, goal: nil, description: nil, dueDate: nil)
        return try await api.patch(path: "/api/v1/projects/\(id)", body: body)
    }

    func generateMilestones(projectId: UUID, note: String? = nil) async throws -> ProjectDTO {
        struct Body: Encodable {
            let source = "pod.projects.automation"
            let contextOverrides: ContextOverrides?

            enum CodingKeys: String, CodingKey {
                case source
                case contextOverrides = "context_overrides"
            }
        }

        struct ContextOverrides: Encodable {
            let additionalNote: String

            enum CodingKeys: String, CodingKey {
                case additionalNote = "additional_note"
            }
        }

        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let overrides = cleanNote.flatMap { value in
            value.isEmpty ? nil : ContextOverrides(additionalNote: value)
        }
        let response: ProjectMilestoneActionResponseDTO = try await api.post(
            path: "/api/v1/projects/\(projectId)/generate-milestones",
            body: Body(contextOverrides: overrides)
        )
        return response.project
    }

    func acceptMilestone(projectId: UUID, milestoneId: String, edits: ProjectMilestoneEdits? = nil) async throws -> ProjectDTO {
        struct Body: Encodable {
            let edits: ProjectMilestoneEdits?
            let actor = "pod.projects.automation"
        }
        let response: ProjectMilestoneActionResponseDTO = try await api.post(
            path: "/api/v1/projects/\(projectId)/milestones/\(milestoneId)/accept",
            body: Body(edits: edits)
        )
        return response.project
    }

    func dropMilestone(projectId: UUID, milestoneId: String, reason: String = "Dropped from Pod Projects review.") async throws -> ProjectDTO {
        struct Body: Encodable {
            let reason: String
            let actor = "pod.projects.automation"
        }
        let response: ProjectMilestoneActionResponseDTO = try await api.post(
            path: "/api/v1/projects/\(projectId)/milestones/\(milestoneId)/drop",
            body: Body(reason: reason)
        )
        return response.project
    }

    func addMilestone(projectId: UUID, title: String, description: String?) async throws -> ProjectDTO {
        struct Body: Encodable {
            let title: String
            let outcome: String
            let size = "medium"
            let dependsOn: [String] = []
            let rationale: String?
            let actor = "pod.projects.automation"

            enum CodingKeys: String, CodingKey {
                case title, outcome, size, rationale, actor
                case dependsOn = "depends_on"
            }
        }
        let cleanOutcome = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = cleanOutcome.flatMap { value in value.isEmpty ? nil : value }
        let response: ProjectMilestoneActionResponseDTO = try await api.post(
            path: "/api/v1/projects/\(projectId)/milestones",
            body: Body(
                title: title,
                outcome: outcome ?? title,
                rationale: outcome
            )
        )
        return response.project
    }

    func advanceToScoping(projectId: UUID) async throws -> ProjectDTO {
        struct Body: Encodable {
            let source = "pod.projects.automation"
        }
        return try await api.post(
            path: "/api/v1/projects/\(projectId)/advance-to-scoping",
            body: Body()
        )
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

    func createTask(
        projectId: UUID,
        title: String,
        description: String? = nil,
        priority: Int = 3,
        dueAt: Date? = nil,
        dueAtSource: String? = nil
    ) async throws -> ProjectTaskDTO {
        struct Body: Encodable {
            let projectId: UUID
            let title: String
            let description: String?
            let priority: Int
            let dueAt: Date?
            let dueAtSource: String?

            enum CodingKeys: String, CodingKey {
                case projectId = "project_id"
                case title, description, priority
                case dueAt = "due_at"
                case dueAtSource = "due_at_source"
            }
        }
        return try await api.post(
            path: "/api/v1/projects/\(projectId)/tasks",
            body: Body(
                projectId: projectId,
                title: title,
                description: description,
                priority: priority,
                dueAt: dueAt,
                dueAtSource: dueAtSource
            )
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

private struct ProjectListResponse: Decodable {
    let items: [ProjectDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [ProjectDTO] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(ProjectDTO.self))
            }
            items = values
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([ProjectDTO].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }
}

private struct ProjectMilestoneActionResponseDTO: Decodable {
    let project: ProjectDTO
}
