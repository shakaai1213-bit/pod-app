import SwiftUI

enum Status: String, CaseIterable {
    case online
    case busy
    case away
    case offline

    var color: Color {
        switch self {
        case .online:  return .green
        case .busy:   return .orange
        case .away:   return .yellow
        case .offline: return .gray
        }
    }
}

enum StatusBadgeSize: String, CaseIterable {
    case small, medium, large

    var diameter: CGFloat {
        switch self {
        case .small:  return 8
        case .medium: return 10
        case .large:  return 12
        }
    }

    var font: Font {
        switch self {
        case .small:  return .system(size: 9)
        case .medium: return .system(size: 11)
        case .large:  return .system(size: 13)
        }
    }

    var paddingH: CGFloat {
        switch self {
        case .small:  return 4
        case .medium: return 6
        case .large:  return 8
        }
    }

    var paddingV: CGFloat {
        switch self {
        case .small:  return 2
        case .medium: return 3
        case .large:  return 4
        }
    }
}

struct StatusBadge: View {
    let status: Status
    var size: StatusBadgeSize = .medium
    var label: String? = nil
    var showPulse: Bool = true

    @State private var isPulsing = false

    private var shouldPulse: Bool {
        status == .busy && showPulse
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(status.color)
                    .frame(width: size.diameter, height: size.diameter)

                if shouldPulse {
                    Circle()
                        .stroke(status.color.opacity(0.4), lineWidth: 1)
                        .frame(width: size.diameter, height: size.diameter)
                        .scaleEffect(isPulsing ? 2.0 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.6)
                }
            }
            .frame(width: size.diameter + 4, height: size.diameter + 4)

            if let label = label {
                Text(label)
                    .font(size.font)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard shouldPulse else { return }
            startPulse()
        }
    }

    private func startPulse() {
        withAnimation(
            .easeOut(duration: 1.0)
            .repeatForever(autoreverses: false)
        ) {
            isPulsing = true
        }
    }
}

// MARK: - Convenience Static Helpers

extension StatusBadge {
    /// Just the dot, no label
    static func dot(_ status: Status, size: StatusBadgeSize = .medium) -> some View {
        StatusBadge(status: status, size: size, label: nil)
    }

    /// Dot with capitalized status label
    static func labeled(_ status: Status, size: StatusBadgeSize = .medium) -> some View {
        StatusBadge(status: status, size: size, label: status.rawValue.capitalized)
    }
}

#Preview {
    VStack(spacing: 24) {
        ForEach(Status.allCases, id: \.self) { status in
            VStack(spacing: 8) {
                StatusBadge.dot(status, size: .small)
                StatusBadge.dot(status, size: .medium)
                StatusBadge.dot(status, size: .large)
                StatusBadge.labeled(status, size: .medium)
            }
        }
    }
    .padding()
    .background(Color.black)
}
