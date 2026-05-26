import Foundation
import SwiftUI

@Observable
final class ArmsViewModel {
    var arms: [ArmTag] = ArmTag.placeholderArms
    var agents: [AgentSummary] = []
    var directiveDrafts: [String: String] = [:]
    var busyArms: Set<String> = []
    var isLoading = false
    var errorMessage: String?
    var toast: ArmsToast?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let armsTask: Void = loadArms()
        async let agentsTask: Void = loadAgents()
        _ = await (armsTask, agentsTask)
    }

    @MainActor
    func loadArms() async {
        do {
            let response: ArmTagsResponse = try await apiClient.get(path: "/api/v1/jarvis/arm-tags")
            let routingResponse: ArmRoutingResponse? = try? await apiClient.get(path: "/api/v1/jarvis/arm-routing")
            let routingByName = Dictionary(uniqueKeysWithValues: (routingResponse?.routing ?? []).map { ($0.arm.lowercased(), $0) })
            let liveByName = Dictionary(uniqueKeysWithValues: response.arms.map {
                ($0.name.lowercased(), $0.toDomain(routing: routingByName[$0.name.lowercased()]))
            })
            arms = ArmTag.canonicalNames.map { liveByName[$0] ?? ArmTag.placeholder(named: $0) }
        } catch {
            errorMessage = "Arms tags unavailable."
            arms = ArmTag.placeholderArms
        }
    }

    @MainActor
    func loadAgents() async {
        do {
            let response: PaginatedResponse<AgentSummaryDTO> = try await apiClient.get(path: "/api/v1/agents?status=active,support&limit=50")
            let mapped = response.items
                .map { $0.toDomain() }
                .filter { AgentRosterPolicy.isActiveOrSupport($0.agent) }
            agents = mapped.sorted { lhs, rhs in
                if lhs.macSortRank != rhs.macSortRank { return lhs.macSortRank < rhs.macSortRank }
                let lhsKey = AgentRosterPolicy.sortKey(for: lhs.name)
                let rhsKey = AgentRosterPolicy.sortKey(for: rhs.name)
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } catch {
            if errorMessage == nil {
                errorMessage = "Team unavailable."
            }
        }
    }

    @MainActor
    func startPolling() async {
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if Task.isCancelled { break }
            await load()
        }
    }

    @MainActor
    func postDirective(for arm: ArmTag) async {
        let key = arm.name.lowercased()
        let directive = (directiveDrafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directive.isEmpty, arm.canPostDirective else { return }
        busyArms.insert(key)
        defer { busyArms.remove(key) }

        do {
            let _: DirectiveResponse = try await apiClient.patch(
                path: "/api/v1/jarvis/arm-tags/\(key)/directive",
                body: DirectiveRequest(directive: directive, postedBy: "maui")
            )
            directiveDrafts[key] = ""
            toast = ArmsToast(message: "Directive queued", isError: false)
            await load()
        } catch {
            toast = ArmsToast(message: "Directive failed", isError: true)
        }
    }

    @MainActor
    func wake(_ arm: ArmTag, note: String = "") async {
        let key = arm.name.lowercased()
        guard arm.canWake else { return }
        busyArms.insert(key)
        defer { busyArms.remove(key) }

        do {
            let response: WakeResponse = try await apiClient.post(
                path: "/api/v1/jarvis/arm-tags/\(key)/wake",
                body: WakeRequest(postedBy: "maui", note: note.isEmpty ? nil : note)
            )
            toast = ArmsToast(message: response.toastMessage, isError: response.deliveryStatus == "failed")
            await load()
        } catch {
            toast = ArmsToast(message: "Wake failed", isError: true)
        }
    }

    func draftBinding(for arm: ArmTag) -> Binding<String> {
        let key = arm.name.lowercased()
        return Binding(
            get: { self.directiveDrafts[key] ?? "" },
            set: { self.directiveDrafts[key] = $0 }
        )
    }

    func isBusy(_ arm: ArmTag) -> Bool {
        busyArms.contains(arm.name.lowercased())
    }
}

struct ArmsToast: Equatable {
    let message: String
    let isError: Bool
}

