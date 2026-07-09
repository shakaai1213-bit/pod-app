import Foundation
import SwiftUI

// MARK: - Captain's Chart

struct CaptainsChartSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var ownedModel: CaptainsChartModel
    @State private var selectedProduct: CaptainsChartProduct?
    @State private var selectedMilestone: CaptainsChartMilestone?
    private let externalModel: CaptainsChartModel?

    private var model: CaptainsChartModel {
        externalModel ?? ownedModel
    }

    private let tileColumns = [
        GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)
    ]
    private let productColumns = [
        GridItem(.adaptive(minimum: 300), spacing: 10, alignment: .top)
    ]

    init(model: CaptainsChartModel? = nil) {
        _ownedModel = State(initialValue: model ?? CaptainsChartModel())
        externalModel = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = model.snapshot {
                CaptainsChartHeader(snapshot: snapshot, isLoading: model.isLoading)

                CaptainsChartMilestoneStrip(milestones: snapshot.milestones) { milestone in
                    selectedMilestone = milestone
                }

                if !snapshot.inFlight.isEmpty {
                    CaptainsChartInFlightStrip(items: snapshot.inFlight)
                }

                LazyVGrid(columns: tileColumns, spacing: 10) {
                    ForEach(snapshot.tiles) { tile in
                        CaptainsChartTile(tile: tile)
                    }
                }

                ForEach(snapshot.sections) { section in
                    CaptainsChartProductSection(section: section, columns: productColumns) { product in
                        selectedProduct = product
                    }
                }
            } else {
                CaptainsChartLoadingCard(isLoading: model.isLoading, errorMessage: model.errorMessage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.load() }
        .refreshable { await model.load(force: true) }
        .sheet(item: $selectedProduct) { product in
            CaptainsChartProductDetailSheet(
                product: product,
                chatAgent: CaptainsChartOwnerParser.firstChatAgent(from: product.owner)
            ) { agent in
                selectedProduct = nil
                appState.pendingDirectChatAgentId = agent.id
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedMilestone) { milestone in
            CaptainsChartMilestoneDetailSheet(milestone: milestone)
                .presentationDetents([.height(180), .medium])
        }
    }
}

// MARK: - Model

@Observable
final class CaptainsChartModel {
    var snapshot: CaptainsChartSnapshot?
    var isLoading = false
    var errorMessage: String?

    private let repository: any CaptainsChartSnapshotRepository
    private var hasLoaded = false

    init(repository: any CaptainsChartSnapshotRepository = BundledCaptainsChartSnapshotRepository()) {
        self.repository = repository
    }

    @MainActor
    func load(force: Bool = false) async {
        guard force || !hasLoaded else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            snapshot = try await repository.fetchSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

protocol CaptainsChartSnapshotRepository {
    func fetchSnapshot() async throws -> CaptainsChartSnapshot
}

struct BundledCaptainsChartSnapshotRepository: CaptainsChartSnapshotRepository {
    func fetchSnapshot() async throws -> CaptainsChartSnapshot {
        guard let url = Bundle.main.url(forResource: "captains_chart.snapshot", withExtension: "json")
            ?? Bundle.main.url(forResource: "captains_chart.snapshot.json", withExtension: nil)
        else {
            throw CaptainsChartSnapshotError.missingResource
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CaptainsChartSnapshot.self, from: data)
    }
}

enum CaptainsChartSnapshotError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "Captain's Chart snapshot is not bundled."
        }
    }
}

struct CaptainsChartSnapshot: Decodable, Equatable {
    let generatedAt: String
    let verifiedBy: String
    let milestones: [CaptainsChartMilestone]
    let inFlight: [CaptainsChartInFlightItem]
    let tiles: [CaptainsChartTileModel]
    let sections: [CaptainsChartProductGroup]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case verifiedBy = "verified_by"
        case milestones
        case inFlight = "in_flight"
        case tiles
        case sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        verifiedBy = try container.decodeIfPresent(String.self, forKey: .verifiedBy) ?? ""
        milestones = try container.decodeIfPresent([CaptainsChartMilestone].self, forKey: .milestones) ?? []
        inFlight = try container.decodeIfPresent([CaptainsChartInFlightItem].self, forKey: .inFlight) ?? []
        tiles = try container.decodeIfPresent([CaptainsChartTileModel].self, forKey: .tiles) ?? []
        sections = try container.decodeIfPresent([CaptainsChartProductGroup].self, forKey: .sections) ?? []
    }
}

