import Foundation
import Observation
import SwiftUI

enum ParkingLotLifecycle: String, CaseIterable, Identifiable {
    case new
    case parked
    case promoted
    case dropped

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .new: "sparkles"
        case .parked: "parkingsign.circle"
        case .promoted: "arrow.up.forward.circle"
        case .dropped: "archivebox"
        }
    }

    var color: Color {
        switch self {
        case .new: AppColors.accentElectric
        case .parked: AppColors.accentWarning
        case .promoted: AppColors.accentSuccess
        case .dropped: AppColors.textTertiary
        }
    }
}

enum ParkingLotItemKind: String, CaseIterable, Identifiable, Codable {
    case idea
    case note
    case question

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ParkingLotTargetKind: String, CaseIterable, Identifiable, Codable {
    case ticket
    case project
    case finding

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .ticket: "ticket"
        case .project: "folder"
        case .finding: "doc.text.magnifyingglass"
        }
    }
}

struct ParkingLotPromotedTargetDTO: Decodable, Equatable {
    let kind: String?
    let id: String?

    private enum CodingKeys: String, CodingKey { case kind, id }

    init(kind: String?, id: String?) {
        self.kind = kind
        self.id = id
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        kind = try? container?.decodeIfPresent(String.self, forKey: .kind)
        id = try? container?.decodeIfPresent(String.self, forKey: .id)
    }
}

struct ParkingLotNoteDTO: Decodable, Identifiable, Equatable {
    let id: String
    let title: String?
    let body: String?
    let itemKind: String?
    let lifecycle: String?
    let capturedBy: String?
    let createdBy: String?
    let captureSource: String?
    let promotedTo: ParkingLotPromotedTargetDTO?
    let triagedBy: String?
    let triagedAt: Date?
    let dropReason: String?
    let createdAt: Date?
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, title, body, lifecycle
        case itemKind = "item_kind"
        case capturedBy = "captured_by"
        case createdBy = "created_by"
        case captureSource = "capture_source"
        case promotedTo = "promoted_to"
        case triagedBy = "triaged_by"
        case triagedAt = "triaged_at"
        case dropReason = "drop_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        title: String?,
        body: String?,
        itemKind: String?,
        lifecycle: String?,
        capturedBy: String?,
        createdBy: String?,
        captureSource: String?,
        promotedTo: ParkingLotPromotedTargetDTO?,
        triagedBy: String?,
        triagedAt: Date?,
        dropReason: String?,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.itemKind = itemKind
        self.lifecycle = lifecycle
        self.capturedBy = capturedBy
        self.createdBy = createdBy
        self.captureSource = captureSource
        self.promotedTo = promotedTo
        self.triagedBy = triagedBy
        self.triagedAt = triagedAt
        self.dropReason = dropReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        id = (try? container?.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        title = try? container?.decodeIfPresent(String.self, forKey: .title)
        body = try? container?.decodeIfPresent(String.self, forKey: .body)
        itemKind = try? container?.decodeIfPresent(String.self, forKey: .itemKind)
        lifecycle = try? container?.decodeIfPresent(String.self, forKey: .lifecycle)
        capturedBy = try? container?.decodeIfPresent(String.self, forKey: .capturedBy)
        createdBy = try? container?.decodeIfPresent(String.self, forKey: .createdBy)
        captureSource = try? container?.decodeIfPresent(String.self, forKey: .captureSource)
        promotedTo = try? container?.decodeIfPresent(ParkingLotPromotedTargetDTO.self, forKey: .promotedTo)
        triagedBy = try? container?.decodeIfPresent(String.self, forKey: .triagedBy)
        triagedAt = try? container?.decodeIfPresent(Date.self, forKey: .triagedAt)
        dropReason = try? container?.decodeIfPresent(String.self, forKey: .dropReason)
        createdAt = try? container?.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? container?.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    var normalizedLifecycle: ParkingLotLifecycle {
        ParkingLotLifecycle(rawValue: lifecycle?.lowercased() ?? "") ?? .new
    }

    var displayTitle: String { title?.nilIfBlankForParkingLot ?? "Untitled capture" }
    var displayBody: String { body?.nilIfBlankForParkingLot ?? "No detail captured." }
    var provenance: String { capturedBy?.nilIfBlankForParkingLot ?? createdBy?.nilIfBlankForParkingLot ?? "Unknown" }
}

private extension String {
    var nilIfBlankForParkingLot: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ParkingLotCreateRequest: Encodable {
    let title: String
    let body: String
    let targetType = "system"
    let noteType = "parking_lot"
    let itemKind: String
    let capturedBy: String
    let captureSource = "pod"
    let source = "pod.parking_lot"
}

struct ParkingLotUpdateRequest: Encodable {
    let lifecycle: String
    let triagedBy: String?
    let triagedAt: Date?
    let dropReason: String?
}

struct ParkingLotPromoteRequest: Encodable {
    let targetKind: String
}

struct ParkingLotPromoteResponseDTO: Decodable {
    let sourceNoteId: String?
    let targetKind: String?
    let targetId: String?
    let promotedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case sourceNoteId = "source_note_id"
        case targetKind = "target_kind"
        case targetId = "target_id"
        case promotedAt = "promoted_at"
    }
}

struct ParkingLotService {
    static let shared = ParkingLotService()
    private let api = APIClient.shared

