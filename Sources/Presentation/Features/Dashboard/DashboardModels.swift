import SwiftUI

// MARK: - Activity Item

struct ActivityItem: Identifiable {
    let id: UUID
    let type: ActivityType
    let description: String
    let timestamp: Date
    let actor: String
    var isAgent: Bool

    init(
        id: UUID = UUID(),
        type: ActivityType,
        description: String,
        timestamp: Date,
        actor: String,
        isAgent: Bool = false
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.timestamp = timestamp
        self.actor = actor
        self.isAgent = isAgent
    }
}

// MARK: - Activity Type

enum ActivityType: String, CaseIterable {
    case taskCompleted = "task_completed"
    case taskCreated = "task_created"
    case messageReceived = "message_received"
    case messageSent = "message_sent"
    case agentStatusChange = "agent_status_change"
    case agentMilestone = "agent_milestone"
    case approvalRequested = "approval_requested"
    case systemAlert = "system_alert"
    case fileUploaded = "file_uploaded"

    var icon: String {
        switch self {
        case .taskCompleted:  return "checkmark.circle.fill"
        case .taskCreated:    return "plus.circle.fill"
        case .messageReceived: return "bubble.left.fill"
        case .messageSent:    return "bubble.right.fill"
        case .agentStatusChange: return "wifi"
        case .agentMilestone: return "star.fill"
        case .approvalRequested: return "checkmark.seal.fill"
        case .systemAlert:    return "exclamationmark.triangle.fill"
        case .fileUploaded:  return "paperclip"
        }
    }

    var iconColor: Color {
        switch self {
        case .taskCompleted:  return AppColors.accentSuccess
        case .taskCreated:    return AppColors.accentWarning
        case .messageReceived: return AppColors.accentElectric
        case .messageSent:    return AppColors.textSecondary
        case .agentStatusChange: return AppColors.accentAgent
        case .agentMilestone: return AppColors.accentAgent
        case .approvalRequested: return AppColors.accentWarning
        case .systemAlert:    return AppColors.accentDanger
        case .fileUploaded:   return AppColors.textSecondary
        }
    }
}

// MARK: - Attention Item

struct AttentionItem: Identifiable {
    let id: UUID
    let type: AttentionType
    let title: String
    let severity: AttentionSeverity
    let actor: String

    init(
        id: UUID = UUID(),
        type: AttentionType,
        title: String,
        severity: AttentionSeverity = .warning,
        actor: String = ""
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.severity = severity
        self.actor = actor
    }
}

// MARK: - Attention Type

enum AttentionType: String, CaseIterable {
    case blockedTask     = "blocked_task"
    case pendingApproval = "pending_approval"
    case agentError      = "agent_error"

    var icon: String {
        switch self {
        case .blockedTask:     return "exclamationmark.triangle.fill"
        case .pendingApproval: return "clock.fill"
        case .agentError:      return "bolt.trianglebadge.exclamationmark.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .blockedTask:     return AppColors.accentWarning
        case .pendingApproval: return AppColors.accentWarning
        case .agentError:      return AppColors.accentDanger
        }
    }
}

// MARK: - Attention Severity

enum AttentionSeverity {
    case warning
    case critical
}
