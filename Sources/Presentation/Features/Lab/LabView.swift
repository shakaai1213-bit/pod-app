import SwiftUI

// MARK: - LabView
//
// Per SPEC-POD-LAB-TAB-2026-05-23. The product catalog surface — what we have, who runs it, what's spinning.
// Mirrors Team-Wiki/operating-system/LAB-SYSTEMS-INDEX.md (currently hardcoded via LabContent.swift;
// swap to GET /api/v1/lab/sections when M-005 v2 ships).

struct LabView: View {

    // Per-section expand/collapse state (default per spec §2).
    @State private var boardsModel = LabBoardsModel()
    @State private var selectedBoard: LabBoardSummary?
    @State private var architectureModel = ArchitectureDiagramModel()
    @State private var showingArchitectureSheet = false
    @State private var stackExpanded     = true
    @State private var fishExpanded      = false
    @State private var workflowsExpanded = false
    @State private var flywheelExpanded  = true
    @State private var buildingExpanded  = true
    @State private var retiredExpanded      = false
    @State private var teamBuildingExpanded = true
    @State private var expandedThemes: Set<String> = ["strategy", "surfaces", "substrate", "health", "doctrine"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 44)
                        .padding(.bottom, 8)

                    stackSection
                    fishSection
                    workflowsSection
                    flywheelSection
                    buildingSection
                    retiredSection
                    boardsSection
                    architectureSection
                    teamBuildingSection
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .task {
                await boardsModel.load()
                await architectureModel.load()
            }
            .refreshable {
                await boardsModel.load(force: true)
                await architectureModel.load(force: true)
            }
            .sheet(item: $selectedBoard) { board in
                LabBoardDetailView(board: board)
            }
            .fullScreenCover(isPresented: $showingArchitectureSheet) {
                ArchitectureDiagramSheet(markdown: architectureModel.markdown)
            }
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lab")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            Text("What we've built, who's running it, what's spinning.")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Section card scaffold

