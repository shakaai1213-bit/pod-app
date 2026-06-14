import SwiftUI

// MARK: - Crew Tab (L2 — SPEC-POD-LAYOUT-REVAMP-2026-W22 §4)
//
// Merges Agents + Arms into one tab with a segmented picker.
// "Agents" segment surfaces Focus, Agents roster, and Workers.
// "Dispatch" segment surfaces the arm cards with Wake/Post routing.
// Tap-to-detail preserved via the existing AgentDetailSheet and arm detail flows.

@Observable
final class LeadPlateViewModel {
    var roster: [AgentDTO] = []
    var selectedLeadId = ""
    var draftLeadId = ""
    var plate: LeadPlateReadDTO?
    var isLoadingRoster = false
    var isLoadingPlate = false
    var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    @MainActor
    func loadRosterIfNeeded() async {
        guard roster.isEmpty, !isLoadingRoster else { return }
        isLoadingRoster = true
        defer { isLoadingRoster = false }

        do {
            let response: PaginatedResponse<AgentDTO> = try await apiClient.get(path: Endpoint.agents.path)
            roster = response.items
                .filter { AgentRosterPolicy.isActiveOrSupport($0.name) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if selectedLeadId.isEmpty, let maui = roster.first(where: { $0.name.lowercased() == "maui" }) ?? roster.first {
                selectedLeadId = maui.id
                draftLeadId = maui.id
            }
        } catch {
            errorMessage = "Lead roster unavailable: \(Self.message(for: error))"
        }
    }

    @MainActor
    func selectLead(_ agent: AgentDTO) async {
        selectedLeadId = agent.id
        draftLeadId = agent.id
        await loadPlate()
    }

    @MainActor
    func loadDraftLead() async {
        let trimmed = draftLeadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a lead id before loading the plate."
            return
        }
        selectedLeadId = trimmed
        await loadPlate()
    }

    @MainActor
    func loadPlate() async {
        let leadId = selectedLeadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leadId.isEmpty else {
            plate = nil
            return
        }

        isLoadingPlate = true
        errorMessage = nil
        defer { isLoadingPlate = false }

        do {
            plate = try await apiClient.get(path: Endpoint.leadPlate(leadId: leadId).path)
        } catch {
            plate = nil
            errorMessage = "Lead plate unavailable: \(Self.message(for: error))"
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.message
        }
        return error.localizedDescription
    }
}

struct CrewTabView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case agents
        case leadPlate
        case planning
        case arms

        var id: String { rawValue }

        var title: String {
            switch self {
            case .agents: return "Agents · Focus · Workers"
            case .leadPlate: return "Lead Plate"
            case .planning: return "Planning"
            case .arms:   return "Arm Dispatch"
            }
        }

        var shortTitle: String {
            switch self {
            case .agents: return "Agents"
            case .leadPlate: return "Plate"
            case .planning: return "Plan"
            case .arms:   return "Dispatch"
            }
        }
    }

    @State private var segment: Segment = .agents

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch segment {
                case .agents:
                    AgentsView()
                case .leadPlate:
                    LeadPlateView()
                case .planning:
                    PlanningView()
                case .arms:
                    ArmsTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            segmentDock
                .padding(.bottom, 84)
        }
        .background(AppColors.backgroundPrimary)
    }

    private var segmentDock: some View {
        segmentPicker
            .padding(.horizontal, AppTheme.spacingMD)
            .padding(.top, AppTheme.spacingXS)
            .padding(.bottom, AppTheme.spacingMD)
            .background(
                LinearGradient(
                    colors: [
                        AppColors.backgroundPrimary.opacity(0),
                        AppColors.backgroundPrimary.opacity(0.92),
                        AppColors.backgroundPrimary
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
    }

    private var segmentPicker: some View {
        HStack(spacing: AppTheme.spacingXS) {
            ForEach(Segment.allCases) { seg in
                segmentButton(for: seg)
            }
        }
        .padding(AppTheme.spacingXS)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMedium))
    }

    private func segmentButton(for seg: Segment) -> some View {
        let isSelected = segment == seg
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { segment = seg }
        } label: {
            Text(seg.shortTitle)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? AppColors.accentElectric : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMedium)
                        .fill(isSelected ? AppColors.backgroundPrimary : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seg.title)
    }
}

