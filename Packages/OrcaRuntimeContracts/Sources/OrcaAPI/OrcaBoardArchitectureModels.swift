import Foundation

public enum OrcaBoardArchitectureVisibility: String, Decodable, Hashable, Sendable {
    case full
    case protectedPointer = "protected_pointer"
}

public enum OrcaBoardClassification: String, Decodable, Hashable, Sendable {
    case portfolio
    case product
    case surfaceProduct = "surface_product"
    case platformService = "platform_service"
    case transportService = "transport_service"
    case operatingSystem = "operating_system"
    case knowledgeSystem = "knowledge_system"
    case adapterSystem = "adapter_system"
    case capabilitySystem = "capability_system"
    case protectedDomain = "protected_domain"
    case unknown
}

public enum OrcaBoardLifecycleState: String, Decodable, Hashable, Sendable {
    case incubating
    case active
    case maintenance
    case paused
    case retiring
    case archived
    case unknown
}

public enum OrcaBoardHealthState: String, Decodable, Hashable, Sendable {
    case healthy
    case attention
    case blocked
    case unknown
}

public enum OrcaBoardFreshnessState: String, Decodable, Hashable, Sendable {
    case fresh
    case stale
    case unknown
}

public struct OrcaBoardArchitectureCounts: Decodable, Hashable, Sendable {
    public let projectCount: Int?
    public let activeProjectCount: Int?
    public let taskCount: Int?
    public let activeTaskCount: Int?
    public let ticketCount: Int?
    public let inProgressCount: Int?
    public let blockedCount: Int?
    public let reviewCount: Int?
    public let approvalCount: Int?
    public let runCount: Int?
    public let staleCount: Int?

    public var isRedacted: Bool {
        projectCount == nil
            && activeProjectCount == nil
            && taskCount == nil
            && activeTaskCount == nil
            && ticketCount == nil
            && inProgressCount == nil
            && blockedCount == nil
            && reviewCount == nil
            && approvalCount == nil
            && runCount == nil
            && staleCount == nil
    }

    private enum CodingKeys: String, CodingKey {
        case projectCount = "project_count"
        case activeProjectCount = "active_project_count"
        case taskCount = "task_count"
        case activeTaskCount = "active_task_count"
        case ticketCount = "ticket_count"
        case inProgressCount = "in_progress_count"
        case blockedCount = "blocked_count"
        case reviewCount = "review_count"
        case approvalCount = "approval_count"
        case runCount = "run_count"
        case staleCount = "stale_count"
    }
}

public struct OrcaBoardArchitectureHealth: Decodable, Hashable, Sendable {
    public let state: OrcaBoardHealthState
    public let reason: String
    public let observedAt: Date?
    public let freshness: OrcaBoardFreshnessState
    public let sourceChecks: [String]

    private enum CodingKeys: String, CodingKey {
        case state, reason, freshness
        case observedAt = "observed_at"
        case sourceChecks = "source_checks"
    }
}

public struct OrcaBoardArchitectureRelease: Decodable, Hashable, Sendable {
    public let revision: String
    public let artifactSHA256: String
    public let releaseManifestSHA256: String
    public let deployedAt: Date
    public let freshness: OrcaBoardFreshnessState
    public let evidenceRefs: [String]

    private enum CodingKeys: String, CodingKey {
        case revision, freshness
        case artifactSHA256 = "artifact_sha256"
        case releaseManifestSHA256 = "release_manifest_sha256"
        case deployedAt = "deployed_at"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(String.self, forKey: .revision)
        artifactSHA256 = try container.decode(String.self, forKey: .artifactSHA256)
        releaseManifestSHA256 = try container.decode(String.self, forKey: .releaseManifestSHA256)
        guard artifactSHA256.isLowercaseSHA256, releaseManifestSHA256.isLowercaseSHA256 else {
            throw DecodingError.dataCorruptedError(
                forKey: .artifactSHA256,
                in: container,
                debugDescription: "Invalid observed release SHA"
            )
        }
        deployedAt = try container.decode(Date.self, forKey: .deployedAt)
        freshness = try container.decode(OrcaBoardFreshnessState.self, forKey: .freshness)
        evidenceRefs = try container.decode([String].self, forKey: .evidenceRefs)
    }
}

