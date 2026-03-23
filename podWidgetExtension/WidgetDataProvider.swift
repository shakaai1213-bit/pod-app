import Foundation
import WidgetKit

// MARK: - Data Models

struct AgentWidgetData: Codable, Identifiable {
    var id: String { name }
    let name: String
    let status: String
    let color: String

    var statusColor: AgentStatus {
        switch status.lowercased() {
        case "online", "active", "working":
            return .online
        case "idle", "standby":
            return .idle
        case "offline", "disconnected":
            return .offline
        case "busy", "thinking", "processing":
            return .busy
        default:
            return .offline
        }
    }
}

struct TaskWidgetData: Codable {
    let total: Int
    let completed: Int

    var remaining: Int { total - completed }

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

struct ActivityWidgetItem: Codable, Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(description)" }
    let icon: String
    let description: String
    let timestamp: Date
    let agentName: String

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

struct TeamActivityData: Codable {
    let agents: [AgentWidgetData]
    let activities: [ActivityWidgetItem]
}

// MARK: - App Group

private enum AppGroup {
    static let suiteName = "group.com.orcamc.pod"
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
}

// MARK: - Widget Data Provider

enum WidgetDataProvider {
    private static let agentDataKey = "cachedAgentData"
    private static let taskDataKey = "cachedTaskData"
    private static let activityDataKey = "cachedActivityData"

    // MARK: - Agent Data

    static func fetchAgentData() async -> [AgentWidgetData] {
        guard let defaults = AppGroup.sharedDefaults,
              let data = defaults.data(forKey: agentDataKey),
              let agents = try? JSONDecoder().decode([AgentWidgetData].self, from: data) else {
            return Self.fallbackAgents()
        }
        return agents
    }

    // MARK: - Task Data

    static func fetchTaskData() async -> TaskWidgetData {
        guard let defaults = AppGroup.sharedDefaults,
              let data = defaults.data(forKey: taskDataKey),
              let tasks = try? JSONDecoder().decode(TaskWidgetData.self, from: data) else {
            return Self.fallbackTasks()
        }
        return tasks
    }

    // MARK: - Team Activity Data

    static func fetchTeamActivityData() async -> TeamActivityData {
        guard let defaults = AppGroup.sharedDefaults,
              let data = defaults.data(forKey: activityDataKey),
              let activity = try? JSONDecoder().decode(TeamActivityData.self, from: data) else {
            return Self.fallbackTeamActivity()
        }
        return activity
    }

    // MARK: - Fallbacks

    private static func fallbackAgents() -> [AgentWidgetData] {
        [
            AgentWidgetData(name: "Maui", status: "online", color: "#34C759"),
            AgentWidgetData(name: "Kai", status: "online", color: "#34C759"),
            AgentWidgetData(name: "Luna", status: "idle", color: "#FF9500"),
            AgentWidgetData(name: "Atlas", status: "offline", color: "#8E8E93"),
        ]
    }

    private static func fallbackTasks() -> TaskWidgetData {
        TaskWidgetData(total: 12, completed: 7)
    }

    private static func fallbackTeamActivity() -> TeamActivityData {
        let now = Date()
        return TeamActivityData(
            agents: fallbackAgents(),
            activities: [
                ActivityWidgetItem(
                    icon: "checkmark.circle.fill",
                    description: "Completed build pipeline",
                    timestamp: now.addingTimeInterval(-180),
                    agentName: "Maui"
                ),
                ActivityWidgetItem(
                    icon: "arrow.triangle.2.circlepath",
                    description: "Synced project files",
                    timestamp: now.addingTimeInterval(-600),
                    agentName: "Kai"
                ),
                ActivityWidgetItem(
                    icon: "doc.text.fill",
                    description: "Updated documentation",
                    timestamp: now.addingTimeInterval(-1800),
                    agentName: "Luna"
                ),
            ]
        )
    }

    // MARK: - Deep Link URLs

    static func deepLinkURL(to tab: DeepLinkTab) -> URL {
        URL(string: "pod://\(tab.rawValue)")!
    }

    enum DeepLinkTab: String {
        case agents
        case projects
        case dashboard
    }
}

// MARK: - Agent Status Color

enum AgentStatus {
    case online
    case idle
    case busy
    case offline
}