struct CaptainsChartMilestone: Decodable, Equatable, Identifiable {
    let id: String
    let label: String
    let state: CaptainsChartMilestoneState

    enum CodingKeys: CodingKey {
        case id
        case label
        case state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Milestone"
        state = try container.decodeIfPresent(CaptainsChartMilestoneState.self, forKey: .state) ?? .open
    }
}

enum CaptainsChartMilestoneState: String, Decodable, Equatable {
    case done
    case next
    case open

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value.lowercased()) ?? .open
    }
}

struct CaptainsChartTileModel: Decodable, Equatable, Identifiable {
    let key: String
    let value: String
    let note: String

    var id: String { key }

    enum CodingKeys: CodingKey {
        case key
        case value
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? "Metric"
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? "-"
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct CaptainsChartInFlightItem: Decodable, Equatable, Identifiable {
    let name: String
    let owner: String
    let state: CaptainsChartInFlightState
    let note: String

    var id: String { "\(name)-\(owner)-\(state.label)" }

    enum CodingKeys: CodingKey {
        case name
        case owner
        case state
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "In flight"
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? "Unassigned"
        state = try container.decodeIfPresent(CaptainsChartInFlightState.self, forKey: .state) ?? .proposed
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

enum CaptainsChartInFlightState: Decodable, Equatable {
    case building
    case running
    case held
    case proposed

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        let normalized = value.lowercased()
        if normalized.contains("building") {
            self = .building
        } else if normalized.contains("running") {
            self = .running
        } else if normalized.contains("held") || normalized.contains("hold") {
            self = .held
        } else if normalized.contains("proposed") {
            self = .proposed
        } else {
            self = .proposed
        }
    }

    var label: String {
        switch self {
        case .building: return "Building"
        case .running: return "Running"
        case .held: return "Held"
        case .proposed: return "Proposed"
        }
    }

    var tint: Color {
        switch self {
        case .building: return CaptainsChartPalette.accent
        case .running: return CaptainsChartPalette.good
        case .held: return CaptainsChartPalette.hold
        case .proposed: return CaptainsChartPalette.watch
        }
    }

    var symbolName: String {
        switch self {
        case .building: return "diamond.fill"
        case .running: return "circle.fill"
        case .held: return "pause.circle"
        case .proposed: return "hexagon"
        }
    }
}

struct CaptainsChartProductGroup: Decodable, Equatable, Identifiable {
    let title: String
    let products: [CaptainsChartProduct]

    var id: String { title }

    enum CodingKeys: CodingKey {
        case title
        case products
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Products"
        products = try container.decodeIfPresent([CaptainsChartProduct].self, forKey: .products) ?? []
    }
}

struct CaptainsChartProduct: Decodable, Equatable, Identifiable {
    let name: String
    let owner: String
    let stage: CaptainsChartStage
    let health: CaptainsChartHealth
    let healthNote: String
    let usage: String
    let nextGate: String

    var id: String { "\(name)-\(owner)" }

    enum CodingKeys: String, CodingKey {
        case name
        case owner
        case stage
        case health
        case healthNote = "health_note"
        case usage
        case nextGate = "next_gate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Product"
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? "Unassigned"
        stage = try container.decodeIfPresent(CaptainsChartStage.self, forKey: .stage) ?? CaptainsChartStage()
        health = try container.decodeIfPresent(CaptainsChartHealth.self, forKey: .health) ?? .watch
        healthNote = try container.decodeIfPresent(String.self, forKey: .healthNote) ?? ""
        usage = try container.decodeIfPresent(String.self, forKey: .usage) ?? ""
        nextGate = try container.decodeIfPresent(String.self, forKey: .nextGate) ?? ""
    }
}

struct CaptainsChartStage: Decodable, Equatable {
    let design: CaptainsChartStageState
    let sign: CaptainsChartStageState
    let build: CaptainsChartStageState
    let live: CaptainsChartStageState
    let instrumented: CaptainsChartStageState

    init(
        design: CaptainsChartStageState = .todo,
        sign: CaptainsChartStageState = .todo,
        build: CaptainsChartStageState = .todo,
        live: CaptainsChartStageState = .todo,
        instrumented: CaptainsChartStageState = .todo
    ) {
        self.design = design
        self.sign = sign
        self.build = build
        self.live = live
        self.instrumented = instrumented
    }

    enum CodingKeys: CodingKey {
        case design
        case sign
        case build
        case live
        case instrumented
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        design = try container.decodeIfPresent(CaptainsChartStageState.self, forKey: .design) ?? .todo
        sign = try container.decodeIfPresent(CaptainsChartStageState.self, forKey: .sign) ?? .todo
        build = try container.decodeIfPresent(CaptainsChartStageState.self, forKey: .build) ?? .todo
        live = try container.decodeIfPresent(CaptainsChartStageState.self, forKey: .live) ?? .todo
        instrumented = try container.decodeIfPresent(CaptainsChartStageState.self, forKey: .instrumented) ?? .todo
    }

    func value(for key: CaptainsChartStageKey) -> CaptainsChartStageState {
        switch key {
        case .design: return design
        case .sign: return sign
        case .build: return build
        case .live: return live
        case .instrumented: return instrumented
        }
    }
}

enum CaptainsChartStageState: String, Decodable, Equatable {
    case done
    case half
    case todo

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value.lowercased()) ?? .todo
    }

