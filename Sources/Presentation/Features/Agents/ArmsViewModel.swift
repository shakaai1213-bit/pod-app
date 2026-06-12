import Foundation
import SwiftUI

@Observable
final class ArmsViewModel {
    var arms: [ArmTag] = ArmTag.placeholderArms
    var chiefArms: [ArmTag] = ArmTag.placeholderChiefArms
    var orcaMiniStatus: OrcaMiniStatus = .missing()
    var directiveDrafts: [String: String] = [:]
    var expandedShipArms: Set<String> = []
    var expandedEvidenceArms: Set<String> = []
    var shipHistoryByArm: [String: [ArmShip]] = [:]
    var shipHistoryErrorsByArm: [String: String] = [:]
    var loadingShipArms: Set<String> = []
    var shipSummaryStateByFamily: [ArmFamily: ArmShipSummaryState] = [
        .maui: .idle,
        .chief: .idle
    ]
    var armOpsByArm: [String: ArmOpsSnapshot] = [:]
    var busyArms: Set<String> = []
    var isLoading = false
    var errorMessage: String?
    var toast: ArmsToast?
    var pendingWakeConfirmation: WakeConfirmation?

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
        markShipSummaryLoadingIfNeeded()
        Task { await refreshShipSummary() }

        async let mauiTask: Void = loadMauiArms()
        async let chiefTask: Void = loadChiefArms()
        async let miniTask: Void = loadOrcaMiniStatus()
        async let opsTask: Void = loadArmOps()
        _ = await (mauiTask, chiefTask, miniTask, opsTask)
    }

    @MainActor
    private func refreshShipSummary() async {
        let shipSummary = await loadShipSummary()
        apply(shipSummary: shipSummary)
    }

    @MainActor
    private func markShipSummaryLoadingIfNeeded() {
        for family in ArmFamily.allCases where shipSummaryStateByFamily[family]?.status != .loaded {
            shipSummaryStateByFamily[family] = .loading
        }
    }

    @MainActor
    private func apply(shipSummary: ArmShipSummaryResult) {
        switch shipSummary {
        case .loaded(let ships, let source):
            var latestByArm: [String: ArmShip] = [:]
            for ship in ships.sorted(by: { $0.timestamp > $1.timestamp }) {
                latestByArm[ship.arm.lowercased()] = latestByArm[ship.arm.lowercased()] ?? ship
            }
            shipHistoryByArm.merge(latestByArm.mapValues { [$0] }) { current, _ in current }
            applyLatestShips(latestByArm)
            for family in ArmFamily.allCases {
                let familyShips = latestByArm.values.filter { ArmFamily.inferred(from: $0.arm) == family }
                let newestShip = familyShips.map(\.timestamp).max()
                let isStale = newestShip.map { Date().timeIntervalSince($0) > 7 * 86_400 } ?? false
                shipSummaryStateByFamily[family] = familyShips.isEmpty
                    ? .empty(source: source)
                    : (isStale ? .stale(source: source, count: familyShips.count) : .loaded(source: source, count: familyShips.count))
            }
        case .unavailable(let message):
            for family in ArmFamily.allCases {
                shipSummaryStateByFamily[family] = .unavailable(message: message)
            }
        }
    }

    @MainActor
    private func applyLatestShips(_ latestByArm: [String: ArmShip]) {
        arms = arms.map { arm in
            var updated = arm
            updated.lastShip = latestByArm[arm.name.lowercased()] ?? arm.lastShip
            return updated
        }
        chiefArms = chiefArms.map { arm in
            var updated = arm
            updated.lastShip = latestByArm[arm.name.lowercased()] ?? arm.lastShip
            return updated
        }
    }

    @MainActor
    private func loadArmOps() async {
        do {
            let response: ArmOpsResponse = try await apiClient.get(path: "/api/v1/jarvis/arm-ops")
            armOpsByArm = Dictionary(uniqueKeysWithValues: response.arms.map {
                let snapshot = $0.toDomain(generatedAt: response.generatedAt)
                return (snapshot.name.lowercased(), snapshot)
            })
        } catch {
            armOpsByArm = [:]
        }
    }

    @MainActor
    private func loadOrcaMiniStatus() async {
        do {
            let response: ArmStateRegistryResponse = try await apiClient.get(path: "/api/v1/state-registry?prefix=infra.orca-mini&limit=20")
            guard let tag = response.items.first(where: { $0.tagId == "infra.orca-mini.status" }) else {
                orcaMiniStatus = .missing()
                return
            }
            orcaMiniStatus = tag.toOrcaMiniStatus()
        } catch {
            orcaMiniStatus = .unavailable(reason: "State Registry unavailable")
        }
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
            let names = Self.rosterNames(
                response: response,
                roster: rosterResponse?.arms,
                family: .maui,
                fallback: ArmTag.mauiNames
            )
            let liveByName = Dictionary(uniqueKeysWithValues: response.arms.map {
                let key = $0.name.lowercased()
                let arm = $0.toDomain(roster: rosterByName[key], routing: routingByName[key], directive: directivesByName[key], fallbackLastShip: shipHistoryByArm[key]?.first)
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
            chiefArms = names.map { name in
                statusByName[name]?.toArmTag(
                    name: name,
                    roster: rosterByName[name],
                    directive: directivesByName[name],
                    fallbackLastShip: shipHistoryByArm[name]?.first
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
                body: ArmDirectiveCreateRequest(directive: directive, postedBy: arm.directiveActor)
            )
            directiveDrafts[key] = ""
            toast = ArmsToast(message: response.toastMessage, isError: false)
            await load()
        } catch {
            toast = ArmsToast(message: "Directive failed", isError: true)
        }
    }

    @MainActor
    func markReadyForReview(_ arm: ArmTag) async {
        let key = arm.name.lowercased()
        guard arm.canRequestReview else { return }
        busyArms.insert(key)
        defer { busyArms.remove(key) }

        do {
            let response: ArmDirectiveWriteResponse = try await apiClient.patch(
                path: "/api/v1/jarvis/arm-directives/\(key)/status",
                body: ArmDirectiveStatusPatchRequest(
                    status: nil,
                    intentState: nil,
                    reviewState: arm.reviewReadyState,
                    reportedBy: arm.reviewReporter,
                    note: nil,
                    reviewNote: "Ready for \(arm.directiveActor.capitalized) review"
                )
            )
            toast = ArmsToast(message: "\(arm.displayName) \(response.directiveStatus)", isError: false)
            await load()
        } catch {
            toast = ArmsToast(message: "Review request failed", isError: true)
        }
    }

    // Green Light no longer dispatches on tap. It stages a confirmation; the
    // actual approve-directive + wake happens in confirmPendingWake() after the
    // user confirms in the dialog. Doctrine: a casual tap must not fire a
    // non-casual action (launching an autonomous arm). Applies to ALL arms, not
    // just the orca/compute wake_confirm set.
    @MainActor
    func greenLight(_ arm: ArmTag) async {
        guard arm.canGreenLight else { return }
        pendingWakeConfirmation = WakeConfirmation(
            arm: arm,
            postedBy: "tony",
            note: arm.directive,
            reason: "Green Light approves the directive and wakes \(arm.displayName) — this dispatches the arm to run its current directive autonomously. Confirm to proceed.",
            action: .greenLight
        )
    }

    // Plain wake also stages a confirmation rather than firing on tap.
    @MainActor
    func wake(_ arm: ArmTag, note: String = "") async {
        guard arm.canWake else { return }
        pendingWakeConfirmation = WakeConfirmation(
            arm: arm,
            postedBy: "maui",
            note: note.isEmpty ? nil : note,
            reason: "Waking \(arm.displayName) dispatches the arm to run its directive autonomously. Confirm to proceed.",
            action: .wake
        )
    }

    @MainActor
    func confirmPendingWake() async {
        // Capture into a local BEFORE clearing the published property — reading
        // self.pendingWakeConfirmation after nilling it was the prior bug.
        guard let pending = pendingWakeConfirmation else { return }
        pendingWakeConfirmation = nil
        let arm = pending.arm
        let key = arm.name.lowercased()
        guard arm.canWake else { return }
        busyArms.insert(key)
        defer { busyArms.remove(key) }

        do {
            // Green Light first approves the directive (intent_state), then wakes.
            if pending.action == .greenLight {
                let _: ArmDirectiveWriteResponse? = try? await apiClient.patch(
                    path: "/api/v1/jarvis/arm-directives/\(key)/status",
                    body: ArmDirectiveStatusPatchRequest(
                        status: nil,
                        intentState: "green_lit",
                        reviewState: nil,
                        reportedBy: pending.postedBy,
                        note: "Green Light from Pod",
                        reviewNote: nil
                    )
                )
            }
            // confirm: true — user has explicitly confirmed in the dialog, so the
            // server-side wake_confirm gate (orca/compute) is satisfied here too.
            let response = try await sendWake(
                arm,
                postedBy: pending.postedBy,
                note: pending.note,
                confirm: true
            )
            toast = ArmsToast(message: response.toastMessage, isError: response.deliveryStatus == "failed")
            await load()
        } catch {
            toast = ArmsToast(
                message: pending.action == .greenLight ? "Green Light failed" : "Wake failed",
                isError: true
            )
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
        if shipHistoryByArm[key]?.count != 5 {
            await loadShips(for: arm)
        }
    }

    func isShipsExpanded(_ arm: ArmTag) -> Bool {
        expandedShipArms.contains(arm.name.lowercased())
    }

    func ships(for arm: ArmTag) -> [ArmShip] {
        shipHistoryByArm[arm.name.lowercased()] ?? arm.lastShip.map { [$0] } ?? []
    }

    func shipHistoryState(for arm: ArmTag) -> ArmShipHistoryState {
        let key = arm.name.lowercased()
        if loadingShipArms.contains(key) {
            return .loading(ships(for: arm))
        }
        if let error = shipHistoryErrorsByArm[key] {
            return .error(error)
        }
        let ships = ships(for: arm)
        if ships.isEmpty {
            return .empty
        }
        return .loaded(ships)
    }

    func shipSummaryState(for family: ArmFamily) -> ArmShipSummaryState {
        shipSummaryStateByFamily[family] ?? .idle
    }

    func armOps(for arm: ArmTag) -> ArmOpsSnapshot? {
        armOpsByArm[arm.name.lowercased()]
    }

    @MainActor
    func toggleEvidence(for arm: ArmTag) {
        let key = arm.name.lowercased()
        if expandedEvidenceArms.contains(key) {
            expandedEvidenceArms.remove(key)
            return
        }
        expandedEvidenceArms.insert(key)
    }

    func isEvidenceExpanded(_ arm: ArmTag) -> Bool {
        expandedEvidenceArms.contains(arm.name.lowercased())
    }

    @MainActor
    private func loadShips(for arm: ArmTag) async {
        let key = arm.name.lowercased()
        loadingShipArms.insert(key)
        shipHistoryErrorsByArm[key] = nil
        defer { loadingShipArms.remove(key) }
        do {
            shipHistoryByArm[key] = try await loadShips(forKey: key, limit: 5)
        } catch {
            if shipHistoryByArm[key] == nil {
                shipHistoryByArm[key] = arm.lastShip.map { [$0] } ?? []
            }
            shipHistoryErrorsByArm[key] = Self.message(for: error)
        }
    }

    private func loadShipSummary() async -> ArmShipSummaryResult {
        do {
            let response: ArmShipsSummaryResponse = try await getWithRequestTimeout(
                path: "/api/v1/jarvis/arm-ships/summary?per_arm_limit=1",
                seconds: 3
            )
            return .loaded(
                ships: response.latestShips,
                source: "summary /api/v1/jarvis/arm-ships/summary?per_arm_limit=1"
            )
        } catch {
            do {
                let response: ArmShipsResponse = try await getWithRequestTimeout(
                    path: "/api/v1/jarvis/arm-ships?limit=100",
                    seconds: 3
                )
                return .loaded(
                    ships: response.ships.map { $0.toDomain(fallbackArm: $0.arm ?? "") },
                    source: "fallback batched /api/v1/jarvis/arm-ships?limit=100"
                )
            } catch {
                return .unavailable("Ship summary unavailable: \(Self.message(for: error)). Detail loads on expand.")
            }
        }
    }

    private func loadShips(forKey key: String, limit: Int) async throws -> [ArmShip] {
        let response: ArmShipsResponse = try await getWithRequestTimeout(
            path: "/api/v1/jarvis/arm-ships?arm=\(key)&limit=\(limit)",
            seconds: 4
        )
        return response.ships.map { $0.toDomain(fallbackArm: key) }
    }

    private func getWithRequestTimeout<T: Decodable>(path: String, seconds: TimeInterval) async throws -> T {
        var request = try await apiClient.buildRequest(path: path, method: "GET")
        request.timeoutInterval = seconds
        return try await apiClient.perform(request)
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.message
        }
        return error.localizedDescription
    }

    private func sendWake(_ arm: ArmTag, postedBy: String, note: String?, confirm: Bool) async throws -> WakeResponse {
        let key = arm.name.lowercased()
        let request = try await apiClient.buildRequest(
            path: "/api/v1/jarvis/arm-tags/\(key)/wake",
            method: "POST",
            body: WakeRequest(postedBy: postedBy, note: note, confirm: confirm ? true : nil)
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }
        if http.statusCode == 409 {
            throw WakeConfirmRequired(reason: Self.wakeConfirmReason(from: data))
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError(code: http.statusCode, message: "Wake failed with status \(http.statusCode)")
        }
        return try JSONDecoder().decode(WakeResponse.self, from: data)
    }

    private static func wakeConfirmReason(from data: Data) -> String {
        let fallback = "This arm requires confirmation before wake."
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any]
        else { return fallback }

        if let reason = payload["wake_confirm_reason"] as? String, !reason.isEmpty {
            return reason
        }
        if let detail = payload["detail"] as? String, !detail.isEmpty {
            return detail
        }
        if let detail = payload["detail"] as? [String: Any] {
            if let reason = detail["wake_confirm_reason"] as? String, !reason.isEmpty {
                return reason
            }
            if let reason = detail["reason"] as? String, !reason.isEmpty {
                return reason
            }
        }
        return fallback
    }
}

