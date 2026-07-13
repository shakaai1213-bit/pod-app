import Observation
import SwiftUI

private func managementColor(_ state: String) -> Color {
    switch state.lowercased() {
    case "green", "current", "done", "closed", "completed", "active":
        return AppColors.accentSuccess
    case "yellow", "stale", "in_progress", "in-progress", "review", "working":
        return AppColors.accentWarning
    case "red", "blocked", "failed", "waiting_on":
        return AppColors.accentDanger
    default:
        return AppColors.textTertiary
    }
}

private func managementErrorText(_ error: Error) -> String {
    if let apiError = error as? APIError { return apiError.message }
    return error.localizedDescription
}

// MARK: - Board Plan

@MainActor
@Observable
final class CaptainBoardPlanViewModel {
    private(set) var boards: [ManagementBoardDirectoryDTO] = []
    private(set) var plan: BoardPlanResponseDTO?
    private(set) var isLoading = false
    private(set) var mutatingCardId: String?
    private(set) var errorMessage: String?
    var selectedBoardId: UUID?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func load(boardId: UUID? = nil, force: Bool = false) async {
        guard !isLoading else { return }
        if !force, plan != nil, boardId == nil || boardId == selectedBoardId { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: ManagementBoardDirectoryResponseDTO = try await apiClient.get(path: "/api/v1/boards")
            boards = response.items
                .filter { $0.slug.lowercased() != "fund" }
                .sorted { lhs, rhs in
                    if lhs.slug == "pod" { return true }
                    if rhs.slug == "pod" { return false }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            if let boardId, boards.contains(where: { $0.id == boardId }) {
                selectedBoardId = boardId
            } else if selectedBoardId == nil || !boards.contains(where: { $0.id == selectedBoardId }) {
                selectedBoardId = boards.first(where: { $0.slug == "pod" })?.id ?? boards.first?.id
            }
            await loadSelectedBoard()
        } catch {
            errorMessage = "Board plan unavailable: \(managementErrorText(error))"
        }
    }

    func select(_ board: ManagementBoardDirectoryDTO) async {
        guard selectedBoardId != board.id else { return }
        selectedBoardId = board.id
        plan = nil
        await loadSelectedBoard()
    }

    func loadSelectedBoard() async {
        guard let selectedBoardId else {
            plan = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            plan = try await apiClient.get(path: "/api/v1/management/boards/\(selectedBoardId.uuidString)/plan")
        } catch {
            plan = nil
            errorMessage = "Board plan unavailable: \(managementErrorText(error))"
        }
    }

    func togglePin(_ card: BoardPlanCardDTO) async {
        guard let selectedBoardId, mutatingCardId == nil else { return }
        mutatingCardId = card.id
        defer { mutatingCardId = nil }
        do {
            if let pin = plan?.pins.first(where: {
                $0.objectType == card.objectType && $0.objectId == card.objectId
            }) {
                try await apiClient.delete(
                    path: "/api/v1/management/boards/\(selectedBoardId.uuidString)/pins/\(pin.id.uuidString)"
                )
            } else {
                let request = BoardPlanPinRequestDTO(
                    objectType: card.objectType,
                    objectId: card.objectId,
                    rank: card.rank == 10_000 ? 100 : card.rank
                )
                let _: BoardPlanPinDTO = try await apiClient.post(
                    path: "/api/v1/management/boards/\(selectedBoardId.uuidString)/pins",
                    body: request
                )
            }
            await loadSelectedBoard()
        } catch {
            errorMessage = "Plan update unavailable: \(managementErrorText(error))"
        }
    }
}

struct CaptainBoardPlanView: View {
    @Bindable var model: CaptainBoardPlanViewModel
    var allowsBoardSelection = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedCard: BoardPlanCardDTO?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            header

