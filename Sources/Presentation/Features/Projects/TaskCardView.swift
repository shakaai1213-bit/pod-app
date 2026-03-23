import SwiftUI

// MARK: - Task Card View

struct TaskCardView: View {

    let task: ProjectTask
    let members: [TeamMember]

    // MARK: - State

    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    // MARK: - Computed

    private var assignee: TeamMember? {
        members.first { task.assigneeId == $0.id }
    }

    private var isOverdue: Bool {
        guard let due = task.dueDate else { return false }
        return due < Date() && !Calendar.current.isDateInToday(due)
    }

    private var visibleTags: [String] {
        Array(task.tags.prefix(3))
    }

    private var extraTagCount: Int {
        max(0, task.tags.count - 3)
    }

    // MARK: - Swipe Actions

    private enum SwipeDirection {
        case left
        case right
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Left swipe (Mark Done)
            swipeBackground(direction: .right, color: AppColors.accentSuccess, icon: "checkmark")

            // Card Content
            cardContent
                .frame(maxWidth: .infinity, alignment: .leading)

            // Right swipe (Defer)
            swipeBackground(direction: .left, color: AppColors.accentWarning, icon: "clock.arrow.circlepath")
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .offset(offset)
        .gesture(swipeGesture)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        .onChange(of: offset) { _, newValue in
            isDragging = abs(newValue.width) > 10
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            // Title + Priority
            HStack(alignment: .top, spacing: Theme.xs) {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                Text(task.title)
                    .podTextStyle(.headline, color: AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }

            // Assignee + Due Date
            HStack(spacing: Theme.xs) {
                if let assignee = assignee {
                    avatarView(assignee)
                    Text(assignee.name)
                        .podTextStyle(.caption, color: AppColors.textSecondary)
                        .lineLimit(1)
                }

                if assignee != nil && task.dueDate != nil {
                    Text("•")
                        .foregroundStyle(AppColors.textTertiary)
                }

                if let due = task.dueDate {
                    dueDateView(due)
                }

                Spacer(minLength: 0)
            }

            // Tags
            if !task.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(visibleTags, id: \.self) { tag in
                        tagPill(tag)
                    }

                    if extraTagCount > 0 {
                        Text("+\(extraTagCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.backgroundTertiary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(Theme.sm)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Swipe Background

    private func swipeBackground(direction: SwipeDirection, color: Color, icon: String) -> some View {
        let isCorrectDirection = direction == .right
        let threshold: CGFloat = 60
        let showThreshold: CGFloat = 40

        return ZStack(alignment: direction == .right ? .leading : .trailing) {
            Rectangle()
                .fill(color.opacity(0.15))
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, Theme.md)
                        .opacity(offset.width.magnitude > showThreshold ? 1 : 0)
                )

            if direction == .right {
                Rectangle()
                    .fill(color.opacity(0.15))
                    .frame(width: max(0, offset.width))
                    .opacity(offset.width > 0 ? 1 : 0)
            } else {
                Rectangle()
                    .fill(color.opacity(0.15))
                    .frame(width: max(0, -offset.width))
                    .opacity(offset.width < 0 ? 1 : 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation
            }
            .onEnded { value in
                let threshold: CGFloat = 80

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if value.translation.width > threshold {
                        // Mark done
                        offset = .zero
                        NotificationCenter.default.post(
                            name: .taskMarkedDone,
                            object: task.id
                        )
                    } else if value.translation.width < -threshold {
                        // Defer
                        offset = .zero
                        NotificationCenter.default.post(
                            name: .taskDeferred,
                            object: task.id
                        )
                    } else {
                        offset = .zero
                    }
                }
            }
    }

    // MARK: - Subviews

    private func avatarView(_ member: TeamMember) -> some View {
        Circle()
            .fill(Color(hexString: member.avatarColor ?? "#6B46C1"))
            .frame(width: 16, height: 16)
            .overlay(
                Text(member.name.prefix(1))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white)
            )
    }

    @ViewBuilder
    private func dueDateView(_ date: Date) -> some View {
        if Calendar.current.isDateInToday(date) {
            Text("Today")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.accentWarning)
        } else if Calendar.current.isDateInTomorrow(date) {
            Text("Tomorrow")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        } else if isOverdue {
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColors.accentDanger)
                Text(date, format: Date.FormatStyle().month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.accentDanger)
            }
        } else {
            Text(date, format: Date.FormatStyle().month(.abbreviated).day())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func tagPill(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppColors.accentAgent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.accentAgent.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Priority Color

    private var priorityColor: Color {
        switch task.priority {
        case .low:      return AppColors.accentSuccess
        case .medium:   return AppColors.accentWarning
        case .high:     return Color.orange
        case .critical: return AppColors.accentDanger
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let taskMarkedDone = Notification.Name("taskMarkedDone")
    static let taskDeferred = Notification.Name("taskDeferred")
    static let taskDelegated = Notification.Name("taskDelegated")
}
