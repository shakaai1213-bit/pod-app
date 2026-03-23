import SwiftUI

// MARK: - Agent Status Card

struct AgentStatusCard: View {

    let agent: Agent
    let onTap: () -> Void

    // MARK: - Computed Properties

    private var avatarColor: Color {
        Color(hex: agent.avatarColor)
    }

    private var statusDotColor: Color {
        switch agent.status {
        case .online: return AppColors.accentSuccess
        case .busy:   return AppColors.accentWarning
        case .idle:   return AppColors.textTertiary
        case .offline: return AppColors.textMuted
        case .error:  return AppColors.accentDanger
        }
    }

    private var lastActivityText: String {
        RelativeTimeFormatter.shared.string(from: agent.lastActivity)
    }

    private var initials: String {
        let parts = agent.name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let second = parts.count > 1 ? parts[1].prefix(1) : ""
        return "\(first)\(second)".uppercased()
    }

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.sm) {
                avatarView
                agentInfo
                Spacer(minLength: 0)
                statusColumn
            }
            .padding(Theme.sm)
            .frame(width: 200)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(avatarColor.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(initials)
                        .podTextStyle(.headline, color: avatarColor)
                )

            Circle()
                .fill(statusDotColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .strokeBorder(AppColors.backgroundTertiary, lineWidth: 2)
                )
                .offset(x: 2, y: 2)
        }
    }

    private var agentInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(agent.name)
                .podTextStyle(.headline, color: AppColors.textPrimary)
                .lineLimit(1)

            Text(agent.role)
                .podTextStyle(.caption, color: AppColors.textSecondary)
                .lineLimit(1)
        }
    }

    private var statusColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(agent.status.displayName)
                .podTextStyle(.label, color: statusDotColor)
                .lineLimit(1)

            Text(lastActivityText)
                .podTextStyle(.caption, color: AppColors.textTertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - Relative Time Formatter

final class RelativeTimeFormatter {
    static let shared = RelativeTimeFormatter()

    private let formatter: RelativeDateTimeFormatter

    private init() {
        formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
    }

    func string(from date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Agent Detail Sheet

struct AgentDetailSheet: View {
    let agent: Agent
    @Environment(\.dismiss) private var dismiss

    private var avatarColor: Color {
        Color(hex: agent.avatarColor)
    }

    private var statusDotColor: Color {
        switch agent.status {
        case .online: return AppColors.accentSuccess
        case .busy:   return AppColors.accentWarning
        case .idle:   return AppColors.textTertiary
        case .offline: return AppColors.textMuted
        case .error:  return AppColors.accentDanger
        }
    }

    private var initials: String {
        let parts = agent.name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let second = parts.count > 1 ? parts[1].prefix(1) : ""
        return "\(first)\(second)".uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    headerSection
                    statusSection
                    currentTaskSection
                    skillsSection
                }
                .padding(Theme.md)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Agent Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var headerSection: some View {
        HStack(spacing: Theme.md) {
            Circle()
                .fill(avatarColor.opacity(0.2))
                .frame(width: 64, height: 64)
                .overlay(
                    Text(initials)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(avatarColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .podTextStyle(.title2, color: AppColors.textPrimary)

                Text(agent.role)
                    .podTextStyle(.body, color: AppColors.textSecondary)
            }

            Spacer()
        }
        .podCard()
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionLabel("Status")

            HStack(spacing: Theme.sm) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)

                Text(agent.status.displayName)
                    .podTextStyle(.body, color: statusDotColor)

                Spacer()

                Text("Last active \(RelativeTimeFormatter.shared.string(from: agent.lastActivity))")
                    .podTextStyle(.caption, color: AppColors.textSecondary)
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
    }

    private var currentTaskSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionLabel("Current Task")

            if let task = agent.currentTask {
                Text(task)
                    .podTextStyle(.body, color: AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            } else {
                Text("No active task")
                    .podTextStyle(.body, color: AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            sectionLabel("Skills")

            FlowLayout(spacing: Theme.xs) {
                ForEach(agent.skills, id: \.self) { skill in
                    Text(skill)
                        .podTextStyle(.label, color: AppColors.accentElectric)
                        .padding(.horizontal, Theme.sm)
                        .padding(.vertical, Theme.xxs)
                        .background(AppColors.accentElectric.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .podTextStyle(.label, color: AppColors.textTertiary)
    }
}

// MARK: - Flow Layout (Simple Wrap)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }

        return (CGSize(width: totalWidth, height: currentY + lineHeight), positions)
    }
}
