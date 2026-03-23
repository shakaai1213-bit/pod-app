import Foundation

enum NotificationAction: Equatable {
    case newMessage(channelId: UUID, preview: String)
    case taskAssigned(taskId: UUID, title: String)
    case approvalRequested(approvalId: UUID, message: String)
    case agentError(agentId: UUID, error: String)
    case unknown

    var title: String {
        switch self {
        case .newMessage:
            return "New Message"
        case .taskAssigned:
            return "Task Assigned"
        case .approvalRequested:
            return "Approval Requested"
        case .agentError:
            return "Agent Error"
        case .unknown:
            return "Notification"
        }
    }

    var iconName: String {
        switch self {
        case .newMessage:
            return "bubble.left.and.bubble.right.fill"
        case .taskAssigned:
            return "checkmark.circle.fill"
        case .approvalRequested:
            return "person.crop.circle.badge.checkmark"
        case .agentError:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "bell.fill"
        }
    }
}

struct PendingNotification: Identifiable {
    let id: UUID
    let action: NotificationAction
    let receivedAt: Date
    var isRead: Bool = false

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: receivedAt, relativeTo: Date())
    }
}