struct AgentSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let glyph: String
    let status: AgentState
    let macLabel: String
    let currentFocus: String?
    let natsLaneOk: Bool
    let avatarColor: String
    let role: String
    let skills: [String]
    let rosterLane: AgentRosterLane

    var agent: Agent {
        Agent(
            id: id,
            name: name,
            role: role,
            status: status,
            currentTask: currentFocus,
            lastActivity: nil,
            skills: skills,
            avatarColor: avatarColor,
            rosterLane: rosterLane,
            isDefaultRoutingEnabled: true
        )
    }

    var macSortRank: Int {
        macLabel.lowercased().contains("chief") ? 1 : 0
    }

    var statusColor: Color {
        switch status {
        case .online, .busy, .idle: return AppColors.accentSuccess
        case .provisioning: return AppColors.accentWarning
        case .offline, .error: return AppColors.textTertiary
        }
    }
}

struct ArmTag: Identifiable, Hashable {
    static let canonicalNames = ["pod", "orca", "compute", "memory", "schoolhouse", "jarvis", "fund", "nats"]

    let id: String
    let name: String
    let state: String
    let currentWork: String
    let ticketRef: String?
    let evidenceRef: String?
    let blockedOn: String?
    let directive: String?
    let owner: String?
    let quality: String
    let updatedAt: Date?
    let ttlSeconds: Int?
    let source: String?
    let sourceDetail: String?
    let lastFetched: Date?
    let agentSubject: String?
    let workspace: String?
    let canWake: Bool
    let protected: Bool
    let protectionReason: String?
    let lastWakeDeliveryStatus: String?
    let lastWakeEnvelopeId: String?

    var displayName: String {
        switch name.lowercased() {
        case "pod": return "Pod Arm"
        case "orca": return "ORCA Arm"
        case "compute": return "Compute Arm"
        case "memory": return "Memory Arm"
        case "schoolhouse": return "Schoolhouse Arm"
        case "jarvis": return "Jarvis Arm"
        case "fund": return "Fund Arm"
        case "nats": return "NATS Arm"
        default: return name.capitalized + " Arm"
        }
    }

    var isFund: Bool { name.lowercased() == "fund" }

    var canPostDirective: Bool {
        canWake && !protected
    }

    var directivePlaceholder: String {
        canPostDirective ? "Post directive..." : manualOnlyTitle
    }

    var manualOnlyTitle: String {
        if let protectionReason, !protectionReason.isEmpty {
            return protectionReason
        }
        return "Manual only"
    }

    var sourceSummary: String {
        guard let source, !source.isEmpty else { return "unknown" }
        return sourceDetail.map { "\(source): \($0)" } ?? source
    }

    var routeSummary: String {
        guard let agentSubject, !agentSubject.isEmpty else { return "No wake route" }
        return workspace.map { "\(agentSubject) · \($0)" } ?? agentSubject
    }

    var wakeSummary: String {
        guard let lastWakeDeliveryStatus, !lastWakeDeliveryStatus.isEmpty else { return "No wake recorded" }
        if let lastWakeEnvelopeId, !lastWakeEnvelopeId.isEmpty {
            return "\(lastWakeDeliveryStatus) · \(String(lastWakeEnvelopeId.prefix(18)))"
        }
        return lastWakeDeliveryStatus
    }

    var freshnessLabel: String {
        guard let updatedAt else { return "unknown" }
        let age = Self.relativeAge(from: updatedAt)
        if let ttlSeconds, Date().timeIntervalSince(updatedAt) > Double(ttlSeconds) {
            return "stale · \(age)"
        }
        return "fresh · \(age)"
    }

    var stateLabel: String {
        state.replacingOccurrences(of: "_", with: " ")
    }

    var qualityColor: Color {
        switch quality.lowercased() {
        case "green": return AppColors.accentSuccess
        case "yellow": return AppColors.accentWarning
        case "red": return AppColors.accentDanger
        default: return AppColors.textTertiary
        }
    }

    var stateColor: Color {
        switch state.lowercased() {
        case "idle": return AppColors.textTertiary
        case "working": return AppColors.accentElectric
        case "blocked": return AppColors.accentDanger
        case "review_needed": return AppColors.accentWarning
        case "done": return AppColors.accentSuccess
        default: return AppColors.textTertiary
        }
    }

    static var placeholderArms: [ArmTag] {
        canonicalNames.map { placeholder(named: $0) }
    }

