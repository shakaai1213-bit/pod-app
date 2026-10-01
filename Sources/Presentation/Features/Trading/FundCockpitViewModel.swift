import Foundation
import Observation

@MainActor
@Observable
final class FundCockpitViewModel {
    var feed: FundCockpitFeedDTO?
    var isLoading = false
    var errorMessage: String?
    var isDenied = false

    private let repository: FundCockpitRepositoryProtocol

    init(repository: FundCockpitRepositoryProtocol = FundCockpitRepository()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        isDenied = false
        defer { isLoading = false }

        do {
            feed = try await repository.fetchCockpit()
            if feed?.isAvailable != true {
                errorMessage = feed?.degradedReason ?? (feed?.quality == "stale"
                    ? "Fund cockpit snapshot is stale."
                    : "Fund cockpit feed is unavailable from ORCA.")
            }
        } catch {
            feed = nil
            if let apiError = error as? APIError, apiError.code == 401 || apiError.code == 403 {
                isDenied = true
                errorMessage = "Access to the protected Fund cockpit was denied by ORCA."
            } else {
                errorMessage = "Fund cockpit feed is unavailable from ORCA."
            }
        }
    }
}