struct ArmsToast: Equatable {
    let message: String
    let isError: Bool
}

struct OrcaMiniStatus: Equatable {
    let tagId: String
    let state: String
    let quality: String
    let disk: String
    let containers: String
    let unhealthyContainers: [String]
    let nfs: String
    let nfsHealthy: Bool?
    let nats: String
    let natsHealthy: Bool?
    let lastBackup: String
    let backupStale: Bool
    let contractUnknown: Bool
    let updatedAt: Date?
    let source: String?
    let missingReason: String?

    static func missing() -> OrcaMiniStatus {
        OrcaMiniStatus(
            tagId: "infra.orca-mini.status",
            state: "waiting",
            quality: "missing",
            disk: "Waiting for tag",
            containers: "Waiting for tag",
            unhealthyContainers: [],
            nfs: "Waiting for tag",
            nfsHealthy: nil,
            nats: "Waiting for tag",
            natsHealthy: nil,
            lastBackup: "Waiting for tag",
            backupStale: false,
            contractUnknown: true,
            updatedAt: nil,
            source: nil,
            missingReason: "Tag missing"
        )
    }

    static func unavailable(reason: String) -> OrcaMiniStatus {
        OrcaMiniStatus(
            tagId: "infra.orca-mini.status",
            state: "unavailable",
            quality: "degraded",
            disk: "Unavailable",
            containers: "Unavailable",
            unhealthyContainers: [],
            nfs: "Unavailable",
            nfsHealthy: nil,
            nats: "Unavailable",
            natsHealthy: nil,
            lastBackup: "Unavailable",
            backupStale: false,
            contractUnknown: true,
            updatedAt: nil,
            source: nil,
            missingReason: reason
        )
    }

