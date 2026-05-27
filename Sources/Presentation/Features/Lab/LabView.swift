import SwiftUI

// MARK: - LabView
//
// Per SPEC-POD-LAB-TAB-2026-05-23. The product catalog surface — what we have, who runs it, what's spinning.
// Mirrors Team-Wiki/operating-system/LAB-SYSTEMS-INDEX.md through ORCA's wiki bridge.

struct LabView: View {

    // Per-section expand/collapse state (default per spec §2).
    @State private var architectureModel = ArchitectureDiagramModel()
    @State private var catalogModel = LabCatalogModel()
    @State private var workflowCatalogModel = LabWorkflowCatalogModel()
    @State private var natsHealthModel = LabNATSHealthModel()
    @State private var showingArchitectureSheet = false
    @State private var stackExpanded     = true
    @State private var fishExpanded      = false
    @State private var workflowsExpanded = false
    @State private var flywheelExpanded  = true
    @State private var buildingExpanded  = true
    @State private var retiredExpanded      = false

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
                    architectureRegistrySection
                    architectureSection
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
                .task {
                    await catalogModel.load()
                    await architectureModel.load()
                    await workflowCatalogModel.load()
                    await natsHealthModel.load()
                }
                .refreshable {
                    await catalogModel.load(force: true)
                    await architectureModel.load(force: true)
                    await workflowCatalogModel.load(force: true)
                    await natsHealthModel.load()
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

    // MARK: - ARCHITECTURE section

    private var architectureRegistrySection: some View {
        sectionCard {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ARCHITECTURE REGISTRY")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Subsystem truth contracts")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                }
                Spacer()
                Text("STAGED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
            }
        } body: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                        .frame(width: 28, height: 28)
                        .background(AppColors.accentElectric.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Boards show where work belongs. The registry will show how each subsystem works.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Source: ORCA-ARCHITECTURE-OWNERSHIP-REGISTRY-2026-05-26.md. Read-only until ORCA exposes a doc-registry/wiki mirror suitable for structured rows.")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

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
        let stack = catalogModel.stack
        return sectionCard {
            sectionHeader(title: "STACK", count: stack.count, expanded: stackExpanded, rightLabel: natsHealthModel.badgeLabel) {
                Task { await natsHealthModel.load() }
            }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { stackExpanded.toggle() }
                }
        } body: {
            if stackExpanded {
                VStack(spacing: 0) {
                    catalogSourceRow
                    ForEach(stack) { layer in
                        stackRow(layer)
                        if layer.id != stack.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }

    private var catalogSourceRow: some View {
        HStack(spacing: 6) {
            Text(catalogModel.sourceLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(catalogModel.sourceLabel == "ORCA" ? AppColors.accentSuccess : AppColors.accentWarning)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppColors.backgroundTertiary.opacity(0.75))
                .clipShape(Capsule())
            if catalogModel.isLoading {
                ProgressView()
                    .scaleEffect(0.65)
            }
            if let error = catalogModel.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                if layer.id == "nats" {
                    natsStatusPill
                } else {
                    statusPill(layer.status)
                }
                ownerChip(layer.owner)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var natsStatusPill: some View {
        Text(natsHealthModel.displayStatus)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(natsHealthModel.statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(natsHealthModel.statusColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("NATS \(natsHealthModel.displayStatus)")
    }

    // MARK: - FISH section
    //
    // Per LAB-SYSTEMS-INDEX §11: Fish are the *research substrate fleet* (Starfish, Chieffish).
    // The Crew (named operators + workers + compute) lives on the Agents tab — Lab does not duplicate.

    private var fishSection: some View {
        let total = catalogModel.fishFleet.count + catalogModel.fishAdjacent.count
        return sectionCard {
            sectionHeader(title: "THE FISH 🐠", count: total, expanded: fishExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { fishExpanded.toggle() }
                }
        } body: {
            if fishExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    fishHeaderNote
                    fishStrip(title: "Research substrate fleet", fish: catalogModel.fishFleet)
                    fishStrip(title: "Adjacent (chief-local, not Pod-surfaced)", fish: catalogModel.fishAdjacent)
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
        let groups = workflowCatalogModel.groups
        let total = groups.reduce(0) { $0 + $1.items.count }
        return sectionCard {
            sectionHeader(title: "WORKFLOWS + PROTOCOLS", count: total, expanded: workflowsExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { workflowsExpanded.toggle() }
                }
        } body: {
            if workflowsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text(workflowCatalogModel.sourceLabel)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(workflowCatalogModel.sourceLabel == "ORCA" ? AppColors.accentSuccess : AppColors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.backgroundTertiary.opacity(0.75))
                            .clipShape(Capsule())
                        if workflowCatalogModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.65)
                        }
                        if let error = workflowCatalogModel.error {
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(2)
                        }
                    }

                    ForEach(groups) { group in
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
            Text("Currently spinning · \(catalogModel.currentlySpinning.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
            ForEach(catalogModel.currentlySpinning) { item in
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
        let building = catalogModel.currentlyBuilding
        return sectionCard {
            sectionHeader(title: "CURRENTLY BUILDING", count: building.count, expanded: buildingExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { buildingExpanded.toggle() }
                }
        } body: {
            if buildingExpanded {
                VStack(spacing: 0) {
                    ForEach(building) { item in
                        buildingRow(item)
                        if item.id != building.last?.id {
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
        let retired = catalogModel.retiredItems
        return sectionCard {
            sectionHeader(title: "RETIRED", count: retired.count, expanded: retiredExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { retiredExpanded.toggle() }
                }
        } body: {
            if retiredExpanded {
                VStack(spacing: 0) {
                    ForEach(retired) { item in
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
                        if item.id != retired.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
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

// MARK: - NATS health

@MainActor
@Observable
private final class LabNATSHealthModel {
    private(set) var status: String?
    private(set) var detail: String?
    private(set) var isLoading = false

    var displayStatus: String {
        if isLoading && status == nil { return "CHECKING" }
        return (status ?? "UNKNOWN").uppercased()
    }

    var badgeLabel: String {
        "NATS \(displayStatus)"
    }

    var statusColor: Color {
        switch (status ?? "").lowercased() {
        case "ok", "healthy", "live", "green":
            return AppColors.accentSuccess
        case "degraded", "warn", "warning", "yellow":
            return AppColors.accentWarning
        case "down", "failed", "error", "red":
            return AppColors.accentDanger
        default:
            return AppColors.textTertiary
        }
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response: LabNATSHealthResponse = try await APIClient.shared.get(path: "/api/v1/nats/health")
            status = response.status ?? response.health ?? response.state ?? "unknown"
            detail = response.message ?? response.summary
        } catch {
            status = "unknown"
            detail = "NATS health endpoint unavailable."
        }
    }
}

private struct LabNATSHealthResponse: Decodable {
    let status: String?
    let health: String?
    let state: String?
    let message: String?
    let summary: String?
}

// MARK: - ORCA-backed Lab catalog

@MainActor
@Observable
private final class LabCatalogModel {
    private(set) var stack: [LabStackLayer] = []
    private(set) var fishFleet: [LabFish] = []
    private(set) var fishAdjacent: [LabFish] = []
    private(set) var currentlySpinning: [LabSpinningItem] = []
    private(set) var currentlyBuilding: [LabBuildingItem] = []
    private(set) var retiredItems: [LabRetiredItem] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var sourceLabel = "ORCA"

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && !stack.isEmpty { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: WikiFileResponse = try await APIClient.shared.get(
                path: "/api/v1/wiki/file?path=operating-system/LAB-SYSTEMS-INDEX.md"
            )
            let parsed = Self.parse(markdown: response.content)
            stack = parsed.stack
            fishFleet = parsed.fishFleet
            fishAdjacent = parsed.fishAdjacent
            currentlySpinning = parsed.currentlySpinning
            currentlyBuilding = parsed.currentlyBuilding
            retiredItems = parsed.retiredItems
            sourceLabel = "ORCA"
            if parsed.stack.isEmpty {
                error = "LAB-SYSTEMS-INDEX parsed empty."
            }
        } catch {
            stack = []
            fishFleet = []
            fishAdjacent = []
            currentlySpinning = []
            currentlyBuilding = []
            retiredItems = []
            sourceLabel = "ORCA ERROR"
            self.error = "LAB-SYSTEMS-INDEX unavailable through ORCA."
        }
    }

    private struct ParsedCatalog {
        let stack: [LabStackLayer]
        let fishFleet: [LabFish]
        let fishAdjacent: [LabFish]
        let currentlySpinning: [LabSpinningItem]
        let currentlyBuilding: [LabBuildingItem]
        let retiredItems: [LabRetiredItem]
    }

    private static func parse(markdown: String) -> ParsedCatalog {
        let control = tableRows(in: markdown, headingPrefix: "## 1 ")
        let operating = tableRows(in: markdown, headingPrefix: "## 2 ")
        let compute = tableRows(in: markdown, headingPrefix: "## 3 ")
        let transport = tableRows(in: markdown, headingPrefix: "## 4 ")
        let memory = tableRows(in: markdown, headingPrefix: "## 5 ")
        let ops = tableRows(in: markdown, headingPrefix: "## 6 ")
        let stackRows = Array((control + operating + compute + transport + memory + ops).prefix(40))
        let stack = stackRows.compactMap(stackLayer(from:))
        let fishRows = tableRows(in: markdown, headingPrefix: "## 11 ")
        let fish = fishRows.compactMap(fishItem(from:))
        let buildingRows = tableRows(in: markdown, headingPrefix: "## 9 ")
        let building = buildingRows.compactMap(buildingItem(from:))
        let spinning = bulletItems(in: markdown, headingPrefix: "## 12 ")
            .prefix(8)
            .map { LabSpinningItem(title: $0, stage: "Experiment", owner: "ORCA") }

        return ParsedCatalog(
            stack: stack,
            fishFleet: fish.filter { $0.id != "octopus" },
            fishAdjacent: fish.filter { $0.id == "octopus" },
            currentlySpinning: Array(spinning),
            currentlyBuilding: building,
            retiredItems: []
        )
    }

    private static func stackLayer(from columns: [String]) -> LabStackLayer? {
        guard columns.count >= 4 else { return nil }
        let title = stripMarkdown(columns[0])
        guard !title.isEmpty else { return nil }
        let id = slug(title)
        let status = labStatus(columns[1])
        let owner = ownerCode(columns[2])
        return LabStackLayer(
            id: id,
            title: title,
            oneLine: stripMarkdown(columns[3]),
            status: status,
            owner: owner,
            icon: icon(for: id),
            tint: tint(for: id, status: status)
        )
    }

    private static func fishItem(from columns: [String]) -> LabFish? {
        guard columns.count >= 5 else { return nil }
        let emoji = stripMarkdown(columns[0])
        let name = stripMarkdown(columns[1])
        guard !name.isEmpty else { return nil }
        let partner = stripMarkdown(columns[2])
        let lane = stripMarkdown(columns[3])
        return LabFish(
            id: slug(name),
            emoji: emoji.isEmpty ? "•" : emoji,
            name: name,
            role: "\(lane) · partner: \(partner)",
            status: labStatus(columns[4])
        )
    }

    private static func buildingItem(from columns: [String]) -> LabBuildingItem? {
        guard columns.count >= 4 else { return nil }
        let title = stripMarkdown(columns[0])
        guard !title.isEmpty else { return nil }
        return LabBuildingItem(
            title: title,
            stage: stripMarkdown(columns[1]),
            owner: ownerCode(columns[2]),
            shortId: shortRef(from: columns[0])
        )
    }

    private static func tableRows(in markdown: String, headingPrefix: String) -> [[String]] {
        guard let section = sectionText(in: markdown, headingPrefix: headingPrefix) else { return [] }
        return section
            .components(separatedBy: "\n")
            .compactMap { line in
                let columns = markdownTableColumns(line)
                guard !columns.isEmpty, !columns.contains(where: { $0.lowercased() == "system" || $0.lowercased() == "project" }) else {
                    return nil
                }
                return columns
            }
    }

    private static func bulletItems(in markdown: String, headingPrefix: String) -> [String] {
        guard let section = sectionText(in: markdown, headingPrefix: headingPrefix) else { return [] }
        return section
            .components(separatedBy: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("- ") else { return nil }
                let item = stripMarkdown(String(trimmed.dropFirst(2)))
                return item.isEmpty ? nil : item
            }
    }

    private static func sectionText(in markdown: String, headingPrefix: String) -> String? {
        let lines = markdown.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix(headingPrefix) }) else { return nil }
        let tail = lines[(start + 1)...]
        let endOffset = tail.firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.endIndex
        return lines[(start + 1)..<endOffset].joined(separator: "\n")
    }

    fileprivate static func markdownTableColumns(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|"), !trimmed.contains("---") else { return [] }
        return trimmed
            .dropFirst()
            .dropLast()
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    fileprivate static func stripMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: #"^\[(.*?)\]\(.*?\)"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func slug(_ value: String) -> String {
        stripMarkdown(value)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func labStatus(_ value: String) -> LabStatus {
        let lower = value.lowercased()
        if lower.contains("retired") || lower.contains("archived") { return .retired }
        if lower.contains("live") || lower.contains("active") || lower.contains("protected") { return .live }
        if lower.contains("building") || lower.contains("signed") { return .building }
        if lower.contains("partial") || lower.contains("prototype") || lower.contains("blueprint") { return .partial }
        return .planned
    }

    private static func ownerCode(_ value: String) -> String {
        let cleaned = stripMarkdown(value)
            .replacingOccurrences(of: #"[^A-Za-z]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = cleaned.components(separatedBy: " ").first, !first.isEmpty else { return "ORCA" }
        return String(first.prefix(3)).uppercased()
    }

    private static func shortRef(from value: String) -> String {
        if let match = value.range(of: #"`([^`]+)`"#, options: .regularExpression) {
            return value[match].replacingOccurrences(of: "`", with: "")
        }
        return String(slug(value).prefix(8))
    }

    private static func icon(for id: String) -> String {
        if id.contains("orca") { return "server.rack" }
        if id.contains("pod") { return "ipad.landscape" }
        if id.contains("wiki") { return "books.vertical.fill" }
        if id.contains("nats") || id.contains("track-b") { return "point.3.connected.trianglepath.dotted" }
        if id.contains("compute") || id.contains("spark") || id.contains("kimi") { return "cpu.fill" }
        if id.contains("memory") || id.contains("chroma") { return "brain" }
        if id.contains("schoolhouse") { return "graduationcap.fill" }
        return "square.stack.3d.up.fill"
    }

    private static func tint(for id: String, status: LabStatus) -> Color {
        if id.contains("nats") { return AppColors.accentSuccess }
        if id.contains("pod") || id.contains("orca") { return AppColors.accentElectric }
        return status.color
    }
}

// MARK: - Architecture diagram

@MainActor
@Observable
private final class LabWorkflowCatalogModel {
    private(set) var groups: [LabWorkflowGroup] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var sourceLabel = "ORCA"

    func load(force: Bool = false) async {
        if isLoading { return }
        if !force && sourceLabel == "ORCA" { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        async let protocolsResponse: WikiFileResponse = APIClient.shared.get(path: "/api/v1/wiki/file?path=sops/PROTOCOLS-INDEX.md")
        async let workflowsResponse: WikiFileResponse = APIClient.shared.get(path: "/api/v1/wiki/file?path=workflows/INDEX.md")

        do {
            let (protocols, workflows) = try await (protocolsResponse, workflowsResponse)
            let parsedGroups = Self.makeGroups(protocolsMarkdown: protocols.content, workflowsMarkdown: workflows.content)
            guard !parsedGroups.isEmpty else {
                groups = []
                sourceLabel = "ORCA"
                error = "ORCA wiki indexes parsed empty."
                return
            }
            groups = parsedGroups
            sourceLabel = "ORCA"
        } catch {
            groups = []
            sourceLabel = "ORCA ERROR"
            self.error = "ORCA wiki indexes unavailable."
        }
    }

    private static func makeGroups(protocolsMarkdown: String, workflowsMarkdown: String) -> [LabWorkflowGroup] {
        var result: [LabWorkflowGroup] = []
        let workflowItems = workflowRows(from: workflowsMarkdown)
        if !workflowItems.isEmpty {
            result.append(LabWorkflowGroup(title: "Canonical workflow index", items: workflowItems))
        }
        let protocolItems = protocolRows(from: protocolsMarkdown)
        if !protocolItems.isEmpty {
            result.append(LabWorkflowGroup(title: "Canonical protocol index", items: protocolItems))
        }
        return result
    }

    private static func workflowRows(from markdown: String) -> [LabWorkflowItem] {
        markdown
            .components(separatedBy: "\n")
            .compactMap { line -> LabWorkflowItem? in
                let columns = LabCatalogModel.markdownTableColumns(line)
                guard columns.count >= 3, columns[0].contains("](") else { return nil }
                let workflow = LabCatalogModel.stripMarkdown(columns[0])
                let roles = LabCatalogModel.stripMarkdown(columns[1])
                let trigger = LabCatalogModel.stripMarkdown(columns[2])
                return LabWorkflowItem(
                    title: "\(workflow) — \(roles)",
                    status: trigger,
                    statusColor: AppColors.accentElectric
                )
            }
    }

    private static func protocolRows(from markdown: String) -> [LabWorkflowItem] {
        markdown
            .components(separatedBy: "\n")
            .compactMap { line -> LabWorkflowItem? in
                let columns = LabCatalogModel.markdownTableColumns(line)
                guard columns.count >= 4, columns[0].contains("PROTOCOL-") else { return nil }
                let proto = LabCatalogModel.stripMarkdown(columns[0])
                let cadence = LabCatalogModel.stripMarkdown(columns[1])
                let owner = LabCatalogModel.stripMarkdown(columns[2])
                let enforcement = LabCatalogModel.stripMarkdown(columns[3])
                return LabWorkflowItem(
                    title: "\(proto) — \(cadence) · \(owner)",
                    status: enforcement,
                    statusColor: AppColors.accentSuccess
                )
            }
    }

}

@MainActor
@Observable
private final class ArchitectureDiagramModel {
    private(set) var markdown = ""
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var sourceLabel = "ORCA"

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
                markdown = ""
                sourceLabel = "ORCA ERROR"
                self.error = "Architecture diagram unavailable through ORCA."
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
