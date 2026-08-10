import CoreFoundation
import Foundation

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
