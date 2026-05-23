import SwiftUI

// MARK: - Cockpit Tier 1: Sign Queue
// Per MILESTONE-TONYS-20MIN-DAY-2026-05-22 — exit criterion 1: "Sign queue readable in Pod in ≤2 minutes.
// Tier 1 cockpit shows what needs Tony's eyes, sorted by gate, with one-tap sign/countermand."
//
// Data sources:
//   - GET /api/v1/tickets/approval-attention  — tickets in waiting_for_human / approval gate
//   - GET /api/v1/notes?sign_state=draft       — notes pending sign

struct CockpitSignQueueSection: View {
    @State private var model = CockpitSignQueueModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 0) {
                if model.isLoading && model.items.isEmpty {
                    skeletonRows
                } else if let err = model.error {
                    errorRow(err)
                } else if model.items.isEmpty {
                    emptyRow
                } else {
                    ForEach(Array(model.items.prefix(5).enumerated()), id: \.element.id) { idx, item in
                        VStack(spacing: 0) {
                            if idx > 0 {
                                Divider()
                                    .background(AppColors.border)
                                    .padding(.leading, 14)
                            }
                            row(item)
                        }
                    }

                    if model.items.count > 5 {
                        Divider().background(AppColors.border)
                        HStack {
                            Text("+\(model.items.count - 5) more pending")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
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
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13))
                .foregroundColor(AppColors.accentElectric)
            Text("NEEDS YOUR SIGN")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
                .kerning(0.5)
            Spacer()
            if !model.items.isEmpty {
                Text("\(model.items.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppColors.accentElectric.opacity(0.15))
                    .clipShape(Capsule())
            }
            Button {
                Task { await model.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Row

    private func row(_ item: CockpitSignItem) -> some View {
        HStack(spacing: 10) {
            // Kind icon
            ZStack {
                Circle()
                    .fill(item.kind.tint.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: item.kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(item.kind.tint)
            }

            // Title + gate
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(item.kind.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(item.kind.tint)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                    Text(item.gateLabel)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            // Actions
            if model.busyIds.contains(item.id) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
            } else {
                HStack(spacing: 6) {
                    Button {
                        Task { await model.sign(item) }
                    } label: {
                        Text("Sign")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.accentElectric)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await model.countermand(item) }
                    } label: {
                        Text("Pass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.backgroundTertiary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(AppColors.border, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - States

    private var skeletonRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 10) {
                    Circle().fill(AppColors.backgroundTertiary).frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(AppColors.backgroundTertiary).frame(height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(AppColors.backgroundTertiary).frame(width: 120, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private func errorRow(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentDanger)
                .font(.system(size: 12))
            Text(msg)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Button("Retry") { Task { await model.load() } }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.accentElectric)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 13))
                .foregroundColor(AppColors.accentSuccess)
            Text("Inbox zero. Nothing waiting on you.")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Cockpit Sign Item

struct CockpitSignItem: Identifiable, Hashable {
    let id: String
    let kind: Kind
    let title: String
    let gateLabel: String  // approval_gate or doc-name or reviewer
    let priority: String?
    let rawId: String      // server UUID for actions

    enum Kind: String {
        case ticket, note

        var label: String {
            switch self {
            case .ticket: return "TICKET"
            case .note:   return "NOTE"
            }
        }

        var icon: String {
            switch self {
            case .ticket: return "ticket.fill"
            case .note:   return "doc.text.fill"
            }
        }

        var tint: Color {
            switch self {
            case .ticket: return AppColors.accentWarning
            case .note:   return AppColors.accentElectric
            }
        }
    }
}

// MARK: - Model

@Observable
final class CockpitSignQueueModel {
    var items: [CockpitSignItem] = []
    var isLoading = false
    var error: String?
    var busyIds: Set<String> = []

    @MainActor
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        var combined: [CockpitSignItem] = []
        var anySucceeded = false

        // Source 1: tickets/approval-attention
        do {
            struct ApprovalAttentionResp: Decodable {
                let items: [ApprovalItem]
                struct ApprovalItem: Decodable {
                    let id: String
                    let title: String
                    let priority: String?
                    let approvalGate: String?
                    enum CodingKeys: String, CodingKey {
                        case id, title, priority
                        case approvalGate = "approval_gate"
                    }
                }
            }
            let resp: ApprovalAttentionResp = try await APIClient.shared.get(path: "/api/v1/tickets/approval-attention")
            anySucceeded = true
            for t in resp.items {
                combined.append(CockpitSignItem(
                    id: "ticket:\(t.id)",
                    kind: .ticket,
                    title: t.title,
                    gateLabel: t.approvalGate ?? "approval pending",
                    priority: t.priority,
                    rawId: t.id
                ))
            }
        } catch {
            // continue — try notes anyway
        }

        // Source 2: notes with sign_state=draft
        do {
            struct DraftNote: Decodable {
                let id: String
                let title: String
                let reviewer: String?
                let owner: String?
            }
            let notes: [DraftNote] = try await APIClient.shared.get(path: "/api/v1/notes?sign_state=draft&limit=100")
            anySucceeded = true
            for n in notes {
                // Skip notes already shown as their own surface (e.g. parking_lot is in Captain's Log)
                if n.title.lowercased().contains("smoke") || n.title.lowercased().contains("test") {
                    continue
                }
                combined.append(CockpitSignItem(
                    id: "note:\(n.id)",
                    kind: .note,
                    title: n.title,
                    gateLabel: n.reviewer ?? n.owner ?? "review pending",
                    priority: nil,
                    rawId: n.id
                ))
            }
        } catch {
            // continue
        }

        if !anySucceeded {
            error = "Sign queue unavailable"
            return
        }

        // Sort: urgent tickets first, then by kind (notes signal doctrine, tickets signal action)
        let priOrder: [String: Int] = ["urgent": 0, "high": 1, "medium": 2, "low": 3]
        items = combined.sorted { a, b in
            let aPri = priOrder[a.priority?.lowercased() ?? ""] ?? 9
            let bPri = priOrder[b.priority?.lowercased() ?? ""] ?? 9
            if aPri != bPri { return aPri < bPri }
            return a.title < b.title
        }
    }

    @MainActor
    func sign(_ item: CockpitSignItem) async {
        guard !busyIds.contains(item.id) else { return }
        busyIds.insert(item.id)
        defer { busyIds.remove(item.id) }

        switch item.kind {
        case .note:
            // PATCH note sign_state=live
            struct PatchBody: Encodable { let signState: String
                enum CodingKeys: String, CodingKey { case signState = "sign_state" }
            }
            do {
                let _: OrcaNote = try await APIClient.shared.patch(
                    path: "/api/v1/notes/\(item.rawId)",
                    body: PatchBody(signState: "live")
                )
                items.removeAll { $0.id == item.id }
            } catch {
                self.error = "Couldn't sign note. Retry."
            }
        case .ticket:
            // POST approval-request resolution
            // For now: mark ticket approval_state=approved via PATCH
            struct PatchBody: Encodable { let approvalState: String
                enum CodingKeys: String, CodingKey { case approvalState = "approval_state" }
            }
            do {
                let _: EmptyResponse = try await APIClient.shared.patch(
                    path: "/api/v1/tickets/\(item.rawId)",
                    body: PatchBody(approvalState: "approved")
                )
                items.removeAll { $0.id == item.id }
            } catch {
                self.error = "Couldn't approve ticket. Retry."
            }
        }
    }

    @MainActor
    func countermand(_ item: CockpitSignItem) async {
        // "Pass" = defer / not-now. For v1 we just remove from local list — full countermand backend later.
        items.removeAll { $0.id == item.id }
    }
}
