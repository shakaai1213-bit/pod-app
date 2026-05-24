import SwiftUI

// MARK: - Work View
// Per SPEC-POD-TABS-HANDOFF §4 — stacked PROJECTS + TICKETS, no segmented control (v3 decision).

struct WorkView: View {
    @State private var model = WorkViewModel()
    @State private var pushProjects = false
    @State private var pushTickets = false
    @State private var pushProjectId: UUID? = nil
    @State private var pushTicketId: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 20)

                    suggestionsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    projectsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    ticketsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable { await model.load() }
            .task { await model.load() }
            // Hidden navigation links for full-list push
            .navigationDestination(isPresented: $pushProjects) {
                ORCAProjectsView()
            }
            .navigationDestination(isPresented: $pushTickets) {
                TicketsView()
            }
            .overlay(alignment: .bottom) {
                if let toast = model.priorityToast {
                    priorityToastView(toast)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast.message)
                        .task(id: toast.message) {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if model.priorityToast == toast {
                                    model.priorityToast = nil
                                }
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.priorityToast)
        }
    }

    private func priorityToastView(_ toast: WorkViewModel.PriorityToast) -> some View {
        let bg = toast.isError ? AppColors.accentDanger : AppColors.backgroundTertiary
        let fg = toast.isError ? Color.white : AppColors.textPrimary
        return HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(fg)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(bg)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)
        .contentShape(Capsule())
        .onTapGesture {
            if let retry = toast.retry {
                model.priorityToast = nil
                retry()
            }
        }
        .accessibilityLabel(toast.message)
        .accessibilityAddTraits(toast.retry != nil ? .isButton : [])
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Work")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            Text("Committed work — projects and the tickets under them.")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Suggestions Section

    private var suggestionsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SUGGESTIONS · \(model.suggestions.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Button {
                    Task { await model.loadSuggestions() }
                } label: {
                    Image(systemName: model.isLoadingSuggestions ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingSuggestions)
                .accessibilityLabel("Refresh Schoolhouse suggestions")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            VStack(spacing: 8) {
                if model.isLoadingSuggestions && model.suggestions.isEmpty {
                    suggestionSkeletons
                } else if let err = model.suggestionsError {
                    errorBanner(message: err) { Task { await model.loadSuggestions() } }
                } else if model.suggestions.isEmpty {
                    emptyState(icon: "sparkle.magnifyingglass", text: "No proposed suggestions waiting.")
                } else {
                    ForEach(model.suggestions.prefix(7)) { suggestion in
                        PodReviewCard(
                            item: suggestionReviewItem(suggestion),
                            isBusy: model.suggestionActionIds.contains(suggestion.id.uuidString),
                            onAction: { action in
                                Task { await model.handleSuggestionAction(action.id, suggestion: suggestion) }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    private func suggestionReviewItem(_ suggestion: SchoolhouseSuggestion) -> PodReviewItem {
        var provenance = [
            suggestion.kind.replacingOccurrences(of: "_", with: " "),
            suggestion.source,
        ]
        if let owner = suggestion.ownerLane, !owner.isEmpty {
            provenance.append(owner)
        }
        if let defaultAction = suggestion.defaultAction, !defaultAction.isEmpty {
            provenance.append("action \(defaultAction)")
        }
        if let dedupeKey = suggestion.dedupeKey, !dedupeKey.isEmpty {
            provenance.append("dedupe \(String(dedupeKey.prefix(12)))")
        }
        if suggestion.dismissCount > 0 {
            provenance.append("dismissed \(suggestion.dismissCount)x")
        }
        if let snoozedUntil = suggestion.snoozedUntil {
            provenance.append("snoozed \(snoozedUntil.formatted(date: .abbreviated, time: .shortened))")
        }

        return PodReviewItem(
            id: suggestion.id.uuidString,
            eyebrow: "Schoolhouse suggestion",
            title: suggestion.title,
            detail: suggestion.summary,
            status: "\(suggestion.riskLevel.uppercased()) · \(suggestion.status)",
            statusColor: suggestion.statusColor,
            provenance: provenance,
            traceId: suggestion.traceId,
            artifactHash: suggestion.artifactHash,
            actions: suggestionActions(for: suggestion)
        )
    }

    private func suggestionActions(for suggestion: SchoolhouseSuggestion) -> [PodReviewAction] {
        let isTerminal = ["accepted", "dismissed", "expired", "converted"].contains(suggestion.status.lowercased())
        return [
            PodReviewAction(
                id: "accept",
                title: "Accept",
                systemImage: "checkmark.seal",
                style: .success,
                isDisabled: isTerminal
            ),
            PodReviewAction(
                id: "convert-ticket",
                title: "Ticket",
                systemImage: "text.badge.plus",
                style: .primary,
                isDisabled: isTerminal
            ),
            PodReviewAction(
                id: "snooze",
                title: "Snooze",
                systemImage: "clock",
                style: .warning,
                isDisabled: isTerminal
            ),
            PodReviewAction(
                id: "dismiss",
                title: "Dismiss",
                systemImage: "xmark.circle",
                style: .destructive,
                isDisabled: isTerminal
            ),
        ]
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("PROJECTS · \(model.projects.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Button {
                    model.showingNewProject = true
                } label: {
                    Text("+ New")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Card
            VStack(spacing: 0) {
                if model.isLoadingProjects && model.projects.isEmpty {
                    projectSkeletons
                } else if let err = model.projectsError {
                    errorBanner(message: err) { Task { await model.loadProjects() } }
                } else if model.projects.isEmpty {
                    emptyState(icon: "square.stack.3d.up", text: "No active projects. Tap + New to start one.")
                } else {
                    ForEach(Array(model.projects.prefix(6).enumerated()), id: \.element.id) { idx, project in
                        VStack(spacing: 0) {
                            if idx > 0 {
                                Divider()
                                    .background(AppColors.border)
                                    .padding(.horizontal, 14)
                            }
                            projectRow(project)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    pushProjectId = project.id
                                    pushProjects = true
                                }
                        }
                    }

                    // View all footer
                    Divider().background(AppColors.border)
                    Button {
                        pushProjects = true
                    } label: {
                        HStack {
                            Text("View all \(model.projects.count) projects ›")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.accentElectric)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
        }
    }

    private func projectRow(_ project: ProjectDTO) -> some View {
        HStack(spacing: 10) {
            // short_id chip
            Text(String(project.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hexString: "0e0e10"))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(AppColors.border, lineWidth: 0.5)
                )

            // Name
            Text(project.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Stage pill
            if let stage = project.stage {
                stagePill(stage)
            }

            // Priority dot — tap to change (P1–P5)
            Menu {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        Task { await model.updateProjectPriority(projectId: project.id, priority: level) }
                    } label: {
                        HStack {
                            Text("P\(level)")
                            if project.priority == level {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(priorityColorInt(project.priority))
                    .frame(width: 7, height: 7)
            }
            .accessibilityLabel("Priority P\(project.priority). Tap to change.")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }

    private func stagePill(_ stage: String) -> some View {
        let (text, fg, bg): (String, Color, Color) = {
            switch stage.lowercased() {
            case "live":       return ("live",      AppColors.accentSuccess,  AppColors.accentSuccess.opacity(0.15))
            case "blueprint":  return ("blueprint", AppColors.textTertiary,  AppColors.textTertiary.opacity(0.12))
            case "build":      return ("build",     AppColors.accentWarning, AppColors.accentWarning.opacity(0.12))
            case "dds":        return ("dds",       AppColors.accentElectric, AppColors.accentElectric.opacity(0.12))
            case "sop":        return ("sop",       AppColors.accentAgent,   AppColors.accentAgent.opacity(0.12))
            case "maintain":   return ("maintain",  AppColors.accentSuccess,  AppColors.accentSuccess.opacity(0.12))
            default:           return (stage,       AppColors.textTertiary,  AppColors.textTertiary.opacity(0.12))
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }

    // MARK: - Tickets Section

    private var ticketsSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("TICKETS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .kerning(0.5)
                Spacer()
                Text("\(model.openTicketCount) open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Card
            VStack(spacing: 0) {
                // Filter bar (sticky inside card)
                ticketFilterBar

                Divider().background(AppColors.border)

                if model.isLoadingTickets && model.tickets.isEmpty {
                    ticketSkeletons
                } else if let err = model.ticketsError {
                    errorBanner(message: err) { Task { await model.loadTickets() } }
                } else if model.filteredTickets.isEmpty {
                    emptyState(icon: "ticket", text: "No open tickets in this view.")
                } else {
                    ForEach(Array(model.filteredTickets.prefix(3).enumerated()), id: \.element.id) { idx, ticket in
                        VStack(spacing: 0) {
                            if idx > 0 {
                                Divider()
                                    .background(AppColors.border)
                                    .padding(.horizontal, 14)
                            }
                            ticketRow(ticket)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    pushTicketId = ticket.id
                                    pushTickets = true
                                }
                        }
                    }

                    // View all footer
                    Divider().background(AppColors.border)
                    Button {
                        pushTickets = true
                    } label: {
                        HStack {
                            Text("View all \(model.filteredTickets.count) tickets ›")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.accentElectric)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
        }
    }

    private var ticketFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkViewModel.TicketFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func filterChip(_ filter: WorkViewModel.TicketFilter) -> some View {
        let isOn = model.activeFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.activeFilter = filter
            }
        } label: {
            Text(filter.label)
                .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                .foregroundColor(isOn ? Color.black : AppColors.textSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(isOn ? AppColors.textPrimary : Color.clear)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isOn ? Color.clear : AppColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 30)
    }

    private func ticketRow(_ ticket: WorkTicketRow) -> some View {
        HStack(spacing: 8) {
            // Priority dot — tap to edit per Aloha 2026-05-23 (ticket 46ca818d)
            Menu {
                ForEach(["urgent", "high", "medium", "low"], id: \.self) { level in
                    Button {
                        Task { await model.updateTicketPriority(ticketId: ticket.id, priority: level) }
                    } label: {
                        HStack {
                            Circle().fill(priorityColor(level)).frame(width: 7, height: 7)
                            Text(level.capitalized)
                            if ticket.priority.lowercased() == level {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(priorityColor(ticket.priority))
                    .frame(width: 7, height: 7)
                    .padding(.leading, 4)
                    .frame(width: 24, height: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Priority: \(ticket.priority). Tap to change.")

            // short_id chip — mirrors Project card chip per Tony 2026-05-23
            ticketShortIdChip(ticket.id)

            // Title
            Text(ticket.title)
                .font(.system(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Owner · priority meta (owner is resolved agent name per ticket 7d4c89a7)
            Text("\(ticket.ownerShort) · \(ticket.priority)")
                .font(.system(size: 11))
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
    }

    private func ticketShortIdChip(_ id: String) -> some View {
        Text(String(id.replacingOccurrences(of: "-", with: "").prefix(8)))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(hexString: "0e0e10"))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
            .accessibilityLabel("Ticket ID \(id.prefix(8))")
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "urgent": return AppColors.accentDanger
        case "high":   return AppColors.accentWarning
        case "medium": return AppColors.accentElectric
        default:       return AppColors.textTertiary
        }
    }

    private func priorityColorInt(_ priority: Int) -> Color {
        switch priority {
        case 1: return AppColors.accentDanger
        case 2: return AppColors.accentWarning
        case 3: return AppColors.accentElectric
        case 4: return AppColors.accentSuccess
        default: return AppColors.textTertiary
        }
    }

    // MARK: - Skeleton / Error / Empty

    private var projectSkeletons: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                skeletonRow(height: 44)
            }
        }
    }

    private var ticketSkeletons: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                skeletonRow(height: 40)
            }
        }
    }

    private var suggestionSkeletons: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { _ in
                skeletonRow(height: 74)
                    .background(AppColors.backgroundPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func skeletonRow(height: CGFloat) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.backgroundTertiary)
                .frame(width: 70, height: 16)
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.backgroundTertiary)
                .frame(height: 16)
        }
        .padding(.horizontal, 14)
        .frame(height: height)
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentDanger)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Button("Retry", action: retry)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)
        }
        .padding(14)
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(14)
    }
}

// MARK: - Work View Model

@Observable
final class WorkViewModel {
    // MARK: Projects
    var projects: [ProjectDTO] = []
    var isLoadingProjects = false
    var projectsError: String?

    // MARK: Tickets
    var tickets: [WorkTicketRow] = []
    var openTicketCount = 0
    var isLoadingTickets = false
    var ticketsError: String?
    var activeFilter: TicketFilter = .all
    var priorityToast: PriorityToast?

    // MARK: Suggestions
    var suggestions: [SchoolhouseSuggestion] = []
    var isLoadingSuggestions = false
    var suggestionsError: String?
    var suggestionActionIds: Set<String> = []

    struct PriorityToast: Equatable {
        let message: String
        let isError: Bool
        let retry: (() -> Void)?
        static func == (lhs: PriorityToast, rhs: PriorityToast) -> Bool {
            lhs.message == rhs.message && lhs.isError == rhs.isError
        }
    }

    // MARK: Sheet
    var showingNewProject = false

    // MARK: - Ticket Filter

    enum TicketFilter: CaseIterable, Equatable {
        case all, mine, urgent, byProject

        var label: String {
            switch self {
            case .all:       return "All"
            case .mine:      return "Mine"
            case .urgent:    return "Urgent"
            case .byProject: return "By project"
            }
        }
    }

    var filteredTickets: [WorkTicketRow] {
        switch activeFilter {
        case .all:
            return tickets
        case .mine:
            return tickets.filter { $0.ownerShort.lowercased().hasPrefix("mau") || $0.assigneeId == "maui" }
        case .urgent:
            return tickets.filter { $0.priority.lowercased() == "urgent" }
        case .byProject:
            // Group by project — just sort by projectId for now
            return tickets.sorted { ($0.projectId ?? "") < ($1.projectId ?? "") }
        }
    }

    // MARK: - Load

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSuggestions() }
            group.addTask { await self.loadProjects() }
            group.addTask { await self.loadTickets() }
        }
    }

    @MainActor
    func loadSuggestions() async {
        isLoadingSuggestions = true
        suggestionsError = nil
        defer { isLoadingSuggestions = false }
        do {
            let items: [SchoolhouseSuggestion] = try await APIClient.shared.get(path: "/api/v1/schoolhouse/suggestions?status=proposed&limit=7")
            suggestions = items.sorted { $0.sortScore > $1.sortScore }
        } catch {
            suggestionsError = "Suggestions unavailable"
        }
    }

    @MainActor
    func loadProjects() async {
        isLoadingProjects = true
        projectsError = nil
        defer { isLoadingProjects = false }
        do {
            let all: [ProjectDTO] = try await APIClient.shared.get(path: "/api/v1/projects/")
            // Show active-ish projects: exclude archived/cancelled
            projects = all.filter { p in
                let excluded = ["archived", "cancelled", "done"]
                return !excluded.contains(p.status.lowercased())
            }
            .sorted { $0.priority < $1.priority }
        } catch {
            projectsError = "Projects unavailable"
        }
    }

    @MainActor
    func loadTickets() async {
        isLoadingTickets = true
        ticketsError = nil
        defer { isLoadingTickets = false }
        do {
            struct TicketListItem: Decodable {
                let id: String
                let title: String
                let status: String
                let priority: String
                let assigneeAgentId: String?
                enum CodingKeys: String, CodingKey {
                    case id, title, status, priority
                    case assigneeAgentId = "assignee_agent_id"
                }
            }
            // Per ticket 7d4c89a7 (UUID→name resolution): fetch tickets AND agents in parallel,
            // resolve assigneeAgentId UUIDs to names client-side.
            async let ticketsAsync: [TicketListItem] = APIClient.shared.get(path: "/api/v1/tickets?status=open&limit=200")
            async let agentsAsync: [AgentNameOnly] = APIClient.shared.get(path: "/api/v1/agents?limit=200")

            let raw = try await ticketsAsync
            let agentList = (try? await agentsAsync) ?? []
            let agentNames: [String: String] = Dictionary(uniqueKeysWithValues: agentList.map { ($0.id, $0.name) })

            openTicketCount = raw.count

            // Priority sort order
            let order: [String: Int] = ["urgent": 0, "high": 1, "medium": 2, "low": 3]
            tickets = raw
                .sorted { (order[$0.priority] ?? 9) < (order[$1.priority] ?? 9) }
                .map { t in
                    let ownerLabel: String = {
                        guard let aid = t.assigneeAgentId else { return "—" }
                        // Look up name; fall back to UUID prefix for orphan IDs (logged but visible)
                        if let name = agentNames[aid] {
                            return name.lowercased()
                        }
                        return String(aid.prefix(6))
                    }()
                    return WorkTicketRow(
                        id: t.id,
                        title: t.title,
                        priority: t.priority,
                        ownerShort: ownerLabel,
                        assigneeId: t.assigneeAgentId,
                        projectId: nil
                    )
                }
        } catch {
            ticketsError = "Tickets unavailable"
        }
    }

    // Tap-to-edit priority — optimistic local update, revert on failure.
    @MainActor
    func updateTicketPriority(ticketId: String, priority: String) async {
        guard let idx = tickets.firstIndex(where: { $0.id == ticketId }) else { return }
        let original = tickets[idx].priority
        guard original.lowercased() != priority.lowercased() else { return }
        tickets[idx].priority = priority
        struct Body: Encodable { let priority: String }
        do {
            let _: TicketPatchResponse = try await APIClient.shared.patch(
                path: "/api/v1/tickets/\(ticketId)",
                body: Body(priority: priority)
            )
            priorityToast = PriorityToast(
                message: "Priority → \(priority.capitalized)",
                isError: false,
                retry: nil
            )
        } catch {
            if let restoreIdx = tickets.firstIndex(where: { $0.id == ticketId }) {
                tickets[restoreIdx].priority = original
            }
            priorityToast = PriorityToast(
                message: "Couldn't update — tap to retry",
                isError: true,
                retry: { [weak self] in
                    Task { await self?.updateTicketPriority(ticketId: ticketId, priority: priority) }
                }
            )
        }
    }

    // Tap-to-edit project priority — optimistic local update, revert on failure.
    @MainActor
    func updateProjectPriority(projectId: UUID, priority: Int) async {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        let original = projects[idx].priority
        guard original != priority else { return }
        // Rebuild with updated priority (ProjectDTO is a let-struct)
        let old = projects[idx]
        projects[idx] = ProjectDTO(
            id: old.id, name: old.name, goal: old.goal, description: old.description,
            status: old.status, priority: priority, projectedCost: old.projectedCost,
            actualCost: old.actualCost, createdBy: old.createdBy, assignedTo: old.assignedTo,
            createdAt: old.createdAt, updatedAt: old.updatedAt,
            startedAt: old.startedAt, completedAt: old.completedAt, dueDate: old.dueDate,
            stage: old.stage
        )
        struct Body: Encodable { let priority: Int }
        do {
            let _: ProjectPatchResponse = try await APIClient.shared.patch(
                path: "/api/v1/projects/\(projectId)",
                body: Body(priority: priority)
            )
            priorityToast = PriorityToast(message: "Priority → P\(priority)", isError: false, retry: nil)
        } catch {
            if let restoreIdx = projects.firstIndex(where: { $0.id == projectId }) {
                let cur = projects[restoreIdx]
                projects[restoreIdx] = ProjectDTO(
                    id: cur.id, name: cur.name, goal: cur.goal, description: cur.description,
                    status: cur.status, priority: original, projectedCost: cur.projectedCost,
                    actualCost: cur.actualCost, createdBy: cur.createdBy, assignedTo: cur.assignedTo,
                    createdAt: cur.createdAt, updatedAt: cur.updatedAt,
                    startedAt: cur.startedAt, completedAt: cur.completedAt, dueDate: cur.dueDate,
                    stage: cur.stage
                )
            }
            priorityToast = PriorityToast(
                message: "Couldn't update — tap to retry",
                isError: true,
                retry: { [weak self] in
                    Task { await self?.updateProjectPriority(projectId: projectId, priority: priority) }
                }
            )
        }
    }

    @MainActor
    func handleSuggestionAction(_ actionId: String, suggestion: SchoolhouseSuggestion) async {
        guard !suggestionActionIds.contains(suggestion.id.uuidString) else { return }
        suggestionActionIds.insert(suggestion.id.uuidString)
        defer { suggestionActionIds.remove(suggestion.id.uuidString) }

        do {
            let updated: SchoolhouseSuggestion
            switch actionId {
            case "accept":
                updated = try await APIClient.shared.post(
                    path: "/api/v1/schoolhouse/suggestions/\(suggestion.id.uuidString)/accept",
                    body: SuggestionDecisionBody(actor: "maui", reason: "Accepted from Pod Work.")
                )
            case "dismiss":
                updated = try await APIClient.shared.post(
                    path: "/api/v1/schoolhouse/suggestions/\(suggestion.id.uuidString)/dismiss",
                    body: SuggestionDecisionBody(actor: "maui", reason: "Dismissed from Pod Work.")
                )
            case "snooze":
                let until = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                updated = try await APIClient.shared.post(
                    path: "/api/v1/schoolhouse/suggestions/\(suggestion.id.uuidString)/snooze",
                    body: SuggestionSnoozeBody(snoozedUntil: until, actor: "maui", reason: "Snoozed from Pod Work.")
                )
            case "convert-ticket":
                updated = try await APIClient.shared.post(
                    path: "/api/v1/schoolhouse/suggestions/\(suggestion.id.uuidString)/convert-to-ticket",
                    body: SuggestionConvertBody(
                        actor: "maui",
                        title: suggestion.title,
                        description: suggestion.ticketDescription,
                        priority: suggestion.ticketPriority,
                        ticketType: "feature",
                        tags: ["schoolhouse", "suggestion", suggestion.kind]
                    )
                )
            default:
                return
            }
            replaceSuggestion(updated)
            priorityToast = PriorityToast(message: "Suggestion \(updated.status)", isError: false, retry: nil)
            await loadTickets()
        } catch {
            priorityToast = PriorityToast(
                message: "Suggestion action failed — tap to retry",
                isError: true,
                retry: { [weak self] in
                    Task { await self?.handleSuggestionAction(actionId, suggestion: suggestion) }
                }
            )
        }
    }

    private func replaceSuggestion(_ suggestion: SchoolhouseSuggestion) {
        if let idx = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
            if suggestion.status == "proposed" || suggestion.status == "snoozed" {
                suggestions[idx] = suggestion
            } else {
                suggestions.remove(at: idx)
            }
        } else if suggestion.status == "proposed" {
            suggestions.insert(suggestion, at: 0)
        }
    }
}

private struct SuggestionDecisionBody: Encodable {
    let actor: String
    let reason: String
}

private struct SuggestionSnoozeBody: Encodable {
    let snoozedUntil: Date
    let actor: String
    let reason: String
}

private struct SuggestionConvertBody: Encodable {
    let actor: String
    let title: String
    let description: String
    let priority: String
    let ticketType: String
    let tags: [String]
}

private struct TicketPatchResponse: Decodable {
    let id: String
}

private struct ProjectPatchResponse: Decodable {
    let id: UUID
}

// MARK: - Schoolhouse Suggestions

struct SchoolhouseSuggestion: Decodable, Identifiable, Hashable {
    let id: UUID
    let kind: String
    let title: String
    let summary: String?
    let status: String
    let source: String
    let sourceRefs: [String: AgentRunJSONValue]?
    let provenance: [String: AgentRunJSONValue]?
    let riskLevel: String
    let ownerLane: String?
    let actionOptions: [AgentRunJSONValue]?
    let defaultAction: String?
    let dedupeKey: String?
    let dismissCount: Int
    let snoozedUntil: Date?
    let convertedTo: [String: AgentRunJSONValue]?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title, summary, status, source, provenance
        case sourceRefs = "source_refs"
        case riskLevel = "risk_level"
        case ownerLane = "owner_lane"
        case actionOptions = "action_options"
        case defaultAction = "default_action"
        case dedupeKey = "dedupe_key"
        case dismissCount = "dismiss_count"
        case snoozedUntil = "snoozed_until"
        case convertedTo = "converted_to"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var traceId: String? {
        stringValue(for: ["trace_id", "agent_run_id", "run_id"], in: provenance)
            ?? stringValue(for: ["trace_id", "agent_run_id", "run_id"], in: sourceRefs)
    }

    var artifactHash: String? {
        stringValue(for: ["sha256", "artifact_hash", "hash"], in: provenance)
            ?? stringValue(for: ["sha256", "artifact_hash", "hash"], in: sourceRefs)
    }

    var ticketPriority: String {
        switch riskLevel.lowercased() {
        case "protected", "tier1": return "high"
        case "tier2": return "medium"
        default: return "low"
        }
    }

    var ticketDescription: String {
        [
            "Converted from Schoolhouse suggestion \(id.uuidString).",
            summary,
            "Kind: \(kind)",
            "Risk: \(riskLevel)",
            ownerLane.map { "Owner lane: \($0)" },
            traceId.map { "Trace: \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    var statusColor: Color {
        switch status.lowercased() {
        case "accepted", "converted":
            return AppColors.accentSuccess
        case "dismissed", "expired":
            return AppColors.textTertiary
        case "snoozed":
            return AppColors.accentWarning
        default:
            switch riskLevel.lowercased() {
            case "protected", "tier1": return AppColors.accentDanger
            case "tier2": return AppColors.accentWarning
            default: return AppColors.accentElectric
            }
        }
    }

    var sortScore: Int {
        let riskScore: Int
        switch riskLevel.lowercased() {
        case "protected": riskScore = 400
        case "tier1": riskScore = 300
        case "tier2": riskScore = 200
        default: riskScore = 100
        }
        let age = min(99, Int(Date().timeIntervalSince(updatedAt) / 3600))
        return riskScore + age
    }

    private func stringValue(for keys: [String], in values: [String: AgentRunJSONValue]?) -> String? {
        guard let values else { return nil }
        for key in keys {
            if let value = values[key]?.displayValue, !value.isEmpty, value != "null" {
                return value
            }
        }
        return nil
    }
}

// MARK: - Work Ticket Row

struct WorkTicketRow: Identifiable {
    let id: String
    let title: String
    var priority: String
    let ownerShort: String   // resolved agent name (lowercased) or 6-char UUID prefix
    let assigneeId: String?
    let projectId: String?
}

// Lightweight agent decode for UUID→name resolution
private struct AgentNameOnly: Decodable {
    let id: String
    let name: String
}
