import Foundation
import Observation

@MainActor
@Observable
final class FundTradesViewModel {
    var feed: FundRouteFeedDTO?
    var isLoading = false
    var errorMessage: String?

    private let repository: FundTradesRepositoryProtocol
    private var hasLoaded = false

    init(
        repository: FundTradesRepositoryProtocol = FundTradesRepository(),
        initialFeed: FundRouteFeedDTO? = nil,
        initialError: String? = nil
    ) {
        self.repository = repository
        self.feed = initialFeed
        self.errorMessage = initialError
        self.hasLoaded = initialFeed != nil || initialError != nil
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        hasLoaded = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            feed = try await repository.fetchFundTrades()
        } catch let apiError as APIError {
            let malformed = apiError.message.localizedCaseInsensitiveContains("decoding")
            let reason = malformed
                ? "Malformed ORCA trade feed. Awaiting valid envelope."
                : "Fund trade feed unavailable from ORCA."
            feed = FundRouteFeedDTO.degraded(reason: reason, quality: malformed ? "malformed" : "unavailable")
            errorMessage = reason
        } catch {
            let reason = "Fund trade feed unavailable from ORCA."
            feed = FundRouteFeedDTO.degraded(reason: reason, quality: "unavailable")
            errorMessage = reason
        }
    }
}