            if let errorMessage = model.errorMessage, model.plan == nil {
                managementError(errorMessage)
            } else if model.isLoading, model.plan == nil {
                HStack(spacing: Theme.sm) {
                    ProgressView().tint(AppColors.accentElectric)
                    Text("Joining ORCA work into the board plan")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
            } else if let plan = model.plan {
                lanes(plan)
                footer(plan)
            } else {
                managementError("No ORCA board is available for this organization.")
            }
        }
        .sheet(item: $selectedCard) { card in
            BoardPlanCardDetail(card: card)
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BOARD PLAN")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.textTertiary)
                Text(model.plan?.boardName ?? "ORCA work")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer(minLength: Theme.sm)

            if allowsBoardSelection {
                Menu {
                    ForEach(model.boards) { board in
                        Button {
                            Task { await model.select(board) }
                        } label: {
                            if board.id == model.selectedBoardId {
                                Label(board.name, systemImage: "checkmark")
                            } else {
                                Text(board.name)
                            }
                        }
                    }
                } label: {
                    Label("Board", systemImage: "rectangle.3.group")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.accentElectric)
                }
                .help("Choose ORCA board")
            }

            Button {
                Task { await model.loadSelectedBoard() }
            } label: {
                Image(systemName: model.isLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentElectric)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
            .help("Refresh board plan")
            .accessibilityLabel("Refresh board plan")
        }
    }

    private func lanes(_ plan: BoardPlanResponseDTO) -> some View {
        let laneWidth: CGFloat = horizontalSizeClass == .regular ? 270 : 238
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.sm) {
                ForEach(plan.lanes) { lane in
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        HStack(spacing: 7) {
                            Image(systemName: laneIcon(lane.key))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(laneColor(lane.key))
                            Text(lane.title.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(laneColor(lane.key))
                            Spacer(minLength: 4)
                            Text("\(lane.cards.count)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .frame(height: 24)

                        if lane.cards.isEmpty {
                            Text("No canonical work in this lane")
                                .font(.caption)
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppColors.border, style: StrokeStyle(lineWidth: 1, dash: [4]))
                                )
                        } else {
                            LazyVStack(spacing: Theme.xs) {
                                ForEach(lane.cards) { card in
                                    BoardPlanCardView(
                                        card: card,
                                        accent: laneColor(lane.key),
                                        isMutating: model.mutatingCardId == card.id,
                                        onOpen: { selectedCard = card },
                                        onTogglePin: { Task { await model.togglePin(card) } }
                                    )
                                }
                            }
                        }
                    }
                    .frame(width: laneWidth, alignment: .top)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func footer(_ plan: BoardPlanResponseDTO) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(AppColors.accentSuccess)
            Text("\(plan.selectionMode == "pins_plus_canonical" ? "Pinned + canonical" : "Canonical") · ORCA · \(plan.computedAt, style: .relative)")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
            Spacer(minLength: 0)
        }
    }

    private func laneColor(_ key: String) -> Color {
        switch key {
        case "done": return AppColors.accentSuccess
        case "in_progress": return AppColors.accentWarning
        case "up_next": return Color(hexString: "22D3EE")
        default: return Color(hexString: "FB7185")
        }
    }

    private func laneIcon(_ key: String) -> String {
        switch key {
        case "done": return "checkmark.circle.fill"
        case "in_progress": return "hammer.fill"
        case "up_next": return "tray.full.fill"
        default: return "hourglass"
        }
    }

    private func managementError(_ text: String) -> some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.accentWarning)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct BoardPlanCardView: View {
    let card: BoardPlanCardDTO
    let accent: Color
    let isMutating: Bool
    let onOpen: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Text(card.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)
                Spacer(minLength: 4)
                Button(action: onTogglePin) {
                    Image(systemName: card.pinned ? "pin.fill" : "pin")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(card.pinned ? accent : AppColors.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
                .help(card.pinned ? "Remove from board plan" : "Pin to board plan")
                .accessibilityLabel(card.pinned ? "Unpin \(card.title)" : "Pin \(card.title)")
            }

            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)
            }

            if let waitReason = card.waitReason, !waitReason.isEmpty {
                Label(waitReason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.accentDanger)
                    .lineLimit(2)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)
            }

            HStack(spacing: 6) {
                Label(card.objectType.capitalized, systemImage: objectIcon)
                if let ownerName = card.ownerName, !ownerName.isEmpty {
                    Label(ownerName.capitalized, systemImage: "person.fill")
                }
                Spacer(minLength: 0)
                Image(systemName: card.latestEvidence == nil ? "questionmark.diamond" : "link.circle.fill")
                    .foregroundStyle(managementColor(card.evidenceState))
            }
            .font(.caption2)
            .foregroundStyle(AppColors.textTertiary)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .padding(Theme.sm)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(accent.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.42), lineWidth: 1)
        )
    }

    private var objectIcon: String {
        switch card.objectType {
        case "ticket": return "ticket.fill"
        case "project": return "square.stack.3d.up.fill"
        default: return "checklist"
        }
    }
}

