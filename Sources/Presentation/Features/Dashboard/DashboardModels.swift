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

// MARK: - State Registry

struct StateRegistryResponse: Decodable {
    let summary: StateRegistrySummary
    let items: [StateTagDTO]
}

struct StateRegistryReviewExportResult: Decodable {
    let message: String
    let path: String?
    let total: Int?
    let stale: Int?
    let degradedOrError: Int?

    enum CodingKeys: String, CodingKey {
        case message
        case path
        case markdownPath = "markdown_path"
        case total
        case stale
        case degradedOrError = "degraded_or_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? "State Registry review export completed."
        let directPath = try container.decodeIfPresent(String.self, forKey: .path)
        let markdownPath = try container.decodeIfPresent(String.self, forKey: .markdownPath)
        path = directPath ?? markdownPath
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        stale = try container.decodeIfPresent(Int.self, forKey: .stale)
        degradedOrError = try container.decodeIfPresent(Int.self, forKey: .degradedOrError)
    }
}

struct DashboardEmptyRequestBody: Encodable {}

struct StateRegistrySummary: Decodable {
    let total: Int
    let stale: Int
    let byQuality: [String: Int]
    let byOwner: [String: Int]

    enum CodingKeys: String, CodingKey {
        case total
        case stale
        case byQuality = "by_quality"
        case byOwner = "by_owner"
    }
}

struct StateTagDTO: Decodable, Identifiable {
    let id: String
    let tagId: String
    let valueText: String
    let quality: String?
    let source: String?
    let owner: String?
    let updatedAt: Date?
    let ttlSeconds: Int?
    let evidenceRef: String?
    let stale: Bool

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
        case value
        case quality
        case source
        case owner
        case updatedAt = "updated_at"
        case ttlSeconds = "ttl_seconds"
        case evidenceRef = "evidence_ref"
        case stale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tagId = try container.decode(String.self, forKey: .tagId)
        self.id = tagId
        self.valueText = Self.decodeValueText(from: container)
        self.quality = try container.decodeIfPresent(String.self, forKey: .quality)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
        self.owner = try container.decodeIfPresent(String.self, forKey: .owner)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.ttlSeconds = try container.decodeIfPresent(Int.self, forKey: .ttlSeconds)
        self.evidenceRef = try container.decodeIfPresent(String.self, forKey: .evidenceRef)
        self.stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
    }

    private static func decodeValueText(from container: KeyedDecodingContainer<CodingKeys>) -> String {
        if let value = try? container.decode(String.self, forKey: .value) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: .value) {
            return "\(value)"
        }
        if let value = try? container.decode(Double.self, forKey: .value) {
            return "\(value)"
        }
        if let value = try? container.decode(Bool.self, forKey: .value) {
            return value ? "true" : "false"
        }
        if let value = try? container.decode(StateTagJSONValue.self, forKey: .value) {
            return value.summary
        }
        return "Structured value"
    }
}

private indirect enum StateTagJSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([StateTagJSONValue])
    case object([String: StateTagJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([StateTagJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: StateTagJSONValue].self))
        }
    }

    var summary: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "None"
        case .array(let values):
            if values.isEmpty {
                return "No entries"
            }
            return "\(values.count) entries"
        case .object(let values):
            let preferredKeys = [
                "status",
                "verified_financial_data_available",
                "pod_policy",
                "required_source",
                "mutation_policy",
                "mirror_visible_to_orca",
            ]
            let parts = preferredKeys.compactMap { key -> String? in
                guard let value = values[key] else { return nil }
                return "\(key.replacingOccurrences(of: "_", with: " ")): \(value.shortValue)"
            }
            if !parts.isEmpty {
                return parts.joined(separator: " · ")
            }
            return "\(values.count) fields"
        }
    }

    private var shortValue: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return "\(values.count) entries"
        case .object(let values):
            return "\(values.count) fields"
        case .null:
            return "none"
        }
    }
}

// MARK: - Startup Truth

struct DashboardStartupStatusResponse: Decodable {
    let ok: Bool
    let checkedAt: Date
    let components: [DashboardStartupStatusComponentDTO]

    enum CodingKeys: String, CodingKey {
        case ok
        case checkedAt = "checked_at"
        case components
    }
}

struct DashboardStartupStatusComponentDTO: Decodable, Identifiable {
    let id: String
    let label: String
    let status: String
    let detail: String
    let source: String
    let endpoint: String?
    let checkedAt: Date
    let latencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, label, status, detail, source, endpoint
        case checkedAt = "checked_at"
        case latencyMs = "latency_ms"
    }

    var isDebt: Bool {
        ["degraded", "unavailable"].contains(status.lowercased())
    }
}