    @ViewBuilder
    private func sectionCard<Header: View, Body: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> Body
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            body()
        }
        .background(AppColors.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func sectionHeader(title: String, count: Int? = nil, expanded: Bool, rightLabel: String? = nil, rightAction: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.textSecondary)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            if let count = count {
                Text("· \(count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
            if let label = rightLabel {
                Button {
                    rightAction?()
                } label: {
                    HStack(spacing: 2) {
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.accentElectric)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppColors.accentElectric)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - BOARDS section

    private var boardsSection: some View {
        sectionCard {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("BOARDS")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppColors.textPrimary)
                        Text("\(boardsModel.boards.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppColors.backgroundTertiary.opacity(0.65))
                            .clipShape(Capsule())
                    }
                    Text("System board map")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                }
                Spacer()
                if boardsModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    Button {
                        Task { await boardsModel.load(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } body: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.boardThemes.enumerated()), id: \.element.id) { idx, theme in
                    let themeBoards = boardsModel.boards.filter { theme.slugs.contains($0.slug) }
                    themeGroupRow(theme: theme, boards: themeBoards)
                    if idx < Self.boardThemes.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
                if let error = boardsModel.error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private struct LabBoardTheme {
        let id: String
        let emoji: String
        let name: String
        let slugs: [String]
    }

    private static let boardThemes: [LabBoardTheme] = [
        .init(id: "strategy",  emoji: "🎯", name: "Strategy",  slugs: ["north-star"]),
        .init(id: "surfaces",  emoji: "📱", name: "Surfaces",  slugs: ["pod", "chat"]),
        .init(id: "substrate", emoji: "🐋", name: "Substrate", slugs: ["orca", "memory", "compute", "nerve"]),
        .init(id: "health",    emoji: "🌸", name: "Health",    slugs: ["observability"]),
        .init(id: "doctrine",  emoji: "⚖️", name: "Doctrine",  slugs: ["governance"]),
    ]

    @ViewBuilder
    private func themeGroupRow(theme: LabBoardTheme, boards: [LabBoardSummary]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if expandedThemes.contains(theme.id) {
                        expandedThemes.remove(theme.id)
                    } else {
                        expandedThemes.insert(theme.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expandedThemes.contains(theme.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 12)
                    Text(theme.emoji)
                        .font(.system(size: 13))
                    Text(theme.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Text("\(boards.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppColors.backgroundTertiary.opacity(0.65))
                        .clipShape(Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if expandedThemes.contains(theme.id) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 86, maximum: 126), spacing: 7)],
                    spacing: 7
                ) {
                    ForEach(boards) { board in
                        boardTile(board)
                            .onTapGesture { selectedBoard = board }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private func boardTile(_ board: LabBoardSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 5) {
                Text(board.icon)
                    .font(.system(size: 15))
                    .frame(width: 18, height: 18)
                Text(board.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }

            HStack(spacing: 5) {
                Text("\(board.projectCount)p")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.textSecondary)
                Text("\(board.activeCount)a")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(AppColors.backgroundTertiary.opacity(0.55))
            .clipShape(Capsule())
        }
        .frame(minHeight: 56, alignment: .topLeading)
        .padding(7)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }

    // MARK: - ARCHITECTURE section

    private var architectureSection: some View {
        sectionCard {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ARCHITECTURE")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Canonical stack map")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                }
                Spacer()
                if architectureModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    HStack(spacing: 8) {
                        Text(architectureModel.sourceLabel)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.accentElectric)
                    }
                }
            }
        } body: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                        .frame(width: 28, height: 28)
                        .background(AppColors.accentElectric.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open full architecture map")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)
                        Text("Mermaid source · zoom and scroll")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(10)
                .background(AppColors.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border, lineWidth: 0.5)
                )

                if let error = architectureModel.error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                showingArchitectureSheet = true
            }
        }
    }

    // MARK: - STACK section

    private var stackSection: some View {
        sectionCard {
            sectionHeader(title: "STACK", count: LabContent.stack.count, expanded: stackExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { stackExpanded.toggle() }
                }
        } body: {
            if stackExpanded {
                VStack(spacing: 0) {
                    ForEach(LabContent.stack) { layer in
                        stackRow(layer)
                        if layer.id != LabContent.stack.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }

    private func stackRow(_ layer: LabStackLayer) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(layer.tint.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: layer.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(layer.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(layer.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(layer.oneLine)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                statusPill(layer.status)
                ownerChip(layer.owner)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - FISH section
    //
    // Per LAB-SYSTEMS-INDEX §11: Fish are the *research substrate fleet* (Starfish, Chieffish).
    // The Crew (named operators + workers + compute) lives on the Agents tab — Lab does not duplicate.

    private var fishSection: some View {
        let total = LabContent.fishFleet.count + LabContent.fishAdjacent.count
        return sectionCard {
            sectionHeader(title: "THE FISH 🐠", count: total, expanded: fishExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { fishExpanded.toggle() }
                }
        } body: {
            if fishExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    fishHeaderNote
                    fishStrip(title: "Research substrate fleet", fish: LabContent.fishFleet)
                    fishStrip(title: "Adjacent (chief-local, not Pod-surfaced)", fish: LabContent.fishAdjacent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var fishHeaderNote: some View {
        Text("Long-running autonomous research agents. Each has a partner-operator who owns its directive queue. Not operators, not workers.")
            .font(.system(size: 11))
            .italic()
            .foregroundColor(AppColors.textTertiary)
    }

    // MARK: - WORKFLOWS + PROTOCOLS section
    //
    // Per LAB-SYSTEMS-INDEX §13: STANDARDS govern what's right; PROTOCOLS govern how we coordinate.
    // Surfaces the canonical doctrine catalog so Tony + new agents can see procedure without grepping.

    private var workflowsSection: some View {
        let total = LabContent.workflows.reduce(0) { $0 + $1.items.count }
        return sectionCard {
            sectionHeader(title: "WORKFLOWS + PROTOCOLS", count: total, expanded: workflowsExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { workflowsExpanded.toggle() }
                }
        } body: {
            if workflowsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(LabContent.workflows) { group in
                        workflowGroupView(group)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private func workflowGroupView(_ group: LabWorkflowGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .tracking(0.5)
            ForEach(group.items) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer(minLength: 6)
                    Text(item.status)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(item.statusColor.opacity(0.15))
                        .foregroundColor(item.statusColor)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func fishStrip(title: String, fish: [LabFish]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .tracking(0.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(fish) { f in
                        fishCard(f)
                    }
                }
            }
        }
    }

    private func fishCard(_ f: LabFish) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(AppColors.backgroundTertiary)
                        .frame(width: 48, height: 48)
                    Text(f.emoji)
                        .font(.system(size: 26))
                }
                Circle()
                    .fill(f.status.color)
                    .frame(width: 7, height: 7)
                    .padding(2)
            }
            Text(f.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
            Text(f.role)
                .font(.system(size: 10))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 110)
        .padding(8)
        .background(AppColors.backgroundTertiary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - FLYWHEEL section

    private var flywheelSection: some View {
        sectionCard {
            sectionHeader(title: "FLYWHEEL 🌀", expanded: flywheelExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { flywheelExpanded.toggle() }
                }
        } body: {
            if flywheelExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    flywheelLoop
                    flywheelNote
                    flywheelSpinning
                    flywheelFooter
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var flywheelLoop: some View {
        // Static text-flow rendering; visual chevrons. Accessibility fallback below.
        VStack(alignment: .leading, spacing: 8) {
            FlywheelLoopDiagram(nodes: LabContent.flywheelNodes)
                .accessibilityLabel("Captured to Assessment to Experiment to Evidence to Decision to Doctrine")
        }
    }

    private var flywheelNote: some View {
        Text("Flywheel ≠ Project Lifecycle. The Flywheel is the experimentation loop (idea → evidence → kept-or-killed). Project Lifecycle is the governance stages (Captured → Assessment → Definition → Blueprint → Scoping → Active → Handoff → Closed). A project moves through the Flywheel inside its Lifecycle stages.")
            .font(.system(size: 11))
            .italic()
            .foregroundColor(AppColors.textTertiary)
    }

    private var flywheelSpinning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Currently spinning · \(LabContent.currentlySpinning.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
            ForEach(LabContent.currentlySpinning) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundColor(AppColors.textTertiary)
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer(minLength: 6)
                    Text(item.stage)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(AppColors.accentElectric.opacity(0.15))
                        .foregroundColor(AppColors.accentElectric)
                        .clipShape(Capsule())
                    ownerChip(item.owner)
                }
            }
        }
    }

    private var flywheelFooter: some View {
        Text("What it costs when it stalls: designer-iteration without ship = process-running. Tickets-as-receipts (not forward work) = false motion.")
            .font(.system(size: 11))
            .italic()
            .foregroundColor(AppColors.textTertiary)
    }

    // MARK: - CURRENTLY BUILDING section

    private var buildingSection: some View {
        sectionCard {
            sectionHeader(title: "CURRENTLY BUILDING", count: LabContent.currentlyBuilding.count, expanded: buildingExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { buildingExpanded.toggle() }
                }
        } body: {
            if buildingExpanded {
                VStack(spacing: 0) {
                    ForEach(LabContent.currentlyBuilding) { item in
                        buildingRow(item)
                        if item.id != LabContent.currentlyBuilding.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }

    private func buildingRow(_ item: LabBuildingItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.stage)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(AppColors.backgroundTertiary)
                        .foregroundColor(AppColors.textSecondary)
                        .clipShape(Capsule())
                    ownerChip(item.owner)
                    Text(item.shortId)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(AppColors.backgroundTertiary.opacity(0.5))
                        .foregroundColor(AppColors.textTertiary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(AppColors.border, lineWidth: 0.5)
                        )
                }
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - RETIRED section

    private var retiredSection: some View {
        sectionCard {
            sectionHeader(title: "RETIRED", count: LabContent.retiredItems.count, expanded: retiredExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { retiredExpanded.toggle() }
                }
        } body: {
            if retiredExpanded {
                VStack(spacing: 0) {
                    ForEach(LabContent.retiredItems) { item in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppColors.textSecondary)
                                Text(item.reason)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.textTertiary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 6)
                            Text("⚫")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        if item.id != LabContent.retiredItems.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }

    // MARK: - TEAM BUILDING MAP section

    private struct TeamMapAgent {
        let emoji: String
        let name: String
        let mac: String       // "shaka" | "chief"
        let themeIds: [String]
        let fish: String?
        let flywheelSteps: [String]
    }

    // TEAM-BUILDING-MAP.md per-agent matrix (Aloha 2026-05-25)
    private static let teamMapAgents: [TeamMapAgent] = [
        .init(emoji: "🪝", name: "Maui",    mac: "shaka", themeIds: ["surfaces", "substrate"], fish: "Starfish ⭐",   flywheelSteps: ["Build", "Codify"]),
        .init(emoji: "🌸", name: "Aloha",   mac: "shaka", themeIds: ["doctrine", "strategy"],  fish: nil,            flywheelSteps: ["Design", "Codify"]),
        .init(emoji: "🦅", name: "Chief",   mac: "chief", themeIds: ["strategy"],              fish: "Chieffish 🐟", flywheelSteps: ["Earn"]),
        .init(emoji: "🐓", name: "Rooster", mac: "chief", themeIds: ["doctrine", "strategy"],  fish: "Roosterfish 🐔", flywheelSteps: ["Learn", "Codify"]),
        .init(emoji: "🪸", name: "Coral",   mac: "shaka", themeIds: ["health"],                fish: nil,            flywheelSteps: ["Learn"]),
        .init(emoji: "🐡", name: "Reef",    mac: "chief", themeIds: ["health", "substrate"],   fish: nil,            flywheelSteps: ["Learn"]),
    ]

    private var teamBuildingSection: some View {
        sectionCard {
            sectionHeader(
                title: "TEAM BUILDING MAP",
                count: Self.teamMapAgents.count,
                expanded: teamBuildingExpanded
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { teamBuildingExpanded.toggle() }
            }
        } body: {
            if teamBuildingExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(Self.teamMapAgents.enumerated()), id: \.offset) { idx, agent in
                        teamMapRow(agent)
                        if idx < Self.teamMapAgents.count - 1 {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }

    private func teamMapRow(_ agent: TeamMapAgent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Agent identity
            VStack(alignment: .center, spacing: 2) {
                Text(agent.emoji)
                    .font(.system(size: 20))
                Text(agent.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                Text(agent.mac)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
            }
            .frame(width: 46)

            VStack(alignment: .leading, spacing: 6) {
                // Theme chips
                HStack(spacing: 4) {
                    ForEach(agent.themeIds, id: \.self) { themeId in
                        if let theme = Self.boardThemes.first(where: { $0.id == themeId }) {
                            HStack(spacing: 3) {
                                Text(theme.emoji)
                                    .font(.system(size: 9))
                                Text(theme.name)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(AppColors.backgroundTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(AppColors.border, lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Spacer(minLength: 0)
                }

                // Fish + Flywheel row
                HStack(spacing: 8) {
                    if let fish = agent.fish {
                        HStack(spacing: 3) {
                            Image(systemName: "fish")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(AppColors.accentElectric)
                            Text(fish)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(AppColors.accentElectric)
                        }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.system(size: 8))
                            .foregroundColor(AppColors.textTertiary)
                        Text(agent.flywheelSteps.joined(separator: " · "))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Shared bits

    private func statusPill(_ status: LabStatus) -> some View {
        HStack(spacing: 3) {
            Text(status.emoji).font(.system(size: 8))
            Text(status.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(status.color)
                .tracking(0.4)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func ownerChip(_ owner: String) -> some View {
        Text(owner)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(AppColors.textSecondary)
            .tracking(0.5)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }

}

// MARK: - Lab boards

private struct LabBoardSummary: Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    let layer: String?
    let component: String?
    let boardDescription: String?
    let projectCount: Int
    let activeCount: Int
    let ticketCount: Int

    var icon: String {
        Self.iconMap[slug] ?? "📋"
    }

    var displayName: String {
        (component?.isEmpty == false ? component : nil)
            ?? Self.displayNameMap[slug]
            ?? name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static let orderedSlugs = [
        "north-star",
        "pod",
        "chat",
        "orca",
        "memory",
        "compute",
        "nerve",
        "observability",
        "governance"
    ]

    static let iconMap: [String: String] = [
        "north-star": "⭐",
        "pod": "📱",
        "chat": "💬",
        "orca": "🐋",
        "memory": "🧠",
        "compute": "🧮",
        "nerve": "⚡",
        "observability": "🌸",
        "governance": "⚖️"
    ]

    static let displayNameMap: [String: String] = [
        "north-star": "north-star",
        "pod": "pod",
        "chat": "chat",
        "orca": "orca",
        "memory": "memory",
        "compute": "compute",
        "nerve": "nerve",
        "observability": "observability",
        "governance": "governance"
    ]
}

@MainActor
@Observable
private final class LabBoardsModel {
    private(set) var boards: [LabBoardSummary] = LabBoardSummary.orderedSlugs.map {
        LabBoardSummary(
            id: $0,
            slug: $0,
            name: $0,
            layer: nil,
            component: nil,
            boardDescription: nil,
            projectCount: 0,
            activeCount: 0,
            ticketCount: 0
        )
    }
    private(set) var isLoading = false
    private(set) var error: String?

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && boards.contains(where: { $0.projectCount > 0 || $0.activeCount > 0 }) { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: LabBoardListResponse = try await APIClient.shared.get(path: "/api/v1/boards")
            let loaded = response.items.map(\.summary)
            boards = Self.ordered(loaded)
        } catch {
            boards = Self.ordered(boards)
            self.error = "Boards unavailable; showing canonical board map."
        }
    }

    private static func ordered(_ boards: [LabBoardSummary]) -> [LabBoardSummary] {
        var bySlug = Dictionary(uniqueKeysWithValues: boards.map { ($0.slug, $0) })
        let canonical = LabBoardSummary.orderedSlugs.map { slug in
            bySlug.removeValue(forKey: slug) ?? LabBoardSummary(
                id: slug,
                slug: slug,
                name: slug,
                layer: nil,
                component: nil,
                boardDescription: nil,
                projectCount: 0,
                activeCount: 0,
                ticketCount: 0
            )
        }
        return canonical + bySlug.values.sorted { $0.slug < $1.slug }
    }
}

private struct LabBoardListResponse: Decodable {
    let items: [LabBoardDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [LabBoardDTO] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(LabBoardDTO.self))
            }
            items = values
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([LabBoardDTO].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }
}

private struct LabBoardDTO: Decodable {
    let id: String
    let slug: String
    let name: String
    let layer: String?
    let component: String?
    let boardDescription: String?
    let projectCount: Int
    let activeCount: Int
    let ticketCount: Int

    var summary: LabBoardSummary {
        LabBoardSummary(
            id: id,
            slug: slug,
            name: name,
            layer: layer,
            component: component,
            boardDescription: boardDescription,
            projectCount: projectCount,
            activeCount: activeCount,
            ticketCount: ticketCount
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        let rawSlug = try container.decodeFlexibleStringIfPresent(forKey: .slug)
            ?? container.decodeFlexibleStringIfPresent(forKey: .name)
            ?? id
        slug = rawSlug.lowercased()
        name = try container.decodeFlexibleStringIfPresent(forKey: .name) ?? slug
        layer = try container.decodeFlexibleStringIfPresent(forKey: .layer)
        component = try container.decodeFlexibleStringIfPresent(forKey: .component)
        boardDescription = try container.decodeFlexibleStringIfPresent(forKey: .description)
            ?? container.decodeFlexibleStringIfPresent(forKey: .objective)
        projectCount = try container.decodeFlexibleIntIfPresent(keys: [.projectCount, .projectsCount, .totalProjects]) ?? 0
        activeCount = try container.decodeFlexibleIntIfPresent(keys: [.activeCount, .activeProjects, .activeProjectCount]) ?? 0
        ticketCount = try container.decodeFlexibleIntIfPresent(keys: [.ticketCount, .ticketsCount, .directTicketCount]) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case layer
        case component
        case description
        case objective
        case projectCount = "project_count"
        case projectsCount = "projects_count"
        case totalProjects = "total_projects"
        case activeCount = "active_count"
        case activeProjects = "active_projects"
        case activeProjectCount = "active_project_count"
        case ticketCount = "ticket_count"
        case ticketsCount = "tickets_count"
        case directTicketCount = "direct_ticket_count"
    }
}

private struct LabBoardProjectListResponse: Decodable {
    let items: [ProjectDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [ProjectDTO] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(ProjectDTO.self))
            }
            items = values
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([ProjectDTO].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }
}

private struct LabBoardTicketSummary: Identifiable, Decodable {
    let id: String
    let title: String
    let status: String
    let priority: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        title = try container.decodeFlexibleStringIfPresent(forKey: .title) ?? "Untitled ticket"
        status = try container.decodeFlexibleStringIfPresent(forKey: .status) ?? "open"
        priority = try container.decodeFlexibleStringIfPresent(forKey: .priority)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case priority
    }
}

private struct LabBoardTicketListResponse: Decodable {
    let items: [LabBoardTicketSummary]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [LabBoardTicketSummary] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(LabBoardTicketSummary.self))
            }
            items = values
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([LabBoardTicketSummary].self, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }
}

@MainActor
@Observable
private final class LabBoardDetailModel {
    private(set) var projects: [ProjectDTO] = []
    private(set) var directTickets: [LabBoardTicketSummary] = []
    private(set) var isLoading = false
    private(set) var error: String?

    func load(board: LabBoardSummary) async {
        if isLoading { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        async let projectsTask = loadProjects(board: board)
        async let ticketsTask = loadTickets(board: board)
        let (loadedProjects, loadedTickets) = await (projectsTask, ticketsTask)

        projects = loadedProjects.projects
        directTickets = loadedTickets.tickets

        if let projectError = loadedProjects.error, let ticketError = loadedTickets.error {
            error = "\(projectError) \(ticketError)"
        } else if let projectError = loadedProjects.error {
            error = projectError
        } else if let ticketError = loadedTickets.error {
            error = ticketError
        }
    }

    private func loadProjects(board: LabBoardSummary) async -> (projects: [ProjectDTO], error: String?) {
        do {
            let response: LabBoardProjectListResponse = try await APIClient.shared.get(path: "/api/v1/boards/\(board.id)/projects")
            return (response.items, nil)
        } catch {
            do {
                let response: LabBoardProjectListResponse = try await APIClient.shared.get(path: "/api/v1/projects?board_id=\(board.id)")
                return (response.items, nil)
            } catch {
                return ([], "Projects unavailable.")
            }
        }
    }

    private func loadTickets(board: LabBoardSummary) async -> (tickets: [LabBoardTicketSummary], error: String?) {
        do {
            let response: LabBoardTicketListResponse = try await APIClient.shared.get(path: "/api/v1/boards/\(board.id)/tickets")
            return (response.items, nil)
        } catch {
            return ([], "Direct tickets unavailable.")
        }
    }
}

private struct LabBoardDetailView: View {
    let board: LabBoardSummary
    @State private var model = LabBoardDetailModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    boardHero
                    projectsSection
                    ticketsSection
                    if let error = model.error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(board.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.accentElectric)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.load(board: board) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
            .task {
                await model.load(board: board)
            }
        }
        .presentationDetents([.large])
    }

    private var boardHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(board.icon)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.displayName.uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text([board.layer, board.component].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
            }

            if let description = board.boardDescription, !description.isEmpty {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                countPill("\(board.projectCount) projects")
                countPill("\(board.activeCount) active")
                countPill("\(board.ticketCount) tickets")
            }
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("PROJECTS", count: model.projects.count)
            if model.isLoading && model.projects.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if model.projects.isEmpty {
                emptyText("No projects on this board yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.projects) { project in
                        projectRow(project)
                        if project.id != model.projects.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var ticketsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("DIRECT TICKETS", count: model.directTickets.count)
            if model.isLoading && model.directTickets.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if model.directTickets.isEmpty {
                emptyText("No direct tickets on this board.")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.directTickets) { ticket in
                        ticketRow(ticket)
                        if ticket.id != model.directTickets.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func projectRow(_ project: ProjectDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
            HStack(spacing: 6) {
                countPill(project.stage ?? project.status)
                countPill("P\(project.priority)")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func ticketRow(_ ticket: LabBoardTicketSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ticket.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
            HStack(spacing: 6) {
                countPill(ticket.status)
                if let priority = ticket.priority {
                    countPill(priority)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.textTertiary)
            Text("· \(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
    }

    private func countPill(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }

    private func emptyText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12))
            .foregroundColor(AppColors.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(UUID.self, forKey: key) {
            return value.uuidString
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(codingPath: codingPath, debugDescription: "No string-like value for \(key.stringValue)")
        )
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(UUID.self, forKey: key) {
            return value.uuidString
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeFlexibleIntIfPresent(keys: [Key]) throws -> Int? {
        for key in keys {
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return Int(value)
            }
            if let value = try? decodeIfPresent(String.self, forKey: key),
               let intValue = Int(value) {
                return intValue
            }
        }
        return nil
    }
}

// MARK: - Architecture diagram

@MainActor
@Observable
private final class ArchitectureDiagramModel {
    private(set) var markdown = ArchitectureDiagramSnapshot.markdown
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var sourceLabel = "SNAPSHOT"

    var previewText: String {
        Self.firstMermaidBlock(in: markdown) ?? markdown
    }

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && sourceLabel == "ORCA" { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: WikiFileResponse = try await APIClient.shared.get(
                path: "/api/v1/wiki/file?path=architecture/ARCHITECTURE-DIAGRAM.md"
            )
            markdown = response.content
            sourceLabel = "ORCA"
        } catch {
            do {
                let response: WikiFileResponse = try await APIClient.shared.get(
                    path: "/api/v1/wiki/file?path=operating-system/architecture/ARCHITECTURE-DIAGRAM.md"
                )
                markdown = response.content
                sourceLabel = "ORCA"
            } catch {
                markdown = ArchitectureDiagramSnapshot.markdown
                sourceLabel = "SNAPSHOT"
                self.error = "Showing bundled snapshot; ORCA wiki file unavailable."
            }
        }
    }

    private static func firstMermaidBlock(in markdown: String) -> String? {
        guard let openRange = markdown.range(of: "```mermaid") else { return nil }
        let bodyStart = openRange.upperBound
        guard let closeRange = markdown[bodyStart...].range(of: "```") else { return nil }
        let block = markdown[bodyStart..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return block.isEmpty ? nil : block
    }
}

private struct WikiFileResponse: Decodable {
    let content: String

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let value = try? single.decode(String.self) {
            content = value
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .content) {
            content = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .markdown) {
            content = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .text) {
            content = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .body) {
            content = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.content,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No wiki file content field")
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case markdown
        case text
        case body
    }
}

private struct ArchitectureDiagramCodeBlock: View {
    let text: String
    let height: CGFloat

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppColors.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(2)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }
}

private struct ArchitectureDiagramSheet: View {
    let markdown: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(markdown)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(16)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 0.75), 2.8)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Architecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.accentElectric)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        scale = max(0.75, scale - 0.15)
                        lastScale = scale
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Button {
                        scale = min(2.8, scale + 0.15)
                        lastScale = scale
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                }
            }
        }
    }
}

private enum ArchitectureDiagramSnapshot {
    static let markdown = """
    # Architecture — Visual Map

    ## 1. The 5-Layer Stack

    ```mermaid
    flowchart TB
        classDef surface fill:#cce5ff,stroke:#004085,color:#000
        classDef integration fill:#d4edda,stroke:#155724,color:#000
        classDef backbone fill:#fff3cd,stroke:#856404,color:#000
        classDef nerve fill:#f8d7da,stroke:#721c24,color:#000
        classDef actor fill:#e2e3e5,stroke:#383d41,color:#000

        subgraph L1["LAYER 1 — Surfaces (what Tony touches)"]
            Pod["Pod (iPad/iPhone)"]
            Chat["Chat"]
            iMsg["iMessage"]
        end

        subgraph L2["LAYER 2 — Schoolhouse OS (integration loop)"]
            SH["Schoolhouse — protocols · standards · workflows · doctrine binding"]
        end

        subgraph L3["LAYER 3 — Substrate"]
            ORCA["3a. ORCA (backend truth · endpoints · projects · tickets · boards · notes)"]
            MEM["3b. Memory (daily logs · Chroma · per-agent · Spine V1)"]
            CMP["3c. Compute (Spark · Kimi · Claude · Mermaid · cascade triage)"]
        end

        subgraph L4["LAYER 4 — Nerve (the wire)"]
            NATS["NATS · Track B envelope · sign chain"]
        end

        subgraph L5["LAYER 5 — Actors + Observability"]
            Agents["Agents (Aloha · Maui · Coral · Reef · Rooster · Chief)"]
            Fish["Fish Fleet (Starfish · Chieffish · Roosterfish) + Workers (Pearl · Mermaid · Turtle · Miner)"]
            Petals["Petals + Watchdogs"]
        end

        Pod -->|reads| ORCA
        Chat -->|reads| ORCA
        iMsg -->|reads| ORCA
        SH -->|orchestrates| ORCA
        SH -->|orchestrates| MEM
        SH -->|orchestrates| CMP
        ORCA <-->|envelopes| NATS
        MEM <-->|envelopes| NATS
        CMP <-->|envelopes| NATS
        Agents <-->|publish/subscribe| NATS
        Fish -->|directive queues| Agents
        Petals -->|alerts| Agents
        Petals -->|metrics| ORCA

        L1 ~~~ L2 ~~~ L3 ~~~ L4 ~~~ L5

        class L1 surface
        class L2 integration
        class L3 backbone
        class L4 nerve
        class L5 actor
    ```

    ## 2. The Operating Rhythm

    ```mermaid
    flowchart LR
        D["1. DESIGN<br>Aloha + Maui<br>Spec / ADR / Standard"]
        B["2. BUILD<br>Codex / Compute<br>Commits + work-log"]
        C["3. CODIFY<br>Aloha + Maui<br>DDS / SOP / Catalog"]
        L["4. LEARN<br>ORCA<br>Suggestions · Memory · Flow"]
        E["5. EARN<br>Chief<br>P&L · Funding · Outcomes"]
        D --> B --> C --> L --> E
        E -.->|next cycle| D
    ```

    ## 3. Boards Overlay

    ```mermaid
    flowchart TB
        subgraph LAYER1["L1 Surfaces"]
            pod[pod]
            chat[chat]
        end
        subgraph LAYER2["L2 Integration"]
            gov[governance]
        end
        subgraph LAYER3["L3 Substrate"]
            orca[orca]
            memory[memory]
            compute[compute]
        end
        subgraph LAYER4["L4 Nerve"]
            nerve[nerve]
        end
        subgraph LAYER5["L5 Observability"]
            obs[observability]
        end
        subgraph CROSSCUT["Cross-cutting / Strategic"]
            ns[north-star]
        end
    ```
    """
}

// MARK: - Flywheel loop diagram

private struct FlywheelLoopDiagram: View {
    let nodes: [String]

    var body: some View {
        // Compact two-row flow with arrows.
        // Top row: 1 → 2 → 3
        // Bottom row: 6 ← 5 ← 4
        let half = (nodes.count + 1) / 2
        let top = Array(nodes.prefix(half))
        let bottom = Array(nodes.suffix(nodes.count - half).reversed())

        return VStack(alignment: .leading, spacing: 8) {
            row(top, showRightArrow: true)
            HStack {
                Spacer()
                Image(systemName: "arrow.turn.right.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
            }
            row(bottom, showRightArrow: false)
        }
    }

    private func row(_ items: [String], showRightArrow: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                node(item)
                if idx < items.count - 1 {
                    Image(systemName: showRightArrow ? "arrow.right" : "arrow.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
    }

    private func node(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppColors.textPrimary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(AppColors.backgroundTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppColors.border, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
