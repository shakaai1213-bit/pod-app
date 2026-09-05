import OrcaDesign
import SwiftUI

// MARK: - Color Extension

extension Color {
    /// Initialize a Color from a hex string (e.g., "3B82F6" or "#3B82F6")
    init(hexString: String) {
        self.init(orcaHex: hexString)
    }
}

// MARK: - App Colors

struct AppColors {
    // MARK: - Backgrounds

    static let backgroundPrimary = OrcaPalette.backgroundPrimary
    static let backgroundSecondary = OrcaPalette.backgroundSecondary
    static let backgroundTertiary = OrcaPalette.backgroundTertiary

    // MARK: - Accents

    static let accentElectric = OrcaPalette.accentElectric
    static let accentSuccess = OrcaPalette.accentSuccess
    static let accentWarning = OrcaPalette.accentWarning
    static let accentDanger = OrcaPalette.accentDanger
    static let accentAgent = OrcaPalette.accentAgent
    static let accentCaptain = OrcaPalette.accentCaptain

    // MARK: - Text

    static let textPrimary = OrcaPalette.textPrimary
    static let textSecondary = OrcaPalette.textSecondary
    static let textTertiary = OrcaPalette.textTertiary
    static let textMuted = OrcaPalette.textMuted

    // MARK: - Borders

    static let border = OrcaPalette.border
    static let borderActive = OrcaPalette.borderActive
}