    var hasAttention: Bool {
        missingReason != nil || !unhealthyContainers.isEmpty || backupStale || contractUnknown || nfsHealthy == false || natsHealthy == false
    }

    var badges: [OrcaMiniBadge] {
        var badges: [OrcaMiniBadge] = []
        if let missingReason {
            badges.append(OrcaMiniBadge(label: missingReason, color: AppColors.accentWarning))
        }
        if !unhealthyContainers.isEmpty {
            badges.append(OrcaMiniBadge(label: "Unhealthy: \(unhealthyContainers.joined(separator: ", "))", color: AppColors.accentDanger))
        }
        if backupStale {
            badges.append(OrcaMiniBadge(label: "Backup stale", color: AppColors.accentWarning))
        }
        if contractUnknown {
            badges.append(OrcaMiniBadge(label: "Contract unknown", color: AppColors.accentWarning))
        }
        if nfsHealthy == false {
            badges.append(OrcaMiniBadge(label: "NFS down", color: AppColors.accentDanger))
        }
        if natsHealthy == false {
            badges.append(OrcaMiniBadge(label: "NATS down", color: AppColors.accentDanger))
        }
        return badges
    }

    var statusLabel: String {
        if missingReason != nil { return "waiting" }
        return hasAttention ? "attention" : "healthy"
    }