    static func placeholder(named name: String) -> ArmTag {
        ArmTag(
            id: name,
            name: name,
            state: "idle",
            currentWork: "Waiting for Jarvis tag data.",
            ticketRef: nil,
            evidenceRef: nil,
            blockedOn: nil,
            directive: nil,
            owner: "maui",
            quality: "yellow",
            updatedAt: nil,
            ttlSeconds: nil,
            source: nil,
            sourceDetail: nil,
            lastFetched: nil,
            agentSubject: nil,
            workspace: nil,
            canWake: name.lowercased() != "fund",
            protected: name.lowercased() == "fund",
            protectionReason: name.lowercased() == "fund" ? "Protected lane" : nil,
            lastWakeDeliveryStatus: nil,
            lastWakeEnvelopeId: nil
        )
    }

    private static func relativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}

private struct ArmTagsResponse: Decodable {
    let arms: [ArmTagDTO]
}

private struct ArmRoutingResponse: Decodable {
    let routing: [ArmRoutingEntryDTO]
}

private struct ArmRoutingEntryDTO: Decodable {
    let arm: String
    let agentSubject: String?
    let workspace: String?
    let canWake: Bool
    let protected: Bool
    let protectionReason: String?

    enum CodingKeys: String, CodingKey {
        case arm, workspace, protected
        case agentSubject = "agent_subject"
        case canWake = "can_wake"
        case protectionReason = "protection_reason"
    }
}

private struct AgentSummaryDTO: Codable {
    let id: String
    let name: String
    let glyph: String?
    let status: String?
    let macLabel: String?
    let currentFocus: String?
    let currentTask: String?
    let natsLaneOk: Bool?
    let avatarColor: String?
    let role: String?
    let rosterLane: String?
    let skills: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, glyph, status, role, skills
        case macLabel = "mac_label"
        case currentFocus = "current_focus"
        case currentTask
        case natsLaneOk = "nats_lane_ok"
        case avatarColor
        case rosterLane = "roster_lane"
    }

    func toDomain() -> AgentSummary {
        let normalized = AgentRosterPolicy.normalizedName(name)
        let resolvedStatus = AgentState(rawValue: status ?? "") ?? .offline
        let lane = rosterLane.flatMap(AgentRosterLane.init(rawValue:)) ?? AgentRosterPolicy.defaultLane(for: normalized)
        let fallback = AgentSummaryFallbacks.profile(for: normalized)
        return AgentSummary(
            id: UUID(uuidString: id) ?? UUID(),
            name: name.capitalized,
            glyph: AgentSummaryFallbacks.glyph(for: normalized),
            status: resolvedStatus,
            macLabel: macLabel ?? AgentSummaryFallbacks.macLabel(for: normalized),
            currentFocus: currentFocus ?? currentTask ?? fallback.focus,
            natsLaneOk: natsLaneOk ?? !(resolvedStatus == .offline || resolvedStatus == .error),
            avatarColor: avatarColor ?? fallback.color,
            role: role ?? fallback.role,
            skills: skills ?? fallback.skills,
            rosterLane: lane
        )
    }
}

private enum AgentSummaryFallbacks {
    static func glyph(for name: String) -> String {
        switch name {
        case "maui": return "🪝"
        case "aloha": return "🌸"
        case "coral": return "🪸"
        case "aurora": return "🌅"
        case "chief": return "🦅"
        case "rooster": return "🐓"
        case "reef": return "🐡"
        case "luna": return "🌙"
        default: return "•"
        }
    }

    static func macLabel(for name: String) -> String {
        switch name {
        case "chief", "rooster", "reef", "luna":
            return "Chief-mac"
        default:
            return "Shaka-mac"
        }
    }

    static func profile(for name: String) -> (role: String, skills: [String], color: String, focus: String?) {
        switch name {
        case "maui":
            return ("Head of Engineering", ["SwiftUI", "Architecture", "Pod"], "#22C55E", "Engineering coordination")
        case "aloha":
            return ("Communications", ["Specs", "Coordination", "Doctrine"], "#A855F7", "Coordination and specs")
        case "coral":
            return ("Support Runtime", ["Runtime Health", "Watchdogs"], "#06B6D4", "Runtime support")
        case "chief":
            return ("Protected Fund Lead", ["Research", "Finance"], "#22C55E", "Protected fund review")
        case "rooster":
            return ("Security", ["Security", "Guardrails"], "#EF4444", "Security guardrails")
        case "reef":
            return ("Chief Mac Support", ["Mirrors", "Chief Mac"], "#14B8A6", "Chief Mac support")
        case "aurora":
            return ("Dormant Advisor", ["Memory", "Coordination"], "#F59E0B", "Dormant advisor")
        case "luna":
            return ("Dormant Fund Analyst", ["Fund Analysis"], "#6366F1", "Dormant analyst")
        default:
            return ("Agent", [], "#3B82F6", nil)
        }
    }
}

