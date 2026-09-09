import SwiftUI
import OrcaAPI

struct ConsoleSectionView: View {
    @Environment(OrcaMacModel.self) private var model
    let section: ConsoleSection

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(section == .fund ? Color.orcaGreen : Color.orcaCyan)
                .frame(width: 34, height: 34)
                .background(
                    (section == .fund ? Color.orcaGreen : Color.orcaCyan).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(section.title)
                        .font(.headline)
                    if section.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if section == .work {
                Picker("Work view", selection: workModeSelection) {
                    ForEach(ConsoleWorkMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
                if model.workMode == .agentWork {
                    Picker("Agent", selection: workControlAgentSelection) {
                        ForEach(model.agents) { agent in
                            Text(agent.name).tag(agent.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .help("Choose named agent work control")
                }
            }
            if model.isLoadingSection {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await model.refreshSelectedSection() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!model.connectionState.isReady || model.isLoadingSection)
            .help("Refresh \(section.title)")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if !model.connectionState.isReady {
            ContentUnavailableView(
                model.connectionState.unavailableTitle,
                systemImage: model.connectionState.unavailableSymbol,
                description: model.connectionDetail.map(Text.init)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if section == .work, model.workMode == .portfolio {
            WorkPortfolioView()
        } else if let error = model.sectionError, model.selectedSnapshot.records.isEmpty {
            ContentUnavailableView(
                "ORCA Data Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if !model.selectedSnapshot.metrics.isEmpty {
                    metrics
                    Divider()
                }
                records
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130, maximum: 210), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(model.selectedSnapshot.metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if let status = metric.status {
                        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2)
                            .foregroundStyle(statusColor(status))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var records: some View {
        List(selection: recordSelection) {
            ForEach(groupNames, id: \.self) { group in
                Section(group) {
                    ForEach(model.selectedSnapshot.records.filter { $0.group == group }) { record in
                        ConsoleRecordRow(record: record)
                            .tag(record.id)
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if model.selectedSnapshot.records.isEmpty && !model.isLoadingSection {
                ContentUnavailableView(
                    "No \(section.title) Records",
                    systemImage: section.symbol
                )
            }
        }
    }

    private var recordSelection: Binding<String?> {
        Binding(
            get: { model.selectedRecordID },
            set: { model.selectRecord($0) }
        )
    }

    private var workControlAgentSelection: Binding<String> {
        Binding(
            get: { model.selectedAgentID },
            set: { model.selectWorkControlAgent($0) }
        )
    }

    private var workModeSelection: Binding<ConsoleWorkMode> {
        Binding(
            get: { model.workMode },
            set: { model.selectWorkMode($0) }
        )
    }

    private var groupNames: [String] {
        model.selectedSnapshot.records.reduce(into: []) { groups, record in
            if !groups.contains(record.group) { groups.append(record.group) }
        }
    }
}

private enum ConsoleBoardPane: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case projects = "Projects"
    case tasks = "Tasks"
    case tickets = "Tickets"

    var id: String { rawValue }
}

private struct WorkPortfolioView: View {
    @Environment(OrcaMacModel.self) private var model
    @State private var isShowingBoardDirectory = false
    @State private var selectedBoardPane = ConsoleBoardPane.plan

    private var featuredBoards: [OrcaBoardDirectoryItem] {
        Array(model.boards.filter { $0.isProduct && $0.slug != "products" }.prefix(6))
    }

    private var selectedBoard: OrcaBoardDirectoryItem? {
        model.boards.first { $0.id == model.selectedBoardID }
    }

    private var selectedProfile: OrcaBoardArchitectureProfile? {
        guard let id = model.selectedBoardID else { return nil }
        return model.boardArchitectureProfilesByID[id]
    }

    var body: some View {
        Group {
            if model.boards.isEmpty, let error = model.boardPlanError {
                ContentUnavailableView(
                    "ORCA Board Data Unavailable",
                    systemImage: "rectangle.3.group",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.boards.isEmpty, model.isLoadingBoardPlan {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !featuredBoards.isEmpty {
                            productSection
                        }
                        boardPlanSection
                        if let error = model.boardPlanError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(Color.orcaCoral)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .sheet(isPresented: $isShowingBoardDirectory) {
            ConsoleBoardDirectoryView()
                .environment(model)
        }
        .onChange(of: model.selectedBoardID) { _, _ in
            selectedBoardPane = .plan
        }
    }

    private var productSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MAIN PRODUCTS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(featuredBoards.count) products")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210, maximum: 310), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(featuredBoards) { board in
                    let profile = model.boardArchitectureProfilesByID[board.id]
                    Button { model.selectBoard(board.id) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox")
                                    .foregroundStyle(Color.orcaCyan)
                                Text(board.displayName)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(boardHealthLabel(profile))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(boardHealthColor(profile))
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 12) {
                                portfolioMetric(profile?.header.counts.inProgressCount, "working")
                                portfolioMetric(profile?.header.counts.reviewCount, "review")
                                portfolioMetric(profile?.header.counts.blockedCount, "blocked")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(board.id == model.selectedBoardID ? Color.orcaCyan : Color(nsColor: .separatorColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var boardPlanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BOARD PLAN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(selectedBoard?.displayName ?? "ORCA Work")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Button {
                    isShowingBoardDirectory = true
                } label: {
                    Label("All Boards", systemImage: "rectangle.grid.2x2")
                }
                .buttonStyle(.borderless)
                .help("Browse and search all ORCA boards")
                Button { Task { await model.refreshBoardPortfolio() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoadingBoardPlan)
                .help("Refresh board plan")
            }

            if selectedBoard?.isProtected == true {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Color.orcaCoral)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Protected board boundary")
                            .font(.body.weight(.semibold))
                        Text("Fund detail remains in the authenticated Fund surface and is not copied into generic Work.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            } else {
                boardArchitectureStatus

                Picker("Board detail", selection: $selectedBoardPane) {
                    ForEach(ConsoleBoardPane.allCases) { pane in
                        Text(paneTitle(pane)).tag(pane)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)

                boardDetailContent

                if let error = model.boardDetailError, selectedBoardPane != .plan {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.orcaCoral)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var boardArchitectureStatus: some View {
        if let profile = selectedProfile?.fullProfile {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(
                        profile.health.state.rawValue.capitalized,
                        systemImage: profile.health.state == .healthy
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(boardHealthColor(selectedProfile))
                    Text(profile.header.lifecycleState.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let release = profile.currentRelease {
                        Text("Release \(release.revision)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(profile.purpose)
                    .font(.body.weight(.semibold))
                Text(profile.health.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let owner = profile.primaryAgent {
                        Label(owner.capitalized, systemImage: "person.fill")
                    }
                    Label("\(profile.sourceRefs.count) sources", systemImage: "link")
                    Text(profile.health.freshness.rawValue.capitalized)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
    }

    private func boardHealthLabel(_ profile: OrcaBoardArchitectureProfile?) -> String {
        guard let profile else { return "Unavailable" }
        if profile.header.isProtected { return "Protected" }
        return profile.header.healthState.rawValue.capitalized
    }

    private func boardHealthColor(_ profile: OrcaBoardArchitectureProfile?) -> Color {
        guard let profile else { return .secondary }
        if profile.header.isProtected { return Color.orcaCoral }
        switch profile.header.healthState {
        case .healthy: return Color.orcaGreen
        case .attention: return .orange
        case .blocked: return Color.orcaCoral
        case .unknown: return .secondary
        }
    }

    @ViewBuilder
    private var boardDetailContent: some View {
        switch selectedBoardPane {
        case .plan:
            if let plan = model.boardPlan {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(plan.lanes) { lane in
                            laneView(lane)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(Color.orcaGreen)
                    Text("\(plan.selectionMode.replacingOccurrences(of: "_", with: " ").capitalized) - ORCA")
                    Spacer()
                    Text(plan.computedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if model.isLoadingBoardPlan {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                boardEmptyState("No active plan", symbol: "rectangle.3.group")
            }
        case .projects:
            boardCollection(model.boardProjects, empty: "No current projects") { project in
                boardCollectionRow(
                    id: project.id,
                    title: project.name,
                    subtitle: project.goal ?? project.projectDescription,
                    state: project.stage,
                    trailing: "P\(project.priority)"
                )
            }
        case .tasks:
            boardCollection(model.boardTasks, empty: "No current tasks") { task in
                boardCollectionRow(
                    id: task.id,
                    title: task.title,
                    subtitle: task.taskDescription,
                    state: task.status,
                    trailing: task.priority.capitalized
                )
            }
        case .tickets:
            boardCollection(model.boardTickets, empty: "No direct tickets") { ticket in
                boardCollectionRow(
                    id: ticket.id,
                    title: ticket.title,
                    subtitle: nil,
                    state: ticket.status,
                    trailing: ticket.priority.capitalized
                )
            }
        }
    }

    private func paneTitle(_ pane: ConsoleBoardPane) -> String {
        switch pane {
        case .plan: return pane.rawValue
        case .projects: return "Projects \(model.boardProjects.count)"
        case .tasks: return "Tasks \(model.boardTasks.count)"
        case .tickets: return "Tickets \(model.boardTickets.count)"
        }
    }

    @ViewBuilder
    private func boardCollection<Item: Identifiable, Row: View>(
        _ items: [Item],
        empty: String,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if model.isLoadingBoardPlan && items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if items.isEmpty {
            boardEmptyState(empty, symbol: "tray")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
    }

    private func boardCollectionRow(
        id: UUID,
        title: String,
        subtitle: String?,
        state: String,
        trailing: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(String(id.uuidString.prefix(8)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(state))
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func boardEmptyState(_ title: String, symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol)
            .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func laneView(_ lane: OrcaBoardPlanLane) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lane.title.uppercased())
                    .font(.caption.weight(.bold))
                Spacer()
                Text("\(lane.cards.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if lane.cards.isEmpty {
                Text("No work in this lane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                ForEach(lane.cards) { card in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(card.title)
                            .font(.body.weight(.medium))
                            .lineLimit(2)
                        if let subtitle = card.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let warning = card.resolvedIntegrityWarnings.first {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                        HStack {
                            if card.resolvedFacets.isEmpty {
                                Label(card.objectType.capitalized, systemImage: facetIcon(card.objectType))
                            } else {
                                ForEach(["ticket", "task", "agent_run"], id: \.self) { type in
                                    let count = card.resolvedFacets.filter { $0.objectType == type }.count
                                    if count > 0 {
                                        Label("\(count)", systemImage: facetIcon(type))
                                            .help("\(count) \(facetLabel(type, count: count))")
                                    }
                                }
                            }
                            Spacer()
                            Text(card.canonicalState.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                }
            }
        }
        .frame(width: 260, alignment: .top)
    }

    private func facetIcon(_ type: String) -> String {
        switch type {
        case "ticket": return "ticket.fill"
        case "project": return "square.stack.3d.up.fill"
        case "agent_run": return "play.circle.fill"
        default: return "checklist"
        }
    }

    private func facetLabel(_ type: String, count: Int) -> String {
        let label = type == "agent_run" ? "run" : type
        return count == 1 ? label : "\(label)s"
    }

    private func portfolioMetric(_ value: Int?, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value.map(String.init) ?? "-")
                .font(.caption.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConsoleBoardDirectoryView: View {
    @Environment(OrcaMacModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var selectedGroup: OrcaBoardArchitectureGroup?

    private var directory: OrcaBoardDirectory {
        OrcaBoardDirectory(items: model.boards)
    }

    private var groups: [(group: OrcaBoardArchitectureGroup, boards: [OrcaBoardDirectoryItem])] {
        directory.grouped(searchQuery: searchQuery, group: selectedGroup)
    }

    private var visibleBoards: [OrcaBoardDirectoryItem] {
        directory.filtered(searchQuery: searchQuery, group: selectedGroup)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summary
                Divider()
                if visibleBoards.isEmpty {
                    emptyDirectory
                } else {
                    List {
                        ForEach(groups, id: \.group) { group in
                            Section("\(group.group.rawValue) - \(group.boards.count)") {
                                ForEach(group.boards) { board in
                                    Button {
                                        model.selectBoard(board.id)
                                        dismiss()
                                    } label: {
                                        boardRow(board)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 720, minHeight: 560)
            .navigationTitle("All Boards")
            .searchable(text: $searchQuery, prompt: "Search boards")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            selectedGroup = nil
                        } label: {
                            if selectedGroup == nil {
                                Label("All Groups", systemImage: "checkmark")
                            } else {
                                Text("All Groups")
                            }
                        }
                        Divider()
                        ForEach(OrcaBoardArchitectureGroup.allCases) { group in
                            Button {
                                selectedGroup = group
                            } label: {
                                if selectedGroup == group {
                                    Label(group.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(group.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label(
                            selectedGroup?.rawValue ?? "All Groups",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }
                    .help("Filter board groups")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyDirectory: some View {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "No Boards in This Group",
                systemImage: "rectangle.3.group",
                description: Text("Choose another board group.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView.search(text: searchQuery)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var summary: some View {
        HStack(spacing: 18) {
            directoryMetric("Boards", visibleBoards.count)
            directoryMetric("Projects", visibleBoards.reduce(0) { $0 + $1.projectCount })
            directoryMetric("Active", visibleBoards.reduce(0) { $0 + $1.activeCount })
            directoryMetric("Tickets", visibleBoards.reduce(0) { $0 + $1.ticketCount })
            Spacer()
            Label("ORCA", systemImage: "checkmark.shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orcaGreen)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func directoryMetric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(minWidth: 70, alignment: .leading)
    }

    private func boardRow(_ board: OrcaBoardDirectoryItem) -> some View {
        let profile = model.boardArchitectureProfilesByID[board.id]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: board.isProtected ? "lock.shield.fill" : boardSymbol(board))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(board.isProtected ? Color.orcaCoral : Color.orcaCyan)
                .frame(width: 30, height: 30)
                .background(
                    (board.isProtected ? Color.orcaCoral : Color.orcaCyan).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(board.displayName)
                    .font(.body.weight(.semibold))
                Text(board.isProtected ? "Protected domain" : (board.boardDescription ?? board.slug))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if board.isProtected {
                Text("Protected")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.orcaCoral)
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(profile?.header.healthState.rawValue.capitalized ?? "Unavailable")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(directoryHealthColor(profile))
                    HStack(spacing: 12) {
                        portfolioMetric(board.projectCount, "projects")
                        portfolioMetric(board.activeCount, "active")
                        portfolioMetric(board.ticketCount, "tickets")
                    }
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func directoryHealthColor(_ profile: OrcaBoardArchitectureProfile?) -> Color {
        guard let state = profile?.header.healthState else { return .secondary }
        switch state {
        case .healthy: return Color.orcaGreen
        case .attention: return .orange
        case .blocked: return Color.orcaCoral
        case .unknown: return .secondary
        }
    }

    private func boardSymbol(_ board: OrcaBoardDirectoryItem) -> String {
        switch board.architectureGroup {
        case .products: return "shippingbox.fill"
        case .surfaces: return "rectangle.on.rectangle.angled"
        case .platform: return "server.rack"
        case .infrastructure: return "wrench.and.screwdriver.fill"
        case .fund: return "lock.shield.fill"
        case .strategy: return "scope"
        case .other: return "rectangle.3.group.fill"
        }
    }

    private func portfolioMetric(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(value)")
                .font(.caption.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 42, alignment: .trailing)
    }
}

private struct ConsoleRecordRow: View {
    let record: ConsoleRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let subtitle = record.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            if let status = record.status {
                Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor(status))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

func statusColor(_ raw: String) -> Color {
    let value = raw.lowercased()
    if value.contains("ok") || value.contains("ready") || value.contains("complete") || value.contains("running") {
        return .orcaGreen
    }
    if value.contains("attention") || value.contains("blocked") || value.contains("failed") || value.contains("offline") {
        return .orcaCoral
    }
    if value.contains("pending") || value.contains("review") || value.contains("claim") {
        return .orcaAmber
    }
    return .secondary
}
