import Foundation

actor ResearchRepository {
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
        let flywheel = try await WorkbenchRepository().loadResearchFlywheel()
        let createdAt = flywheel.generatedAt ?? Date()
        var findings: [ResearchFinding] = []

        if let bodyPolicy = flywheel.bodyPolicy {
            findings.append(
                makeFinding(
                    topic: "Policy",
                    content: [
                        "protected research: \(bodyPolicy.protectedResearch ?? "pointer-only")",
                        "source bodies read: \(bodyPolicy.sourceBodiesRead ? "yes" : "no")",
                        "source bodies copied: \(bodyPolicy.sourceBodiesCopied ? "yes" : "no")",
                        "embeddings created: \(bodyPolicy.embeddingsCreated ? "yes" : "no")",
                        "fish woken: \(bodyPolicy.fishWoken ? "yes" : "no")",
                        "memory promoted: \(bodyPolicy.memoryPromoted ? "yes" : "no")"
                    ].joined(separator: " | "),
                    createdAt: createdAt
                )
            )
        }

        if let summary = flywheel.fish?.summary {
            findings.append(
                makeFinding(
                    topic: "Fish",
                    content: "\(summary.count) fish; \(summary.producing) producing; \(summary.idle) idle; \(summary.blocked) blocked; \(summary.autoresearchReady) autoresearch-ready.",
                    createdAt: createdAt
                )
            )
        }

        for fish in flywheel.fish?.fish ?? [] {
            let details = [
                fish.owner.map { "owner: \($0)" },
                fish.runtimeStatus.map { "runtime: \($0)" },
                fish.statusReason.map { "reason: \($0)" },
                fish.directiveSlug.map { "directive: \($0)" },
                fish.findings.map { "findings: \($0.count)" },
                fish.queue.map { "queue pending: \($0.pendingCount)" },
                fish.autoresearch.map { "autoresearch: \($0.configured ? "configured" : "not configured")" }
            ].compactMap { $0 }

            findings.append(
                makeFinding(
                    topic: fish.fish.capitalized,
                    content: details.isEmpty ? "Workbench metadata present." : details.joined(separator: " | "),
                    agentId: fish.owner,
                    createdAt: fish.findings?.latestMtime ?? createdAt
                )
            )
        }

        if let referenceSummary = flywheel.referenceCandidates?.summary {
            findings.append(
                makeFinding(
                    topic: "References",
                    content: "\(referenceSummary.instanceCount) candidates; \(referenceSummary.reviewFlags.values.reduce(0, +)) review flags; promotion mode: \(referenceSummary.promotionMode ?? "review-only").",
                    createdAt: createdAt
                )
            )
        }

        if let railCounts = flywheel.researchRail?.counts {
            findings.append(
                makeFinding(
                    topic: "Research Rail",
                    content: "\(railCounts.requests) requests; \(railCounts.packets) packets; \(railCounts.awaitingReview) awaiting review; \(railCounts.activeRequests) active.",
                    createdAt: createdAt
                )
            )
        }

        if let policy = flywheel.flywheel {
            findings.append(
                makeFinding(
                    topic: "Flywheel",
                    content: [
                        "planner writes: \(policy.plannerWriteMode ?? "unknown")",
                        "memory promotion: \(policy.memoryPromotionMode ?? "unknown")",
                        "review loop: \(policy.recommendedReviewLoop ?? "owner-review")"
                    ].joined(separator: " | "),
                    createdAt: createdAt
                )
            )
        }

        guard let topic, !topic.isEmpty else {
            return findings
        }
        return findings.filter { $0.topic.localizedCaseInsensitiveContains(topic) }
    }

    private func makeFinding(
        topic: String,
        content: String,
        agentId: String? = nil,
        createdAt: Date
    ) -> ResearchFinding {
        ResearchFinding(
            id: "\(topic.lowercased().replacingOccurrences(of: " ", with: "-"))-\(Int(createdAt.timeIntervalSince1970))",
            topic: topic,
            content: content,
            sourceUrl: nil,
            sourceTitle: "ORCA Workbench research-flywheel",
            agentId: agentId,
            confidence: "metadata",
            createdAt: createdAt
        )
    }
}
