import Foundation

@MainActor
@Observable
final class ResearchViewModel {
    var findings: [ResearchRepository.ResearchFinding] = []
    var isLoading = false
    var errorMessage: String?
    var selectedTopic: String?
    var lastRefreshedAt: Date?
    var latestFindingAt: Date?

    private var pollingTask: Task<Void, Never>?
    
    let topics = ["iOS 26", "MLX", "SSE", "Offline", "NATS", "SwiftData"]
    
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            await loadFindings()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
                await loadFindings(showLoading: false)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func loadFindings(showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        let repo = ResearchRepository()
        do {
            let loadedFindings = try await repo.loadFindings(topic: selectedTopic)
            findings = loadedFindings
            latestFindingAt = loadedFindings.map(\.createdAt).max()
            lastRefreshedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
        if showLoading {
            isLoading = false
        }
    }
}
