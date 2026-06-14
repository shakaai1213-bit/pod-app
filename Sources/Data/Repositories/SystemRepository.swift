import Foundation

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
        sections = try container.decodeIfPresent([ControlRoomSectionDTO].self, forKey: .sections) ?? []
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