    var label: String {
        switch self {
        case .done: return "Done"
        case .half: return "Partial"
        case .todo: return "Todo"
        }
    }
}

enum CaptainsChartStageKey: CaseIterable, Hashable {
    case design
    case sign
    case build
    case live
    case instrumented

    var label: String {
        switch self {
        case .design: return "Design"
        case .sign: return "Sign"
        case .build: return "Build"
        case .live: return "Live"
        case .instrumented: return "Instr."
        }
    }

    var detailLabel: String {
        switch self {
        case .design: return "Design"
        case .sign: return "Sign"
        case .build: return "Build"
        case .live: return "Live"
        case .instrumented: return "Instrumented"
        }
    }
}

enum CaptainsChartHealth: String, Decodable, Equatable {
    case steady
    case watch
    case attention
    case hold

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value.lowercased()) ?? .watch
    }

    var label: String {
        switch self {
        case .steady: return "Steady"
        case .watch: return "Watch"
        case .attention: return "Attention"
        case .hold: return "Hold"
        }
    }

    var tint: Color {
        switch self {
        case .steady: return CaptainsChartPalette.good
        case .watch: return CaptainsChartPalette.watch
        case .attention: return CaptainsChartPalette.alert
        case .hold: return CaptainsChartPalette.hold
        }
    }
}

// MARK: - Views

private struct CaptainsChartHeader: View {
    let snapshot: CaptainsChartSnapshot
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "map.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CaptainsChartPalette.accent)

                Text("NORTH POD LABS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CaptainsChartPalette.accent)
                    .tracking(0.8)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }

            Text("Captain's Chart")
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .foregroundStyle(AppColors.textPrimary)

            Text("The lab, in one map.")
                .font(.system(size: 13, weight: .regular, design: .serif).italic())
                .foregroundStyle(AppColors.textSecondary)

            Text(stampText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.textPrimary.opacity(0.6))
                .frame(height: 1)
        }
    }

    private var stampText: String {
        let generated = snapshot.generatedAt.isEmpty ? "bundled stub" : snapshot.generatedAt
        let verifier = snapshot.verifiedBy.isEmpty ? "snapshot resource" : snapshot.verifiedBy
        return "generated \(generated) - verified by \(verifier) - feed /cockpit/snapshot"
    }
}

private struct CaptainsChartMilestoneStrip: View {
    let milestones: [CaptainsChartMilestone]
    let onSelect: (CaptainsChartMilestone) -> Void

    var body: some View {
        FlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
            ForEach(milestones) { milestone in
                Button {
                    onSelect(milestone)
                } label: {
                    Text(milestone.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(milestone.state.foregroundColor)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(milestone.state.backgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(milestone.state.foregroundColor.opacity(0.55), lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Milestone \(milestone.label)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 1)
        .padding(.bottom, 4)
    }
}

private struct CaptainsChartInFlightStrip: View {
    let items: [CaptainsChartInFlightItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CaptainsChartPalette.accent)

                Text("NOW IN FLIGHT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(items) { item in
                        CaptainsChartInFlightCard(item: item)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 2)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 3)
    }
}

private struct CaptainsChartInFlightCard: View {
    let item: CaptainsChartInFlightItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                CaptainsChartInFlightStateChip(state: item.state)
            }

            Text(item.owner)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)

