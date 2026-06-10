import Foundation
import SwiftUI

private let planningAgentOrder = [
    "maui", "chief", "aloha", "coral", "reef", "rooster", "aurora", "shaka", "luna"
]

private enum PlanningSurfaceMode: String, CaseIterable, Identifiable {
    case today
    case agent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .agent: return "Agent"
        }
    }

    var icon: String {
        switch self {
        case .today: return "calendar.day.timeline.left"
        case .agent: return "person.crop.circle.badge.clock"
        }
    }
}

@Observable
final class PlanningViewModel {
    var teamEvents: [PlanningEvent] = []
    var agentEvents: [PlanningEvent] = []
    var planningContext: PlanningContext?
    var selectedAgent = "maui"
    var isLoading = false
    var errorMessage: String?
    var generatedAt = Date()

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let teamTask: Void = loadTeamToday()
        async let agentTask: Void = loadSelectedAgent()
        _ = await (teamTask, agentTask)
        generatedAt = Date()
    }

    @MainActor
    func selectAgent(_ agent: String) async {
        selectedAgent = agent
        await loadSelectedAgent()
    }

    @MainActor
    private func loadTeamToday() async {
        let range = Self.todayRange()
        do {
            let response: PlanningEventsEnvelope = try await apiClient.get(
                path: "/api/v1/calendar?from=\(range.from)&to=\(range.to)"
            )
            teamEvents = response.events.sortedForPlanning
        } catch {
            teamEvents = []
            errorMessage = "Planning calendar unavailable from ORCA."
        }
    }

    @MainActor
    private func loadSelectedAgent() async {
        let agent = selectedAgent.lowercased()
        do {
            let today: PlanningEventsEnvelope = try await apiClient.get(
                path: "/api/v1/agents/\(agent)/calendar/today"
            )
            agentEvents = today.events.sortedForPlanning
        } catch {
            agentEvents = []
        }

        do {
            planningContext = try await apiClient.get(
                path: "/api/v1/agents/\(agent)/planning-context"
            )
        } catch {
            planningContext = nil
        }
    }

    static func todayRange(now: Date = Date(), calendar: Calendar = .current) -> (from: String, to: String) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return (formatter.string(from: start), formatter.string(from: end))
    }
}

private extension Array where Element == PlanningEvent {
    var sortedForPlanning: [PlanningEvent] {
        sorted {
            if $0.startSortKey != $1.startSortKey { return $0.startSortKey < $1.startSortKey }
            if $0.ownerAgent != $1.ownerAgent { return $0.ownerAgent < $1.ownerAgent }
            return $0.title < $1.title
        }
    }
}

struct PlanningEventsEnvelope: Decodable {
    let events: [PlanningEvent]

    private enum CodingKeys: String, CodingKey {
        case events
        case items
        case data
        case instances
        case calendar
    }

