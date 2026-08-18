import Foundation
import OrcaDomain
import OrcaRuntimeContracts

public enum OrcaRuntimeProjectionError: Error, Equatable, LocalizedError {
    case incompleteRoster(expected: Set<String>, actual: Set<String>)
    case duplicateAgent(String)

    public var errorDescription: String? {
        switch self {
        case let .incompleteRoster(expected, actual):
            return "ORCA Agent Packs do not match the seven-agent roster (expected \(expected.sorted()), received \(actual.sorted()))."
        case let .duplicateAgent(agentID):
            return "ORCA Agent Packs contain duplicate agent \(agentID)."
        }
    }
}

public struct OrcaRuntimeAgent: Identifiable, Equatable, Sendable {
    public let profile: OrcaAgentProfile
    public let runtimeHost: String
    public let runtimePosture: String
    public let supportedAdapterIDs: [String]
    public let configurationSHA256: String

    public var id: String { profile.id }
}

public enum OrcaRuntimeProjection {
    public static func agents(
        from bundle: Components.Schemas.ChatRuntimeAgentPackBundleRead
    ) throws -> [OrcaRuntimeAgent] {
        let ids = bundle.packs.map { $0.agentKey.lowercased() }
        guard Set(ids).count == ids.count else {
            let duplicate = ids.first { id in ids.filter { $0 == id }.count > 1 } ?? "unknown"
            throw OrcaRuntimeProjectionError.duplicateAgent(duplicate)
        }
        let actual = Set(ids)
        let expected = OrcaAgentProfile.ids
        guard actual == expected else {
            throw OrcaRuntimeProjectionError.incompleteRoster(expected: expected, actual: actual)
        }
        let packs = Dictionary(uniqueKeysWithValues: bundle.packs.map { ($0.agentKey.lowercased(), $0) })
        return OrcaAgentProfile.fallbackRoster.compactMap { profile in
            guard let pack = packs[profile.id] else { return nil }
            return OrcaRuntimeAgent(
                profile: profile,
                runtimeHost: pack.runtimeHost.rawValue,
                runtimePosture: pack.runtimePosture,
                supportedAdapterIDs: pack.supportedAdapterIds.sorted(),
                configurationSHA256: pack.payloadSha256
            )
        }
    }

    public static func profiles(
        from bundle: Components.Schemas.ChatRuntimeAgentPackBundleRead
    ) throws -> [OrcaAgentProfile] {
        try agents(from: bundle).map(\.profile)
    }
}
