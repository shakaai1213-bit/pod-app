import SwiftUI

// MARK: - LabView
//
// Per SPEC-POD-LAB-TAB-2026-05-23. The product catalog surface — what we have, who runs it, what's spinning.
// Mirrors Team-Wiki/operating-system/LAB-SYSTEMS-INDEX.md (currently hardcoded via LabContent.swift;
// swap to GET /api/v1/lab/sections when M-005 v2 ships).

struct LabView: View {

    // Per-section expand/collapse state (default per spec §2).
    @State private var architectureModel = ArchitectureDiagramModel()
    @State private var showingArchitectureSheet = false
    @State private var stackExpanded     = true
    @State private var fishExpanded      = false
    @State private var workflowsExpanded = false
    @State private var flywheelExpanded  = true
    @State private var buildingExpanded  = true
    @State private var retiredExpanded   = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 8)

                    architectureSection
                    stackSection
                    fishSection
                    workflowsSection
                    flywheelSection
                    buildingSection
                    retiredSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .task {
                await architectureModel.load()
            }
            .refreshable {
                await architectureModel.load(force: true)
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

    private var architectureSection: some View {
        sectionCard {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                Text("ARCHITECTURE")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if architectureModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    Text(architectureModel.sourceLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        } body: {
            VStack(alignment: .leading, spacing: 8) {
                Text("System map · tap to expand")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.textTertiary)

                ArchitectureDiagramCodeBlock(
                    text: architectureModel.previewText,
                    minHeight: 220
                )
                .frame(maxHeight: 260)
                .overlay(alignment: .bottomTrailing) {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.accentElectric)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.backgroundSecondary.opacity(0.92))
                        .clipShape(Capsule())
                        .padding(8)
                }

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
    let minHeight: CGFloat

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppColors.textPrimary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: minHeight)
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