private struct BoardPlanCardDetail: View {
    let card: BoardPlanCardDTO
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Canonical State") {
                    LabeledContent("Type", value: card.objectType.capitalized)
                    LabeledContent("State", value: card.canonicalState.replacingOccurrences(of: "_", with: " ").capitalized)
                    if let owner = card.ownerName { LabeledContent("Owner", value: owner.capitalized) }
                    LabeledContent("ORCA", value: card.canonicalRef)
                }
                if let reason = card.waitReason {
                    Section("Waiting On") { Text(reason) }
                }
                Section("Evidence") {
                    if let evidence = card.latestEvidence {
                        LabeledContent(evidence.kind.replacingOccurrences(of: "_", with: " ").capitalized, value: evidence.ref)
                    } else {
                        Text("No completion evidence is linked.")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .navigationTitle(card.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

// MARK: - Crew Management

enum AgentManagementMode: String {
    case focus
    case load
    case plan
    case dispatch

    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .focus: return "scope"
        case .load: return "gauge.with.dots.needle.50percent"
        case .plan: return "list.bullet.clipboard"
        case .dispatch: return "paperplane.fill"
        }
    }
}

@MainActor
@Observable
final class AgentManagementViewModel {
    private(set) var response: AgentManagementResponseDTO?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, response != nil { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            response = try await APIClient.shared.get(path: "/api/v1/management/agents")
        } catch {
            errorMessage = "Crew management unavailable: \(managementErrorText(error))"
        }
    }
}

struct AgentManagementRosterView: View {
    @Bindable var model: AgentManagementViewModel
    let mode: AgentManagementMode

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    header
                    if let response = model.response {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 300), spacing: Theme.sm)],
                            spacing: Theme.sm
                        ) {
                            ForEach(response.agents) { agent in
                                AgentManagementCardView(agent: agent, mode: mode)
                            }
                        }
                        Text("ORCA · \(response.computedAt, style: .relative) · \(response.unknownCount) incomplete")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                    } else if model.isLoading {
                        ProgressView("Joining seven-agent ORCA state")
                            .tint(AppColors.accentElectric)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        Label(model.errorMessage ?? "Crew management unavailable", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.accentWarning)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .padding(.horizontal, Theme.md)
                .padding(.top, 56)
                .padding(.bottom, 150)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable { await model.load(force: true) }
            .task { await model.load() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Crew · \(mode.title)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Seven signed agents · ORCA lifecycle, work, evidence, and Schoolhouse dispatch")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.sm)
            Button { Task { await model.load(force: true) } } label: {
                Image(systemName: model.isLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.accentElectric)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .help("Refresh crew")
            .accessibilityLabel("Refresh crew")
        }
    }
}