public struct OrcaBoardArchitectureSource: Decodable, Hashable, Sendable {
    public let sourceType: String
    public let ref: String
    public let revision: String?
    public let observedAt: Date
    public let freshness: OrcaBoardFreshnessState

    private enum CodingKeys: String, CodingKey {
        case ref, revision, freshness
        case sourceType = "source_type"
        case observedAt = "observed_at"
    }
}

public struct OrcaBoardArchitectureHeader: Decodable, Hashable, Sendable {
    public let schemaVersion: String
    public let configSHA256: String
    public let generatedAt: Date
    public let boardID: UUID
    public let slug: String
    public let name: String
    public let groupID: UUID?
    public let groupSlug: String
    public let classification: OrcaBoardClassification
    public let lifecycleState: OrcaBoardLifecycleState
    public let isProtected: Bool
    public let publicSummary: String?
    public let healthState: OrcaBoardHealthState
    public let counts: OrcaBoardArchitectureCounts
    public let detailAvailable: Bool

    public var architectureGroup: OrcaBoardArchitectureGroup {
        switch groupSlug.lowercased() {
        case "products": return .products
        case "surfaces": return .surfaces
        case "platform": return .platform
        case "infrastructure": return .infrastructure
        case "fund": return .fund
        case "strategy": return .strategy
        default: return .other
        }
    }

    private enum CodingKeys: String, CodingKey {
        case slug, name, classification, protected, counts
        case schemaVersion = "schema_version"
        case configSHA256 = "config_sha256"
        case generatedAt = "generated_at"
        case boardID = "board_id"
        case groupID = "group_id"
        case groupSlug = "group_slug"
        case lifecycleState = "lifecycle_state"
        case publicSummary = "public_summary"
        case healthState = "health_state"
        case detailAvailable = "detail_available"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        guard schemaVersion == "orca.board-architecture-profile.v1" else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported board architecture profile schema"
            )
        }
        configSHA256 = try container.decode(String.self, forKey: .configSHA256)
        guard configSHA256.isLowercaseSHA256 else {
            throw DecodingError.dataCorruptedError(
                forKey: .configSHA256,
                in: container,
                debugDescription: "Invalid board architecture configuration SHA"
            )
        }
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        boardID = try container.decode(UUID.self, forKey: .boardID)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        groupSlug = try container.decode(String.self, forKey: .groupSlug)
        classification = try container.decode(OrcaBoardClassification.self, forKey: .classification)
        lifecycleState = try container.decode(OrcaBoardLifecycleState.self, forKey: .lifecycleState)
        isProtected = try container.decode(Bool.self, forKey: .protected)
        publicSummary = try container.decodeIfPresent(String.self, forKey: .publicSummary)
        healthState = try container.decode(OrcaBoardHealthState.self, forKey: .healthState)
        counts = try container.decode(OrcaBoardArchitectureCounts.self, forKey: .counts)
        detailAvailable = try container.decode(Bool.self, forKey: .detailAvailable)
    }
}

public struct OrcaBoardArchitectureFullProfile: Decodable, Hashable, Sendable {
    public let header: OrcaBoardArchitectureHeader
    public let purpose: String
    public let antiScope: String?
    public let objective: String?
    public let primaryAgent: String?
    public let deputyAgent: String?
    public let fallbackAgent: String?
    public let authorityTier: String?
    public let approvalPolicyRef: String?
    public let charterRef: String?
    public let runbookRefs: [String]?
    public let upstreamBoardIDs: [UUID]?
    public let downstreamBoardIDs: [UUID]?
    public let serviceNames: [String]?
    public let repositories: [String]?
    public let packages: [String]?
    public let endpoints: [String]?
    public let daemons: [String]?
    public let hostPlacements: [String]?
    public let dataStoreRefs: [String]?
    public let health: OrcaBoardArchitectureHealth
    public let currentRelease: OrcaBoardArchitectureRelease?
    public let currentProjectID: UUID?
    public let currentProjectName: String?
    public let nextGate: String?
    public let highestImpactBlocker: String?
    public let sourceRefs: [OrcaBoardArchitectureSource]

