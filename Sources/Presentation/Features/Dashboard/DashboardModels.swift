import SwiftUI

// MARK: - Activity Item

struct ActivityItem: Identifiable {
    let id: UUID
    let type: ActivityType
    let description: String
    let timestamp: Date
    let actorName: String
    let isActorAgent: Bool

    init(
        id: UUID = UUID(),
        type: ActivityType,
        description: String,
        timestamp: Date,
        actorName: String,
        isActorAgent: Bool
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.timestamp = timestamp
        self.actorName = actorName
        self.isActorAgent = isActorAgent
    }
}

// MARK: - Activity Type

enum ActivityType: String, CaseIterable {
    case taskCompleted = "task_completed"
    case messageSent   = "message_sent"
    case agentMilestone = "agent_milestone"
    case taskCreated   = "task_created"
    case fileUploaded  = "file_uploaded"

    var icon: String {
        switch self {
        case .taskCompleted:  return "checkmark.circle.fill"
        case .messageSent:    return "bubble.left.and.bubble.right.fill"
        case .agentMilestone: return "star.fill"
        case .taskCreated:    return "plus.circle.fill"
        case .fileUploaded:   return "paperclip"
        }
    }

    var iconColor: Color {
        switch self {
        case .taskCompleted:  return AppColors.accentSuccess
        case .messageSent:    return AppColors.accentElectric
        case .agentMilestone: return AppColors.accentAgent
        case .taskCreated:    return AppColors.accentWarning
        case .fileUploaded:   return AppColors.textSecondary
        }
    }
}

// MARK: - Attention Item

struct AttentionItem: Identifiable {
    let id: UUID
    let type: AttentionType
    let title: String
    let subtitle: String?
    let severity: AttentionSeverity

    init(
        id: UUID = UUID(),
        type: AttentionType,
        title: String,
        subtitle: String? = nil,
        severity: AttentionSeverity = .warning
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.severity = severity
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
