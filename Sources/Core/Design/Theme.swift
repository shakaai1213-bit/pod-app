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