    var statusColor: Color {
        if !unhealthyContainers.isEmpty || nfsHealthy == false || natsHealthy == false {
            return AppColors.accentDanger
        }
        if missingReason != nil || backupStale || contractUnknown || quality.lowercased() == "degraded" || quality.lowercased() == "yellow" {
            return AppColors.accentWarning
        }
        return AppColors.accentSuccess
    }

    var freshnessLabel: String {
        guard let updatedAt else { return "unknown" }
        return Self.relativeAge(from: updatedAt)
    }

    private static func relativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}

struct OrcaMiniBadge {
    let label: String
    let color: Color
}

struct WakeConfirmation: Identifiable, Equatable {
    enum Action: Equatable { case wake, greenLight }
    let id = UUID()
    let arm: ArmTag
    let postedBy: String
    let note: String?
    let reason: String
    var action: Action = .wake
}

private struct WakeConfirmRequired: Error {
    let reason: String
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
    let reviewState: String?
    let reviewUpdatedAt: Date?
    let reviewReportedBy: String?
    let reviewNote: String?
    let reviewEvidenceRef: String?
    var lastShip: ArmShip?

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
        case "chief-research": return "Chief Research Arm"
        case "chief-data": return "Chief Data Arm"
        case "chief-predictions": return "Chief Predictions Arm"
        case "chief-ml": return "Chief ML Arm"
        case "chief-trading": return "Chief Trading Arm"
        case "chief-algos": return "Chief Algos Arm"
        case "chief-fund": return "Chief Fund Arm"
        case "chief-mac-infra": return "Chief Mac Infra Arm"
        default: return name.capitalized + " Arm"
        }
    }

    var isFund: Bool { name.lowercased() == "fund" }

    var canPostDirective: Bool {
        !protected
    }

    var canGreenLight: Bool {
        canWake && !protected && proposedByArm && intentState?.lowercased() == "proposed" && directive?.isEmpty == false
    }

    var canRequestReview: Bool {
        !protected && directive?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var directiveActor: String {
        family == .chief ? "chief" : "maui"
    }

    var reviewReadyState: String {
        family == .chief ? "ready_for_chief" : "ready_for_maui"
    }

    var reviewReporter: String {
        if let owner, owner.lowercased().hasSuffix("-arm") {
            return owner
        }
        return family == .chief ? "\(name.lowercased())-arm" : "codex-\(name.lowercased())-arm"
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

    var reviewStatusLabel: String {
        guard let reviewState, !reviewState.isEmpty else { return "not ready" }
        return reviewState.replacingOccurrences(of: "_", with: " ")
    }

    var reviewStatusColor: Color {
        switch reviewState?.lowercased() {
        case "ready_for_maui", "ready_for_chief", "ready_for_aloha", "ready_for_rooster":
            return AppColors.accentElectric
        case "changes_requested":
            return AppColors.accentDanger
        case "reviewed":
            return AppColors.accentSuccess
        default:
            return AppColors.textTertiary
        }
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
            reviewState: nil,
            reviewUpdatedAt: nil,
            reviewReportedBy: nil,
            reviewNote: nil,
            reviewEvidenceRef: nil,
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

    static func inferred(from armName: String) -> ArmFamily {
        armName.lowercased().hasPrefix("chief-") ? .chief : .maui
    }

    var title: String {
        switch self {
        case .maui: return "Maui Arms"
        case .chief: return "Chief Arms"
        }
    }
}

enum ArmShipSummaryResult {
    case loaded(ships: [ArmShip], source: String)
    case unavailable(String)

    func latestShipsByName(for names: [String]) -> [String: [ArmShip]] {
        guard case .loaded(let ships, _) = self else { return [:] }
        let wanted = Set(names.map { $0.lowercased() })
        var latestByName: [String: ArmShip] = [:]
        for ship in ships
            .filter({ wanted.contains($0.arm.lowercased()) })
            .sorted(by: { $0.timestamp > $1.timestamp }) {
            let key = ship.arm.lowercased()
            latestByName[key] = latestByName[key] ?? ship
        }
        return latestByName.mapValues { [$0] }
    }
}

enum ArmShipHistoryState: Equatable {
    case loading([ArmShip])
    case loaded([ArmShip])
    case empty
    case error(String)
}

struct ArmShipSummaryState: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case stale
        case empty
        case unavailable
    }

    let status: Status
    let message: String
    let source: String?
    let count: Int

    static let idle = ArmShipSummaryState(status: .idle, message: "Ship summary waiting", source: nil, count: 0)
    static let loading = ArmShipSummaryState(status: .loading, message: "Loading batched ship summary", source: nil, count: 0)

    static func loaded(source: String, count: Int) -> ArmShipSummaryState {
        ArmShipSummaryState(status: .loaded, message: "\(count) arm summaries loaded", source: source, count: count)
    }

    static func empty(source: String) -> ArmShipSummaryState {
        ArmShipSummaryState(status: .empty, message: "No ships recorded for this family", source: source, count: 0)
    }

    static func stale(source: String, count: Int) -> ArmShipSummaryState {
        ArmShipSummaryState(status: .stale, message: "\(count) stale arm summaries", source: source, count: count)
    }

    static func unavailable(message: String) -> ArmShipSummaryState {
        ArmShipSummaryState(status: .unavailable, message: message, source: nil, count: 0)
    }

    var label: String {
        switch status {
        case .idle: return "waiting"
        case .loading: return "loading"
        case .loaded: return "summary"
        case .stale: return "stale"
        case .empty: return "empty"
        case .unavailable: return "unavailable"
        }
    }

    var color: Color {
        switch status {
        case .loaded:
            return AppColors.accentSuccess
        case .loading:
            return AppColors.accentElectric
        case .stale, .empty:
            return AppColors.accentWarning
        case .unavailable:
            return AppColors.accentDanger
        case .idle:
            return AppColors.textTertiary
        }
    }
}

