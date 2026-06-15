import SwiftUI

// MARK: - LabView
//
// Per SPEC-POD-LAB-TAB-2026-05-23. The product catalog surface — what we have, who runs it, what's spinning.
// Mirrors Team-Wiki/operating-system/LAB-SYSTEMS-INDEX.md through ORCA's wiki bridge.

struct LabView: View {

    // Per-section expand/collapse state (default per spec §2).
    @State private var catalogModel = LabCatalogModel()
    @State private var workflowCatalogModel = LabWorkflowCatalogModel()
    @State private var fishExpanded      = false
    @State private var workflowsExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 44)
                        .padding(.bottom, 8)

                    fishSection
                    workflowsSection
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
                .task {
                    await catalogModel.load()
                    await workflowCatalogModel.load()
                }
                .refreshable {
                    await catalogModel.load(force: true)
                    await workflowCatalogModel.load(force: true)
                }
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lab")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            Text("Experiments: fish agents + workflows.")
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

}

// MARK: - ORCA-backed Lab catalog

@MainActor
@Observable
final class LabCatalogModel {
    private(set) var stack: [LabStackLayer] = []
    private(set) var fishFleet: [LabFish] = []
    private(set) var fishAdjacent: [LabFish] = []
    private(set) var currentlySpinning: [LabSpinningItem] = []
    private(set) var projectSections: [LabProjectSection] = []
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
            let response: LabSectionsResponse = try await APIClient.shared.get(path: "/api/v1/lab/sections")
            let sections = Self.projectSections(from: response)
            guard !sections.isEmpty else {
                throw APIError.message("Lab sections parsed empty.", code: nil)
            }
            applyStaticContent()
            projectSections = sections
            currentlyBuilding = sections.flatMap(\.projects)
            sourceLabel = "ORCA"
        } catch {
            applyStaticContent()
            sourceLabel = "FALLBACK"
            self.error = "ORCA Lab sections unavailable."
        }
    }

    private func applyStaticContent() {
        stack = LabContent.stack
        fishFleet = LabContent.fishFleet
        fishAdjacent = LabContent.fishAdjacent
        currentlySpinning = LabContent.currentlySpinning
        projectSections = []
        currentlyBuilding = LabContent.currentlyBuilding
        retiredItems = LabContent.retiredItems
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

    private static func projectSections(from response: LabSectionsResponse) -> [LabProjectSection] {
        response.sections.compactMap { section in
            let projects = section.projects.map { project in
                LabBuildingItem(
                    title: project.name,
                    stage: project.stage.isEmpty ? project.status : project.stage,
                    owner: layerCode(section.layer),
                    shortId: String(project.id.prefix(8)),
                    layer: section.layer
                )
            }
            guard !projects.isEmpty else { return nil }
            return LabProjectSection(layer: section.layer, boardId: section.boardId, projects: projects)
        }
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
            shortId: shortRef(from: columns[0]),
            layer: nil
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

    private static func layerCode(_ value: String) -> String {
        switch value.lowercased() {
        case "products":
            return "PRO"
        case "platform":
            return "PLT"
        default:
            return ownerCode(value)
        }
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

struct LabProjectSection: Identifiable {
    let layer: String
    let boardId: String
    let projects: [LabBuildingItem]

    var id: String { boardId }
}

private struct LabSectionsResponse: Decodable {
    let sections: [LabSectionResponse]
}

private struct LabSectionResponse: Decodable {
    let layer: String
    let boardId: String
    let projects: [LabProjectResponse]

    enum CodingKeys: String, CodingKey {
        case layer
        case boardId = "board_id"
        case projects
    }
}

private struct LabProjectResponse: Decodable {
    let id: String
    let name: String
    let goal: String?
    let stage: String
    let status: String
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
final class ArchitectureDiagramModel {
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

struct WikiFileResponse: Decodable {
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

struct ArchitectureDiagramSheet: View {
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