private struct ArmTagDTO: Decodable {
    let name: String
    let tagData: ArmTagRecordDTO?

    enum CodingKeys: String, CodingKey {
        case name
        case tagData = "tag_data"
    }

    func toDomain(routing: ArmRoutingEntryDTO?) -> ArmTag {
        let data = tagData?.value
        return ArmTag(
            id: name.lowercased(),
            name: name.lowercased(),
            state: data?.state ?? "idle",
            currentWork: data?.currentWork ?? "No current work set.",
            ticketRef: data?.ticketRef,
            evidenceRef: data?.evidenceRef,
            blockedOn: data?.blockedOn,
            directive: data?.directive,
            owner: data?.owner,
            quality: data?.quality ?? tagData?.quality ?? "yellow",
            updatedAt: data?.updatedAt ?? tagData?.updatedAt,
            ttlSeconds: data?.ttlSeconds ?? tagData?.ttlSeconds,
            source: data?.source,
            sourceDetail: data?.sourceDetail,
            lastFetched: data?.lastFetched,
            agentSubject: routing?.agentSubject,
            workspace: routing?.workspace,
            canWake: routing?.canWake ?? (name.lowercased() != "fund"),
            protected: routing?.protected ?? (name.lowercased() == "fund"),
            protectionReason: routing?.protectionReason,
            lastWakeDeliveryStatus: data?.lastWakeDeliveryStatus,
            lastWakeEnvelopeId: data?.lastWakeEnvelopeId
        )
    }
}

private struct ArmTagRecordDTO: Decodable {
    let value: ArmTagDataDTO?
    let quality: String?
    let updatedAt: Date?
    let ttlSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case value, quality
        case updatedAt = "updated_at"
        case ttlSeconds = "ttl_s"
    }
}

private struct ArmTagDataDTO: Decodable {
    let state: String?
    let currentWork: String?
    let ticketRef: String?
    let evidenceRef: String?
    let blockedOn: String?
    let directive: String?
    let owner: String?
    let quality: String?
    let updatedAt: Date?
    let ttlSeconds: Int?
    let source: String?
    let sourceDetail: String?
    let lastFetched: Date?
    let lastWakeDeliveryStatus: String?
    let lastWakeEnvelopeId: String?

    enum CodingKeys: String, CodingKey {
        case state
        case currentWork = "current_work"
        case ticketRef = "ticket_ref"
        case evidenceRef = "evidence_ref"
        case blockedOn = "blocked_on"
        case directive
        case owner
        case quality
        case updatedAt = "updated_at"
        case ttlSeconds = "ttl_s"
        case source
        case sourceDetail = "source_detail"
        case lastFetched = "last_fetched"
        case lastWakeDeliveryStatus = "last_wake_delivery_status"
        case lastWakeEnvelopeId = "last_wake_envelope_id"
    }
}

private struct DirectiveRequest: Encodable {
    let directive: String
    let postedBy: String

    enum CodingKeys: String, CodingKey {
        case directive
        case postedBy = "posted_by"
    }
}

private struct DirectiveResponse: Decodable {
    let updated: Bool?
    let arm: String?
    let directive: String?
}

private struct WakeRequest: Encodable {
    let postedBy: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case postedBy = "posted_by"
        case note
    }
}

private struct WakeResponse: Decodable {
    let dispatched: Bool
    let envelopeId: String?
    let arm: String?
    let contextSummary: String?
    let deliveryStatus: String?

    enum CodingKeys: String, CodingKey {
        case dispatched, arm
        case envelopeId = "envelope_id"
        case contextSummary = "context_summary"
        case deliveryStatus = "delivery_status"
    }

    var toastMessage: String {
        switch deliveryStatus {
        case "confirmed":
            return "Wake delivered"
        case "failed":
            return "Wake failed"
        case "unconfirmed":
            return "Wake unconfirmed"
        default:
            return dispatched ? "Wake dispatched" : "Wake queued"
        }
    }
}
