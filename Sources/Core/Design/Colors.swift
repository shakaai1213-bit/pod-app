import SwiftUI

// MARK: - Color Extension

extension Color {
    /// Initialize a Color from a hex string (e.g., "3B82F6" or "#3B82F6")
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - App Colors

struct AppColors {
    // MARK: - Backgrounds

    static let backgroundPrimary   = Color(hexString: "0A0A0F")
    static let backgroundSecondary = Color(hexString: "141419")
    static let backgroundTertiary  = Color(hexString: "1C1C24")

    // MARK: - Accents

    static let accentElectric = Color(hexString: "3B82F6")
    static let accentSuccess  = Color(hexString: "22C55E")
    static let accentWarning  = Color(hexString: "F59E0B")
    static let accentDanger   = Color(hexString: "EF4444")
    static let accentAgent    = Color(hexString: "A855F7")
    static let accentCaptain   = Color(hexString: "F97316")

    // MARK: - Text

    static let textPrimary   = Color(hexString: "F8FAFC")
    static let textSecondary = Color(hexString: "94A3B8")
    static let textTertiary  = Color(hexString: "475569")
    static let textMuted      = Color(hexString: "2D3748")

    // MARK: - Borders

    static let border       = Color(hexString: "1E293B")
    static let borderActive = Color(hexString: "334155")
}
