import Foundation
import os.log

// MARK: - Knowledge ViewModel

@Observable
final class KnowledgeViewModel {

    // MARK: - Published State

    var standards: [Standard] = []
    var categories: [StandardCategory] = StandardCategory.allCases
    var selectedCategory: StandardCategory?
    var searchText: String = ""
    var recentStandards: [Standard] = []
    var favoriteStandards: [Standard] = []
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Computed

    var filteredStandards: [Standard] {
        var result = standards

        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { s in
                s.title.lowercased().contains(query) ||
                s.tags.contains { $0.lowercased().contains(query) } ||
                s.authorName.lowercased().contains(query)
            }
        }

        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    var categoryCounts: [StandardCategory: Int] {
        Dictionary(grouping: standards, by: \.category).mapValues(\.count)
    }

    // MARK: - Private

    private let recentStorageKey = "pod.recentStandards"
    private let favoritesStorageKey = "pod.favoriteStandards"

    // MARK: - Init

    init() {
        loadLocalFavorites()
        loadRecentStandards()
    }

    // MARK: - Load

    func loadStandards() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched: [Standard] = try await APIClient.shared.get(path: "/api/v1/standards")
            await MainActor.run {
                self.standards = fetched
                self.recomputeDerived()
                self.isLoading = false
            }
        } catch let error as APIError where error.code == 404 {
            // Backend doesn't have standards endpoint yet — use mock data
            await MainActor.run {
                self.standards = MockData.standards
                self.recomputeDerived()
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.standards = MockData.standards
                self.errorMessage = nil
                self.isLoading = false
            }
        }
    }

    func loadStandard(id: UUID) async -> Standard? {
        do {
            let standard: Standard = try await APIClient.shared.get(path: "/api/v1/standards/\(id.uuidString)")
            await MainActor.run {
                if let idx = standards.firstIndex(where: { $0.id == id }) {
                    standards[idx] = standard
                } else {
                    standards.append(standard)
                }
                addToRecent(standard)
            }
            return standard
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    // MARK: - Create

    func createStandard(_ standard: Standard) async -> Bool {
        do {
            let created: Standard = try await APIClient.shared.post(
                path: "/api/v1/standards",
                body: standard
            )
            await MainActor.run {
                standards.append(created)
                self.recomputeDerived()
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Update

    func updateStandard(_ standard: Standard) async -> Bool {
        do {
            let updated: Standard = try await APIClient.shared.put(
                path: "/api/v1/standards/\(standard.id.uuidString)",
                body: standard
            )
            await MainActor.run {
                if let idx = standards.firstIndex(where: { $0.id == standard.id }) {
                    standards[idx] = updated
                }
                self.recomputeDerived()
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Delete

    func deleteStandard(id: UUID) async -> Bool {
        do {
            try await APIClient.shared.delete(path: "/api/v1/standards/\(id.uuidString)")
            await MainActor.run {
                standards.removeAll { $0.id == id }
                self.recomputeDerived()
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Favorite

    func toggleFavorite(id: UUID) async {
        if let idx = standards.firstIndex(where: { $0.id == id }) {
            standards[idx].isFavorite.toggle()
            await MainActor.run {
                recomputeDerived()
                persistFavorites()
            }
        }
    }

    // MARK: - Search

    func searchStandards(_ query: String) async -> [Standard] {
        guard !query.isEmpty else { return [] }

        do {
            let results: [Standard] = try await APIClient.shared.get(
                path: "/api/v1/standards/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
            )
            return results
        } catch {
            return []
        }
    }

    // MARK: - Recent

    private func addToRecent(_ standard: Standard) {
        recentStandards.removeAll { $0.id == standard.id }
        recentStandards.insert(standard, at: 0)
        if recentStandards.count > 20 {
            recentStandards = Array(recentStandards.prefix(20))
        }
        persistRecent()
    }

    private func loadRecentStandards() {
        if let data = UserDefaults.standard.data(forKey: recentStorageKey),
           let decoded = try? JSONDecoder().decode([Standard].self, from: data) {
            recentStandards = decoded
        }
    }

    private func persistRecent() {
        if let encoded = try? JSONEncoder().encode(recentStandards) {
            UserDefaults.standard.set(encoded, forKey: recentStorageKey)
        }
    }

    // MARK: - Favorites

    private func loadLocalFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesStorageKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            let ids = Set(decoded)
            for i in standards.indices {
                standards[i].isFavorite = ids.contains(standards[i].id)
            }
        }
    }

    private func persistFavorites() {
        let ids = standards.filter(\.isFavorite).map(\.id)
        if let encoded = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(encoded, forKey: favoritesStorageKey)
        }
    }

    // MARK: - Derived

    private func recomputeDerived() {
        favoriteStandards = standards.filter(\.isFavorite)
    }

    // MARK: - Helpers

    func standard(for id: UUID) -> Standard? {
        standards.first { $0.id == id }
    }

    func relatedStandards(for standard: Standard) -> [Standard] {
        standard.relatedStandardIds.compactMap { id in
            standards.first { $0.id == id }
        }
    }
}
