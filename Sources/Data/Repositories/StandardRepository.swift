import Foundation

@MainActor
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
            let fetched: [Standard] = try await api.get(path: "/api/v1/standards")
            standards = fetched
            await cache.syncStandards(fetched)
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
            let fetched: [Standard] = try await api.get(
                path: "/api/v1/standards?category=\(category.rawValue)"
            )

            // Merge: replace matching IDs, append new ones
            for item in fetched {
                if let index = standards.firstIndex(where: { $0.id == item.id }) {
                    standards[index] = item
                } else {
                    standards.append(item)
                }
            }

            await cache.syncStandards(fetched)
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
            let fetched: Standard = try await api.get(path: "/api/v1/standards/\(id.uuidString)")

            if let index = standards.firstIndex(where: { $0.id == id }) {
                standards[index] = fetched
            } else {
                standards.append(fetched)
            }
            await cache.syncStandards([fetched])
            return fetched
        } catch {
            return standards.first { $0.id == id }
        }
    }

    // MARK: - Favorites

    func loadFavorites() async {
        isLoading = true
        defer { isLoading = false }
        let cached = cache.fetchFavorites().map { $0.toStandard() }

        do {
            let fetched: [Standard] = try await api.get(path: "/api/v1/standards?favorites=true")
            await cache.syncStandards(fetched)
            standards = fetched
        } catch {
            standards = cached
            lastError = error
        }
    }

    func toggleFavorite(standardId: UUID) {
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
}
