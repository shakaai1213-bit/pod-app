import Foundation
import SwiftUI

// MARK: - Captain's Chart

struct CaptainsChartSection: View {
    @State private var model = CaptainsChartModel()

    private let tileColumns = [
        GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)
    ]
    private let productColumns = [
        GridItem(.adaptive(minimum: 300), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = model.snapshot {
                CaptainsChartHeader(snapshot: snapshot, isLoading: model.isLoading)

                CaptainsChartMilestoneStrip(milestones: snapshot.milestones)

                LazyVGrid(columns: tileColumns, spacing: 10) {
                    ForEach(snapshot.tiles) { tile in
                        CaptainsChartTile(tile: tile)
                    }
                }

                ForEach(snapshot.sections) { section in
                    CaptainsChartProductSection(section: section, columns: productColumns)
                }
            } else {
                CaptainsChartLoadingCard(isLoading: model.isLoading, errorMessage: model.errorMessage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.load() }
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
    let tiles: [CaptainsChartTileModel]
    let sections: [CaptainsChartProductGroup]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case verifiedBy = "verified_by"
        case milestones
        case tiles
        case sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        verifiedBy = try container.decodeIfPresent(String.self, forKey: .verifiedBy) ?? ""
        milestones = try container.decodeIfPresent([CaptainsChartMilestone].self, forKey: .milestones) ?? []
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

    var body: some View {
        FlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
            ForEach(milestones) { milestone in
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
        }
        .padding(.horizontal, 14)
        .padding(.top, 1)
        .padding(.bottom, 4)
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
                    CaptainsChartProductCard(product: product)
                }
            }
        }
    }

    private var sectionNote: String? {
        switch section.title {
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
