import Foundation

@Observable
final class StandardRepository {
    private let api = APIClient.shared
    private let cache = PersistenceController.shared

    var standards: [Standard] = []
    var isLoading: Bool = false
    var lastError: Error?

    private init() {}

    // MARK: - Load All

    func loadStandards() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let dtos: [KnowledgeEntry] = try await api.get("/api/v1/knowledge")
            let remote = dtos.map { mapKnowledgeEntryToStandard($0) }
            standards = remote
            await cache.syncStandards(remote)
        } catch {
            lastError = error
            let cached = cache.fetchRecentStandards(limit: 50)
            standards = cached.map { $0.toStandard() }
        }
    }

    // MARK: - Load by Category

    func loadStandards(category: StandardCategory) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let dtos: [KnowledgeEntry] = try await api.get(
                "/api/v1/knowledge?category=\(category.rawValue)"
            )
            let remote = dtos.map { mapKnowledgeEntryToStandard($0) }

            // Merge: replace matching IDs, append new ones
            for item in remote {
                if let index = standards.firstIndex(where: { $0.id == item.id }) {
                    standards[index] = item
                } else {
                    standards.append(item)
                }
            }

            await cache.syncStandards(remote)
        } catch {
            lastError = error
            let cached = cache.fetchStandardsByCategory(category.rawValue)
            let fromCache = cached.map { $0.toStandard() }
            let filtered = standards.filter { $0.category != category }
            standards = filtered + fromCache
        }
    }

    // MARK: - Fetch Single

    func fetchStandard(id: UUID) async -> Standard? {
        do {
            let dto: KnowledgeEntry = try await api.get("/api/v1/knowledge/\(id.uuidString)")
            let standard = mapKnowledgeEntryToStandard(dto)

            if let index = standards.firstIndex(where: { $0.id == id }) {
                standards[index] = standard
            } else {
                standards.append(standard)
            }
            await cache.syncStandards([standard])
            return standard
        } catch {
            return cache.fetchCachedAgent(id: id).map { _ in
                standards.first { $0.id == id } ?? standards.first { $0.id == id }!
            }
        }
    }

    // MARK: - Favorites

    func loadFavorites() async {
        isLoading = true
        defer { isLoading = false }
        // Favorites are cached locally; merge with remote if available
        let cached = cache.fetchFavorites().map { $0.toStandard() }
        let cachedIds = Set(cached.map { $0.id })

        do {
            let dtos: [KnowledgeEntry] = try await api.get("/api/v1/knowledge?favorites=true")
            let remote = dtos.map { mapKnowledgeEntryToStandard($0) }
            await cache.syncStandards(remote)
            standards = remote
        } catch {
            standards = cached
            lastError = error
        }
    }

    func toggleFavorite(standardId: UUID) async {
        cache.toggleFavorite(standardId: standardId)
        if let index = standards.firstIndex(where: { $0.id == standardId }) {
            standards[index].isFavorite.toggle()
        }
    }

    // MARK: - Reading Progress

    func updateReadingProgress(standardId: UUID, position: Int) {
        cache.updateReadingHistory(standardId: standardId, position: position)
        if let index = standards.firstIndex(where: { $0.id == standardId }) {
            standards[index].readingPosition = position
        }
    }

    func getReadingPosition(standardId: UUID) -> Int? {
        cache.fetchReadingHistory(standardId: standardId)?.readingPosition
    }

    // MARK: - Queries

    func getStandard(id: UUID) -> Standard? {
        standards.first { $0.id == id }
    }

    func standardsByCategory(_ category: StandardCategory) -> [Standard] {
        standards.filter { $0.category == category }
    }

    func searchStandards(query: String) -> [Standard] {
        let lowercased = query.lowercased()
        return standards.filter {
            $0.title.lowercased().contains(lowercased) ||
            $0.content.lowercased().contains(lowercased) ||
            $0.tags.contains { $0.lowercased().contains(lowercased) }
        }
    }

    var recentStandards: [Standard] {
        Array(standards.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))
    }

    var favoriteStandards: [Standard] {
        standards.filter { $0.isFavorite }
    }

    // MARK: - Mapping

    private func mapKnowledgeEntryToStandard(_ dto: KnowledgeEntry) -> Standard {
        Standard(
            id: UUID(uuidString: dto.id) ?? UUID(),
            title: dto.title,
            category: StandardCategory(rawValue: dto.category) ?? .standards,
            content: dto.content,
            authorId: UUID(uuidString: dto.authorId) ?? UUID(),
            authorName: dto.authorName,
            tags: dto.tags,
            version: dto.version,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            isFavorite: false,
            readingPosition: nil,
            relatedStandardIds: [],
            versions: []
        )
    }
}
