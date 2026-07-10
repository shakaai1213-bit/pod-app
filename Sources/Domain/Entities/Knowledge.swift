import Foundation

// MARK: - Standard

struct Standard: Identifiable {
    let id: UUID
    var title: String
    let category: StandardCategory
    var content: String
    let authorId: UUID
    var authorName: String = "Unknown"
    var tags: [String]
    let version: Int
    let createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var readingPosition: Int?
    var relatedStandardIds: [UUID] = []
    var versions: [StandardVersion] = []
}

extension Standard: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, category, content, tags, version, versions
        case authorId = "author_id"
        case authorName = "author_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isFavorite = "is_favorite"
        case readingPosition = "reading_position"
        case relatedStandardIds = "related_standard_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(StandardCategory.self, forKey: .category)
        content = try container.decode(String.self, forKey: .content)
        authorId = try container.decode(UUID.self, forKey: .authorId)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName) ?? "Unknown"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        readingPosition = try container.decodeIfPresent(Int.self, forKey: .readingPosition)
        relatedStandardIds = try container.decodeIfPresent([UUID].self, forKey: .relatedStandardIds) ?? []
        versions = try container.decodeIfPresent([StandardVersion].self, forKey: .versions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(content, forKey: .content)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(authorName, forKey: .authorName)
        try container.encode(tags, forKey: .tags)
        try container.encode(version, forKey: .version)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(readingPosition, forKey: .readingPosition)
        try container.encode(relatedStandardIds, forKey: .relatedStandardIds)
        try container.encode(versions, forKey: .versions)
    }
}

// Manual Hashable to avoid potential auto-synthesis issues with @Observable macro
// and nested [StandardVersion] arrays in Swift 6 strict concurrency mode.
extension Standard: Hashable {
    static func == (lhs: Standard, rhs: Standard) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct StandardListResponse: Decodable {
    let items: [Standard]

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var values: [Standard] = []
            while !array.isAtEnd {
                values.append(try array.decode(Standard.self))
            }
            items = values
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Standard].self, forKey: .items) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }
}

// MARK: - Standard Version

struct StandardVersion: Identifiable, Codable, Hashable {
    let id: UUID
    let version: Int
    let content: String
    let authorId: UUID
    let authorName: String
    let updatedAt: Date

    static func == (lhs: StandardVersion, rhs: StandardVersion) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Standard Category

enum StandardCategory: String, Codable, CaseIterable {
    case standards
    case frameworks
    case playbooks
    case runbooks

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .standards:  return "doc.text"
        case .frameworks: return "square.grid.2x2"
        case .playbooks:  return "list.bullet.clipboard"
        case .runbooks:   return "wrench.and.screwdriver"
        }
    }

    var color: String {
        switch self {
        case .standards:  return "3B82F6"
        case .frameworks:  return "A855F7"
        case .playbooks:   return "22C55E"
        case .runbooks:     return "F97316"
        }
    }
}
