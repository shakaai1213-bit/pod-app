import SwiftUI

// MARK: - Theme

/// Core design constants for the Pod app.
/// Follows an 8pt spacing grid and defines reusable visual tokens.
enum Theme {

    // MARK: - Spacing (8pt grid)

    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 8
    static let sm:  CGFloat = 12
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48

    // MARK: - Corner Radii

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusPill:  CGFloat = 999

    // MARK: - Animation

    enum Animation {
        /// Default short transition duration (e.g., opacity changes)
        static let duration: Double = 0.2

        /// Spring animation: bounce = 0.3, response = 0.4
        static let spring = SwiftUI.Animation.spring(
            response: 0.4,
            dampingFraction: 0.3
        )

        /// Snappier spring for micro-interactions
        static let springBouncy = SwiftUI.Animation.spring(
            response: 0.3,
            dampingFraction: 0.3
        )

        /// Ease-in-out for standard transitions
        static let easeInOut = SwiftUI.Animation.easeInOut(
            duration: Self.duration
        )

        /// Immediate / no animation
        static let immediate = SwiftUI.Animation.linear(duration: 0)
    }

    // MARK: - Shadows

    enum Shadow {
        /// Small shadow — used for cards, subtle elevation
        static let small = ShadowConfig(
            color: .black.opacity(0.25),
            radius: 4,
            x: 0,
            y: 2
        )

        /// Medium shadow — used for modals, floating elements
        static let medium = ShadowConfig(
            color: .black.opacity(0.35),
            radius: 8,
            x: 0,
            y: 4
        )

        /// Large shadow — used for overlays, drag-and-drop lift
        static let large = ShadowConfig(
            color: .black.opacity(0.45),
            radius: 16,
            x: 0,
            y: 8
        )
    }
}

// MARK: - ShadowConfig

struct ShadowConfig {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    func apply(to shape: some View) -> some View {
        shape.shadow(
            color: color,
            radius: radius,
            x: x,
            y: y
        )
    }
}

// MARK: - View Helpers

extension View {
    func podShadow(_ config: ShadowConfig) -> some View {
        self.shadow(
            color: config.color,
            radius: config.radius,
            x: config.x,
            y: config.y
        )
    }

    func podCard() -> some View {
        self
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .podShadow(Theme.Shadow.small)
    }
}