    private enum CodingKeys: String, CodingKey {
        case purpose, health, repositories, packages, endpoints, daemons
        case antiScope = "anti_scope"
        case objective
        case primaryAgent = "primary_agent"
        case deputyAgent = "deputy_agent"
        case fallbackAgent = "fallback_agent"
        case authorityTier = "authority_tier"
        case approvalPolicyRef = "approval_policy_ref"
        case charterRef = "charter_ref"
        case runbookRefs = "runbook_refs"
        case upstreamBoardIDs = "upstream_board_ids"
        case downstreamBoardIDs = "downstream_board_ids"
        case serviceNames = "service_names"
        case hostPlacements = "host_placements"
        case dataStoreRefs = "data_store_refs"
        case currentRelease = "current_release"
        case currentProjectID = "current_project_id"
        case currentProjectName = "current_project_name"
        case nextGate = "next_gate"
        case highestImpactBlocker = "highest_impact_blocker"
        case sourceRefs = "source_refs"
    }

    public init(from decoder: Decoder) throws {
        header = try OrcaBoardArchitectureHeader(from: decoder)
        let requiresProtectedPointer = header.classification == .protectedDomain
            || header.classification == .unknown
            || header.groupSlug.lowercased() == "fund"
            || header.slug.lowercased() == "fund"
        guard !header.isProtected, !requiresProtectedPointer, header.detailAvailable else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Full board profile violates protection contract")
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        purpose = try container.decode(String.self, forKey: .purpose)
        antiScope = try container.decodeIfPresent(String.self, forKey: .antiScope)
        objective = try container.decodeIfPresent(String.self, forKey: .objective)
        primaryAgent = try container.decodeIfPresent(String.self, forKey: .primaryAgent)
        deputyAgent = try container.decodeIfPresent(String.self, forKey: .deputyAgent)
        fallbackAgent = try container.decodeIfPresent(String.self, forKey: .fallbackAgent)
        authorityTier = try container.decodeIfPresent(String.self, forKey: .authorityTier)
        approvalPolicyRef = try container.decodeIfPresent(String.self, forKey: .approvalPolicyRef)
        charterRef = try container.decodeIfPresent(String.self, forKey: .charterRef)
        runbookRefs = try container.decodeIfPresent([String].self, forKey: .runbookRefs)
        upstreamBoardIDs = try container.decodeIfPresent([UUID].self, forKey: .upstreamBoardIDs)
        downstreamBoardIDs = try container.decodeIfPresent([UUID].self, forKey: .downstreamBoardIDs)
        serviceNames = try container.decodeIfPresent([String].self, forKey: .serviceNames)
        repositories = try container.decodeIfPresent([String].self, forKey: .repositories)
        packages = try container.decodeIfPresent([String].self, forKey: .packages)
        endpoints = try container.decodeIfPresent([String].self, forKey: .endpoints)
        daemons = try container.decodeIfPresent([String].self, forKey: .daemons)
        hostPlacements = try container.decodeIfPresent([String].self, forKey: .hostPlacements)
        dataStoreRefs = try container.decodeIfPresent([String].self, forKey: .dataStoreRefs)
        health = try container.decode(OrcaBoardArchitectureHealth.self, forKey: .health)
        guard health.state == header.healthState else {
            throw DecodingError.dataCorruptedError(
                forKey: .health,
                in: container,
                debugDescription: "Board health summary disagrees with signed health detail"
            )
        }
        currentRelease = try container.decodeIfPresent(OrcaBoardArchitectureRelease.self, forKey: .currentRelease)
        currentProjectID = try container.decodeIfPresent(UUID.self, forKey: .currentProjectID)
        currentProjectName = try container.decodeIfPresent(String.self, forKey: .currentProjectName)
        nextGate = try container.decodeIfPresent(String.self, forKey: .nextGate)
        highestImpactBlocker = try container.decodeIfPresent(String.self, forKey: .highestImpactBlocker)
        sourceRefs = try container.decode([OrcaBoardArchitectureSource].self, forKey: .sourceRefs)
    }
}

