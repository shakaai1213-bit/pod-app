import SwiftUI

// MARK: - Captain's Log View
// Per SPEC-POD-TABS-HANDOFF §5 — read view (Step 3) + compose (Step 4) + promote actions (Step 5).

struct CaptainsLogView: View {
    @State private var model = CaptainsLogViewModel()
    @State private var composeExpanded = false
    @State private var composeText = ""
    @State private var composeKind: CaptainsLogViewModel.ItemKind = .note
    @FocusState private var composeFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 20)

                    logCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .refreshable { await model.load() }
            .task { await model.load() }
            .sheet(item: $model.pendingDropEntry) { entry in
                DropReasonSheet(entry: entry) { reason in
                    Task { await model.drop(entry, reason: reason) }
                }
                .presentationDetents([.height(220)])
            }
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Captain's Log")
                    .font(.title.weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("Your running notes. The team reads; Aloha digests.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            // + button — expands inline compose row
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    composeExpanded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    composeFocused = true
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(AppColors.accentElectric)
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Log Card

    private var logCard: some View {
        VStack(spacing: 0) {
            // Compose row placeholder (Step 4)
            composeRowPlaceholder

            Divider().background(AppColors.border)

            if model.isLoading && model.entries.isEmpty {
                entrySkeletons
            } else if let err = model.error {
                errorBanner(message: err) { Task { await model.load() } }
            } else if model.entries.isEmpty {
                emptyState
            } else {
                ForEach(Array(model.entries.enumerated()), id: \.element.id) { idx, entry in
                    VStack(spacing: 0) {
                        if idx > 0 {
                            Divider().background(AppColors.border)
                        }
                        entryRow(entry)
                    }
                }
            }
        }
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }

    // MARK: - Compose Row

    @ViewBuilder
    private var composeRowPlaceholder: some View {
        if composeExpanded {
            composeRowExpanded
        } else {
            composeRowCollapsed
        }
    }

    private var composeRowCollapsed: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppColors.accentElectric.opacity(0.3))
                    .frame(width: 24, height: 24)
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppColors.accentElectric.opacity(0.6))
            }
            Text("Add a note…")
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                composeExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                composeFocused = true
            }
        }
    }

    private var composeRowExpanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Kind picker
            HStack(spacing: 6) {
                ForEach(CaptainsLogViewModel.ItemKind.allCases, id: \.self) { kind in
                    Button {
                        composeKind = kind
                    } label: {
                        Text(kind.label)
                            .font(.caption2.weight(composeKind == kind ? .semibold : .regular))
                            .foregroundColor(composeKind == kind ? .white : AppColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(composeKind == kind ? AppColors.accentElectric : Color.clear)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(composeKind == kind ? Color.clear : AppColors.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // Text editor
            ZStack(alignment: .topLeading) {
                if composeText.isEmpty {
                    Text("What's on your mind?")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $composeText)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 60, maxHeight: 140)
                    .focused($composeFocused)
            }
            .padding(8)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(composeFocused ? AppColors.accentElectric : AppColors.border, lineWidth: 1)
            )

            // Error banner
            if let composeErr = model.composeError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.accentDanger)
                        .font(.caption2)
                    Text(composeErr)
                        .font(.caption)
                        .foregroundColor(AppColors.accentDanger)
                }
            }

            // Action row
            HStack {
                Button("Cancel") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        composeExpanded = false
                        composeText = ""
                        composeFocused = false
                        model.composeError = nil
                    }
                }
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)

                Spacer()

                Button {
                    Task {
                        let trimmed = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            model.composeError = "Note can't be empty"
                            return
                        }
                        let ok = await model.submit(body: trimmed, kind: composeKind)
                        if ok {
                            await MainActor.run {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    composeExpanded = false
                                    composeText = ""
                                    composeFocused = false
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if model.isSubmitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                                .tint(.white)
                        }
                        Text(model.isSubmitting ? "Saving…" : "Save")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.accentElectric.opacity(0.4) : AppColors.accentElectric)
                    .clipShape(Capsule())
                }
                .disabled(model.isSubmitting || composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: CaptainsLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Meta row
            HStack(spacing: 0) {
                Text(entry.capturedBy)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(" · ")
                    .foregroundColor(AppColors.textSecondary)
                    .font(.caption)
                Text(entry.createdAt.relativeAgo)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                // Undigested dot
                if entry.lifecycle == "new" {
                    undigestedDot
                }
            }

            // Body
            Text(entry.body)
                .font(.footnote)
                .foregroundColor(Color(hexString: "cfcfd4"))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Footer per lifecycle
            lifecycleFooter(entry)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.capturedBy) \(entry.createdAt.relativeAgo): \(entry.body). \(entry.lifecycleAccessibilityStatus).")
    }

    private var undigestedDot: some View {
        ZStack {
            Circle()
                .fill(AppColors.accentWarning.opacity(0.25))
                .frame(width: 14, height: 14)
            Circle()
                .fill(AppColors.accentWarning)
                .frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private func lifecycleFooter(_ entry: CaptainsLogEntry) -> some View {
        switch entry.lifecycle {
        case "new":
            HStack(spacing: 8) {
                // Promote menu — Step 5 actions (Promote/Park/Drop)
                Menu {
                    Button {
                        Task { await model.promote(entry, target: "ticket") }
                    } label: {
                        Label("Promote to Ticket", systemImage: "ticket")
                    }
                    Button {
                        Task { await model.promote(entry, target: "project") }
                    } label: {
                        Label("Promote to Project", systemImage: "square.stack.3d.up")
                    }
                    Divider()
                    Button {
                        Task { await model.park(entry) }
                    } label: {
                        Label("Park", systemImage: "pause")
                    }
                    Button(role: .destructive) {
                        model.pendingDropEntry = entry
                    } label: {
                        Label("Drop…", systemImage: "xmark")
                    }
                } label: {
                    HStack(spacing: 4) {
                        if model.busyEntryIds.contains(entry.id) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.5)
                                .tint(.white)
                        } else {
                            Text("Promote")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.accentElectric)
                    .clipShape(Capsule())
                }
                .disabled(model.busyEntryIds.contains(entry.id))
                .accessibilityLabel("Promote this note — opens menu")

                Text("awaiting Aloha digest")
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }
        case "parked":
            HStack(spacing: 4) {
                Image(systemName: "pause.fill")
                    .font(.caption2)
                Text("parked")
                    .font(.caption)
            }
            .foregroundColor(AppColors.textSecondary)
            .italic()
        case "promoted":
            if let promotedId = entry.promotedToId {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text("promoted to ticket \(String(promotedId.prefix(8)))")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.accentElectric)
                        .underline()
                }
            }
        case "dropped":
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.caption2)
                Text("dropped" + (entry.dropReason.map { " — \($0)" } ?? ""))
                    .font(.caption)
            }
            .foregroundColor(AppColors.textSecondary)
            .italic()
        case "digested-no-action":
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.semibold))
                Text("digested by Aloha — no action")
                    .font(.caption)
            }
            .foregroundColor(AppColors.accentSuccess)
        case "digested-action":
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.semibold))
                Text("digested by Aloha")
                    .font(.caption)
            }
            .foregroundColor(AppColors.accentSuccess)
        default:
            EmptyView()
        }
    }

    // MARK: - Skeleton / Error / Empty

    private var entrySkeletons: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(AppColors.backgroundTertiary).frame(width: 60, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(AppColors.backgroundTertiary).frame(width: 40, height: 12)
                    }
                    RoundedRectangle(cornerRadius: 4).fill(AppColors.backgroundTertiary).frame(height: 14)
                    RoundedRectangle(cornerRadius: 4).fill(AppColors.backgroundTertiary).frame(width: 200, height: 14)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                Divider().background(AppColors.border)
            }
        }
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentDanger)
            Text(message)
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Button("Retry", action: retry)
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppColors.accentElectric)
        }
        .padding(14)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16))
                .foregroundColor(AppColors.textSecondary)
            Text("Nothing here yet. Tap + to capture a note.")
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(14)
    }
}