            Text(item.note)
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(width: 218, alignment: .topLeading)
        .frame(minHeight: 106, alignment: .topLeading)
        .background(CaptainsChartPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(CaptainsChartPalette.line, lineWidth: 0.75)
        )
    }
}

private struct CaptainsChartInFlightStateChip: View {
    let state: CaptainsChartInFlightState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.symbolName)
                .font(.system(size: 8, weight: .bold))

            Text(state.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.3)
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(state.tint.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.label) state")
    }
}

private struct CaptainsChartTile: View {
    let tile: CaptainsChartTileModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tile.key.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)
                .tracking(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Text(tile.value)
                .font(.system(size: 25, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(tile.note)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        .background(CaptainsChartPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(CaptainsChartPalette.line, lineWidth: 0.75)
        )
    }
}

private struct CaptainsChartProductSection: View {
    let section: CaptainsChartProductGroup
    let columns: [GridItem]
    let onProductTap: (CaptainsChartProduct) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(AppColors.textPrimary)

                if let note = sectionNote {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 9)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(section.products) { product in
                    Button {
                        onProductTap(product)
                    } label: {
                        CaptainsChartProductCard(product: product)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(product.name), open product details")
                }
            }
        }
    }

    private var sectionNote: String? {
        switch section.title.replacingOccurrences(of: "—", with: "-") {
        case "The Loop - agent operating system":
            return "Signal -> receipt -> wake -> claim -> act -> writeback -> evidence"
        case "Compute & Models":
            return "Buy nothing - measure everything - route ruthlessly downward"
        default:
            return nil
        }
    }
}

private struct CaptainsChartProductCard: View {
    let product: CaptainsChartProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Text(product.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text(product.owner)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 128, alignment: .trailing)
            }

            CaptainsChartHealthPill(health: product.health, note: product.healthNote)

            CaptainsChartStageTrack(stage: product.stage)

            CaptainsChartDashedDivider()

            Text(product.usage)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Next gate: \(product.nextGate)")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 206, alignment: .topLeading)
        .background(CaptainsChartPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(CaptainsChartPalette.line, lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct CaptainsChartHealthPill: View {
    let health: CaptainsChartHealth
    let note: String

    var body: some View {
        HStack(spacing: 6) {
            if health == .hold {
                Circle()
                    .strokeBorder(health.tint, lineWidth: 1.5)
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .fill(health.tint)
                    .frame(width: 7, height: 7)
            }

            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .textCase(.uppercase)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(health.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(health.tint.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var label: String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return health.label }
        return "\(health.label) - \(trimmed)"
    }
}

private struct CaptainsChartStageTrack: View {
    let stage: CaptainsChartStage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(CaptainsChartStageKey.allCases, id: \.self) { key in
                    HStack(spacing: 0) {
                        CaptainsChartStageDot(state: stage.value(for: key))

                        if key != .instrumented {
                            Rectangle()
                                .fill(stage.value(for: key) == .done ? CaptainsChartPalette.accent : CaptainsChartPalette.line)
                                .frame(height: 1.5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 0) {
                ForEach(CaptainsChartStageKey.allCases, id: \.self) { key in
                    Text(key.label)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textTertiary)
                        .textCase(.uppercase)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 1)
    }
}

private struct CaptainsChartStageDot: View {
    let state: CaptainsChartStageState
    private let size: CGFloat = 10

    var body: some View {
        ZStack(alignment: .leading) {
            Circle()
                .strokeBorder(borderColor, lineWidth: 1.5)
                .frame(width: size, height: size)

            if state == .done {
                Circle()
                    .fill(CaptainsChartPalette.accent)
                    .frame(width: size, height: size)
            } else if state == .half {
                Rectangle()
                    .fill(CaptainsChartPalette.accent)
                    .frame(width: size / 2, height: size)
                    .clipShape(Circle())

                Circle()
                    .strokeBorder(CaptainsChartPalette.accent, lineWidth: 1.5)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }

    private var borderColor: Color {
        switch state {
        case .done, .half:
            return CaptainsChartPalette.accent
        case .todo:
            return AppColors.textTertiary
        }
    }
}

private struct CaptainsChartDashedDivider: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay {
                CaptainsChartDashedLine()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(CaptainsChartPalette.line)
            }
            .padding(.top, 1)
    }
}

private struct CaptainsChartDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct CaptainsChartLoadingCard: View {
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "map.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CaptainsChartPalette.accent)

                Text("CAPTAIN'S CHART")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .tracking(0.5)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }

            Text(errorMessage ?? "Loading bundled product map")
                .font(.system(size: 12))
                .foregroundStyle(errorMessage == nil ? AppColors.textSecondary : AppColors.accentWarning)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CaptainsChartPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(CaptainsChartPalette.line, lineWidth: 0.75)
        )
    }
}

private struct CaptainsChartProductDetailSheet: View {
    let product: CaptainsChartProduct
    let chatAgent: AgentInfo?
    let onOpenChat: (AgentInfo) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(product.name)
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                            .foregroundStyle(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(product.owner)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CaptainsChartHealthPill(health: product.health, note: product.healthNote)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Stage")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.textTertiary)
                            .tracking(0.6)
                            .textCase(.uppercase)

                        CaptainsChartStageTrack(stage: product.stage)

                        CaptainsChartStageStatusList(stage: product.stage)
                    }
                    .padding(12)
                    .background(CaptainsChartPalette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(CaptainsChartPalette.line, lineWidth: 0.75)
                    )

                    CaptainsChartDetailRow(label: "Usage", value: product.usage)
                    CaptainsChartDetailRow(label: "Next gate", value: product.nextGate)
                    CaptainsChartDetailRow(label: "Owner", value: product.owner)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Product Detail")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let chatAgent {
                    Button {
                        onOpenChat(chatAgent)
                    } label: {
                        Label("Open chat with \(chatAgent.name)", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textPrimary)
                    .background(CaptainsChartPalette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(AppColors.backgroundPrimary.opacity(0.96))
                }
            }
        }
    }
}

private struct CaptainsChartStageStatusList: View {
    let stage: CaptainsChartStage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(CaptainsChartStageKey.allCases, id: \.self) { key in
                HStack(spacing: 8) {
                    CaptainsChartStageDot(state: stage.value(for: key))

                    Text(key.detailLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer()

                    Text(stage.value(for: key).label)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.textTertiary)
                        .textCase(.uppercase)
                }
            }
        }
    }
}

