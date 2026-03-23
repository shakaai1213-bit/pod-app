import Foundation

// MARK: - Project

struct Project: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let boardGroupId: UUID
    let status: ProjectStatus
    let stage: ProjectStage
    let createdAt: Date
    let updatedAt: Date
    let taskCount: Int
    let completedTaskCount: Int

    var completionPercentage: Double {
        guard taskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(taskCount) * 100
    }
}

extension Project: Codable {}
extension Project: Hashable {}

// MARK: - Project Status

enum ProjectStatus: String, Codable, CaseIterable {
    case active
    case paused
    case completed
}

// MARK: - Project Stage

enum ProjectStage: String, Codable, CaseIterable {
    case plan
    case dev
    case verify
    case test
    case done

    var displayName: String {
        switch self {
        case .plan:    return "Plan"
        case .dev:     return "Development"
        case .verify:  return "Verify"
        case .test:    return "Test"
        case .done:    return "Done"
        }
    }
}

// MARK: - Task

struct Task: Identifiable {
    let id: UUID
    let projectId: UUID
    var title: String
    var description: String
    var status: TaskStatus
    var stage: ProjectStage
    var assigneeId: UUID?
    var dueDate: Date?
    var priority: Priority
    var tags: [String]
}

extension Task: Codable {}
extension Task: Hashable {}

// MARK: - Task Status

enum TaskStatus: String, Codable, CaseIterable {
    case todo
    case inProgress
    case review
    case done

    var displayName: String {
        switch self {
        case .todo:       return "To Do"
        case .inProgress: return "In Progress"
        case .review:     return "Review"
        case .done:       return "Done"
        }
    }
}

// MARK: - Priority

enum Priority: String, Codable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case critical

    var displayName: String {
        rawValue.capitalized
    }

    var sortOrder: Int {
        switch self {
        case .low:      return 0
        case .medium:   return 1
        case .high:     return 2
        case .critical: return 3
        }
    }

    static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
