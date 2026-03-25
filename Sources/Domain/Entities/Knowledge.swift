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

extension Standard: Codable {}

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


