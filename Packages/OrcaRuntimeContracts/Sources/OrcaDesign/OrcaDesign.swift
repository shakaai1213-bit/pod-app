import OrcaDomain
import SwiftUI

public extension Color {
    init(orcaHex: String) {
        let hex = orcaHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let alpha: UInt64
        let red: UInt64
        let green: UInt64
        let blue: UInt64
        switch hex.count {
        case 3:
            (alpha, red, green, blue) = (
                255,
                (value >> 8) * 17,
                (value >> 4 & 0xF) * 17,
                (value & 0xF) * 17
            )
        case 8:
            (alpha, red, green, blue) = (
                value >> 24,
                value >> 16,
                value >> 8 & 0xFF,
                value & 0xFF
            )
        default:
            (alpha, red, green, blue) = (255, value >> 16, value >> 8 & 0xFF, value & 0xFF)
        }
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }

    static let orcaCyan = Color(orcaHex: "14A3AB")
    static let orcaGreen = Color(orcaHex: "299E5E")
    static let orcaAmber = Color(orcaHex: "E09524")
    static let orcaCoral = Color(orcaHex: "E05240")
}

public enum OrcaPalette {
    public static let backgroundPrimary = Color(orcaHex: "0A0A0F")
    public static let backgroundSecondary = Color(orcaHex: "141419")
    public static let backgroundTertiary = Color(orcaHex: "1C1C24")
    public static let accentElectric = Color(orcaHex: "3B82F6")
    public static let accentSuccess = Color(orcaHex: "22C55E")
    public static let accentWarning = Color(orcaHex: "F59E0B")
    public static let accentDanger = Color(orcaHex: "EF4444")
    public static let accentAgent = Color(orcaHex: "A855F7")
    public static let accentCaptain = Color(orcaHex: "F97316")
    public static let textPrimary = Color(orcaHex: "F8FAFC")
    public static let textSecondary = Color(orcaHex: "94A3B8")
    public static let textTertiary = Color(orcaHex: "9A9AA1")
    public static let textMuted = Color(orcaHex: "2D3748")
    public static let border = Color(orcaHex: "1E293B")
    public static let borderActive = Color(orcaHex: "334155")
}

public extension OrcaAgentProfile.Accent {
    var color: Color {
        switch self {
        case .pink: return Color(orcaHex: "DB4085")
        case .orange: return Color(orcaHex: "E86B21")
        case .violet: return Color(orcaHex: "7557C7")
        case .green: return .orcaGreen
        case .red: return Color(orcaHex: "D63D38")
        case .cyan: return .orcaCyan
        case .teal: return Color(orcaHex: "1A9485")
        }
    }
}