private struct LeadPlateView: View {
    @State private var viewModel = LeadPlateViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 2)

                    leadSelector
                        .padding(.horizontal, 16)

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                            .padding(.horizontal, 16)
                    }

                    if viewModel.isLoadingPlate && viewModel.plate == nil {
                        loadingState
                            .padding(.horizontal, 16)
                    } else if let plate = viewModel.plate {
                        plateContent(plate)
                            .padding(.horizontal, 16)
                    } else {
                        emptyState
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 96)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable {
                await viewModel.loadRosterIfNeeded()
                await viewModel.loadPlate()
            }
            .task {
                await viewModel.loadRosterIfNeeded()
                await viewModel.loadPlate()
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lead Plate")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("Read-only workload, pressure, and time-ledger view for lead-owned reports.")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                Task { await viewModel.loadPlate() }
            } label: {
                Image(systemName: viewModel.isLoadingPlate ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                    .frame(width: 36, height: 36)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoadingPlate || viewModel.selectedLeadId.isEmpty)
            .accessibilityLabel("Refresh Lead Plate")
        }
    }

    private var leadSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("LEAD", count: viewModel.roster.count, suffix: "candidates")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if viewModel.isLoadingRoster {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(AppColors.accentElectric)
                    }
                    ForEach(viewModel.roster, id: \.id) { agent in
                        Button {
                            Task { await viewModel.selectLead(agent) }
                        } label: {
                            leadChip(agent.name, isSelected: viewModel.selectedLeadId == agent.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }

            HStack(spacing: 8) {
                TextField("Lead id", text: $viewModel.draftLeadId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(AppColors.backgroundPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(AppColors.border, lineWidth: 0.5)
                    )
                    .onSubmit {
                        Task { await viewModel.loadDraftLead() }
                    }

                Button {
                    Task { await viewModel.loadDraftLead() }
                } label: {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.backgroundPrimary)
                        .frame(width: 38, height: 38)
                        .background(AppColors.accentElectric)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingPlate)
                .accessibilityLabel("Load Lead Plate")
            }
        }
        .podCard(padding: 12)
    }

    private func plateContent(_ plate: LeadPlateReadDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            leadHeader(plate.lead)
            summarySection(plate.summary)
            reportsSection(plate.reports)
            decisionQueueSection(plate.decisionQueue)
            diagnosticsSection(plate.source)
        }
    }

    private func leadHeader(_ lead: LeadPlateLeadDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lead.leadName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(lead.leadId)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                metric(label: "Reports", value: "\(lead.activeReportCount)", color: AppColors.accentElectric)
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(lead.ownedBoards) { board in
                    chip(board.displayName, color: AppColors.textSecondary)
                }
                if lead.ownedBoards.isEmpty {
                    chip("No owned boards", color: AppColors.textTertiary)
                }
            }
        }
        .podCard(padding: 14)
    }

    private func summarySection(_ summary: LeadPlateSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SUMMARY", count: summary.idle + summary.blocked + summary.decisionQueue + summary.staleClaim, suffix: "signals")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                metricTile("Idle", summary.idle, color: AppColors.textSecondary)
                metricTile("Blocked", summary.blocked, color: AppColors.accentDanger)
                metricTile("Decision Queue", summary.decisionQueue, color: AppColors.accentElectric)
                metricTile("Stale Claim", summary.staleClaim, color: AppColors.accentWarning)
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(summary.pressureStates.sorted(by: { $0.key < $1.key }), id: \.key) { state, count in
                    chip("\(state.displayLeadPlateLabel): \(count)", color: pressureColor(state))
                }
            }
        }
        .podCard(padding: 14)
    }

    private func reportsSection(_ reports: [LeadPlateReportRowDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("REPORTS", count: reports.count)

            if reports.isEmpty {
                compactEmpty("No active reports for this lead.")
            } else {
                ForEach(reports) { report in
                    reportCard(report)
                }
            }
        }
    }

    private func reportCard(_ report: LeadPlateReportRowDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(report.agentName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                chip(report.pressureState.displayLeadPlateLabel, color: pressureColor(report.pressureState))
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(report.boardRefs) { board in
                    chip(board.displayName, color: AppColors.textSecondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                countTile("Open", report.counts.open, color: AppColors.textSecondary)
                countTile("Claimed", report.counts.claimed, color: AppColors.textSecondary)
                countTile("Doing", report.counts.inProgress, color: AppColors.accentSuccess)
                countTile("Blocked", report.counts.blocked, color: AppColors.accentDanger)
                countTile("Stale", report.counts.staleClaim, color: AppColors.accentWarning)
                countTile("Idle", report.counts.idle, color: AppColors.textTertiary)
                countTile("Decisions", report.counts.decisionQueue, color: AppColors.accentElectric)
                countTile("Workload", report.counts.totalOpenWorkload, color: AppColors.accentElectric)
            }

            digestBlock(title: "Time Ledger", lines: timeLedgerDigest(report.timeLedger))
            digestBlock(title: "Drilldown Tickets", lines: ticketDigest(report.drilldownTicketRefs))

            if !report.pressureReasons.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(Array(report.pressureReasons.prefix(4).enumerated()), id: \.offset) { _, reason in
                        chip(objectDigest(reason), color: AppColors.accentWarning)
                    }
                }
            }
        }
        .podCard(padding: 12)
    }

    private func decisionQueueSection(_ tickets: [LeadPlateDecisionTicketDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("DECISION QUEUE", count: tickets.count)

            if tickets.isEmpty {
                compactEmpty("No tickets waiting for decision.")
            } else {
                ForEach(tickets) { ticket in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(ticket.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            chip(ticket.approvalState.displayLeadPlateLabel, color: AppColors.accentElectric)
                        }
                        Text(ticket.ticketId)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            chip(ticket.status.displayLeadPlateLabel, color: AppColors.textSecondary)
                            if let agentName = ticket.agentName?.nilIfBlank {
                                chip(agentName, color: AppColors.textSecondary)
                            }
                            if let priority = ticket.priority?.nilIfBlank {
                                chip(priority.displayLeadPlateLabel, color: AppColors.accentWarning)
                            }
                            if let boardId = ticket.boardId?.nilIfBlank {
                                chip("Board \(boardId)", color: AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(10)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(AppColors.accentElectric.opacity(0.35), lineWidth: 0.75)
                    )
                }
            }
        }
        .podCard(padding: 14)
    }

    private func diagnosticsSection(_ source: LeadPlateSourceDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SOURCE", count: source.sources.count, suffix: "sources")

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(source.sources, id: \.self) { value in
                    chip(value, color: AppColors.textSecondary)
                }
                ForEach(source.provenance.sorted(by: { $0.key < $1.key }).prefix(6), id: \.key) { key, value in
                    chip("\(key.displayLeadPlateLabel): \(value.scalarDescription)", color: AppColors.textTertiary)
                }
            }

            if !source.gaps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gaps")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.accentWarning)
                    ForEach(Array(source.gaps.prefix(5).enumerated()), id: \.offset) { _, gap in
                        Text(objectDigest(gap))
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .podCard(padding: 14)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(AppColors.accentElectric)
            Text("Loading lead plate")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .podCard(padding: 14)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No lead plate loaded")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
            Text("Choose an agent lead or enter a lead id to load the read-only plate.")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .podCard(padding: 14)
    }

    private func sectionHeader(_ title: String, count: Int, suffix: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
            Text("·")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
            Text(suffix.map { "\(count) \($0)" } ?? "\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)
            Spacer()
        }
    }

    private func leadChip(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isSelected ? AppColors.backgroundPrimary : AppColors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isSelected ? AppColors.accentElectric : AppColors.backgroundPrimary)
            .clipShape(Capsule())
    }

    private func metric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
        }
        .fixedSize()
    }

    private func metricTile(_ label: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(8)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func countTile(_ label: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(7)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func chip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func compactEmpty(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundColor(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentWarning)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColors.accentWarning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func digestBlock(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            if lines.isEmpty {
                Text("No entries")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            } else {
                ForEach(lines.prefix(4), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func timeLedgerDigest(_ ledger: [String: LeadPlateJSONValue]) -> [String] {
        let preferred = ["total_minutes", "active_minutes", "idle_minutes", "blocked_minutes", "last_activity_at", "updated_at"]
        let preferredLines = preferred.compactMap { key -> String? in
            guard let value = ledger[key] else { return nil }
            return "\(key.displayLeadPlateLabel): \(value.scalarDescription)"
        }
        if !preferredLines.isEmpty { return preferredLines }
        return ledger.sorted(by: { $0.key < $1.key }).prefix(4).map { key, value in
            "\(key.displayLeadPlateLabel): \(value.scalarDescription)"
        }
    }

    private func ticketDigest(_ refs: [[String: LeadPlateJSONValue]]) -> [String] {
        refs.prefix(6).map { item in
            let ticket = item["ticket_id"]?.scalarDescription ?? item["id"]?.scalarDescription ?? "ticket"
            let title = item["title"]?.scalarDescription
            let status = item["status"]?.scalarDescription
            return [ticket, title, status].compactMap { $0?.nilIfBlank }.joined(separator: " · ")
        }
    }

    private func objectDigest(_ object: [String: LeadPlateJSONValue]) -> String {
        object.sorted(by: { $0.key < $1.key })
            .prefix(4)
            .map { "\($0.key.displayLeadPlateLabel): \($0.value.scalarDescription)" }
            .joined(separator: " · ")
    }

    private func pressureColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "green":
            return AppColors.accentSuccess
        case "yellow":
            return AppColors.accentWarning
        case "red":
            return AppColors.accentDanger
        default:
            return AppColors.textSecondary
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var displayLeadPlateLabel: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

#Preview {
    CrewTabView()
        .background(AppColors.backgroundPrimary)
}
