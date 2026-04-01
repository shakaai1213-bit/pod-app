import Foundation

@MainActor
@Observable
final class ResearchViewModel {
    var findings: [ResearchRepository.ResearchFinding] = []
    var isLoading = false
    var errorMessage: String?
    var selectedTopic: String?
    
    let topics = ["iOS 26", "MLX", "SSE", "Offline", "NATS", "SwiftData"]
    
    func loadFindings() async {
        isLoading = true
        errorMessage = nil
        let repo = ResearchRepository()
        do {
            findings = try await repo.loadFindings(topic: selectedTopic)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
