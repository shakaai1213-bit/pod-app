import Foundation

#if SWIFT_PACKAGE
private enum ContractPackageAPIError: Error {
    case unavailable
}

actor APIClient {
    static let shared = APIClient()

    func get<T: Decodable>(path _: String) async throws -> T {
        throw ContractPackageAPIError.unavailable
    }
}
#endif

struct ControlRoomDigestDTO: Decodable {
    let generatedAt: Date?
    let windowHours: Int?
    let status: String
    let signalCount: Int
    let signals: [ControlRoomSignalDTO]
    let sections: [ControlRoomSectionDTO]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case windowHours = "window_hours"
        case status
        case signalCount = "signal_count"
        case signals
        case sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt)
        windowHours = try container.decodeFlexibleIntIfPresent(forKey: .windowHours)
        status = try container.decodeFlexibleStringIfPresent(forKey: .status) ?? "unknown"
        signalCount = try container.decodeFlexibleIntIfPresent(forKey: .signalCount) ?? 0
        signals = try container.decodeIfPresent([ControlRoomSignalDTO].self, forKey: .signals) ?? []
        if let array = try? container.decode([ControlRoomSectionDTO].self, forKey: .sections) {
            sections = array
        } else if let keyed = try? container.decode(
            [String: [String: ControlRoomJSONValue]].self,
            forKey: .sections
        ) {
            sections = keyed
                .map { ControlRoomSectionDTO(sectionId: $0.key, payload: $0.value) }
                .sorted { $0.sortOrder < $1.sortOrder }
        } else {
            sections = []
        }
    }
}

struct ControlRoomSignalDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let status: String?
    let severity: String?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status, severity, summary, message, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleStringIfPresent(forKey: .id) ?? UUID().uuidString
        title = try container.decodeFlexibleStringIfPresent(forKey: .title)
            ?? container.decodeFlexibleStringIfPresent(forKey: .name)
            ?? container.decodeFlexibleStringIfPresent(forKey: .message)
            ?? "Signal"
        status = try container.decodeFlexibleStringIfPresent(forKey: .status)
        severity = try container.decodeFlexibleStringIfPresent(forKey: .severity)
        summary = try container.decodeFlexibleStringIfPresent(forKey: .summary)
            ?? container.decodeFlexibleStringIfPresent(forKey: .message)
    }
}

struct ControlRoomSectionDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let status: String?
    let items: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, summary, status, items, name, body
    }

    init(id: String, title: String, summary: String?, status: String?, items: [String]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleStringIfPresent(forKey: .id) ?? UUID().uuidString
        title = try container.decodeFlexibleStringIfPresent(forKey: .title)
            ?? container.decodeFlexibleStringIfPresent(forKey: .name)
            ?? "Section"
        summary = try container.decodeFlexibleStringIfPresent(forKey: .summary)
            ?? container.decodeFlexibleStringIfPresent(forKey: .body)
        status = try container.decodeFlexibleStringIfPresent(forKey: .status)
        items = try container.decodeFlexibleStringArrayIfPresent(forKey: .items) ?? []
    }

    fileprivate init(sectionId: String, payload: [String: ControlRoomJSONValue]) {
        let facts = payload
            .compactMap { key, value -> (key: String, value: String)? in
                guard !Self.hiddenFactKeys.contains(key), let display = value.scalarDisplay else { return nil }
                return (key, display)
            }
            .sorted {
                let lhs = Self.factPriority($0.key)
                let rhs = Self.factPriority($1.key)
                return lhs == rhs ? $0.key < $1.key : lhs < rhs
            }
            .map { "\(Self.displayName($0.key)): \($0.value)" }

        id = sectionId
        title = Self.displayName(sectionId)
        summary = facts.first
        items = Array(facts.dropFirst().prefix(3))
        status = payload["status"]?.scalarDisplay
            ?? Self.derivedStatus(sectionId: sectionId, payload: payload)
    }

    fileprivate var sortOrder: Int {
        Self.sectionOrder[id] ?? 100
    }

    private static let hiddenFactKeys: Set<String> = [
        "status", "endpoint", "registry_path", "manifest_path", "generated_at",
        "last_refresh", "fetched_at", "window_hours", "stale_after_hours"
    ]

    private static let sectionOrder: [String: Int] = [
        "activation": 0,
        "agent_run_reviews": 1,
        "memory": 2,
        "compute": 3,
        "ticket_quality": 4,
        "jarvis_directives": 5,
        "nats": 6,
        "chief_graph_snapshot": 7,
    ]

    private static func factPriority(_ key: String) -> Int {
        if key.contains("attention") || key.contains("failure") || key.contains("pending") || key.contains("review") {
            return 0
        }
        if key.contains("count") || key.contains("total") || key.contains("score") || key == "up" {
            return 1
        }
        return 2
    }

    private static func displayName(_ raw: String) -> String {
        raw
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func derivedStatus(
        sectionId: String,
        payload: [String: ControlRoomJSONValue]
    ) -> String? {
        if sectionId == "activation", (payload["required_attention_count"]?.numberValue ?? 0) > 0 {
            return "needs_attention"
        }
        return nil
    }
}

