import Foundation

// MARK: - Standard

struct Standard: Identifiable {
    let id: UUID
    var title: String
    let category: StandardCategory
    var content: String
    let authorId: UUID
    var tags: [String]
    let version: Int
    let createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var readingPosition: Int?
}

extension Standard: Codable {}
extension Standard: Hashable {}

// MARK: - Standard Category

enum StandardCategory: String, Codable, CaseIterable {
    case standards
    case frameworks
    case playbooks
    case runbooks

    var displayName: String {
        rawValue.capitalized
    }
}
