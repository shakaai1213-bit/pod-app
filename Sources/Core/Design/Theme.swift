import SwiftUI

// MARK: - Theme

/// Design system spacing, radii, animation, and shadow tokens
struct Theme {
    // MARK: Spacing (8pt grid)
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    // MARK: Corner Radii
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusPill: CGFloat = 999

    // MARK: Animation
    static let springBounce: CGFloat = 0.3
    static let springResponse: Double = 0.4
    static let durationDefault: Double = 0.2
    static let durationFast: Double = 0.15
    static let durationSlow: Double = 0.3

    // MARK: Shadows
    struct ShadowConfig {
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        let opacity: CGFloat

        static let small = ShadowConfig(radius: 4, x: 0, y: 2, opacity: 0.1)
        static let medium = ShadowConfig(radius: 8, x: 0, y: 4, opacity: 0.15)
        static let large = ShadowConfig(radius: 16, x: 0, y: 8, opacity: 0.2)
        static let glow = ShadowConfig(radius: 12, x: 0, y: 0, opacity: 0.3)
    }

    // MARK: - Surface & Text (back-compat for podApp.swift)

    static let surface: Color = AppColors.backgroundSecondary
    static let primaryText: Color = AppColors.textPrimary
    static let inverseText: Color = AppColors.textPrimary
    static let errorColor: Color = AppColors.accentDanger
    static let glow: Color = AppColors.accentElectric.opacity(0.4)
}

// MARK: - View Helpers

extension View {
    func podCard(padding: CGFloat = Theme.md) -> some View {
        self
            .padding(padding)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .shadow(
                color: .black.opacity(Theme.ShadowConfig.small.opacity),
                radius: Theme.ShadowConfig.small.radius,
                x: Theme.ShadowConfig.small.x,
                y: Theme.ShadowConfig.small.y
            )
    }

    func podGlow(color: Color = AppColors.accentElectric) -> some View {
        self.shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 0)
    }

    func podShadow(_ config: Theme.ShadowConfig) -> some View {
        self.shadow(
            color: .black.opacity(config.opacity),
            radius: config.radius,
            x: config.x,
            y: config.y
        )
    }
}

// MARK: - Shared Review Cards

enum PodReviewActionStyle: Sendable, Hashable {
    case primary
    case success
    case warning
    case destructive
    case neutral

    var color: Color {
        switch self {
        case .primary: return AppColors.accentElectric
        case .success: return AppColors.accentSuccess
        case .warning: return AppColors.accentWarning
        case .destructive: return AppColors.accentDanger
        case .neutral: return AppColors.textSecondary
        }
    }
}

struct PodReviewAction: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let style: PodReviewActionStyle
    let isDisabled: Bool

    init(
        id: String,
        title: String,
        systemImage: String,
        style: PodReviewActionStyle = .primary,
        isDisabled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isDisabled = isDisabled
    }
}

struct PodReviewItem: Identifiable {
    let id: String
    let eyebrow: String
    let title: String
    let detail: String?
    let status: String
    let statusColor: Color
    let provenance: [String]
    let traceId: String?
    let artifactHash: String?
    let actions: [PodReviewAction]

    init(
        id: String,
        eyebrow: String,
        title: String,
        detail: String? = nil,
        status: String,
        statusColor: Color = AppColors.accentElectric,
        provenance: [String] = [],
        traceId: String? = nil,
        artifactHash: String? = nil,
        actions: [PodReviewAction] = []
    ) {
        self.id = id
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.status = status
        self.statusColor = statusColor
        self.provenance = provenance
        self.traceId = traceId
        self.artifactHash = artifactHash
        self.actions = actions
    }
}

struct PodReviewCard: View {
    let item: PodReviewItem
    var isBusy: Bool = false
    var onAction: (PodReviewAction) -> Void = { _ in }
    var onOpenTrace: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(item.statusColor)

                Spacer(minLength: 8)
            }

            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = item.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.provenance.isEmpty || item.artifactHash != nil || item.traceId != nil {
                FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(item.provenance, id: \.self) { value in
                        reviewPill(value)
                    }
                    if let artifactHash = item.artifactHash, !artifactHash.isEmpty {
                        reviewPill("sha \(String(artifactHash.prefix(12)))")
                    }
                    if let traceId = item.traceId, !traceId.isEmpty {
                        Button {
                            onOpenTrace?(traceId)
                        } label: {
                            Label(String(traceId.prefix(12)), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColors.accentElectric)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppColors.accentElectric.opacity(0.10))
                        .clipShape(Capsule())
                        .disabled(onOpenTrace == nil)
                    }
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Label(item.status, systemImage: isBusy ? "clock.arrow.circlepath" : "checkmark.seal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.statusColor)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(item.statusColor.opacity(0.10))
                    .clipShape(Capsule())

                Spacer(minLength: 8)

                if !item.actions.isEmpty {
                    ForEach(item.actions) { action in
                        Button {
                            onAction(action)
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(action.style.color)
                        .disabled(action.isDisabled || isBusy)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.statusColor.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.eyebrow), \(item.title), \(item.status)")
    }

    private func reviewPill(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppColors.backgroundTertiary)
            .clipShape(Capsule())
    }
}
