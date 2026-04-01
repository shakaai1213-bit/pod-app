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

    func createProject(name: String, goal: String? = nil, priority: Int = 3) async throws -> ProjectDTO {
        let body = ProjectCreateRequest(name: name, goal: goal, description: nil, priority: priority, dueDate: nil)
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

    func createTask(projectId: UUID, title: String, status: String = "backlog", priority: Int = 3) async throws -> ProjectTaskDTO {
        struct Body: Encodable {
            let title: String
            let status: String
            let priority: Int
        }
        return try await api.post(
            path: "/api/v1/projects/\(projectId)/tasks",
            body: Body(title: title, status: status, priority: priority)
        )
    }
}
