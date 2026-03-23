import SwiftUI

// MARK: - App Theme

/// Unified design system tokens for the pod app
struct AppTheme {
    // MARK: - Background Colors

    static let background: Color = AppColors.backgroundPrimary
    static let surface: Color = AppColors.backgroundSecondary
    static let surfaceElevated: Color = AppColors.backgroundTertiary
    static let surfaceOverlay: Color = AppColors.backgroundSecondary.opacity(0.6)

    // MARK: - Text Colors

    static let primaryText: Color = AppColors.textPrimary
    static let secondaryText: Color = AppColors.textSecondary
    static let tertiaryText: Color = AppColors.textTertiary
    static let inverseText: Color = AppColors.textPrimary  // White on dark

    // MARK: - Accent Colors

    static let primaryAccent: Color = AppColors.accentElectric
    static let glowAccent: Color = AppColors.accentElectric.opacity(0.4)

    // MARK: - Semantic Colors

    static let error: Color = AppColors.accentDanger
    static let success: Color = AppColors.accentSuccess
    static let warning: Color = AppColors.accentWarning
    static let border: Color = AppColors.border
    static let borderActive: Color = AppColors.borderActive

    // MARK: - Tab Accent Colors

    static let electricBlue: Color = AppColors.accentElectric
    static let electricPurple: Color = AppColors.accentAgent
    static let electricGreen: Color = AppColors.accentSuccess
    static let electricOrange: Color = AppColors.accentWarning

    // MARK: - Spacing (8pt grid)

    static let spacingXXS: CGFloat = 4
    static let spacingXS: CGFloat = 8
    static let spacingSM: CGFloat = 12
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacingXXL: CGFloat = 48

    // MARK: - Corner Radii

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusPill: CGFloat = 999
}