private struct AgentManagementCardView: View {
    let agent: AgentManagementCardDTO
    let mode: AgentManagementMode

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .top, spacing: Theme.sm) {
                ZStack {
                    Circle()
                        .fill(managementColor(agent.wakeStatus).opacity(0.14))
                        .frame(width: 42, height: 42)
                    Text(String(agent.displayName.prefix(1)).uppercased())
                        .font(.headline.weight(.bold))
                        .foregroundStyle(managementColor(agent.wakeStatus))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(agent.title ?? agent.lifecycleStatus.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: mode.icon)
                    .foregroundStyle(managementColor(agent.wakeStatus))
            }

            modeContent
            themeFooter
        }
        .padding(Theme.md)
        .frame(maxWidth: .infinity, minHeight: 224, alignment: .topLeading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(managementColor(agent.wakeStatus).opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .focus:
            if agent.focus.items.isEmpty {
                unknownRow(agent.focus.source.detail)
            } else {
                ForEach(agent.focus.items.prefix(3)) { item in
                    detailRow(icon: "scope", title: item.title, detail: item.state)
                }
            }
        case .load:
            HStack(spacing: Theme.xs) {
                metric("Tickets", agent.load.activeTickets)
                metric("Tasks", agent.load.activeTasks)
                metric("Plan", agent.load.plannerItems)
                metric("Runs", agent.load.activeRuns)
            }
            HStack {
                Label("\(agent.load.blocked) blocked", systemImage: "exclamationmark.triangle")
                Spacer()
                Text(agent.load.capacity.map { "\(agent.load.pressurePct ?? 0, specifier: "%.0f")% of \($0)" } ?? "Capacity unknown")
            }
            .font(.caption2)
            .foregroundStyle(managementColor(agent.load.status))
            Text(agent.load.reason)
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        case .plan:
            if agent.plan.items.isEmpty {
                unknownRow(agent.plan.source.detail)
            } else {
                ForEach(agent.plan.items.prefix(4)) { item in
                    detailRow(icon: "list.bullet", title: item.title, detail: item.lane)
                }
            }
        case .dispatch:
            if agent.dispatch.items.isEmpty {
                unknownRow(agent.dispatch.source.detail)
            } else {
                ForEach(agent.dispatch.items.prefix(4)) { run in
                    detailRow(
                        icon: "paperplane.fill",
                        title: run.runType.replacingOccurrences(of: "_", with: " ").capitalized,
                        detail: [run.state, run.provider, run.host].compactMap { $0 }.joined(separator: " · ")
                    )
                }
            }
        }
    }

    private var themeFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("THEME ALIGNMENT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Text(agent.theme.ratioPct.map { "\($0, specifier: "%.0f")%" } ?? "UNKNOWN")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(managementColor(agent.theme.state))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.backgroundTertiary)
                    Capsule()
                        .fill(managementColor(agent.theme.state))
                        .frame(width: proxy.size.width * CGFloat(min(100, agent.theme.ratioPct ?? 0) / 100))
                }
            }
            .frame(height: 4)
        }
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(AppColors.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func detailRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColors.accentElectric)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                Text(detail.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func unknownRow(_ detail: String) -> some View {
        Label(detail, systemImage: "questionmark.diamond")
            .font(.caption)
            .foregroundStyle(AppColors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Loop Gauge and Atlas

@MainActor
@Observable
final class LoopAtlasViewModel {
    private(set) var response: LoopAtlasResponseDTO?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, response != nil { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            response = try await APIClient.shared.get(path: "/api/v1/management/loop-atlas")
        } catch {
            errorMessage = "Loop health unavailable: \(managementErrorText(error))"
        }
    }
}

struct LoopGaugeView: View {
    @Bindable var model: LoopAtlasViewModel
    @State private var showingAtlas = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .center, spacing: Theme.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THE BIG LOOP")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("Sense · decide · act · verify · record")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                Spacer(minLength: Theme.sm)
                Button { showingAtlas = true } label: {
                    Image(systemName: "arrow.up.right.and.arrow.down.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accentElectric)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(model.response == nil)
                .help("Open Big Loop atlas")
                .accessibilityLabel("Open Big Loop atlas")
            }

            if let response = model.response {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.xs)],
                    spacing: Theme.xs
                ) {
                    ForEach(response.gauge) { cell in
                        gaugeCell(cell)
                    }
                }

                captainQueue(response.captainQueue)

                Text("ORCA · \(response.computedAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            } else if model.isLoading {
                ProgressView("Computing loop health")
                    .tint(AppColors.accentElectric)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                Label(model.errorMessage ?? "Loop health unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.accentWarning)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
        }
        .sheet(isPresented: $showingAtlas) {
            if let response = model.response {
                BigLoopAtlasView(response: response)
            }
        }
    }

    private func gaugeCell(_ cell: LoopGaugeCellDTO) -> some View {
        let color = managementColor(cell.status)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(cell.title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Spacer(minLength: 2)
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(cell.value, format: .number.precision(.fractionLength(0 ... 1)))
                .font(.system(size: 19, weight: .bold).monospacedDigit())
                .foregroundStyle(AppColors.textPrimary)
            Text(cell.unit)
                .font(.system(size: 9))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3), lineWidth: 1))
        .help(cell.cause)
    }

    @ViewBuilder
    private func captainQueue(_ queue: [CaptainDecisionDTO]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CAPTAIN DECISIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Text("\(queue.count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(queue.isEmpty ? AppColors.accentSuccess : AppColors.accentWarning)
            }
            if queue.isEmpty {
                Label("No explicit Captain gate is waiting", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.accentSuccess)
            } else {
                ForEach(queue.prefix(4)) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(AppColors.accentWarning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(2)
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Text(item.waitingSince, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }
}

private struct BigLoopAtlasView: View {
    let response: LoopAtlasResponseDTO
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.md) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.xs)],
                        spacing: Theme.xs
                    ) {
                        ForEach(Array(response.lanes.enumerated()), id: \.element.id) { index, lane in
                            loopNode(lane, index: index)
                        }
                    }
                    .padding(.vertical, Theme.sm)

                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Text("EVERY LOOP READS AND WRITES ORCA")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColors.accentElectric)
                        ForEach(response.lanes) { lane in
                            HStack(alignment: .top, spacing: Theme.sm) {
                                Circle()
                                    .fill(managementColor(lane.status))
                                    .frame(width: 9, height: 9)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(lane.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                        Spacer()
                                        Text("\(lane.count)")
                                            .font(.caption.weight(.bold).monospacedDigit())
                                            .foregroundStyle(managementColor(lane.status))
                                    }
                                    Text(lane.cause)
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                            .padding(Theme.sm)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(Theme.md)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Big Loop Atlas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }

    private func loopNode(_ lane: LoopAtlasLaneDTO, index: Int) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text("\(index + 1)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Text("\(lane.count)")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(managementColor(lane.status))
            }
            Text(lane.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(managementColor(lane.status).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Project Command Room

@MainActor
@Observable
final class ProjectCommandRoomViewModel {
    private(set) var response: ProjectCommandRoomResponseDTO?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(projectId: UUID, force: Bool = false) async {
        guard !isLoading else { return }
        if !force, response?.projectId == projectId { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            response = try await APIClient.shared.get(
                path: "/api/v1/management/projects/\(projectId.uuidString)"
            )
        } catch {
            response = nil
            errorMessage = "Evidence ladder unavailable: \(managementErrorText(error))"
        }
    }
}

struct ProjectEvidenceLadderView: View {
    let projectId: UUID
    @State private var model = ProjectCommandRoomViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Text("EVIDENCE LADDER")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                if let completion = model.response?.completionPct {
                    Text("\(completion, specifier: "%.0f")%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppColors.accentSuccess)
                } else {
                    Text("UNKNOWN")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                Button { Task { await model.load(projectId: projectId, force: true) } } label: {
                    Image(systemName: model.isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.accentElectric)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Refresh evidence ladder")
                .accessibilityLabel("Refresh evidence ladder")
            }

            if let response = model.response {
                if response.milestones.isEmpty {
                    Label("No accepted milestones are structured in ORCA yet", systemImage: "questionmark.diamond")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    ForEach(Array(response.milestones.enumerated()), id: \.element.id) { index, milestone in
                        milestoneRow(index: index, milestone: milestone)
                    }
                }
                Text("Completion receives credit only from linked milestone evidence.")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            } else if model.isLoading {
                ProgressView("Joining milestones and evidence")
                    .tint(AppColors.accentElectric)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                Label(model.errorMessage ?? "Evidence ladder unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.accentWarning)
                    .frame(maxWidth: .infinity, minHeight: 72)
            }
        }
        .task(id: projectId) { await model.load(projectId: projectId) }
    }

    private func milestoneRow(index: Int, milestone: ProjectMilestoneManagementDTO) -> some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            ZStack {
                Circle()
                    .fill(managementColor(milestone.evidenceState).opacity(0.14))
                    .frame(width: 32, height: 32)
                Text("\(index + 1)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(managementColor(milestone.evidenceState))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(milestone.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) {
                    Text(milestone.state.replacingOccurrences(of: "_", with: " ").capitalized)
                    if let owner = milestone.ownerName { Text(owner.capitalized) }
                    Text("\(milestone.evidenceRefs.count) evidence")
                }
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
                if let wait = milestone.waitReason {
                    Label(wait, systemImage: "hourglass")
                        .font(.caption2)
                        .foregroundStyle(AppColors.accentWarning)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: milestone.evidenceRefs.isEmpty ? "circle" : "checkmark.seal.fill")
                .foregroundStyle(managementColor(milestone.evidenceState))
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