    init(from decoder: Decoder) throws {
        if let array = try? [PlanningEvent](from: decoder) {
            events = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeIfPresent([PlanningEvent].self, forKey: .events)
            ?? container.decodeIfPresent([PlanningEvent].self, forKey: .items)
            ?? container.decodeIfPresent([PlanningEvent].self, forKey: .data)
            ?? container.decodeIfPresent([PlanningEvent].self, forKey: .instances)
            ?? container.decodeIfPresent([PlanningEvent].self, forKey: .calendar)
            ?? []
    }
}

struct PlanningEvent: Decodable, Identifiable, Hashable {
    let id: String
    let ownerAgent: String
    let kind: String?
    let title: String
    let status: String?
    let startsAt: String?
    let endsAt: String?
    let ticketId: String?
    let boardId: String?
    let milestoneId: String?
    let role: String?
    let outcome: String?
    let evidenceRefs: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case uid
        case eventId = "event_id"
        case ownerAgent = "owner_agent"
        case agent
        case kind
        case type = "@type"
        case title
        case name
        case summary
        case status
        case startsAt = "starts_at"
        case startAt = "start_at"
        case start
        case startTz = "start_tz"
        case due
        case endsAt = "ends_at"
        case endAt = "end_at"
        case end
        case endTz = "end_tz"
        case ticketId = "ticket_id"
        case boardId = "board_id"
        case milestoneId = "milestone_id"
        case role
        case outcome
        case evidenceRefs = "evidence_refs"
        case assignments
        case links
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .eventId)
            ?? c.decodeIfPresent(String.self, forKey: .uid)
            ?? UUID().uuidString
        ownerAgent = try c.decodeIfPresent(String.self, forKey: .ownerAgent)
            ?? c.decodeIfPresent(String.self, forKey: .agent)
            ?? "unassigned"
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
            ?? c.decodeIfPresent(String.self, forKey: .type)
        title = try c.decodeIfPresent(String.self, forKey: .title)
            ?? c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decodeIfPresent(String.self, forKey: .summary)
            ?? "Untitled block"
        status = try c.decodeIfPresent(String.self, forKey: .status)
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt)
            ?? c.decodeIfPresent(String.self, forKey: .startAt)
            ?? Self.dateString(c, .start)
            ?? Self.dateString(c, .startTz)
            ?? Self.dateString(c, .due)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt)
            ?? c.decodeIfPresent(String.self, forKey: .endAt)
            ?? Self.dateString(c, .end)
            ?? Self.dateString(c, .endTz)
        ticketId = try c.decodeIfPresent(String.self, forKey: .ticketId)
            ?? Self.firstString(c, in: .assignments, key: "ticket_id")
            ?? Self.firstString(c, in: .links, key: "ticket_id")
        boardId = try c.decodeIfPresent(String.self, forKey: .boardId)
            ?? Self.firstString(c, in: .assignments, key: "board_id")
            ?? Self.firstString(c, in: .links, key: "board_id")
        milestoneId = try c.decodeIfPresent(String.self, forKey: .milestoneId)
            ?? Self.firstString(c, in: .assignments, key: "milestone_id")
        role = try c.decodeIfPresent(String.self, forKey: .role)
            ?? Self.firstString(c, in: .assignments, key: "role")
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        evidenceRefs = (try? c.decodeIfPresent([String].self, forKey: .evidenceRefs)) ?? []
    }

    var startSortKey: String { startsAt ?? "" }

    var timeLabel: String {
        let start = Self.displayTime(startsAt) ?? "TBD"
        guard let end = Self.displayTime(endsAt), end != start else { return start }
        return "\(start)-\(end)"
    }

    var statusLabel: String {
        (status ?? "planned").replacingOccurrences(of: "_", with: " ").capitalized
    }

    var statusColor: Color {
        switch (status ?? "planned").lowercased() {
        case "active": return AppColors.accentSuccess
        case "done", "closed": return AppColors.textTertiary
        case "overdue", "blocked": return AppColors.accentWarning
        case "cancelled", "canceled": return AppColors.accentDanger
        default: return AppColors.accentElectric
        }
    }

    var linkSummary: String? {
        [ticketId.map { "ticket \($0)" }, boardId.map { "board \($0)" }, milestoneId.map { "milestone \($0)" }]
            .compactMap { $0 }
            .first
    }

    private static func displayTime(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = Self.parseDate(raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }
        if raw.count >= 16 {
            let start = raw.index(raw.startIndex, offsetBy: 11, limitedBy: raw.endIndex) ?? raw.startIndex
            let end = raw.index(start, offsetBy: 5, limitedBy: raw.endIndex) ?? raw.endIndex
            return String(raw[start..<end])
        }
        return raw
    }

    private static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func dateString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        guard let object = try? container.decodeIfPresent([String: AgentRunJSONValue].self, forKey: key) else {
            return nil
        }
        for candidate in ["date_time", "dateTime", "local", "utc", "at", "time"] {
            if let value = object[candidate]?.stringValue, !value.isEmpty {
                return value
            }
        }
        if let date = object["date"]?.stringValue, let time = object["time"]?.stringValue {
            return "\(date)T\(time)"
        }
        return nil
    }

    private static func firstString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        in key: CodingKeys,
        key field: String
    ) -> String? {
        guard let values = try? container.decodeIfPresent([AgentRunJSONValue].self, forKey: key) else {
            return nil
        }
        for value in values {
            guard case .object(let object) = value, let match = object[field]?.stringValue, !match.isEmpty else {
                continue
            }
            return match
        }
        return nil
    }
}

