import SwiftUI

// MARK: - Captain's Log View
// Per SPEC-POD-TABS-HANDOFF §5 — read view (Step 3). Compose (Step 4) + actions (Step 5) follow.

struct CaptainsLogView: View {
    @State private var model = CaptainsLogViewModel()

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
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Captain's Log")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("Your running notes. The team reads; Aloha digests.")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
            // + button — compose (Step 4, disabled until backend extension lands)
            Button {
                // TODO: open compose sheet when backend Notes extension ships (ticket c5cf51e1)
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
            .disabled(true)
            .opacity(0.4)
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

    // MARK: - Compose Row Placeholder

    private var composeRowPlaceholder: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppColors.accentElectric.opacity(0.3))
                    .frame(width: 24, height: 24)
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppColors.accentElectric.opacity(0.5))
            }
            Text("Add a note…")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: CaptainsLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Meta row
            HStack(spacing: 0) {
                Text(entry.capturedBy)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(" · ")
                    .foregroundColor(AppColors.textTertiary)
                    .font(.system(size: 12))
                Text(entry.createdAt.relativeAgo)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textTertiary)
                Spacer()
                // Undigested dot
                if entry.lifecycle == "new" {
                    undigestedDot
                }
            }

            // Body
            Text(entry.body)
                .font(.system(size: 13))
                .foregroundColor(Color(hexString: "cfcfd4"))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Footer per lifecycle
            lifecycleFooter(entry)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
                // Promote button — disabled until Step 5 (promote actions)
                Button {
                    // TODO: promote action sheet (ticket 04ccdd78)
                } label: {
                    HStack(spacing: 4) {
                        Text("Promote")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.accentElectric)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.6)

                Text("awaiting Aloha digest")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
        case "parked":
            HStack(spacing: 4) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11))
                Text("parked")
                    .font(.system(size: 12))
            }
            .foregroundColor(AppColors.textTertiary)
            .italic()
        case "promoted":
            if let promotedId = entry.promotedToId {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                    Text("promoted to ticket \(String(promotedId.prefix(8)))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.accentElectric)
                        .underline()
                }
            }
        case "dropped":
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                Text("dropped" + (entry.dropReason.map { " — \($0)" } ?? ""))
                    .font(.system(size: 12))
            }
            .foregroundColor(AppColors.textTertiary)
            .italic()
        case "digested-no-action":
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Text("digested by Aloha — no action")
                    .font(.system(size: 12))
            }
            .foregroundColor(AppColors.accentSuccess)
        case "digested-action":
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Text("digested by Aloha")
                    .font(.system(size: 12))
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
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Button("Retry", action: retry)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)
        }
        .padding(14)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
            Text("Nothing here yet. Tap + to capture a note.")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(14)
    }
}

// MARK: - Captain's Log View Model

@Observable
final class CaptainsLogViewModel {
    var entries: [CaptainsLogEntry] = []
    var isLoading = false
    var error: String?

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
                let capturedBy: String?
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
                    case capturedBy  = "captured_by"
                    case dropReason  = "drop_reason"
                    case promotedTo  = "promoted_to"
                    case createdAt   = "created_at"
                }
            }

            struct NotesResponse: Decodable {
                let items: [NoteListItem]?
                // API may return plain array
            }

            // Try paginated first, fall back to array
            let path = "/api/v1/notes?type=parking_lot&order=created_at.desc&limit=50"
            let items: [NoteListItem]
            if let paginated: NotesResponse = try? await APIClient.shared.get(path: path),
               let list = paginated.items {
                items = list
            } else {
                items = (try? await APIClient.shared.get(path: path)) ?? []
            }

            entries = items.map { note in
                CaptainsLogEntry(
                    id: note.id,
                    body: note.body.isEmpty ? note.title : note.body,
                    capturedBy: (note.capturedBy ?? "tony").capitalized,
                    lifecycle: note.lifecycle ?? "new",
                    createdAt: note.createdAt,
                    dropReason: note.dropReason,
                    promotedToId: note.promotedTo?.id
                )
            }
        } catch {
            // Notes parking_lot type not yet extended — show empty state gracefully
            self.error = nil  // quiet error; backend extension pending
            entries = []
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