    func fetch() async throws -> [ParkingLotNoteDTO] {
        try await api.get(path: "/api/v1/notes/system/global?note_type=parking_lot&limit=100")
    }

    @discardableResult
    func capture(_ body: String, itemKind: ParkingLotItemKind = .idea, capturedBy: String = "pod-user") async throws -> ParkingLotNoteDTO {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if ProcessInfo.processInfo.arguments.contains("--parking-lot-scenario=chat") {
            return ParkingLotNoteDTO(
                id: "test-chat-capture",
                title: "[TEST] Synthetic chat capture",
                body: trimmed,
                itemKind: itemKind.rawValue,
                lifecycle: "new",
                capturedBy: capturedBy,
                createdBy: nil,
                captureSource: "pod",
                promotedTo: nil,
                triagedBy: nil,
                triagedAt: nil,
                dropReason: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        let title = String(firstLine.prefix(120))
        let request = ParkingLotCreateRequest(
            title: title,
            body: trimmed,
            itemKind: itemKind.rawValue,
            capturedBy: capturedBy
        )
        return try await api.post(path: "/api/v1/notes/system/global", body: request)
    }

    @discardableResult
    func park(noteId: String) async throws -> ParkingLotNoteDTO {
        try await api.patch(
            path: "/api/v1/notes/\(noteId)",
            body: ParkingLotUpdateRequest(
                lifecycle: ParkingLotLifecycle.parked.rawValue,
                triagedBy: "tony",
                triagedAt: Date(),
                dropReason: nil
            )
        )
    }

    @discardableResult
    func drop(noteId: String, reason: String) async throws -> ParkingLotNoteDTO {
        try await api.patch(
            path: "/api/v1/notes/\(noteId)",
            body: ParkingLotUpdateRequest(
                lifecycle: ParkingLotLifecycle.dropped.rawValue,
                triagedBy: nil,
                triagedAt: nil,
                dropReason: reason
            )
        )
    }

    func promote(noteId: String, targetKind: ParkingLotTargetKind) async throws -> ParkingLotPromoteResponseDTO {
        try await api.post(
            path: "/api/v1/notes/\(noteId)/promote",
            body: ParkingLotPromoteRequest(targetKind: targetKind.rawValue)
        )
    }
}

@Observable
@MainActor
final class ParkingLotViewModel {
    var items: [ParkingLotNoteDTO] = []
    var selectedLifecycle: ParkingLotLifecycle = .new
    var composeText = ""
    var selectedItemKind: ParkingLotItemKind = .idea
    var isLoading = false
    var isSubmitting = false
    var busyNoteIds: Set<String> = []
    var errorMessage: String?
    var confirmationMessage: String?

    private let service = ParkingLotService.shared
    private let syntheticScenario: String?

    init() {
        syntheticScenario = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--parking-lot-scenario=") })?
            .replacingOccurrences(of: "--parking-lot-scenario=", with: "")
        if syntheticScenario == "populated" {
            items = Self.syntheticItems
        }
        if let filterArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--parking-lot-filter=") }),
           let lifecycle = ParkingLotLifecycle(rawValue: filterArgument.replacingOccurrences(of: "--parking-lot-filter=", with: "")) {
            selectedLifecycle = lifecycle
        }
    }

    var filteredItems: [ParkingLotNoteDTO] {
        items
            .filter { $0.normalizedLifecycle == selectedLifecycle }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func count(for lifecycle: ParkingLotLifecycle) -> Int {
        items.filter { $0.normalizedLifecycle == lifecycle }.count
    }

    func load() async {
        guard syntheticScenario == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await service.fetch()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func capture(capturedBy: String) async {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let note = try await service.capture(text, itemKind: selectedItemKind, capturedBy: capturedBy)
            items.insert(note, at: 0)
            composeText = ""
            selectedLifecycle = .new
            confirmationMessage = "Captured in Parking Lot. No work was dispatched."
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func park(_ note: ParkingLotNoteDTO) async {
        await mutate(note) { try await service.park(noteId: note.id) }
    }

    func drop(_ note: ParkingLotNoteDTO, reason: String) async {
        await mutate(note) { try await service.drop(noteId: note.id, reason: reason) }
    }

    func promote(_ note: ParkingLotNoteDTO, targetKind: ParkingLotTargetKind) async {
        guard !busyNoteIds.contains(note.id) else { return }
        busyNoteIds.insert(note.id)
        errorMessage = nil
        defer { busyNoteIds.remove(note.id) }
        do {
            let result = try await service.promote(noteId: note.id, targetKind: targetKind)
            let target = ParkingLotPromotedTargetDTO(kind: result.targetKind, id: result.targetId)
            replace(note, lifecycle: .promoted, promotedTo: target, dropReason: nil)
            selectedLifecycle = .promoted
            confirmationMessage = "Promoted to \(targetKind.title)."
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func mutate(_ note: ParkingLotNoteDTO, operation: () async throws -> ParkingLotNoteDTO) async {
        guard !busyNoteIds.contains(note.id) else { return }
        busyNoteIds.insert(note.id)
        errorMessage = nil
        defer { busyNoteIds.remove(note.id) }
        do {
            let updated = try await operation()
            if let index = items.firstIndex(where: { $0.id == note.id }) {
                items[index] = updated
            }
            selectedLifecycle = updated.normalizedLifecycle
            confirmationMessage = updated.normalizedLifecycle == .parked ? "Item parked." : "Item dropped with provenance preserved."
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func replace(
        _ note: ParkingLotNoteDTO,
        lifecycle: ParkingLotLifecycle,
        promotedTo: ParkingLotPromotedTargetDTO?,
        dropReason: String?
    ) {
        guard let index = items.firstIndex(where: { $0.id == note.id }) else { return }
        items[index] = ParkingLotNoteDTO(
            id: note.id,
            title: note.title,
            body: note.body,
            itemKind: note.itemKind,
            lifecycle: lifecycle.rawValue,
            capturedBy: note.capturedBy,
            createdBy: note.createdBy,
            captureSource: note.captureSource,
            promotedTo: promotedTo,
            triagedBy: note.triagedBy,
            triagedAt: Date(),
            dropReason: dropReason,
            createdAt: note.createdAt,
            updatedAt: Date()
        )
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError { return apiError.message }
        return error.localizedDescription
    }

    private static let syntheticItems: [ParkingLotNoteDTO] = {
        let now = Date()
        return [
            ParkingLotNoteDTO(id: "test-new", title: "[TEST] Synthetic new idea", body: "Test-only capture for queue visual verification.", itemKind: "idea", lifecycle: "new", capturedBy: "test-fixture", createdBy: nil, captureSource: "pod", promotedTo: nil, triagedBy: nil, triagedAt: nil, dropReason: nil, createdAt: now.addingTimeInterval(-180), updatedAt: now.addingTimeInterval(-180)),
            ParkingLotNoteDTO(id: "test-parked", title: "[TEST] Synthetic parked note", body: "Test-only parked item for lifecycle verification.", itemKind: "note", lifecycle: "parked", capturedBy: "test-fixture", createdBy: nil, captureSource: "pod", promotedTo: nil, triagedBy: "tony", triagedAt: now.addingTimeInterval(-120), dropReason: nil, createdAt: now.addingTimeInterval(-300), updatedAt: now.addingTimeInterval(-120)),
            ParkingLotNoteDTO(id: "test-promoted", title: "[TEST] Synthetic promoted question", body: "Test-only promoted item for target provenance verification.", itemKind: "question", lifecycle: "promoted", capturedBy: "test-fixture", createdBy: nil, captureSource: "pod", promotedTo: .init(kind: "ticket", id: "TEST-0001"), triagedBy: "tony", triagedAt: now.addingTimeInterval(-90), dropReason: nil, createdAt: now.addingTimeInterval(-420), updatedAt: now.addingTimeInterval(-90)),
            ParkingLotNoteDTO(id: "test-dropped", title: "[TEST] Synthetic dropped idea", body: "Test-only dropped item for provenance verification.", itemKind: "idea", lifecycle: "dropped", capturedBy: "test-fixture", createdBy: nil, captureSource: "pod", promotedTo: nil, triagedBy: nil, triagedAt: nil, dropReason: "[TEST] Duplicate fixture", createdAt: now.addingTimeInterval(-600), updatedAt: now.addingTimeInterval(-60))
        ]
    }()
}

struct ParkingLotView: View {
    @EnvironmentObject private var appState: AppState
    @State private var model = ParkingLotViewModel()
    @State private var pendingPark: ParkingLotNoteDTO?
    @State private var modal: ParkingLotActionModal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                composeCard
                lifecycleFilters
                statusBanner
                queueContent
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 80)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Parking Lot")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onAppear {
            guard let requestedModal = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("--parking-lot-modal=") })?
                .replacingOccurrences(of: "--parking-lot-modal=", with: ""),
                  let note = model.items.first(where: { $0.normalizedLifecycle == .new }) else { return }
            if requestedModal == "promote" { modal = .promote(note) }
            if requestedModal == "drop" { modal = .drop(note) }
            if requestedModal == "park" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pendingPark = note }
            }
        }
        .refreshable { await model.load() }
        .confirmationDialog(
            "Park this item?",
            isPresented: Binding(
                get: { pendingPark != nil },
                set: { if !$0 { pendingPark = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Park for later") {
                if let note = pendingPark { Task { await model.park(note) } }
                pendingPark = nil
            }
            Button("Cancel", role: .cancel) { pendingPark = nil }
        } message: {
            Text("This records Tony's triage timestamp and does not dispatch work.")
        }
        .sheet(item: $modal) { modal in
            switch modal {
            case .promote(let note):
                ParkingLotPromoteSheet(note: note) { kind in
                    self.modal = nil
                    Task { await model.promote(note, targetKind: kind) }
                }
            case .drop(let note):
                ParkingLotDropSheet(note: note) { reason in
                    self.modal = nil
                    Task { await model.drop(note, reason: reason) }
                }
            }
        }
    }

    private var capturedBy: String {
        appState.currentUser?.name.nilIfBlankForParkingLot
            ?? appState.authManager.currentUser?.name.nilIfBlankForParkingLot
            ?? "pod-user"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("PARKING LOT", systemImage: "parkingsign.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.accentElectric)
            Text("Capture now. Decide deliberately later.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            Text("Capturing never dispatches work. Promote is the explicit handoff boundary.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Capture an idea, note, or question…", text: $model.composeText, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .foregroundStyle(AppColors.textPrimary)
                .padding(12)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Picker("Kind", selection: $model.selectedItemKind) {
                    ForEach(ParkingLotItemKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .pickerStyle(.menu)
                Spacer()
                Button {
                    Task { await model.capture(capturedBy: capturedBy) }
                } label: {
                    Label(model.isSubmitting ? "Capturing" : "Capture", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accentElectric)
                .disabled(model.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSubmitting)
            }
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 0.5))
    }

    private var lifecycleFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ParkingLotLifecycle.allCases) { lifecycle in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { model.selectedLifecycle = lifecycle }
                    } label: {
                        Label("\(lifecycle.title) \(model.count(for: lifecycle))", systemImage: lifecycle.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.selectedLifecycle == lifecycle ? Color.white : lifecycle.color)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(model.selectedLifecycle == lifecycle ? lifecycle.color : lifecycle.color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(AppColors.accentDanger)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.accentDanger.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let message = model.confirmationMessage {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(AppColors.accentSuccess)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.accentSuccess.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var queueContent: some View {
        if model.isLoading && model.items.isEmpty {
            ProgressView("Loading Parking Lot…")
                .frame(maxWidth: .infinity, minHeight: 180)
                .foregroundStyle(AppColors.textSecondary)
        } else if model.filteredItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: model.selectedLifecycle.icon)
                    .font(.system(size: 34))
                    .foregroundStyle(model.selectedLifecycle.color)
                Text("No \(model.selectedLifecycle.title.lowercased()) items")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text(model.selectedLifecycle == .new ? "The queue is clear. Capture something above or type “parking lot: …” in direct chat." : "Nothing in this lifecycle yet.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: 340)
            }
            .frame(maxWidth: .infinity, minHeight: 210)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            LazyVStack(spacing: 10) {
                ForEach(model.filteredItems) { note in
                    ParkingLotRow(
                        note: note,
                        isBusy: model.busyNoteIds.contains(note.id),
                        onPark: { pendingPark = note },
                        onPromote: { modal = .promote(note) },
                        onDrop: { modal = .drop(note) }
                    )
                }
            }
        }
    }
}

private enum ParkingLotActionModal: Identifiable {
    case promote(ParkingLotNoteDTO)
    case drop(ParkingLotNoteDTO)

    var id: String {
        switch self {
        case .promote(let note): "promote-\(note.id)"
        case .drop(let note): "drop-\(note.id)"
        }
    }
}

private struct ParkingLotRow: View {
    let note: ParkingLotNoteDTO
    let isBusy: Bool
    let onPark: () -> Void
    let onPromote: () -> Void
    let onDrop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(note.displayBody)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(4)
                }
                Spacer(minLength: 8)
                if isBusy { ProgressView().controlSize(.small) }
            }

            HStack(spacing: 7) {
                Label(note.normalizedLifecycle.title, systemImage: note.normalizedLifecycle.icon)
                    .foregroundStyle(note.normalizedLifecycle.color)
                Text("·")
                Text(note.itemKind?.capitalized ?? "Item")
                Text("·")
                Label(note.provenance, systemImage: "person.crop.circle")
                if let createdAt = note.createdAt {
                    Text("·")
                    Text(createdAt, style: .relative)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColors.textTertiary)

            if let target = note.promotedTo,
               let kind = target.kind?.nilIfBlankForParkingLot,
               let id = target.id?.nilIfBlankForParkingLot {
                Label("\(kind.capitalized) · \(id)", systemImage: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.accentSuccess)
                    .textSelection(.enabled)
            }

            if let reason = note.dropReason?.nilIfBlankForParkingLot {
                Label(reason, systemImage: "text.quote")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            if note.normalizedLifecycle == .new || note.normalizedLifecycle == .parked {
                HStack(spacing: 8) {
                    if note.normalizedLifecycle == .new {
                        Button("Park", systemImage: "parkingsign.circle", action: onPark)
                    }
                    Button("Promote", systemImage: "arrow.up.forward.circle", action: onPromote)
                    Button("Drop", systemImage: "archivebox", action: onDrop)
                        .tint(AppColors.accentDanger)
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
        .padding(14)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 0.5))
    }
}

private struct ParkingLotPromoteSheet: View {
    let note: ParkingLotNoteDTO
    let onPromote: (ParkingLotTargetKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var targetKind: ParkingLotTargetKind = .ticket

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(note.displayTitle).font(.headline)
                Text("Promotion creates one first-class object and records its link on this source note.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                Picker("Target kind", selection: $targetKind) {
                    ForEach(ParkingLotTargetKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.icon).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                Spacer()
            }
            .padding(20)
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Promote item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Promote") { onPromote(targetKind) } }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ParkingLotDropSheet: View {
    let note: ParkingLotNoteDTO
    let onDrop: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(note.displayTitle).font(.headline)
                Text("Add a reason. The item stays in the Dropped lifecycle so its provenance is preserved.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                TextField("Reason for dropping", text: $reason, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(12)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer()
            }
            .padding(20)
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Drop item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Drop", role: .destructive) { onDrop(reason.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