fileprivate indirect enum ControlRoomJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ControlRoomJSONValue])
    case array([ControlRoomJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: ControlRoomJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([ControlRoomJSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var scalarDisplay: String? {
        switch self {
        case .string(let value):
            return value.replacingOccurrences(of: "_", with: " ")
        case .number(let value):
            return value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.2f", value)
        case .bool(let value):
            return value ? "yes" : "no"
        case .object, .array, .null:
            return nil
        }
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

struct RuntimeRegistryDTO: Decodable {
    let generatedAt: Date?
    let summary: RuntimeRegistrySummary
    let items: [RuntimeRegistryItemDTO]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case summary
        case items
    }
}

struct RuntimeRegistrySummary: Decodable {
    let total: Int
    let byStatus: [String: Int]

    enum CodingKeys: String, CodingKey {
        case total
        case byStatus = "by_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decodeFlexibleIntIfPresent(forKey: .total) ?? 0
        byStatus = try container.decodeIfPresent([String: Int].self, forKey: .byStatus) ?? [:]
    }
}

struct RuntimeRegistryItemDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let status: String
    let kind: String?
    let owner: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, kind, owner
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleStringIfPresent(forKey: .id) ?? UUID().uuidString
        name = try container.decodeFlexibleStringIfPresent(forKey: .name) ?? id
        status = try container.decodeFlexibleStringIfPresent(forKey: .status) ?? "unknown"
        kind = try container.decodeFlexibleStringIfPresent(forKey: .kind)
        owner = try container.decodeFlexibleStringIfPresent(forKey: .owner)
    }
}

struct SystemBoardDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let agentCount: Int
    let activeProjectCount: Int
    let ticketCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case agentCount = "agent_count"
        case agentsCount = "agents_count"
        case activeProjectCount = "active_project_count"
        case activeProjectsCount = "active_projects_count"
        case projectCount = "project_count"
        case projectsCount = "projects_count"
        case ticketCount = "ticket_count"
        case taskCount = "task_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleStringIfPresent(forKey: .id) ?? UUID().uuidString
        name = try container.decodeFlexibleStringIfPresent(forKey: .name)
            ?? container.decodeFlexibleStringIfPresent(forKey: .slug)
            ?? id
        agentCount = try container.decodeFlexibleIntIfPresent(forKey: .agentCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .agentsCount)
            ?? 0
        activeProjectCount = try container.decodeFlexibleIntIfPresent(forKey: .activeProjectCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .activeProjectsCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .projectCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .projectsCount)
            ?? 0
        ticketCount = try container.decodeFlexibleIntIfPresent(forKey: .ticketCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .taskCount)
            ?? 0
    }
}

final class SystemRepository {
    private let api = APIClient.shared

    func fetchControlRoomDigest() async throws -> ControlRoomDigestDTO {
        try await api.get(path: "/api/v1/control-room/digest")
    }

    func fetchRuntimeRegistry() async throws -> RuntimeRegistryDTO {
        try await api.get(path: "/api/v1/runtime-registry")
    }

    func fetchBoards() async throws -> [SystemBoardDTO] {
        let response: SystemBoardListResponse = try await api.get(path: "/api/v1/boards")
        return response.items
    }
}

private struct SystemBoardListResponse: Decodable {
    let items: [SystemBoardDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [SystemBoardDTO] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(SystemBoardDTO.self))
            }
            items = values
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([SystemBoardDTO].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeFlexibleStringArrayIfPresent(forKey key: Key) throws -> [String]? {
        if let values = try? decode([String].self, forKey: key) {
            return values
        }
        if let value = try? decode(String.self, forKey: key) {
            return [value]
        }
        return nil
    }
}
