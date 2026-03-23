import SwiftUI

/// Priority is defined in Domain/Entities/Projects.swift
/// This file re-exports it for convenience in the Presentation layer.

enum PriorityBadgeSize: String, CaseIterable {
    case small, medium, large

    var font: Font {
        switch self {
        case .small:  return .system(size: 10, weight: .semibold)
        case .medium: return .system(size: 12, weight: .semibold)
        case .large:  return .system(size: 14, weight: .semibold)
        }
    }

    var paddingH: CGFloat {
        switch self {
        case .small:  return 6
        case .medium: return 8
        case .large:  return 10
        }
    }

    var paddingV: CGFloat {
        switch self {
        case .small:  return 3
        case .medium: return 4
        case .large:  return 5
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small:  return 4
        case .medium: return 6
        case .large:  return 8
        }
    }
}

struct PriorityBadge: View {
    let priority: Priority
    var size: PriorityBadgeSize = .medium
    var showIcon: Bool = true

    var body: some View {
        HStack(spacing: 3) {
            if showIcon, let icon = priority.icon {
                Image(systemName: icon)
                    .font(.system(size: fontSize - 2, weight: .bold))
            }
            Text(priority.label)
                .font(size.font)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, size.paddingH)
        .padding(.vertical, size.paddingV)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }

    private var foreground: Color {
        switch priority {
        case .low:
            return .primary
        case .medium, .high, .critical:
            return priority.color.opacity(priority == .high || priority == .critical ? 1.0 : 0.9)
        }
    }

    private var background: Color {
        priority.color.opacity(priority == .low ? 0.15 : 0.2)
    }

    private var fontSize: CGFloat {
        switch size {
        case .small:  return 10
        case .medium: return 12
        case .large:  return 14
        }
    }
}

// MARK: - Convenience Initializers

extension PriorityBadge {
    /// Pill with text only, no icon
    static func label(_ priority: Priority, size: PriorityBadgeSize = .medium) -> some View {
        PriorityBadge(priority: priority, size: size, showIcon: false)
    }

    /// Pill with icon + text
    static func full(_ priority: Priority, size: PriorityBadgeSize = .medium) -> some View {
        PriorityBadge(priority: priority, size: size, showIcon: true)
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach(Priority.allCases, id: \.self) { priority in
            HStack(spacing: 12) {
                PriorityBadge.full(priority, size: .small)
                PriorityBadge.full(priority, size: .medium)
                PriorityBadge.full(priority, size: .large)
            }
        }

        Divider()

        ForEach(Priority.allCases, id: \.self) { priority in
            HStack(spacing: 12) {
                PriorityBadge.label(priority, size: .small)
                PriorityBadge.label(priority, size: .medium)
                PriorityBadge.label(priority, size: .large)
            }
        }
    }
    .padding()
    .background(Color.black)
}
