import Foundation

protocol FundTradesRepositoryProtocol {
    func fetchFundTrades() async throws -> FundRouteFeedDTO
}

final class FundTradesRepository: FundTradesRepositoryProtocol {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchFundTrades() async throws -> FundRouteFeedDTO {
        try await apiClient.get(path: "/api/v1/fund/routes/trades")
    }
}
