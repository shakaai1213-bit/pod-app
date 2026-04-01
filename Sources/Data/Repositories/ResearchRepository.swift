import Foundation

actor ResearchRepository {
    private let api = APIClient.shared
    
    struct ResearchFinding: Codable, Identifiable {
        let id: String
        let topic: String
        let content: String
        let sourceUrl: String?
        let sourceTitle: String?
        let agentId: String?
        let confidence: String
        let createdAt: Date
        
        enum CodingKeys: String, CodingKey {
            case id, topic, content, confidence
            case sourceUrl = "source_url"
            case sourceTitle = "source_title"
            case agentId = "agent_id"
            case createdAt = "created_at"
        }
    }
    
    func loadFindings(topic: String? = nil) async throws -> [ResearchFinding] {
        var path = "/api/v1/research/findings"
        if let topic = topic {
            path += "?topic=\(topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? topic)"
        }
        return try await api.get(path: path)
    }
}