struct PlanningContext: Decodable, Hashable {
    let agent: String
    let asOf: String?
    let currentBlock: PlanningContextBlock?
    let nextBlock: PlanningContextBlock?
    let overdue: [PlanningContextBlock]
    let nextCheckpoint: PlanningContextBlock?
    let dependencyOrder: [String]
    let provenance: [String: AgentRunJSONValue]?

    private enum CodingKeys: String, CodingKey {
        case agent
        case asOf = "as_of"
        case currentBlock = "current_block"
        case nextBlock = "next_block"
        case overdue
        case nextCheckpoint = "next_checkpoint"
        case dependencyOrder = "dependency_order"
        case provenance
    }
}

struct PlanningContextBlock: Decodable, Identifiable, Hashable {
    let eventId: String?
    let title: String
    let ticketId: String?
    let starts: String?
    let ends: String?
    let at: String?
    let wasDue: String?

    var id: String { eventId ?? "\(title)-\(starts ?? at ?? wasDue ?? "")" }

    private enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case title
        case ticketId = "ticket_id"
        case starts
        case ends
        case at
        case wasDue = "was_due"
    }
}

private extension AgentRunJSONValue {
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return "\(value)"
        case .double(let value): return "\(value)"
        case .bool(let value): return value ? "true" : "false"
        case .null, .object, .array: return nil
        }
    }
}

