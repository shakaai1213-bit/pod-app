import Foundation
import Observation

@MainActor
@Observable
final class FundCockpitViewModel {
    var feed: FundCockpitFeedDTO?
    var isLoading = false
    var errorMessage: String?

    private let repository: FundCockpitRepositoryProtocol

    init(repository: FundCockpitRepositoryProtocol = FundCockpitRepository()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            feed = try await repository.fetchCockpit()
            if feed?.isAvailable != true {
                errorMessage = feed?.quality == "stale"
                    ? "Fund cockpit snapshot is stale."
                    : "Fund cockpit feed is unavailable from ORCA."
            }
        } catch {
            feed = nil
            errorMessage = "Fund cockpit feed is unavailable from ORCA."
        }
    }
}
