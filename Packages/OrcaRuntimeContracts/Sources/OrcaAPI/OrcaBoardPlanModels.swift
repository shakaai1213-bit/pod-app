import Foundation

public struct OrcaBoardDirectoryItem: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let slug: String
    public let name: String
    public let layer: String?
    public let component: String?
    public let boardDescription: String?
    public let projectCount: Int
    public let activeCount: Int
    public let ticketCount: Int

    public var displayName: String {
        guard let component, !component.isEmpty else { return name }
        return component
    }

    public var isProtected: Bool { slug.lowercased() == "fund" }

    public var isProduct: Bool {
        let description = boardDescription?.lowercased() ?? ""
        return description.contains("[product")
            || description.contains("product vertical")
            || ["campwatch", "guardian", "tiki"].contains(slug.lowercased())
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, layer, component, description, objective
        case projectCount = "project_count"
        case projectsCount = "projects_count"
        case totalProjects = "total_projects"
        case activeCount = "active_count"
        case activeProjects = "active_projects"
        case activeProjectCount = "active_project_count"
        case ticketCount = "ticket_count"
        case ticketsCount = "tickets_count"
        case directTicketCount = "direct_ticket_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        layer = try container.decodeIfPresent(String.self, forKey: .layer)
        component = try container.decodeIfPresent(String.self, forKey: .component)
        boardDescription = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .objective)
        projectCount = Self.firstInt(
            in: container,
            keys: [.projectCount, .projectsCount, .totalProjects]
        ) ?? 0
        activeCount = Self.firstInt(
            in: container,
            keys: [.activeCount, .activeProjects, .activeProjectCount]
        ) ?? 0
        ticketCount = Self.firstInt(
            in: container,
            keys: [.ticketCount, .ticketsCount, .directTicketCount]
        ) ?? 0
    }

    private static func firstInt(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
            if let text = try? container.decodeIfPresent(String.self, forKey: key),
               let value = Int(text) { return value }
        }
        return nil
    }
}

public struct OrcaBoardDirectory: Decodable, Hashable, Sendable {
    public let items: [OrcaBoardDirectoryItem]

    public init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            var result: [OrcaBoardDirectoryItem] = []
            while !container.isAtEnd {
                result.append(try container.decode(OrcaBoardDirectoryItem.self))
            }
            items = result
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([OrcaBoardDirectoryItem].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey { case items }
}

public struct OrcaEvidenceReference: Decodable, Hashable, Sendable {
    public let kind: String
    public let ref: String
    public let occurredAt: Date?
    public let source: String?

    private enum CodingKeys: String, CodingKey {
        case kind, ref, source
        case occurredAt = "occurred_at"
    }
}

public struct OrcaBoardPlanPin: Decodable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let boardId: UUID
    public let objectType: String
    public let objectId: UUID
    public let rank: Int
    public let createdAt: Date
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, rank
        case boardId = "board_id"
        case objectType = "object_type"
        case objectId = "object_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct OrcaBoardPlanPinRequest: Encodable, Sendable {
    public let objectType: String
    public let objectId: UUID
    public let rank: Int

    public init(objectType: String, objectId: UUID, rank: Int) {
        self.objectType = objectType
        self.objectId = objectId
        self.rank = rank
    }
}

public struct OrcaBoardPlanFacet: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let objectType: String
    public let objectId: UUID
    public let relationship: String
    public let title: String?
    public let state: String
    public let boardId: UUID?
    public let canonicalRef: String

    private enum CodingKeys: String, CodingKey {
        case id, relationship, title, state
        case objectType = "object_type"
        case objectId = "object_id"
        case boardId = "board_id"
        case canonicalRef = "canonical_ref"
    }
}

public struct OrcaBoardPlanCard: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let objectType: String
    public let objectId: UUID
    public let title: String
    public let subtitle: String?
    public let column: String
    public let canonicalState: String
    public let priority: String?
    public let ownerAgentId: UUID?
    public let ownerName: String?
    public let waitReason: String?
    public let waitKind: String?
    public let pinned: Bool
    public let rank: Int
    public let latestEvidence: OrcaEvidenceReference?
    public let evidenceState: String
    public let projectIds: [UUID]
    public let runIds: [UUID]
    public let canonicalRef: String
    public let canonicalWorkId: String?
    public let facets: [OrcaBoardPlanFacet]?
    public let pinIds: [UUID]?
    public let integrityWarnings: [String]?

    public var resolvedCanonicalWorkId: String { canonicalWorkId ?? id }
    public var resolvedFacets: [OrcaBoardPlanFacet] { facets ?? [] }
    public var resolvedPinIds: [UUID] { pinIds ?? [] }
    public var resolvedIntegrityWarnings: [String] { integrityWarnings ?? [] }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, column, priority, pinned, rank
        case objectType = "object_type"
        case objectId = "object_id"
        case canonicalState = "canonical_state"
        case ownerAgentId = "owner_agent_id"
        case ownerName = "owner_name"
        case waitReason = "wait_reason"
        case waitKind = "wait_kind"
        case latestEvidence = "latest_evidence"
        case evidenceState = "evidence_state"
        case projectIds = "project_ids"
        case runIds = "run_ids"
        case canonicalRef = "canonical_ref"
        case canonicalWorkId = "canonical_work_id"
        case facets
        case pinIds = "pin_ids"
        case integrityWarnings = "integrity_warnings"
    }
}

public struct OrcaBoardPlanLane: Decodable, Identifiable, Hashable, Sendable {
    public let key: String
    public let title: String
    public let cards: [OrcaBoardPlanCard]
    public var id: String { key }
}

public struct OrcaBoardPlan: Decodable, Hashable, Sendable {
    public let computedAt: Date
    public let boardId: UUID
    public let boardName: String
    public let boardSlug: String
    public let selectionMode: String
    public let pins: [OrcaBoardPlanPin]
    public let lanes: [OrcaBoardPlanLane]
    public let counts: [String: Int]
    public let sourceRefs: [String]

    private enum CodingKeys: String, CodingKey {
        case pins, lanes, counts
        case computedAt = "computed_at"
        case boardId = "board_id"
        case boardName = "board_name"
        case boardSlug = "board_slug"
        case selectionMode = "selection_mode"
        case sourceRefs = "source_refs"
    }
}
