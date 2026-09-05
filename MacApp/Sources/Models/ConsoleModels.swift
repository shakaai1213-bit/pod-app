import CoreFoundation
import Foundation
import OrcaAPI
import OrcaRuntimeContracts

enum ConsoleWorkMode: String, CaseIterable, Identifiable {
    case portfolio
    case agentWork

    var id: String { rawValue }
    var title: String { self == .portfolio ? "Portfolio" : "Agent Work" }
}

struct ConsoleMetric: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    let status: String?
}

struct ConsoleField: Identifiable, Equatable, Sendable {
    var id: String { label }
    let label: String
    let value: String
}

struct ConsoleRecord: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let status: String?
    let group: String
    let fields: [ConsoleField]
}

struct ConsoleSectionSnapshot: Equatable, Sendable {
    let section: ConsoleSection
    let metrics: [ConsoleMetric]
    let records: [ConsoleRecord]
    let sources: [String]
    let updatedAt: Date

    static func empty(_ section: ConsoleSection) -> ConsoleSectionSnapshot {
        ConsoleSectionSnapshot(
            section: section,
            metrics: [],
            records: [],
            sources: [],
            updatedAt: .distantPast
        )
    }

    static func workControl(_ projection: OrcaWorkControlProjection) -> ConsoleSectionSnapshot {
        let counts = projection.counts
        let metrics = [
            ConsoleMetric(id: "ready", label: "Ready Now", value: "\(counts.readyNow)", status: counts.readyNow > 0 ? "ready" : "ok"),
            ConsoleMetric(id: "assigned", label: "Assigned", value: "\(counts.assigned)", status: nil),
            ConsoleMetric(id: "waiting", label: "Waiting", value: "\(counts.waitingOnOthers)", status: counts.waitingOnOthers > 0 ? "attention" : "ok"),
            ConsoleMetric(id: "approvals", label: "Approvals", value: "\(counts.approvals)", status: counts.approvals > 0 ? "pending" : "ok"),
            ConsoleMetric(id: "protected", label: "Protected", value: "\(counts.protected)", status: counts.protected > 0 ? "protected" : nil),
            ConsoleMetric(id: "historical", label: "Historical", value: "\(counts.historical)", status: nil),
        ]
        var records: [ConsoleRecord] = []
        for group in OrcaWorkControlProjection.Group.allCases where group != .approvals {
            records += projection.items(in: group).map { workRecord($0, group: group) }
        }
        records += projection.approvals.map(approvalRecord)
        return ConsoleSectionSnapshot(
            section: .work,
            metrics: metrics,
            records: records,
            sources: [
                "/api/v1/chat-runtime/v1/agents/\(projection.agentKey)/work-control",
                projection.sourceContract,
                "bundle:\(projection.bundleSHA256)",
            ],
            updatedAt: projection.generatedAt
        )
    }

    private static func workRecord(
        _ item: OrcaWorkControlProjection.Item,
        group: OrcaWorkControlProjection.Group
    ) -> ConsoleRecord {
        var fields = [
            ConsoleField(label: "ID", value: item.id),
            ConsoleField(label: "Kind", value: item.kind.capitalized),
            ConsoleField(label: "Priority", value: item.priority),
            ConsoleField(label: "Approval", value: item.approvalState),
            ConsoleField(label: "Execution", value: item.executionEligible ? "Eligible" : "Held"),
        ]
        if let waitingOn = item.waitingOn {
            fields.append(ConsoleField(label: "Waiting On", value: waitingOn))
        }
        if let blockedOn = item.blockedOn {
            fields.append(ConsoleField(label: "Blocked On", value: blockedOn))
        }
        return ConsoleRecord(
            id: "\(group.rawValue):\(item.id)",
            title: item.title,
            subtitle: item.reason,
            status: item.stale ? "stale" : item.status,
            group: group.rawValue,
            fields: fields
        )
    }

    private static func approvalRecord(
        _ approval: OrcaWorkControlProjection.Approval
    ) -> ConsoleRecord {
        ConsoleRecord(
            id: "approval:\(approval.id)",
            title: approval.actionType.replacingOccurrences(of: "_", with: " ").capitalized,
            subtitle: approval.reason,
            status: approval.stale ? "stale" : "pending",
            group: OrcaWorkControlProjection.Group.approvals.rawValue,
            fields: [
                ConsoleField(label: "ID", value: approval.id),
                ConsoleField(label: "Authority", value: approval.authority),
                ConsoleField(label: "Resolution", value: approval.resolutionEnabled ? "Enabled" : "Held"),
            ]
        )
    }
}

enum ConsoleJSON: Decodable, Equatable, Sendable {
    case object([String: ConsoleJSON])
    case array([ConsoleJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(foundationValue value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let object as [String: Any]:
            self = .object(try object.mapValues(ConsoleJSON.init(foundationValue:)))
        case let array as [Any]:
            self = .array(try array.map(ConsoleJSON.init(foundationValue:)))
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        default:
            throw DecodingError.typeMismatch(
                ConsoleJSON.self,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unsupported ORCA JSON value"
                )
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: ConsoleJSON].self) {
            self = .object(value)
        } else if let value = try? container.decode([ConsoleJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            throw DecodingError.typeMismatch(
                ConsoleJSON.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported ORCA JSON value"
                )
            )
        }
    }

    var objectValue: [String: ConsoleJSON]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [ConsoleJSON]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var displayValue: String? {
        switch self {
        case let .string(value): return value
        case let .number(value):
            return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        case let .bool(value): return value ? "Yes" : "No"
        case .null: return nil
        case let .array(value): return "\(value.count) items"
        case let .object(value):
            for key in ["label", "title", "name", "summary", "status", "state"] {
                if let text = value[key]?.displayValue, !text.isEmpty { return text }
            }
            return "\(value.count) fields"
        }
    }
}