struct ArmOpsSnapshot: Identifiable, Hashable {
    let name: String
    let family: ArmFamily
    let displayName: String
    let directiveStatus: String?
    let intentState: String?
    let dispatchStatus: String?
    let reviewState: String?
    let reviewReportedBy: String?
    let latestRun: ArmRunEvidence?
    let protected: Bool
    let generatedAt: Date?

    var id: String { name }

    var hasEvidence: Bool {
        latestRun != nil || dispatchStatus != nil || directiveStatus != nil || reviewState != nil
    }

    var stateLabel: String {
        if let runStatus = latestRun?.runStatusStatus, !runStatus.isEmpty {
            return runStatus.replacingOccurrences(of: "_", with: " ")
        }
        if let dispatchStatus, !dispatchStatus.isEmpty {
            return dispatchStatus.replacingOccurrences(of: "_", with: " ")
        }
        if let directiveStatus, !directiveStatus.isEmpty {
            return directiveStatus.replacingOccurrences(of: "_", with: " ")
        }
        if let intentState, !intentState.isEmpty {
            return intentState.replacingOccurrences(of: "_", with: " ")
        }
        return latestRun?.statusLabel ?? "no run evidence"
    }

    var stateLabelKey: String {
        stateLabel
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    var statusColor: Color {
        let status = (latestRun?.runStatusStatus ?? dispatchStatus ?? directiveStatus ?? latestRun?.status ?? "").lowercased()
        switch status {
        case "completed", "done", "reviewed", "owner_reviewed":
            return AppColors.accentSuccess
        case "blocked", "failed", "cancelled", "error":
            return AppColors.accentDanger
        case "in_progress", "running", "dispatching", "review_ready":
            return AppColors.accentWarning
        default:
            return latestRun == nil ? AppColors.textTertiary : AppColors.accentElectric
        }
    }
}

struct ArmRunEvidence: Identifiable, Hashable, Decodable {
    let arm: String?
    let tagId: String?
    let runId: String?
    let traceId: String?
    let status: String?
    let startedAt: Date?
    let completedAt: Date?
    let returncode: Int?
    let runDir: String?
    let promptPath: String?
    let eventsPath: String?
    let stderrPath: String?
    let outputPath: String?
    let resultPath: String?
    let reportPath: String?
    let activationContextPath: String?
    let runStatusPath: String?
    let evidencePath: String?
    let codexThreadId: String?
    let eventCount: Int
    let fileChangeCount: Int
    let result: [String: AgentRunJSONValue]?
    let report: [String: AgentRunJSONValue]?
    let activationContext: [String: AgentRunJSONValue]?
    let runStatus: [String: AgentRunJSONValue]?
    let workLogPath: String?

    enum CodingKeys: String, CodingKey {
        case arm
        case tagId = "tag_id"
        case runId = "run_id"
        case traceId = "trace_id"
        case status
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case returncode
        case runDir = "run_dir"
        case promptPath = "prompt_path"
        case eventsPath = "events_path"
        case stderrPath = "stderr_path"
        case outputPath = "output_path"
        case resultPath = "result_path"
        case reportPath = "report_path"
        case activationContextPath = "activation_context_path"
        case runStatusPath = "run_status_path"
        case evidencePath = "evidence_path"
        case codexThreadId = "codex_thread_id"
        case eventCount = "event_count"
        case fileChangeCount = "file_change_count"
        case result, report
        case activationContext = "activation_context"
        case runStatus = "run_status"
        case workLogPath = "work_log_path"
    }

    var id: String {
        runId ?? traceId ?? codexThreadId ?? runDir ?? "unknown-run"
    }

    var statusLabel: String {
        (runStatusStatus ?? status)?.replacingOccurrences(of: "_", with: " ") ?? "unknown"
    }

    var compactId: String {
        guard let runId, !runId.isEmpty else { return "No run id" }
        return String(runId.prefix(22))
    }

