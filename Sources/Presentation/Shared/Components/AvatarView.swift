import SwiftUI

enum AvatarSize: String, CaseIterable {
    case xs, sm, md, lg, xl

    var diameter: CGFloat {
        switch self {
        case .xs:  return 20
        case .sm:  return 28
        case .md:  return 36
        case .lg:  return 48
        case .xl:  return 64
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .xs:  return 8
        case .sm:  return 11
        case .md:  return 14
        case .lg:  return 18
        case .xl:  return 24
        }
    }

    var statusDotSize: CGFloat {
        switch self {
        case .xs:  return 6
        case .sm:  return 8
        case .md:  return 10
        case .lg:  return 12
        case .xl:  return 14
        }
    }

    var ringWidth: CGFloat {
        switch self {
        case .xs:  return 1
        case .sm:  return 1.5
        case .md:  return 2
        case .lg:  return 2
        case .xl:  return 2.5
        }
    }
}

struct AvatarView: View {
    let name: String
    var status: Status? = nil
    var size: AvatarSize = .md
    var showRing: Bool = false
    var image: UIImage? = nil

    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    private var backgroundColor: Color {
        Color(AvatarView.colorForName(name))
    }

    private var ringColor: Color {
        status?.color ?? .green
    }

    public static func colorForName(_ name: String) -> Color {
        let palette: [Color] = [
            .red, .orange, .yellow, .green,
            .teal, .blue, .indigo, .purple, .pink,
        ]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Avatar circle
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(initials)
                        .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size.diameter, height: size.diameter)
            .background(backgroundColor)
            .clipShape(Circle())
            .overlay {
                if showRing, status != nil {
                    Circle()
                        .stroke(ringColor, lineWidth: size.ringWidth)
                }
            }

            // Status dot
            if let status = status {
                StatusBadge.dot(status, size: .small)
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityLabel("\(name) avatar")
    }
}

// MARK: - Avatar with fallback icon (for agents, bots, etc.)

struct SystemAvatarView: View {
    let systemImage: String
    var status: Status? = nil
    var size: AvatarSize = .md
    var color: Color = .accentColor

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: size.fontSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size.diameter, height: size.diameter)
                .background(color.gradient)
                .clipShape(Circle())
                .overlay {
                    if status != nil {
                        Circle()
                            .stroke(statusColor, lineWidth: size.ringWidth)
                    }
                }

            if let status = status {
                StatusBadge.dot(status, size: .small)
                    .offset(x: 2, y: 2)
            }
        }
    }

    private var statusColor: Color {
        status?.color ?? .clear
    }
}

#Preview {
    VStack(spacing: 24) {
        // Name-based avatars
        HStack(spacing: 16) {
            ForEach(AvatarSize.allCases, id: \.self) { size in
                AvatarView(name: "Maui", size: size)
            }
        }

        // With status
        HStack(spacing: 24) {
            AvatarView(name: "Maui", status: .online, size: .lg, showRing: true)
            AvatarView(name: "Researcher", status: .busy, size: .lg, showRing: true)
            AvatarView(name: "Builder", status: .away, size: .lg, showRing: true)
            AvatarView(name: "Analyst", status: .offline, size: .lg, showRing: true)
        }

        // System avatars
        HStack(spacing: 24) {
            SystemAvatarView(systemImage: "cpu", size: .lg, color: .purple)
            SystemAvatarView(systemImage: "brain", size: .lg, color: .blue)
            SystemAvatarView(systemImage: "hammer", size: .lg, color: .orange)
            SystemAvatarView(systemImage: "chart.bar", size: .lg, color: .green)
        }
    }
    .padding()
    .background(Color.black)
}
