import Foundation

protocol FundCockpitRepositoryProtocol {
    func fetchCockpit() async throws -> FundCockpitFeedDTO
}

final class FundCockpitRepository: FundCockpitRepositoryProtocol {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchCockpit() async throws -> FundCockpitFeedDTO {
        try await apiClient.get(path: "/api/v1/fund/routes/cockpit")
    }
}
