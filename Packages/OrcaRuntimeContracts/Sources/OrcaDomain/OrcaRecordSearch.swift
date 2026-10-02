import Foundation

/// Search only fields supplied by the authorized server response.
public enum OrcaRecordSearch {
    public static func matches(_ query: String, values: [String?]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !needle.isEmpty else { return true }
        return values.compactMap { $0 }.contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// Read-only projection of the existing All Agents lens. No decision action.
public struct OrcaApprovalDiscovery: Decodable, Sendable {
    public struct Group: Decodable, Sendable {
        public let name: String
        public let items: [Item]
    }
    public struct Item: Decodable, Identifiable, Sendable {
        public let id: String
        public let kind: String
        public let title: String
        public let authority: String?
        public let approvalID: String?
        public let linkedTicketIDs: [String]
        public let status: String
        enum CodingKeys: String, CodingKey {
            case id, kind, title, authority, status
            case approvalID = "approval_id"
            case linkedTicketIDs = "linked_ticket_ids"
        }
    }
    public let groups: [Group]
    public var pendingApprovals: [Item] {
        var seen = Set<String>()
        return groups.flatMap(\.items).filter {
            $0.kind == "approval" && $0.status == "pending" && seen.insert($0.approvalID ?? $0.id).inserted
        }
    }
}