    var threadLabel: String {
        guard let codexThreadId, !codexThreadId.isEmpty else { return "No Codex thread" }
        return String(codexThreadId.prefix(24))
    }

    var summary: String? {
        Self.summary(from: report) ?? Self.summary(from: runStatus) ?? Self.summary(from: result)
    }

    var runStatusStatus: String? {
        Self.string(["status", "state"], from: runStatus)
    }

    var directiveSummary: String? {
        Self.string(["directive_summary", "directive", "body", "prompt", "summary"], from: activationContext)
    }

    var activationOwner: String? {
        Self.string(["owner", "posted_by", "requested_by"], from: activationContext)
    }

    var activationFamily: String? {
        Self.string(["family", "arm_family"], from: activationContext)
    }

    var permissionsSummary: String? {
        var bits: [String] = []
        if let mayApprove = Self.bool(["may_approve", "can_approve"], from: activationContext) {
            bits.append("may approve: \(mayApprove ? "true" : "false")")
        }
        if let reviewRequired = Self.string(["review_required", "owner_review_required", "approval_required"], from: activationContext) {
            bits.append(reviewRequired)
        }
        if let reviewer = Self.string(["reviewer", "review_owner", "owner_review"], from: activationContext) {
            bits.append("review: \(reviewer)")
        }
        if bits.isEmpty {
            return nil
        }
        return bits.joined(separator: " · ")
    }

    var reportSummary: String? {
        Self.summary(from: report)
    }

    var reportFindings: [String] {
        Self.stringList(["findings"], from: report)
    }

    var reportDeliverables: [String] {
        Self.stringList(["deliverables", "files_touched", "outputs"], from: report)
    }

    var reportBlockedOn: [String] {
        Self.stringList(["blocked_on", "blockers"], from: report) + Self.stringList(["blocked_on"], from: runStatus)
    }

    private static func summary(from object: [String: AgentRunJSONValue]?) -> String? {
        string(["summary", "message", "result", "outcome"], from: object)
    }

    private static func string(_ keys: [String], from object: [String: AgentRunJSONValue]?) -> String? {
        guard let object else { return nil }
        for key in keys {
            if let value = object[key]?.stringValue {
                return value
            }
        }
        return nil
    }

    private static func bool(_ keys: [String], from object: [String: AgentRunJSONValue]?) -> Bool? {
        guard let object else { return nil }
        for key in keys {
            if let value = object[key]?.boolValue {
                return value
            }
        }
        return nil
    }

    private static func stringList(_ keys: [String], from object: [String: AgentRunJSONValue]?) -> [String] {
        guard let object else { return [] }
        for key in keys {
            if let array = object[key]?.arrayValue {
                return array.compactMap(\.stringValue)
            }
            if let string = object[key]?.stringValue {
                return [string]
            }
        }
        return []
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

    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        case .string(let text):
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    var objectValue: [String: AgentRunJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [AgentRunJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
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

private struct ArmOpsResponse: Decodable {
    let arms: [ArmOpsEntryDTO]
    let generatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case arms
        case generatedAt = "generated_at"
    }
}

private struct ArmOpsEntryDTO: Decodable {
    let name: String
    let familyRaw: String
    let displayName: String
    let directive: [String: AgentRunJSONValue]?
    let dispatch: [String: AgentRunJSONValue]?
    let review: [String: AgentRunJSONValue]?
    let latestRun: ArmRunEvidence?
    let protected: Bool

    enum CodingKeys: String, CodingKey {
        case name, directive, dispatch, review, protected
        case familyRaw = "family"
        case displayName = "display_name"
        case latestRun = "latest_run"
    }

    func toDomain(generatedAt: Date?) -> ArmOpsSnapshot {
        ArmOpsSnapshot(
            name: name.lowercased(),
            family: familyRaw == "chief" ? .chief : .maui,
            displayName: displayName,
            directiveStatus: string("status", in: directive) ?? string("directive_status", in: directive),
            intentState: string("intent_state", in: directive),
            dispatchStatus: string("status", in: dispatch),
            reviewState: string("state", in: review) ?? string("review_state", in: directive),
            reviewReportedBy: string("reported_by", in: review) ?? string("review_reported_by", in: directive),
            latestRun: latestRun,
            protected: protected,
            generatedAt: generatedAt
        )
    }

    private func string(_ key: String, in object: [String: AgentRunJSONValue]?) -> String? {
        payload(from: object)?[key]?.stringValue ?? object?[key]?.stringValue
    }

    private func payload(from object: [String: AgentRunJSONValue]?) -> [String: AgentRunJSONValue]? {
        guard let object else { return nil }
        return object["value"]?.objectValue ?? object
    }
}

private struct ArmShipsResponse: Decodable {
    let ships: [ArmShipDTO]
}

private struct ArmShipsSummaryResponse: Decodable {
    let arms: [ArmShipSummaryArmDTO]
    let count: Int?
    let shipsCount: Int?
    let readBudget: Int?
    let registryPath: String?

    enum CodingKeys: String, CodingKey {
        case arms, count
        case shipsCount = "ships_count"
        case readBudget = "read_budget"
        case registryPath = "registry_path"
    }

    var latestShips: [ArmShip] {
        arms.compactMap { $0.latestShip }
    }
}

private struct ArmShipSummaryArmDTO: Decodable {
    let arm: String
    let family: String?
    let namespace: String?
    let displayName: String?
    let protected: Bool?
    let canWake: Bool?
    let latestShipDTO: ArmShipDTO?
    let ships: [ArmShipDTO]

    enum CodingKeys: String, CodingKey {
        case arm, family, namespace, protected, ships
        case displayName = "display_name"
        case canWake = "can_wake"
        case latestShipDTO = "latest_ship"
    }

    var latestShip: ArmShip? {
        (latestShipDTO ?? ships.first)?.toDomain(fallbackArm: arm)
    }
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
            needsEngagementReason: string("needs_engagement_reason"),
            reviewState: string("review_state"),
            reviewUpdatedAt: date("review_updated_at"),
            reviewReportedBy: string("review_reported_by"),
            reviewNote: string("review_note"),
            reviewEvidenceRef: string("review_evidence_ref")
        )
    }

    func toArmTag(name: String, roster: ArmRosterEntryDTO?, directive: ArmDirective?, fallbackLastShip: ArmShip?) -> ArmTag {
        let isChiefFund = name == "chief-fund"
        let protectedLane = roster?.protected ?? isChiefFund
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
            canWake: roster?.canWake ?? !isChiefFund,
            protected: protectedLane,
            protectionReason: protectedLane ? (roster?.protectionReason ?? "Tier-4: Chief/Rooster/Tony approval required") : roster?.protectionReason,
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
            reviewState: directive?.reviewState ?? string("directive_review_state") ?? string("review_state"),
            reviewUpdatedAt: directive?.reviewUpdatedAt ?? date("directive_review_updated_at") ?? date("review_updated_at"),
            reviewReportedBy: directive?.reviewReportedBy ?? string("directive_review_reported_by") ?? string("review_reported_by"),
            reviewNote: directive?.reviewNote ?? string("directive_review_note") ?? string("review_note"),
            reviewEvidenceRef: directive?.reviewEvidenceRef ?? string("directive_review_evidence_ref") ?? string("review_evidence_ref"),
            lastShip: fallbackLastShip
        )
    }