public struct OrcaBoardArchitectureProtectedProfile: Decodable, Hashable, Sendable {
    public let header: OrcaBoardArchitectureHeader

    public init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: OrcaAnyCodingKey.self).allKeys.map(\.stringValue)
        let allowed = Set([
            "schema_version", "config_sha256", "generated_at", "board_id", "slug", "name",
            "group_id", "group_slug", "classification", "lifecycle_state", "protected",
            "public_summary", "health_state", "counts", "detail_available", "visibility",
        ])
        guard keys.allSatisfy(allowed.contains) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Protected board pointer contains disallowed detail")
            )
        }
        header = try OrcaBoardArchitectureHeader(from: decoder)
        guard header.isProtected,
              !header.detailAvailable,
              header.publicSummary == nil,
              header.healthState == .unknown,
              header.counts.isRedacted else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Protected board pointer violates protection contract")
            )
        }
    }
}

public enum OrcaBoardArchitectureProfile: Decodable, Hashable, Sendable, Identifiable {
    case full(OrcaBoardArchitectureFullProfile)
    case protectedPointer(OrcaBoardArchitectureProtectedProfile)

    public var header: OrcaBoardArchitectureHeader {
        switch self {
        case let .full(profile): return profile.header
        case let .protectedPointer(profile): return profile.header
        }
    }

    public var id: UUID { header.boardID }

    public var fullProfile: OrcaBoardArchitectureFullProfile? {
        guard case let .full(profile) = self else { return nil }
        return profile
    }

    private enum CodingKeys: String, CodingKey { case visibility }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(OrcaBoardArchitectureVisibility.self, forKey: .visibility) {
        case .full:
            self = .full(try OrcaBoardArchitectureFullProfile(from: decoder))
        case .protectedPointer:
            self = .protectedPointer(try OrcaBoardArchitectureProtectedProfile(from: decoder))
        }
    }
}

public struct OrcaBoardArchitectureDirectory: Decodable, Hashable, Sendable {
    public let schemaVersion: String
    public let configSHA256: String
    public let generatedAt: Date
    public let profiles: [OrcaBoardArchitectureProfile]

    public var directoryItems: [OrcaBoardDirectoryItem] {
        profiles.map(OrcaBoardDirectoryItem.init(profile:))
    }

    private enum CodingKeys: String, CodingKey {
        case profiles
        case schemaVersion = "schema_version"
        case configSHA256 = "config_sha256"
        case generatedAt = "generated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        guard schemaVersion == "orca.board-architecture-directory.v1" else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported board architecture directory schema"
            )
        }
        configSHA256 = try container.decode(String.self, forKey: .configSHA256)
        guard configSHA256.isLowercaseSHA256 else {
            throw DecodingError.dataCorruptedError(
                forKey: .configSHA256,
                in: container,
                debugDescription: "Invalid board architecture directory SHA"
            )
        }
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        profiles = try container.decode([OrcaBoardArchitectureProfile].self, forKey: .profiles)
        guard profiles.allSatisfy({
            $0.header.configSHA256 == configSHA256 && $0.header.generatedAt == generatedAt
        }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .profiles,
                in: container,
                debugDescription: "Board profile configuration does not match its directory"
            )
        }
        guard Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map { $0.header.slug }).count == profiles.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .profiles,
                in: container,
                debugDescription: "Board architecture directory contains duplicate identities"
            )
        }
    }
}

private struct OrcaAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension String {
    var isLowercaseSHA256: Bool {
        utf8.count == 64 && utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
