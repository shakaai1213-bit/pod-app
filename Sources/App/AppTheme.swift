import SwiftUI

enum AppTheme {

    // MARK: - Colors

    static let primaryText = Color(hex: "#E2E8F0")
    static let secondaryText = Color(hex: "#94A3B8")
    static let tertiaryText = Color(hex: "#64748B")
    static let surface = Color(hex: "#1E1E2E")
    static let surfaceElevated = Color(hex: "#2A2A3E")
    static let background = Color.black
    static let primaryAccent = Color(hex: "#6B46C1")
    static let glowAccent = Color(hex: "#6B46C1").opacity(0.4)
    static let inverseText = Color.white
    static let error = Color(hex: "#EF4444")
    static let border = Color(hex: "#334155")
    static let surfaceOverlay = Color(hex: "#4B5563")

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: - Radius

    static let radiusSM: CGFloat = 4
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 16
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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
