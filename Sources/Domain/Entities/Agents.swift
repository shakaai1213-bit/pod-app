import Foundation
import SwiftUI

// MARK: - Agent

struct Agent: Identifiable {
    var id: UUID
    var name: String
    var role: String
    var status: AgentState
    var currentTask: String?
    var lastActivity: Date?
    var skills: [String]
    var avatarColor: String?
    var rosterLane: AgentRosterLane
    var isDefaultRoutingEnabled: Bool
    var quarantineState: String?
    var rosterNote: String?

    init(
        id: UUID,
        name: String,
        role: String,
        status: AgentState,
        currentTask: String? = nil,
        lastActivity: Date? = nil,
        skills: [String] = [],
        avatarColor: String? = nil,
        rosterLane: AgentRosterLane? = nil,
        isDefaultRoutingEnabled: Bool? = nil,
        quarantineState: String? = nil,
        rosterNote: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.status = status
        self.currentTask = currentTask
        self.lastActivity = lastActivity
        self.skills = skills
        self.avatarColor = avatarColor
        let resolvedLane = rosterLane ?? AgentRosterPolicy.defaultLane(for: name)
        self.rosterLane = resolvedLane
        self.isDefaultRoutingEnabled = isDefaultRoutingEnabled ?? (resolvedLane != .dormantArchive)
        self.quarantineState = quarantineState
        self.rosterNote = rosterNote
    }
}

extension Agent: Codable {}
extension Agent: Hashable {}

// MARK: - Agent Roster Policy

enum AgentRosterLane: String, Codable, CaseIterable {
    case activeMain = "active_main"
    case supportRuntime = "support_runtime"
    case dormantArchive = "dormant_archive"
    case unknown

    var label: String {
        switch self {
        case .activeMain: return "Active Main"
        case .supportRuntime: return "Support Runtime"
        case .dormantArchive: return "Archived"
        case .unknown: return "Review"
        }
    }
}

enum AgentRosterPolicy {
    static let activeDisplayOrder = ["maui", "aloha", "chief", "rooster", "coral", "reef"]
    static let dormantDisplayOrder = ["aurora", "shaka-agent", "shaka", "luna"]
    static let supportRuntimeNames: Set<String> = ["coral", "reef"]

    private static let activeNames = Set(activeDisplayOrder)
    private static let dormantNames = Set(dormantDisplayOrder)

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isActiveOrSupport(_ name: String) -> Bool {
        activeNames.contains(normalizedName(name))
    }

    static func defaultLane(for name: String) -> AgentRosterLane {
        let normalized = normalizedName(name)
        if dormantNames.contains(normalized) {
            return .dormantArchive
        }
        if supportRuntimeNames.contains(normalized) {
            return .supportRuntime
        }
        if activeNames.contains(normalized) {
            return .activeMain
        }
        return .unknown
    }

    static func isActiveOrSupport(_ agent: Agent) -> Bool {
        agent.rosterLane == .activeMain || agent.rosterLane == .supportRuntime
    }

    static func isDormantOrArchived(_ name: String) -> Bool {
        dormantNames.contains(normalizedName(name))
    }

    static func isDormantOrArchived(_ agent: Agent) -> Bool {
        agent.rosterLane == .dormantArchive || isDormantOrArchived(agent.name)
    }

    static func sortKey(for name: String) -> Int {
        activeDisplayOrder.firstIndex(of: normalizedName(name)) ?? Int.max
    }

    static func dormantSortKey(for name: String) -> Int {
        dormantDisplayOrder.firstIndex(of: normalizedName(name)) ?? Int.max
    }

    static func filterActive(_ agents: [Agent]) -> [Agent] {
        agents
            .filter { isActiveOrSupport($0) }
            .sorted { lhs, rhs in
                let lhsKey = laneSortKey(lhs.rosterLane)
                let rhsKey = laneSortKey(rhs.rosterLane)
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    static func filterDormant(_ agents: [Agent]) -> [Agent] {
        agents
            .filter { isDormantOrArchived($0) }
            .sorted { lhs, rhs in
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func laneSortKey(_ lane: AgentRosterLane) -> Int {
        switch lane {
        case .activeMain: return 0
        case .supportRuntime: return 1
        case .unknown: return 2
        case .dormantArchive: return 3
        }
    }
}

// MARK: - Agent Status

enum AgentState: String, Codable, CaseIterable {
    case online
    case busy
    case idle
    case offline
    case error
    case provisioning

    var displayName: String {
        switch self {
        case .provisioning: return "Provisioning"
        default: return rawValue.capitalized
        }
    }

    var isAvailable: Bool {
        self == .online || self == .idle
    }
}
