import SwiftUI

// MARK: - Playground Panel (Locker-phase NATS tail)
// Surfaces Maui's inbox tail in the Dashboard Locker entry.
// No new top-level tab — panel lives in Dashboard per PLAYGROUND-INTEGRATION-PLAN-2026-06-14.

@Observable
final class PlaygroundPanelModel {
    var tail: InboxTailDTO?
    var isLoading = false
    var errorMessage: String?

    @MainActor
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tail = try await APIClient.shared.get(path: Endpoint.agentInboxTail(name: "maui", limit: 5).path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PlaygroundPanelView: View {
    let model: PlaygroundPanelModel
    let onChatTap: (() -> Void)?

    private let playgroundTeal = Color(red: 0.20, green: 0.70, blue: 0.90)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            panelHeader
            panelContent
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(playgroundTeal.opacity(0.30), lineWidth: 1)
        )
    }

    private var panelHeader: some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(playgroundTeal)
            Text("PLAYGROUND")
                .podTextStyle(.label, color: AppColors.textTertiary)
            if let tail = model.tail, tail.unreadEntries > 0 {
                Text("·  \(tail.unreadEntries) unread")
                    .podTextStyle(.label, color: playgroundTeal)
            }
            Spacer()
            if model.isLoading {
                ProgressView().scaleEffect(0.55)
            }
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        if let tail = model.tail {
            if tail.recent.isEmpty {
                Text("No recent inbox messages")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                messageList(tail.recent)
            }
            actionRow
        } else if model.isLoading {
            Text("Loading NATS tail...")
                .podTextStyle(.caption, color: AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = model.errorMessage {
            Text(error)
                .podTextStyle(.caption, color: AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
    }

    private func messageList(_ entries: [InboxTailEntryDTO]) -> some View {
        VStack(spacing: 0) {
            ForEach(entries.prefix(5)) { entry in
                HStack(alignment: .top, spacing: Theme.xs) {
                    Circle()
                        .fill(entry.isUnread ? playgroundTeal : Color.clear)
                        .overlay(
                            Circle()
                                .strokeBorder(entry.isUnread ? playgroundTeal : AppColors.textTertiary.opacity(0.4), lineWidth: 1)
                        )
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(entry.from)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(entry.isUnread ? AppColors.textPrimary : AppColors.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(relativeAge(entry.timestamp))
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        Text(entry.displayTitle)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
                if entry.id != entries.prefix(5).last?.id {
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: Theme.sm) {
            Button {
                onChatTap?()
            } label: {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(playgroundTeal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(playgroundTeal.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, Theme.xs)
    }

    private func relativeAge(_ ts: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: ts)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: ts)
        }
        guard let date else { return "" }
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 90 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h" }
        return "\(Int(elapsed / 86400))d"
    }
}