    func toOrcaMiniStatus() -> OrcaMiniStatus {
        let unhealthyContainers = parsedUnhealthyContainers()
        let nfsHealthy = bool("nfs_mounted") ?? bool("nfs_mount_ok") ?? healthyStatus(string("nfs_status") ?? string("nfs_mount_status"))
        let natsHealthy = bool("nats_connected") ?? bool("nats_ok") ?? healthyStatus(string("nats_status") ?? string("nats_connection_status"))
        let backupDate = date("last_backup_at") ?? date("backup_at")
        let backupStale = bool("backup_stale")
            ?? bool("last_backup_stale")
            ?? staleStatus(string("backup_status"))
            ?? backupDate.map(Self.isBackupStale)
            ?? false
        let contractUnknown = hasUnknownContainerStatus() || nfsHealthy == nil || natsHealthy == nil
        return OrcaMiniStatus(
            tagId: tagId,
            state: string("state") ?? string("status") ?? "reported",
            quality: string("quality") ?? quality ?? "green",
            disk: diskLabel(),
            containers: containerLabel(unhealthyContainers: unhealthyContainers),
            unhealthyContainers: unhealthyContainers,
            nfs: statusLabel(
                boolValue: nfsHealthy,
                explicit: string("nfs_status") ?? string("nfs_mount_status"),
                healthyText: "mounted",
                unhealthyText: "unmounted"
            ),
            nfsHealthy: nfsHealthy,
            nats: statusLabel(
                boolValue: natsHealthy,
                explicit: string("nats_status") ?? string("nats_connection_status"),
                healthyText: "connected",
                unhealthyText: "disconnected"
            ),
            natsHealthy: natsHealthy,
            lastBackup: backupLabel(),
            backupStale: backupStale,
            contractUnknown: contractUnknown,
            updatedAt: date("updated_at") ?? updatedAt,
            source: string("source"),
            missingReason: nil
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

    private func double(_ key: String) -> Double? {
        guard let raw = value[key] else { return nil }
        return raw.doubleValue
    }

    private func date(_ key: String) -> Date? {
        guard let text = string(key) else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private func diskLabel() -> String {
        if let label = string("disk_free_label") ?? string("disk") ?? string("disk_status") {
            return label
        }
        if let gb = double("disk_free_gb") ?? double("free_disk_gb") {
            return "\(Self.compactNumber(gb)) GB free"
        }
        if let percent = double("disk_free_percent") ?? double("free_disk_percent") {
            return "\(Self.compactNumber(percent))% free"
        }
        return "unknown"
    }

    private func backupLabel() -> String {
        if let label = string("last_backup") ?? string("last_backup_label") {
            return label
        }
        if let backupAt = date("last_backup_at") ?? date("backup_at") {
            return "\(Self.relativeAge(from: backupAt)) ago"
        }
        if let status = string("backup_status") {
            return status
        }
        return "unknown"
    }

    private func containerLabel(unhealthyContainers: [String]) -> String {
        if let label = string("containers_label") ?? string("container_status") {
            return label
        }
        if let count = int("container_count") ?? int("containers_count") {
            let unhealthyCount = unhealthyContainers.count
            return unhealthyCount == 0 ? "\(count) healthy" : "\(count - unhealthyCount)/\(count) healthy"
        }
        if let containers = value["containers"]?.objectValue {
            let count = containers.count
            let unhealthyCount = unhealthyContainers.count
            return unhealthyCount == 0 ? "\(count) healthy" : "\(count - unhealthyCount)/\(count) healthy"
        }
        return unhealthyContainers.isEmpty ? "unknown" : "\(unhealthyContainers.count) unhealthy"
    }

    private func parsedUnhealthyContainers() -> [String] {
        if let explicit = value["unhealthy_containers"]?.arrayValue {
            return explicit.compactMap(\.stringValue)
        }
        if let containers = value["containers"]?.objectValue {
            return containers.compactMap { name, payload in
                let status = Self.containerStatus(from: payload)
                return Self.isContainerHealthy(status) ? nil : name
            }
            .sorted()
        }
        if let containers = value["containers"]?.arrayValue {
            return containers.compactMap { payload in
                guard let object = payload.objectValue else { return nil }
                let name = object["name"]?.stringValue ?? object["container"]?.stringValue ?? "container"
                let status = object["health"]?.stringValue ?? object["status"]?.stringValue ?? object["state"]?.stringValue
                return Self.isContainerHealthy(status) ? nil : name
            }
        }
        return []
    }

    private func hasUnknownContainerStatus() -> Bool {
        if let containers = value["containers"]?.objectValue {
            return containers.values.contains { payload in
                Self.containerStatus(from: payload)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            }
        }
        if let containers = value["containers"]?.arrayValue {
            return containers.contains { payload in
                guard let object = payload.objectValue else { return true }
                let status = object["health"]?.stringValue ?? object["status"]?.stringValue ?? object["state"]?.stringValue
                return status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            }
        }
        return false
    }

    private func healthyStatus(_ status: String?) -> Bool? {
        guard let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !status.isEmpty else {
            return nil
        }
        if ["ok", "up", "healthy", "mounted", "connected", "running", "true"].contains(status) {
            return true
        }
        if ["down", "unhealthy", "unmounted", "disconnected", "stale", "failed", "false"].contains(status) {
            return false
        }
        return nil
    }

    private func staleStatus(_ status: String?) -> Bool? {
        guard let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !status.isEmpty else {
            return nil
        }
        if status.contains("stale") || status.contains("missing") || status.contains("failed") {
            return true
        }
        if status.contains("fresh") || status.contains("ok") || status.contains("current") {
            return false
        }
        return nil
    }

    private func statusLabel(boolValue: Bool?, explicit: String?, healthyText: String, unhealthyText: String) -> String {
        if let explicit, !explicit.isEmpty {
            return explicit
        }
        if let boolValue {
            return boolValue ? healthyText : unhealthyText
        }
        return "unknown"
    }

    private static func containerStatus(from payload: AgentRunJSONValue) -> String? {
        if let text = payload.stringValue {
            return text
        }
        if let object = payload.objectValue {
            return object["health"]?.stringValue ?? object["status"]?.stringValue ?? object["state"]?.stringValue
        }
        return nil
    }

    private static func isContainerHealthy(_ status: String?) -> Bool {
        guard let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !status.isEmpty else {
            return false
        }
        return ["ok", "up", "healthy", "running"].contains(status)
    }

    private static func isBackupStale(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > 30 * 60
    }

    private static func relativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }

    private static func compactNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
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
            needsEngagementReason: string("needs_engagement_reason"),
            reviewState: string("review_state"),
            reviewUpdatedAt: date("review_updated_at"),
            reviewReportedBy: string("review_reported_by"),
            reviewNote: string("review_note"),
            reviewEvidenceRef: string("review_evidence_ref")
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
    let reviewState: String?
    let reviewUpdatedAt: Date?
    let reviewReportedBy: String?
    let reviewNote: String?
    let reviewEvidenceRef: String?
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
            reviewState: directive?.reviewState ?? data?.directiveReviewState,
            reviewUpdatedAt: directive?.reviewUpdatedAt ?? data?.directiveReviewUpdatedAt,
            reviewReportedBy: directive?.reviewReportedBy ?? data?.directiveReviewReportedBy,
            reviewNote: directive?.reviewNote ?? data?.directiveReviewNote,
            reviewEvidenceRef: directive?.reviewEvidenceRef ?? data?.directiveReviewEvidenceRef,
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
    let directiveReviewState: String?
    let directiveReviewUpdatedAt: Date?
    let directiveReviewReportedBy: String?
    let directiveReviewNote: String?
    let directiveReviewEvidenceRef: String?
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
        case directiveReviewState = "directive_review_state"
        case directiveReviewUpdatedAt = "directive_review_updated_at"
        case directiveReviewReportedBy = "directive_review_reported_by"
        case directiveReviewNote = "directive_review_note"
        case directiveReviewEvidenceRef = "directive_review_evidence_ref"
        case lastShip = "last_ship"
    }
}

private struct ArmDirectiveStatusPatchRequest: Encodable {
    let status: String?
    let intentState: String?
    let reviewState: String?
    let reportedBy: String
    let note: String?
    let reviewNote: String?
    let evidenceRef: String? = nil
    let reviewEvidenceRef: String? = nil

    enum CodingKeys: String, CodingKey {
        case status
        case intentState = "intent_state"
        case reviewState = "review_state"
        case reportedBy = "reported_by"
        case note
        case reviewNote = "review_note"
        case evidenceRef = "evidence_ref"
        case reviewEvidenceRef = "review_evidence_ref"
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
    let confirm: Bool?

    init(postedBy: String, note: String?, confirm: Bool? = nil) {
        self.postedBy = postedBy
        self.note = note
        self.confirm = confirm
    }

    enum CodingKeys: String, CodingKey {
        case postedBy = "posted_by"
        case note
        case confirm
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
