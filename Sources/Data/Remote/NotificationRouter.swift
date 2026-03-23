import Foundation
import SwiftUI

@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    var navigationPath: [ScreenDestination] = []
    var selectedTab: AppTab = .chat
    var showApprovalSheet: Bool = false
    var pendingApprovalId: UUID?

    private init() {}

    func route(_ action: NotificationAction) {
        switch action {
        case .newMessage(let channelId, _):
            selectedTab = .chat
            navigateTo(.chat(channelId: channelId))

        case .taskAssigned(let taskId, _):
            selectedTab = .projects
            navigateTo(.projects(taskId: taskId))

        case .approvalRequested(let approvalId, _):
            selectedTab = .dashboard
            pendingApprovalId = approvalId
            showApprovalSheet = true
            navigateTo(.approvals(approvalId: approvalId))

        case .agentError(let agentId, _):
            selectedTab = .agents
            navigateTo(.agents(agentId: agentId))

        case .unknown:
            break
        }
    }

    func navigateTo(_ destination: ScreenDestination) {
        navigationPath.removeAll()
        navigationPath.append(destination)
    }

    func pushTo(_ destination: ScreenDestination) {
        navigationPath.append(destination)
    }

    func popToRoot() {
        navigationPath.removeAll()
    }

    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        let service = PushNotificationService.shared
        guard let action = service.handleNotification(userInfo: userInfo) else { return }
        route(action)
    }

    func reset() {
        navigationPath.removeAll()
        showApprovalSheet = false
        pendingApprovalId = nil
    }
}

enum ScreenDestination: Hashable {
    case chat(channelId: UUID)
    case projects(taskId: UUID)
    case approvals(approvalId: UUID)
    case agents(agentId: UUID)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .chat(let channelId):
            hasher.combine("chat")
            hasher.combine(channelId)
        case .projects(let taskId):
            hasher.combine("projects")
            hasher.combine(taskId)
        case .approvals(let approvalId):
            hasher.combine("approvals")
            hasher.combine(approvalId)
        case .agents(let agentId):
            hasher.combine("agents")
            hasher.combine(agentId)
        }
    }

    static func == (lhs: ScreenDestination, rhs: ScreenDestination) -> Bool {
        switch (lhs, rhs) {
        case (.chat(let a), .chat(let b)):
            return a == b
        case (.projects(let a), .projects(let b)):
            return a == b
        case (.approvals(let a), .approvals(let b)):
            return a == b
        case (.agents(let a), .agents(let b)):
            return a == b
        default:
            return false
        }
    }
}

enum AppTab: Int, CaseIterable {
    case chat = 0
    case projects = 1
    case dashboard = 2
    case agents = 3

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .projects: return "Projects"
        case .dashboard: return "Dashboard"
        case .agents: return "Agents"
        }
    }

    var iconName: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .projects: return "list.bullet.clipboard"
        case .dashboard: return "chart.bar"
        case .agents: return "cpu"
        }
    }
}