private struct CaptainsChartDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)

            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CaptainsChartPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(CaptainsChartPalette.line, lineWidth: 0.75)
        )
    }
}

private struct CaptainsChartMilestoneDetailSheet: View {
    let milestone: CaptainsChartMilestone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Milestone")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)

            Text(milestone.label)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(milestone.state.label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(milestone.state.foregroundColor)
                .textCase(.uppercase)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.backgroundPrimary)
    }
}

private enum CaptainsChartOwnerParser {
    static func firstChatAgent(from owner: String) -> AgentInfo? {
        let lowercasedOwner = owner.lowercased()
        let candidates = AgentInfo.team.compactMap { agent -> (AgentInfo, String.Index)? in
            let tokens = [agent.id.lowercased(), agent.name.lowercased()]
            let matches = tokens.compactMap { lowercasedOwner.range(of: $0)?.lowerBound }
            guard let firstMatch = matches.min() else { return nil }
            return (agent, firstMatch)
        }

        return candidates.min { lhs, rhs in lhs.1 < rhs.1 }?.0
    }
}

private enum CaptainsChartPalette {
    static let card = Color(hexString: "13232A")
    static let line = Color(hexString: "24383E")
    static let accent = Color(hexString: "43B3BD")
    static let accentSoft = Color(hexString: "43B3BD").opacity(0.12)
    static let good = Color(hexString: "58B183")
    static let watch = Color(hexString: "D9A83F")
    static let alert = Color(hexString: "E07A63")
    static let hold = Color(hexString: "8BA0A8")
}

private extension CaptainsChartMilestoneState {
    var label: String {
        switch self {
        case .done: return "Done"
        case .next: return "Next"
        case .open: return "Open"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .done: return CaptainsChartPalette.good
        case .next: return CaptainsChartPalette.accent
        case .open: return AppColors.textSecondary
        }
    }

    var backgroundColor: Color {
        switch self {
        case .done: return CaptainsChartPalette.good.opacity(0.11)
        case .next: return CaptainsChartPalette.accentSoft
        case .open: return CaptainsChartPalette.card
        }
    }
}
