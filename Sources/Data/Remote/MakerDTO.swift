import Foundation

struct ReadyIdea: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let discovery: ReadyIdeaDiscovery?
    let assessment: ReadyIdeaAssessment?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, summary, discovery, assessment
        case createdAt = "created_at"
    }

    var scope: String? { discovery?.scope }
    var effortEstimate: String? { discovery?.effortEstimate }
    var rationale: String? { assessment?.rationale }
}

struct ReadyIdeaDiscovery: Decodable {
    let scope: String?
    let effortEstimate: String?

    enum CodingKeys: String, CodingKey {
        case scope
        case effortEstimate = "effort_estimate"
    }
}

struct ReadyIdeaAssessment: Decodable {
    let rationale: String?
}
