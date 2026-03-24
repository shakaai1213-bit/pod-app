import Foundation
import SwiftUI

// MARK: - Projects ViewModel

@Observable
final class ProjectsViewModel {

    // MARK: - Published State

    var boardGroups: [BoardGroup] = []
    var myTasks: [ProjectTask] = []
    var selectedBoard: Board?
    var isLoading: Bool = false

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
        await MainActor.run { isLoading = true }

        do {
            let groups: [BoardGroup] = try await apiClient.get(path: "/api/v1/board-groups")
            await MainActor.run {
                self.boardGroups = groups
                self.isLoading = false
            }
        } catch {
            await MainActor.run { self.isLoading = false }
            // Load mock data for development
            await MainActor.run { self.loadMockData() }
        }
    }

    func loadTasks(boardId: UUID) async {
        do {
            let _: [ProjectTask] = try await apiClient.get(path: "/api/v1/boards/\(boardId)/tasks")
        } catch {
            // Use mock tasks
        }
    }

    func loadMyTasks() async {
        do {
            let tasks: [ProjectTask] = try await apiClient.get(path: "/api/v1/tasks/me")
            await MainActor.run { self.myTasks = tasks }
        } catch {
            await MainActor.run { self.myTasks = Self.mockTasks }
        }
    }

    // MARK: - Mutations

    func createTask(boardId: UUID, title: String, description: String) async {
        do {
            let body = CreateTaskRequest(title: title, description: description)
            let task: ProjectTask = try await apiClient.post(path: "/api/v1/boards/\(boardId)/tasks", body: body)
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

    // MARK: - Mock Data

    private func loadMockData() {
        boardGroups = Self.mockBoardGroups
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

// MARK: - Mock Data

extension ProjectsViewModel {

    static let mockMembers: [TeamMember] = [
        TeamMember(id: UUID(), name: "Alex Chen", avatarColor: "3B82F6"),
        TeamMember(id: UUID(), name: "Sam Rivera", avatarColor: "22C55E"),
        TeamMember(id: UUID(), name: "Jordan Lee", avatarColor: "A855F7"),
        TeamMember(id: UUID(), name: "Casey Kim", avatarColor: "F97316"),
    ]

    static let mockBoardGroups: [BoardGroup] = [
        BoardGroup(
            id: UUID(),
            name: "Engineering",
            boards: [
                Board(id: UUID(), name: "Backend API", description: "REST & GraphQL endpoints", stageCounts: [.plan: 3, .dev: 5, .verify: 2, .test: 1, .done: 8], taskCount: 19, completedTaskCount: 8, lastActivity: Date().addingTimeInterval(-3600)),
                Board(id: UUID(), name: "iOS App", description: "Native SwiftUI application", stageCounts: [.plan: 2, .dev: 8, .verify: 3, .test: 2, .done: 12], taskCount: 27, completedTaskCount: 12, lastActivity: Date().addingTimeInterval(-600)),
                Board(id: UUID(), name: "Infrastructure", description: "CI/CD, monitoring, and deployment", stageCounts: [.plan: 1, .dev: 2, .verify: 1, .test: 0, .done: 5], taskCount: 9, completedTaskCount: 5, lastActivity: Date().addingTimeInterval(-86400)),
            ],
            taskCount: 55,
            completedTaskCount: 25
        ),
        BoardGroup(
            id: UUID(),
            name: "Product",
            boards: [
                Board(id: UUID(), name: "Q1 Roadmap", description: "Feature planning and prioritization", stageCounts: [.plan: 5, .dev: 3, .verify: 2, .test: 1, .done: 4], taskCount: 15, completedTaskCount: 4, lastActivity: Date().addingTimeInterval(-7200)),
                Board(id: UUID(), name: "User Research", description: "Interviews and usability studies", stageCounts: [.plan: 2, .dev: 1, .verify: 1, .test: 0, .done: 3], taskCount: 7, completedTaskCount: 3, lastActivity: Date().addingTimeInterval(-172800)),
            ],
            taskCount: 22,
            completedTaskCount: 7
        ),
        BoardGroup(
            id: UUID(),
            name: "Design",
            boards: [
                Board(id: UUID(), name: "Design System", description: "Component library and tokens", stageCounts: [.plan: 4, .dev: 6, .verify: 2, .test: 1, .done: 10], taskCount: 23, completedTaskCount: 10, lastActivity: Date().addingTimeInterval(-1800)),
            ],
            taskCount: 23,
            completedTaskCount: 10
        ),
    ]

    static let mockTasks: [ProjectTask] = [
        ProjectTask(
            id: UUID(),
            projectId: UUID(),
            title: "Implement JWT refresh token flow",
            description: "Add refresh token rotation and proper expiration handling",
            status: .inProgress,
            stage: .dev,
            assigneeId: mockMembers[0].id,
            dueDate: Date().addingTimeInterval(-86400), // yesterday → overdue
            priority: .high,
            tags: ["security", "backend"]
        ),
        ProjectTask(
            id: UUID(),
            projectId: UUID(),
            title: "Fix iOS push notification badge count",
            description: "Badge count not clearing when messages are read",
            status: .todo,
            stage: .plan,
            assigneeId: mockMembers[1].id,
            dueDate: Date(),
            priority: .critical,
            tags: ["ios", "bug"]
        ),
        ProjectTask(
            id: UUID(),
            projectId: UUID(),
            title: "Add rate limiting to message API",
            description: "Implement per-user rate limits for the chat endpoint",
            status: .todo,
            stage: .verify,
            assigneeId: mockMembers[2].id,
            dueDate: Date().addingTimeInterval(86400), // tomorrow
            priority: .medium,
            tags: ["api", "performance"]
        ),
        ProjectTask(
            id: UUID(),
            projectId: UUID(),
            title: "Design onboarding flow screens",
            description: "Create 5 screens for the new user onboarding experience",
            status: .todo,
            stage: .plan,
            assigneeId: mockMembers[3].id,
            dueDate: Date().addingTimeInterval(172800),
            priority: .low,
            tags: ["design", "ux"]
        ),
        ProjectTask(
            id: UUID(),
            projectId: UUID(),
            title: "Write unit tests for auth module",
            description: "Achieve 80% coverage on the authentication module",
            status: .inProgress,
            stage: .test,
            assigneeId: mockMembers[0].id,
            dueDate: Date().addingTimeInterval(259200),
            priority: .high,
            tags: ["testing", "backend"]
        ),
    ]
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