struct PlanningView: View {
    @State private var viewModel = PlanningViewModel()
    @State private var selectedMode: PlanningSurfaceMode = .today

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 14)

                    healthStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    modePicker
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    Group {
                        switch selectedMode {
                        case .today:
                            teamTodaySection
                        case .agent:
                            agentPlanningSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 92)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Planning")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("Today's blocks, current focus, and checkpoint order from ORCA.")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                Task { await viewModel.load() }
            } label: {
                Image(systemName: viewModel.isLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                    .frame(width: 36, height: 36)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Refresh Planning")
        }
    }

    private var healthStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                planningChip(
                    title: "Team",
                    value: "\(viewModel.teamEvents.count)",
                    color: viewModel.errorMessage == nil ? AppColors.accentSuccess : AppColors.accentWarning,
                    icon: viewModel.errorMessage == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                planningChip(
                    title: viewModel.selectedAgent.capitalized,
                    value: "\(viewModel.agentEvents.count)",
                    color: AppColors.accentElectric,
                    icon: "person.crop.circle"
                )
                planningChip(
                    title: "Context",
                    value: viewModel.planningContext == nil ? "0" : "1",
                    color: viewModel.planningContext == nil ? AppColors.textTertiary : AppColors.accentSuccess,
                    icon: "point.topleft.down.curvedto.point.bottomright.up"
                )
                planningChip(
                    title: "Mode",
                    value: "Read",
                    color: AppColors.textSecondary,
                    icon: "lock.open.display"
                )
            }
            .padding(.horizontal, 2)
        }
    }

    private func planningChip(title: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.16), lineWidth: 0.5))
    }

    private var modePicker: some View {
        Picker("Planning view", selection: $selectedMode) {
            ForEach(PlanningSurfaceMode.allCases) { mode in
                Label(mode.title, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var teamTodaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("TEAM TODAY", count: viewModel.teamEvents.count)

            if let error = viewModel.errorMessage, viewModel.teamEvents.isEmpty {
                planningEmpty(icon: "calendar.badge.exclamationmark", title: error)
            } else if viewModel.isLoading && viewModel.teamEvents.isEmpty {
                planningEmpty(icon: "hourglass", title: "Loading planning blocks")
            } else if viewModel.teamEvents.isEmpty {
                planningEmpty(icon: "calendar", title: "No planning blocks for today")
            } else {
                VStack(spacing: 9) {
                    ForEach(viewModel.teamEvents) { event in
                        planningEventCard(event, showAgent: true)
                    }
                }
            }
        }
    }

    private var agentPlanningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            agentPicker

            if let context = viewModel.planningContext {
                contextSection(context)
            } else {
                planningEmpty(icon: "point.topleft.down.curvedto.point.bottomright.up", title: "Planning context unavailable")
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("\(viewModel.selectedAgent.uppercased()) TODAY", count: viewModel.agentEvents.count)
                if viewModel.agentEvents.isEmpty {
                    planningEmpty(icon: "calendar", title: "No blocks for this agent")
                } else {
                    VStack(spacing: 9) {
                        ForEach(viewModel.agentEvents) { event in
                            planningEventCard(event, showAgent: false)
                        }
                    }
                }
            }
        }
    }

    private var agentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(planningAgentOrder, id: \.self) { agent in
                    let isSelected = viewModel.selectedAgent == agent
                    Button {
                        Task { await viewModel.selectAgent(agent) }
                    } label: {
                        Text(agent.capitalized)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? AppColors.accentElectric : AppColors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(isSelected ? AppColors.accentElectric.opacity(0.13) : AppColors.backgroundSecondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? AppColors.accentElectric.opacity(0.45) : AppColors.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func contextSection(_ context: PlanningContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("PLANNING CONTEXT", count: context.contextItemCount)

            if let current = context.currentBlock {
                currentBlockCard(current)
            }
            if let next = context.nextBlock {
                contextRow(label: "Next", block: next, color: AppColors.accentElectric)
            }
            if let checkpoint = context.nextCheckpoint {
                contextRow(label: "Checkpoint", block: checkpoint, color: AppColors.accentWarning)
            }
            ForEach(context.overdue.prefix(3)) { block in
                contextRow(label: "Overdue", block: block, color: AppColors.accentDanger)
            }
            if !context.dependencyOrder.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(context.dependencyOrder.prefix(8), id: \.self) { eventId in
                        Text(String(eventId.prefix(12)))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(AppColors.backgroundTertiary)
                            .clipShape(Capsule())
                    }
                }
            }

            if context.contextItemCount == 0 {
                planningEmpty(icon: "tray", title: "No active planning context")
                    .padding(.top, 2)
            }
        }
        .planningCard()
    }

    private func currentBlockCard(_ block: PlanningContextBlock) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .semibold))
                Text("CURRENT BLOCK")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(AppColors.accentSuccess)

            Text(block.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            let meta = block.contextMeta
            if !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentSuccess.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(AppColors.accentSuccess.opacity(0.28), lineWidth: 0.75)
        )
    }

    private func contextRow(label: String, block: PlanningContextBlock, color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
                .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(block.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                let meta = block.contextMeta
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func planningEventCard(_ event: PlanningEvent, showAgent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.timeLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(event.statusColor)
                    .frame(width: 102, alignment: .leading)

                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                if showAgent {
                    planningPill(event.ownerAgent.capitalized, color: AppColors.accentAgent)
                }
                planningPill(event.statusLabel, color: event.statusColor)
                if let kind = event.kind, !kind.isEmpty {
                    planningPill(kind.replacingOccurrences(of: "_", with: " "), color: AppColors.textSecondary)
                }
                if let role = event.role, !role.isEmpty {
                    planningPill(role, color: AppColors.textSecondary)
                }
                if let link = event.linkSummary {
                    planningPill(link, color: AppColors.accentElectric)
                }
                if !event.evidenceRefs.isEmpty {
                    planningPill("\(event.evidenceRefs.count) evidence", color: AppColors.accentSuccess)
                }
            }

            if let outcome = event.outcome, !outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(outcome)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .planningCard()
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .kerning(0.5)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func planningPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
    }

    private func planningEmpty(icon: String, title: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .planningCard()
    }
}

private extension PlanningContext {
    var contextItemCount: Int {
        [currentBlock, nextBlock, nextCheckpoint].compactMap { $0 }.count
            + overdue.count
            + (dependencyOrder.isEmpty ? 0 : 1)
    }
}

private extension PlanningContextBlock {
    var contextMeta: String {
        [ticketId.map { "ticket \($0)" }, starts.map { "starts \($0)" }, ends.map { "ends \($0)" }, at.map { "at \($0)" }, wasDue.map { "due \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private extension View {
    func planningCard() -> some View {
        self
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
    }
}