// MARK: - Captain's Log View Model

@Observable
final class CaptainsLogViewModel {
    private static let projectId = "7a02b7c9-09be-4958-810f-92c7a2caaabe"
    private static let noteType = "captains_log"
    private static let source = "pod.captains_log"

    // ItemKind per SPEC-POD-TABS-HANDOFF §5.2: idea / note / question
    enum ItemKind: String, CaseIterable {
        case idea, note, question

        var label: String {
            switch self {
            case .idea:     return "Idea"
            case .note:     return "Note"
            case .question: return "Question"
            }
        }
    }

    var entries: [CaptainsLogEntry] = []
    var isLoading = false
    var error: String?
    var isSubmitting = false
    var composeError: String?
    var busyEntryIds: Set<String> = []
    var pendingDropEntry: CaptainsLogEntry?
    var actionError: String?

    @MainActor
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            struct NoteListItem: Decodable {
                let id: String
                let title: String
                let body: String
                let createdBy: String?
                let lifecycle: String?
                let dropReason: String?
                let promotedTo: PromotedTo?
                let createdAt: Date

                struct PromotedTo: Decodable {
                    let kind: String
                    let id: String
                }

                enum CodingKeys: String, CodingKey {
                    case id, title, body, lifecycle
                    case createdBy   = "created_by"
                    case dropReason  = "drop_reason"
                    case promotedTo  = "promoted_to"
                    case createdAt   = "created_at"
                }
            }

            let path = "/api/v1/projects/\(Self.projectId)/notes?note_type=\(Self.noteType)&limit=50"
            let items: [NoteListItem] = try await APIClient.shared.get(path: path)

