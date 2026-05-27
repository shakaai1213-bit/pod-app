import Foundation
import SwiftUI

@Observable
final class ArmsViewModel {
    var arms: [ArmTag] = ArmTag.placeholderArms
    var chiefArms: [ArmTag] = ArmTag.placeholderChiefArms
    var directiveDrafts: [String: String] = [:]
    var expandedShipArms: Set<String> = []
    var shipHistoryByArm: [String: [ArmShip]] = [:]
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

        await loadArms()
    }

    @MainActor
    func loadArms() async {
        async let mauiTask: Void = loadMauiArms()
        async let chiefTask: Void = loadChiefArms()
        _ = await (mauiTask, chiefTask)
    }

    @MainActor
    private func loadMauiArms() async {
        do {
            let response: ArmTagsResponse = try await apiClient.get(path: "/api/v1/jarvis/arm-tags")
            let rosterResponse: ArmRosterResponse? = try? await apiClient.get(path: "/api/v1/jarvis/arm-roster")
            let rosterByName = Dictionary(uniqueKeysWithValues: (rosterResponse?.arms ?? []).map { ($0.name.lowercased(), $0) })
            let routingByName = Dictionary(uniqueKeysWithValues: (rosterResponse?.arms ?? []).map { ($0.name.lowercased(), $0.toRouting()) })
            let directivesResponse: ArmDirectivesResponse? = try? await apiClient.get(path: "/api/v1/jarvis/arm-directives")
            let directivesByName = Dictionary(uniqueKeysWithValues: (directivesResponse?.directives ?? []).map { ($0.name.lowercased(), $0.toDomain()) })
            var shipsByName: [String: [ArmShip]] = [:]
            let names = Self.rosterNames(
                response: response,
                roster: rosterResponse?.arms,
                family: .maui,
                fallback: ArmTag.mauiNames
            )
            for arm in names {
                shipsByName[arm] = (try? await loadShips(forKey: arm, limit: 5)) ?? []
            }
            shipHistoryByArm.merge(shipsByName) { _, new in new }
            let liveByName = Dictionary(uniqueKeysWithValues: response.arms.map {
                let key = $0.name.lowercased()
                let arm = $0.toDomain(roster: rosterByName[key], routing: routingByName[key], directive: directivesByName[key], fallbackLastShip: shipsByName[key]?.first)
                return (arm.name.lowercased(), arm)
            })
            arms = names.map { liveByName[$0] ?? ArmTag.placeholder(named: $0, family: .maui, roster: rosterByName[$0], routing: routingByName[$0]) }
        } catch {
            errorMessage = "Arms tags unavailable."
            arms = ArmTag.placeholderArms
        }
    }

    @MainActor
    private func loadChiefArms() async {
        do {
            let response: ArmStateRegistryResponse = try await apiClient.get(path: "/api/v1/state-registry?prefix=chief_arm.&limit=100")
            let statusByName = Dictionary(uniqueKeysWithValues: response.items.compactMap { item -> (String, StateRegistryTagDTO)? in
                guard item.tagId.hasPrefix("chief_arm."), item.tagId.hasSuffix(".status") else { return nil }
                return (item.armName(suffix: ".status"), item)
            })
            let directivesByName = Dictionary(uniqueKeysWithValues: response.items.compactMap { item -> (String, ArmDirective)? in
                guard item.tagId.hasPrefix("chief_arm."), item.tagId.hasSuffix(".directive") else { return nil }
                return (item.armName(suffix: ".directive"), item.toDirective())
            })
            let rosterResponse: ArmRosterResponse? = try? await apiClient.get(path: "/api/v1/jarvis/arm-roster")
            let rosterByName = Dictionary(uniqueKeysWithValues: (rosterResponse?.arms ?? []).map { ($0.name.lowercased(), $0) })
            let routingByName = Dictionary(uniqueKeysWithValues: (rosterResponse?.arms ?? []).map { ($0.name.lowercased(), $0.toRouting()) })
            let names = Self.rosterNames(
                statusNames: Array(statusByName.keys),
                roster: rosterResponse?.arms,
                family: .chief,
                fallback: ArmTag.chiefNames
            )
            var shipsByName: [String: [ArmShip]] = [:]
            for arm in names {
                shipsByName[arm] = (try? await loadShips(forKey: arm, limit: 5)) ?? []
            }
            shipHistoryByArm.merge(shipsByName) { _, new in new }
            chiefArms = names.map { name in
                statusByName[name]?.toArmTag(
                    name: name,
                    roster: rosterByName[name],
                    directive: directivesByName[name],
                    fallbackLastShip: shipsByName[name]?.first
                ) ?? ArmTag.placeholder(named: name, family: .chief, roster: rosterByName[name], routing: routingByName[name])
            }
        } catch {
            chiefArms = ArmTag.placeholderChiefArms
        }
    }

    private static func rosterNames(
        response: ArmTagsResponse,
        roster: [ArmRosterEntryDTO]?,
        family: ArmFamily,
        fallback: [String]
    ) -> [String] {
        let statusNames = response.arms
            .map(\.name)
            .map { $0.lowercased() }
        return rosterNames(statusNames: statusNames, roster: roster, family: family, fallback: fallback)
    }

    private static func rosterNames(
        statusNames: [String],
        roster: [ArmRosterEntryDTO]?,
        family: ArmFamily,
        fallback: [String]
    ) -> [String] {
        var seen: Set<String> = []
        let rosterNames = (roster ?? [])
            .filter { $0.family == family && $0.status.lowercased() != "retired" }
            .map { $0.name.lowercased() }
        let liveNames = statusNames.filter { family == .chief ? $0.hasPrefix("chief-") : !$0.hasPrefix("chief-") }
        let candidates = rosterNames + liveNames
        let source = candidates.isEmpty ? fallback : candidates
        let preferred = family == .chief ? ArmTag.chiefNames : ArmTag.mauiNames
        return source
            .filter { seen.insert($0).inserted }
            .sorted { lhs, rhs in
                let lhsIndex = preferred.firstIndex(of: lhs) ?? Int.max
                let rhsIndex = preferred.firstIndex(of: rhs) ?? Int.max
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return lhs < rhs
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
            let response: ArmDirectiveWriteResponse = try await apiClient.put(
                path: "/api/v1/jarvis/arm-directives/\(key)",
                body: ArmDirectiveCreateRequest(directive: directive, postedBy: "maui")
            )
            directiveDrafts[key] = ""
            toast = ArmsToast(message: response.toastMessage, isError: false)
            await load()
        } catch {
            toast = ArmsToast(message: "Directive failed", isError: true)
        }
    }

    @MainActor
    func greenLight(_ arm: ArmTag) async {
        let key = arm.name.lowercased()
        guard arm.canGreenLight else { return }
        busyArms.insert(key)
        defer { busyArms.remove(key) }

        do {
            let _: ArmDirectiveWriteResponse? = try? await apiClient.patch(
                path: "/api/v1/jarvis/arm-directives/\(key)/status",
                body: ArmDirectiveStatusPatchRequest(
                    status: nil,
                    intentState: "green_lit",
                    reportedBy: "tony",
                    note: "Green Light from Pod"
                )
            )
            let response: WakeResponse = try await apiClient.post(
                path: "/api/v1/jarvis/arm-tags/\(key)/wake",
                body: WakeRequest(postedBy: "tony", note: arm.directive)
            )
            toast = ArmsToast(message: response.toastMessage, isError: response.deliveryStatus == "failed")
            await load()
        } catch {
            toast = ArmsToast(message: "Green Light failed", isError: true)
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

    @MainActor
    func toggleShips(for arm: ArmTag) async {
        let key = arm.name.lowercased()
        if expandedShipArms.contains(key) {
            expandedShipArms.remove(key)
            return
        }
        expandedShipArms.insert(key)
        if shipHistoryByArm[key] == nil {
            await loadShips(for: arm)
        }
    }

    func isShipsExpanded(_ arm: ArmTag) -> Bool {
        expandedShipArms.contains(arm.name.lowercased())
    }

    func ships(for arm: ArmTag) -> [ArmShip] {
        shipHistoryByArm[arm.name.lowercased()] ?? arm.lastShip.map { [$0] } ?? []
    }

    @MainActor
    private func loadShips(for arm: ArmTag) async {
        let key = arm.name.lowercased()
        do {
            shipHistoryByArm[key] = try await loadShips(forKey: key, limit: 5)
        } catch {
            shipHistoryByArm[key] = arm.lastShip.map { [$0] } ?? []
        }
    }

    private func loadShips(forKey key: String, limit: Int) async throws -> [ArmShip] {
        let response: ArmShipsResponse = try await apiClient.get(path: "/api/v1/jarvis/arm-ships?arm=\(key)&limit=\(limit)")
        return response.ships.map { $0.toDomain(fallbackArm: key) }
    }
}

struct ArmsToast: Equatable {
    let message: String
    let isError: Bool
}

struct ArmTag: Identifiable, Hashable {
    static let mauiNames = ["architecture", "pod", "orca", "compute", "memory", "schoolhouse", "jarvis", "nats", "fish", "fund", "surfaces"]
    static let chiefNames = ["chief-research", "chief-data", "chief-predictions", "chief-ml", "chief-trading", "chief-algos", "chief-fund"]

    let id: String
    let name: String
    let family: ArmFamily
    let displayNameOverride: String?
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
    let directiveStatus: String?
    let directiveDoneAt: Date?
    let directivePostedBy: String?
    let directiveTraceId: String?
    let proposedByArm: Bool
    let intentState: String?
    let needsEngagement: Bool
    let needsEngagementReason: String?
    let lastShip: ArmShip?

    var displayName: String {
        if let displayNameOverride, !displayNameOverride.isEmpty {
            return displayNameOverride
        }
        switch name.lowercased() {
        case "architecture": return "Architecture Arm"
        case "pod": return "Pod Arm"
        case "orca": return "ORCA Arm"
        case "compute": return "Compute Arm"
        case "memory": return "Memory Arm"
        case "schoolhouse": return "Schoolhouse Arm"
        case "jarvis": return "Jarvis Arm"
        case "fund": return "Fund Arm"
        case "nats": return "NATS Arm"
        case "fish": return "Fish Arm"
        case "surfaces": return "Surfaces Arm"
        case "chief-trading": return "Chief Trading Arm"
        case "chief-fund": return "Chief Fund Arm"
        case "chief-predictions": return "Chief Predictions Arm"
        case "chief-mac-infra": return "Chief Mac Infra Arm"
        case "chief-data": return "Chief Data Arm"
        case "chief-research": return "Chief Research Arm"
        default: return name.capitalized + " Arm"
        }
    }

    var isFund: Bool { name.lowercased() == "fund" }

    var canPostDirective: Bool {
        canWake && !protected
    }

    var canGreenLight: Bool {
        canWake && !protected && proposedByArm && intentState?.lowercased() == "proposed" && directive?.isEmpty == false
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

    var directiveStatusLabel: String {
        if let intentState, !intentState.isEmpty, intentState.lowercased() != "green_lit" {
            return intentState.replacingOccurrences(of: "_", with: " ")
        }
        guard let directiveStatus, !directiveStatus.isEmpty else {
            return directive?.isEmpty == false ? "queued" : "none"
        }
        return directiveStatus.replacingOccurrences(of: "_", with: " ")
    }

    var directiveStatusColor: Color {
        switch intentState?.lowercased() {
        case "proposed":
            return AppColors.accentElectric
        case "reviewed":
            return AppColors.accentWarning
        default:
            break
        }
        switch directiveStatus?.lowercased() {
        case "completed":
            return AppColors.accentSuccess
        case "blocked", "cancelled":
            return AppColors.accentDanger
        case "in_progress", "received":
            return AppColors.accentWarning
        default:
            return directive?.isEmpty == false ? AppColors.accentElectric : AppColors.textTertiary
        }
    }

    var freshnessLabel: String {
        guard let updatedAt else { return "unknown" }
        let age = Self.relativeAge(from: updatedAt)
        if let ttlSeconds, Date().timeIntervalSince(updatedAt) > Double(ttlSeconds) {
            return "stale · \(age)"
        }
        return "fresh · \(age)"
    }

    var lastShipLabel: String {
        guard let lastShip else { return "No ships recorded" }
        return "\(lastShip.subject) · \(Self.relativeAge(from: lastShip.timestamp))"
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
        mauiNames.map { placeholder(named: $0, family: .maui) }
    }

    static var placeholderChiefArms: [ArmTag] {
        chiefNames.map { placeholder(named: $0, family: .chief) }
    }

    fileprivate static func placeholder(
        named name: String,
        family: ArmFamily = .maui,
        roster: ArmRosterEntryDTO? = nil,
        routing: ArmRoutingEntryDTO? = nil
    ) -> ArmTag {
        let isProtectedFund = name.lowercased() == "fund" || name.lowercased() == "chief-fund"
        return ArmTag(
            id: "\(family.rawValue)-\(name)",
            name: name,
            family: family,
            displayNameOverride: roster?.displayName,
            state: "idle",
            currentWork: "Waiting for Jarvis tag data.",
            ticketRef: nil,
            evidenceRef: nil,
            blockedOn: nil,
            directive: nil,
            owner: roster?.owner ?? (family == .chief ? "chief" : "maui"),
            quality: "yellow",
            updatedAt: nil,
            ttlSeconds: nil,
            source: nil,
            sourceDetail: nil,
            lastFetched: nil,
            agentSubject: roster?.agentSubject ?? routing?.agentSubject,
            workspace: roster?.workspace ?? routing?.workspace,
            canWake: roster?.canWake ?? routing?.canWake ?? !isProtectedFund,
            protected: roster?.protected ?? routing?.protected ?? isProtectedFund,
            protectionReason: roster?.protectionReason ?? routing?.protectionReason ?? (isProtectedFund ? "Tier-4 protected lane" : nil),
            lastWakeDeliveryStatus: nil,
            lastWakeEnvelopeId: nil,
            directiveStatus: nil,
            directiveDoneAt: nil,
            directivePostedBy: nil,
            directiveTraceId: nil,
            proposedByArm: false,
            intentState: nil,
            needsEngagement: false,
            needsEngagementReason: nil,
            lastShip: nil
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

enum ArmFamily: String, CaseIterable, Identifiable {
    case maui
    case chief

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maui: return "Maui Arms"
        case .chief: return "Chief Arms"
        }
    }
}

private extension AgentRunJSONValue {
    var stringValue: String? {
        switch self {
        case .string(let text):
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        case .int(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let text):
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        case .string(let text):
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}

struct ArmShip: Identifiable, Hashable, Decodable {
    let arm: String
    let subject: String
    let timestamp: Date
    let sha: String
    let area: String
    let gate: String
    let alohaReviewStatus: String
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case arm, subject, timestamp, sha, area, gate, tag
        case alohaReviewStatus = "aloha_review_status"
    }

    init(
        arm: String,
        subject: String,
        timestamp: Date,
        sha: String,
        area: String,
        gate: String,
        alohaReviewStatus: String,
        tag: String?
    ) {
        self.arm = arm
        self.subject = subject
        self.timestamp = timestamp
        self.sha = sha
        self.area = area
        self.gate = gate
        self.alohaReviewStatus = alohaReviewStatus
        self.tag = tag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.arm = (try? container.decode(String.self, forKey: .arm)) ?? ""
        self.subject = try container.decode(String.self, forKey: .subject)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.sha = (try? container.decode(String.self, forKey: .sha)) ?? "WORKTREE"
        self.area = (try? container.decode(String.self, forKey: .area)) ?? "ORCA"
        self.gate = (try? container.decode(String.self, forKey: .gate)) ?? "follow-on"
        self.alohaReviewStatus = (try? container.decode(String.self, forKey: .alohaReviewStatus)) ?? "pending"
        self.tag = try? container.decode(String.self, forKey: .tag)
    }

    func resolvedArm(_ fallback: String) -> ArmShip {
        guard arm.isEmpty else { return self }
        return ArmShip(
            arm: fallback,
            subject: subject,
            timestamp: timestamp,
            sha: sha,
            area: area,
            gate: gate,
            alohaReviewStatus: alohaReviewStatus,
            tag: tag
        )
    }

    var id: String {
        "\(arm)-\(timestamp.timeIntervalSince1970)-\(sha)-\(subject)"
    }

    var reviewLabel: String {
        alohaReviewStatus.replacingOccurrences(of: "_", with: " ")
    }

    var reviewColor: Color {
        switch alohaReviewStatus.lowercased() {
        case "acked":
            return AppColors.accentSuccess
        case "revision_requested":
            return AppColors.accentDanger
        default:
            return AppColors.accentWarning
        }
    }
}

private struct ArmTagsResponse: Decodable {
    let arms: [ArmTagDTO]
}

private struct ArmShipsResponse: Decodable {
    let ships: [ArmShipDTO]
}

private struct ArmShipDTO: Decodable {
    let arm: String?
    let subject: String
    let timestamp: Date
    let sha: String?
    let area: String?
    let gate: String?
    let alohaReviewStatus: String?
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case arm, subject, timestamp, sha, area, gate, tag
        case alohaReviewStatus = "aloha_review_status"
    }

    func toDomain(fallbackArm: String) -> ArmShip {
        ArmShip(
            arm: arm ?? fallbackArm,
            subject: subject,
            timestamp: timestamp,
            sha: sha ?? "WORKTREE",
            area: area ?? "ORCA",
            gate: gate ?? "follow-on",
            alohaReviewStatus: alohaReviewStatus ?? "pending",
            tag: tag
        )
    }
}

private struct ArmDirectivesResponse: Decodable {
    let directives: [ArmDirectiveDTO]
}

private struct ArmRosterResponse: Decodable {
    let arms: [ArmRosterEntryDTO]
}

private struct ArmRosterEntryDTO: Decodable {
    let name: String
    let familyRaw: String
    let namespace: String?
    let tag: String?
    let displayName: String?
    let owner: String?
    let agentSubject: String?
    let workspace: String?
    let canWake: Bool
    let protected: Bool
    let protectionReason: String?
    let status: String
    let sortOrder: Int?
    let area: String?
    let board: String?

    enum CodingKeys: String, CodingKey {
        case name, namespace, tag, owner, workspace, protected, status, area, board
        case familyRaw = "family"
        case displayName = "display_name"
        case agentSubject = "agent_subject"
        case canWake = "can_wake"
        case protectionReason = "protection_reason"
        case sortOrder = "sort_order"
    }

    var family: ArmFamily {
        familyRaw == "chief" ? .chief : .maui
    }

    func toRouting() -> ArmRoutingEntryDTO {
        ArmRoutingEntryDTO(
            arm: name,
            agentSubject: agentSubject,
            workspace: workspace,
            canWake: canWake,
            protected: protected,
            protectionReason: protectionReason
        )
    }
}

private struct ArmStateRegistryResponse: Decodable {
    let items: [StateRegistryTagDTO]
}

private struct StateRegistryTagDTO: Decodable {
    let tagId: String
    let value: [String: AgentRunJSONValue]
    let quality: String?
    let updatedAt: Date?
    let ttlSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case value, quality
        case tagId = "tag_id"
        case updatedAt = "updated_at"
        case ttlSeconds = "ttl_seconds"
    }

    func armName(suffix: String) -> String {
        tagId
            .replacingOccurrences(of: "chief_arm.", with: "")
            .replacingOccurrences(of: suffix, with: "")
            .lowercased()
    }

    func toDirective() -> ArmDirective {
        ArmDirective(
            name: armName(suffix: ".directive"),
            tag: tagId,
            directive: string("directive"),
            status: string("directive_status") ?? string("status"),
            postedBy: string("posted_by"),
            note: string("note"),
            traceId: string("trace_id"),
            doneAt: date("done_at"),
            proposedByArm: bool("proposed_by_arm"),
            intentState: string("intent_state"),
            needsEngagement: bool("needs_engagement") ?? false,
            needsEngagementReason: string("needs_engagement_reason")
        )
    }

    func toArmTag(name: String, roster: ArmRosterEntryDTO?, directive: ArmDirective?, fallbackLastShip: ArmShip?) -> ArmTag {
        let isChiefFund = name == "chief-fund"
        return ArmTag(
            id: "chief-\(name)",
            name: name,
            family: .chief,
            displayNameOverride: roster?.displayName,
            state: string("state") ?? "idle",
            currentWork: string("current_work") ?? "No current work set.",
            ticketRef: string("ticket_ref"),
            evidenceRef: string("evidence_ref"),
            blockedOn: string("blocked_on"),
            directive: directive?.directive ?? string("directive"),
            owner: roster?.owner ?? string("owner") ?? "chief",
            quality: string("quality") ?? quality ?? "yellow",
            updatedAt: date("updated_at") ?? updatedAt,
            ttlSeconds: int("ttl_s") ?? ttlSeconds,
            source: string("source"),
            sourceDetail: string("source_detail"),
            lastFetched: date("last_fetched"),
            agentSubject: roster?.agentSubject ?? "agents.chief.inbox",
            workspace: roster?.workspace,
            canWake: false,
            protected: roster?.protected ?? isChiefFund,
            protectionReason: isChiefFund ? "Tier-4: Chief/Rooster/Tony approval required" : "Chief-controlled lane; Maui view only",
            lastWakeDeliveryStatus: string("last_wake_delivery_status"),
            lastWakeEnvelopeId: string("last_wake_envelope_id"),
            directiveStatus: directive?.status ?? string("directive_status"),
            directiveDoneAt: directive?.doneAt,
            directivePostedBy: directive?.postedBy,
            directiveTraceId: directive?.traceId,
            proposedByArm: directive?.proposedByArm ?? bool("proposed_by_arm") ?? false,
            intentState: directive?.intentState ?? string("intent_state"),
            needsEngagement: directive?.needsEngagement ?? bool("needs_engagement") ?? false,
            needsEngagementReason: directive?.needsEngagementReason ?? string("needs_engagement_reason"),
            lastShip: fallbackLastShip
        )
    }

    private func string(_ key: String) -> String? {
        guard let raw = value[key] else { return nil }
        return raw.stringValue
    }

    private func bool(_ key: String) -> Bool? {
        guard let raw = value[key] else { return nil }
        return raw.boolValue
    }

    private func int(_ key: String) -> Int? {
        guard let raw = value[key] else { return nil }
        return raw.intValue
    }

    private func date(_ key: String) -> Date? {
        guard let text = string(key) else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}

private struct ArmDirectiveDTO: Decodable {
    let name: String
    let tag: String
    let tagData: [String: AgentRunJSONValue]

    enum CodingKeys: String, CodingKey {
        case name, tag
        case tagData = "tag_data"
    }

    func toDomain() -> ArmDirective {
        ArmDirective(
            name: name,
            tag: tag,
            directive: string("directive"),
            status: string("directive_status") ?? string("status"),
            postedBy: string("posted_by"),
            note: string("note"),
            traceId: string("trace_id"),
            doneAt: date("done_at"),
            proposedByArm: bool("proposed_by_arm"),
            intentState: string("intent_state"),
            needsEngagement: bool("needs_engagement") ?? false,
            needsEngagementReason: string("needs_engagement_reason")
        )
    }

    private func string(_ key: String) -> String? {
        guard let value = valueDict[key] ?? tagData[key] else { return nil }
        switch value {
        case .string(let text):
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        case .int(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    private func date(_ key: String) -> Date? {
        guard let text = string(key) else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private func bool(_ key: String) -> Bool? {
        guard let value = valueDict[key] ?? tagData[key] else { return nil }
        return value.boolValue
    }

    private var valueDict: [String: AgentRunJSONValue] {
        guard case .object(let value)? = tagData["value"] else { return [:] }
        return value
    }
}

private struct ArmDirective: Hashable {
    let name: String
    let tag: String
    let directive: String?
    let status: String?
    let postedBy: String?
    let note: String?
    let traceId: String?
    let doneAt: Date?
    let proposedByArm: Bool?
    let intentState: String?
    let needsEngagement: Bool
    let needsEngagementReason: String?
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

    init(
        arm: String,
        agentSubject: String?,
        workspace: String?,
        canWake: Bool,
        protected: Bool,
        protectionReason: String?
    ) {
        self.arm = arm
        self.agentSubject = agentSubject
        self.workspace = workspace
        self.canWake = canWake
        self.protected = protected
        self.protectionReason = protectionReason
    }

    enum CodingKeys: String, CodingKey {
        case arm, workspace, protected
        case agentSubject = "agent_subject"
        case canWake = "can_wake"
        case protectionReason = "protection_reason"
    }
}

private struct ArmTagDTO: Decodable {
    let name: String
    let tagData: ArmTagRecordDTO?

    enum CodingKeys: String, CodingKey {
        case name
        case tagData = "tag_data"
    }

    func toDomain(roster: ArmRosterEntryDTO?, routing: ArmRoutingEntryDTO?, directive: ArmDirective?, fallbackLastShip: ArmShip?) -> ArmTag {
        let data = tagData?.value
        let key = name.lowercased()
        let normalizedName = key == "arch" ? "architecture" : key
        return ArmTag(
            id: "maui-\(normalizedName)",
            name: normalizedName,
            family: .maui,
            displayNameOverride: roster?.displayName,
            state: data?.state ?? "idle",
            currentWork: data?.currentWork ?? "No current work set.",
            ticketRef: data?.ticketRef,
            evidenceRef: data?.evidenceRef,
            blockedOn: data?.blockedOn,
            directive: directive?.directive ?? data?.directive,
            owner: roster?.owner ?? data?.owner,
            quality: data?.quality ?? tagData?.quality ?? "yellow",
            updatedAt: data?.updatedAt ?? tagData?.updatedAt,
            ttlSeconds: data?.ttlSeconds ?? tagData?.ttlSeconds,
            source: data?.source,
            sourceDetail: data?.sourceDetail,
            lastFetched: data?.lastFetched,
            agentSubject: roster?.agentSubject ?? routing?.agentSubject,
            workspace: roster?.workspace ?? routing?.workspace,
            canWake: roster?.canWake ?? routing?.canWake ?? (normalizedName != "fund"),
            protected: roster?.protected ?? routing?.protected ?? (normalizedName == "fund"),
            protectionReason: roster?.protectionReason ?? routing?.protectionReason,
            lastWakeDeliveryStatus: data?.lastWakeDeliveryStatus,
            lastWakeEnvelopeId: data?.lastWakeEnvelopeId,
            directiveStatus: directive?.status,
            directiveDoneAt: directive?.doneAt,
            directivePostedBy: directive?.postedBy,
            directiveTraceId: directive?.traceId,
            proposedByArm: directive?.proposedByArm ?? data?.proposedByArm ?? false,
            intentState: directive?.intentState ?? data?.intentState,
            needsEngagement: directive?.needsEngagement ?? data?.needsEngagement ?? false,
            needsEngagementReason: directive?.needsEngagementReason ?? data?.needsEngagementReason,
            lastShip: data?.lastShip?.resolvedArm(normalizedName) ?? fallbackLastShip
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
    let proposedByArm: Bool?
    let intentState: String?
    let needsEngagement: Bool?
    let needsEngagementReason: String?
    let lastShip: ArmShip?

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
        case proposedByArm = "proposed_by_arm"
        case intentState = "intent_state"
        case needsEngagement = "needs_engagement"
        case needsEngagementReason = "needs_engagement_reason"
        case lastShip = "last_ship"
    }
}

private struct ArmDirectiveStatusPatchRequest: Encodable {
    let status: String?
    let intentState: String?
    let reportedBy: String
    let note: String?
    let evidenceRef: String? = nil

    enum CodingKeys: String, CodingKey {
        case status
        case intentState = "intent_state"
        case reportedBy = "reported_by"
        case note
        case evidenceRef = "evidence_ref"
    }
}

private struct ArmDirectiveCreateRequest: Encodable {
    let directive: String
    let postedBy: String
    let note: String? = nil
    let traceId: String? = nil
    let ttlSeconds: Int = 86_400

    enum CodingKeys: String, CodingKey {
        case directive
        case postedBy = "posted_by"
        case note
        case traceId = "trace_id"
        case ttlSeconds = "ttl_seconds"
    }
}

private struct ArmDirectiveWriteResponse: Decodable {
    let updated: Bool
    let arm: String
    let tag: String
    let directiveStatus: String
    let doneAt: Date?

    enum CodingKeys: String, CodingKey {
        case updated, arm, tag
        case directiveStatus = "directive_status"
        case doneAt = "done_at"
    }

    var toastMessage: String {
        "Directive \(directiveStatus.replacingOccurrences(of: "_", with: " "))"
    }
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
