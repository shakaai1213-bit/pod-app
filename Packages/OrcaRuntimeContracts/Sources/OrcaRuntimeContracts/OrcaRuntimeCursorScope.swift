import CryptoKit
import Foundation

public struct OrcaRuntimeCursorScope: Equatable, Hashable, Sendable {
    public let origin: String
    public let organizationID: String
    public let agentKey: String
    public let turnID: String

    public init?(
        origin: String,
        organizationID: String,
        agentKey: String,
        turnID: String
    ) {
        guard let url = URL(string: origin),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              ["http", "https"].contains(scheme),
              UUID(uuidString: organizationID) != nil,
              UUID(uuidString: turnID) != nil else {
            return nil
        }
        let normalizedAgent = agentKey.lowercased()
        guard !normalizedAgent.isEmpty,
              normalizedAgent.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" }) else {
            return nil
        }
        let port = url.port.map { ":\($0)" } ?? ""
        let path = url.path == "/" ? "" : url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.origin = "\(scheme)://\(host)\(port)\(path.isEmpty ? "" : "/\(path)")"
        self.organizationID = organizationID.lowercased()
        self.agentKey = normalizedAgent
        self.turnID = turnID.lowercased()
    }

    public var storageKey: String {
        let material = "\(origin)\n\(organizationID)\n\(agentKey)\n\(turnID)"
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "orca.runtime.reconciliation-cursor.v1.\(digest)"
    }
}

public final class OrcaRuntimeCursorStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func cursor(for scope: OrcaRuntimeCursorScope) -> String? {
        lock.withLock {
            defaults.string(forKey: scope.storageKey)
        }
    }

    public func store(_ cursor: String, for scope: OrcaRuntimeCursorScope) {
        lock.withLock {
            defaults.set(cursor, forKey: scope.storageKey)
        }
    }

    public func removeCursor(for scope: OrcaRuntimeCursorScope) {
        lock.withLock {
            defaults.removeObject(forKey: scope.storageKey)
        }
    }
}
