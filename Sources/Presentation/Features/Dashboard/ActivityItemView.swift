import SwiftUI

// MARK: - Activity Item View

struct ActivityItemView: View {

    let item: ActivityItem

    // MARK: - Computed

    private var timestampText: String {
        RelativeTimeFormatter.shared.string(from: item.timestamp)
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            iconView
            contentView
            Spacer(minLength: 0)
            timestampView
        }
        .padding(.vertical, Theme.xs)
    }

    // MARK: - Subviews

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(item.type.iconColor.opacity(0.15))
                .frame(width: 32, height: 32)

            Image(systemName: item.type.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.type.iconColor)
        }
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.description)
                .podTextStyle(.body, color: AppColors.textPrimary)
                .lineLimit(2)

            HStack(spacing: 4) {
                if item.isAgent {
                    Image(systemName: "cpu")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppColors.accentAgent)
                }

                Text(item.actor)
                    .podTextStyle(.caption, color: item.isAgent ? AppColors.accentAgent : AppColors.textSecondary)
            }
        }
    }

    private var timestampView: some View {
        Text(timestampText)
            .podTextStyle(.caption, color: AppColors.textTertiary)
            .frame(minWidth: 36, alignment: .trailing)
    }
}
