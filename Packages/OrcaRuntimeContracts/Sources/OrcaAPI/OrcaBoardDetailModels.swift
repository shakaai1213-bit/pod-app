import Foundation

public enum OrcaBoardProtectionPolicy {
    public static func isSafeProject(
        selectedBoardID: UUID,
        projectBoardIDs: Set<UUID>,
        protectedBoardIDs: Set<UUID>
    ) -> Bool {
        !protectedBoardIDs.isEmpty
            && projectBoardIDs.contains(selectedBoardID)
            && projectBoardIDs.isDisjoint(with: protectedBoardIDs)
    }

    public static func isSafeTicket(
        isProtected: Bool,
        computeTag: String?,
        autonomyLevel: String?
    ) -> Bool {
        let tag = computeTag?.lowercased()
        return !isProtected
            && tag != "financial"
            && tag != "security"
            && autonomyLevel?.lowercased() != "protected_approval_required"
    }
}

public struct OrcaBoardCollectionPage<Item>: Decodable, Sendable where Item: Decodable & Sendable {
    public let items: [Item]

    public init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            var values: [Item] = []
            while !container.isAtEnd {
                values.append(try container.decode(Item.self))
            }
            items = values
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([Item].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey { case items }
}

public struct OrcaBoardProjectSummary: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let boardId: UUID?
    public let boardIds: [UUID]
    public let name: String
    public let goal: String?
    public let projectDescription: String?
    public let status: String
    public let stage: String
    public let priority: Int
    public let dueDate: Date?

    public func belongs(to boardId: UUID) -> Bool {
        self.boardId == boardId || boardIds.contains(boardId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, goal, status, stage, priority
        case boardId = "board_id"
        case boardIds = "board_ids"
        case projectDescription = "description"
        case dueDate = "due_date"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        boardId = try container.decodeIfPresent(UUID.self, forKey: .boardId)
        boardIds = try container.decodeIfPresent([UUID].self, forKey: .boardIds) ?? []
        name = try container.decode(String.self, forKey: .name)
        goal = try container.decodeIfPresent(String.self, forKey: .goal)
        projectDescription = try container.decodeIfPresent(String.self, forKey: .projectDescription)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "backlog"
        stage = try container.decodeIfPresent(String.self, forKey: .stage) ?? "blueprint"
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 3
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
    }
}

public struct OrcaBoardTaskSummary: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let taskDescription: String?
    public let status: String
    public let priority: String
    public let dueAt: Date?
    public let isProtected: Bool
    public let pointer: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, status, priority, protected, pointer
        case taskDescription = "description"
        case dueAt = "due_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled task"
        taskDescription = try container.decodeIfPresent(String.self, forKey: .taskDescription)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "inbox"
        priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? "medium"
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        isProtected = try container.decodeIfPresent(Bool.self, forKey: .protected) ?? false
        pointer = try container.decodeIfPresent(String.self, forKey: .pointer)
    }
}

public struct OrcaBoardTicketSummary: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let status: String
    public let priority: String
    public let isProtected: Bool
    public let computeTag: String?
    public let autonomyLevel: String?

    public var isSafeForGenericSurface: Bool {
        OrcaBoardProtectionPolicy.isSafeTicket(
            isProtected: isProtected,
            computeTag: computeTag,
            autonomyLevel: autonomyLevel
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, status, priority, protected
        case computeTag = "compute_tag"
        case autonomyLevel = "autonomy_level"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled ticket"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "open"
        priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? "medium"
        isProtected = try container.decodeIfPresent(Bool.self, forKey: .protected) ?? false
        computeTag = try container.decodeIfPresent(String.self, forKey: .computeTag)
        autonomyLevel = try container.decodeIfPresent(String.self, forKey: .autonomyLevel)
    }
}