            entries = items.map { note in
                CaptainsLogEntry(
                    id: note.id,
                    body: note.body.isEmpty ? note.title : note.body,
                    capturedBy: (note.createdBy ?? "tony").capitalized,
                    lifecycle: note.lifecycle ?? "new",
                    createdAt: note.createdAt,
                    dropReason: note.dropReason,
                    promotedToId: note.promotedTo?.id
                )
            }
        } catch {
            self.error = "Couldn't load Captain's Log."
            entries = []
        }
    }

    @MainActor
    func submit(body: String, kind: ItemKind) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        composeError = nil
        defer { isSubmitting = false }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(trimmed.prefix(60)) + (trimmed.count > 60 ? "…" : "")

        struct CreateBody: Encodable {
            let targetType: String
            let targetId: String
            let noteType: String
            let itemKind: String        // idea/note/question
            let lifecycle: String       // "new"
            let captureSource: String   // "pod"
            let title: String
            let body: String
            let tags: [String]
            let source: String
            let traceId: String
            let signState: String

            enum CodingKeys: String, CodingKey {
                case title, body, tags, source, lifecycle
                case targetType    = "target_type"
                case targetId      = "target_id"
                case noteType      = "note_type"
                case itemKind      = "item_kind"
                case captureSource = "capture_source"
                case traceId       = "trace_id"
                case signState     = "sign_state"
            }
        }

        let request = CreateBody(
            targetType: "project",
            targetId: Self.projectId,
            noteType: Self.noteType,
            itemKind: kind.rawValue,
            lifecycle: "new",
            captureSource: "pod",
            title: title,
            body: trimmed,
            tags: ["captains-log", kind.rawValue],
            source: Self.source,
            traceId: "pod-captains-log-\(Int(Date().timeIntervalSince1970))",
            signState: "draft"
        )

        do {
            let _: ProjectNoteDTO = try await APIClient.shared.post(
                path: "/api/v1/projects/\(Self.projectId)/notes",
                body: request
            )
            await load()
            return true
        } catch {
            composeError = "Couldn't save note."
            return false
        }
    }

    @MainActor
    func promote(_ entry: CaptainsLogEntry, target: String) async {
        guard !busyEntryIds.contains(entry.id) else { return }
        busyEntryIds.insert(entry.id)
        actionError = nil
        defer { busyEntryIds.remove(entry.id) }

        // Per backend NotePromoteRequest schema: target_kind (required)
        struct PromoteBody: Encodable {
            let targetKind: String
            enum CodingKeys: String, CodingKey {
                case targetKind = "target_kind"
            }
        }

        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                path: "/api/v1/notes/\(entry.id)/promote",
                body: PromoteBody(targetKind: target)
            )
            await load()
        } catch {
            actionError = "Couldn't promote note."
        }
    }

    @MainActor
    func park(_ entry: CaptainsLogEntry) async {
        guard !busyEntryIds.contains(entry.id) else { return }
        busyEntryIds.insert(entry.id)
        actionError = nil
        defer { busyEntryIds.remove(entry.id) }

        struct ParkBody: Encodable {
            let lifecycle: String
            let source: String
        }

        do {
            let _: EmptyResponse = try await APIClient.shared.patch(path: "/api/v1/notes/\(entry.id)", body: ParkBody(lifecycle: "parked", source: Self.source))
            await load()
        } catch {
            actionError = "Couldn't park note."
        }
    }

    @MainActor
    func drop(_ entry: CaptainsLogEntry, reason: String) async {
        guard !busyEntryIds.contains(entry.id) else { return }
        busyEntryIds.insert(entry.id)
        pendingDropEntry = nil
        actionError = nil
        defer { busyEntryIds.remove(entry.id) }

        do {
            _ = reason
            try await APIClient.shared.delete(path: "/api/v1/projects/\(Self.projectId)/notes/\(entry.id)")
            await load()
        } catch {
            actionError = "Couldn't drop note."
        }
    }
}

// MARK: - Captain's Log Entry

struct CaptainsLogEntry: Identifiable {
    let id: String
    let body: String
    let capturedBy: String
    let lifecycle: String
    let createdAt: Date
    let dropReason: String?
    let promotedToId: String?
}

private extension CaptainsLogEntry {
    var lifecycleAccessibilityStatus: String {
        switch lifecycle {
        case "new":
            return "awaiting Aloha digest"
        case "parked":
            return "parked"
        case "promoted":
            return promotedToId.map { "promoted to ticket \(String($0.prefix(8)))" } ?? "promoted"
        case "dropped":
            return "dropped" + (dropReason.map { " — \($0)" } ?? "")
        case "digested-no-action":
            return "digested by Aloha, no action"
        case "digested-action":
            return "digested by Aloha"
        default:
            return lifecycle.replacingOccurrences(of: "-", with: " ")
        }
    }
}

private struct DropReasonSheet: View {
    let entry: CaptainsLogEntry
    let onDrop: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Drop note")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            TextField("Reason", text: $reason, axis: .vertical)
                .font(.subheadline)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(AppColors.textSecondary)

                Spacer()

                Button("Drop") {
                    onDrop(reason.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .background(AppColors.backgroundPrimary)
    }
}

// MARK: - Date Extension

private extension Date {
    var relativeAgo: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400))d ago" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: self)
    }
}
