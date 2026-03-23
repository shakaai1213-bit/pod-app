import Foundation

// MARK: - Standard

struct Standard: Identifiable {
    let id: UUID
    var title: String
    let category: StandardCategory
    var content: String
    let authorId: UUID
    var authorName: String
    var tags: [String]
    let version: Int
    let createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var readingPosition: Int?
    var relatedStandardIds: [UUID]
    var versions: [StandardVersion]
}

extension Standard: Codable {}
extension Standard: Hashable {}

// MARK: - Standard Version

struct StandardVersion: Identifiable, Codable, Hashable {
    let id: UUID
    let version: Int
    let content: String
    let authorId: UUID
    let authorName: String
    let updatedAt: Date
}

// MARK: - Standard Category

enum StandardCategory: String, Codable, CaseIterable {
    case standards
    case frameworks
    case playbooks
    case runbooks

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .standards:  return "doc.text"
        case .frameworks: return "square.grid.2x2"
        case .playbooks:  return "list.bullet.clipboard"
        case .runbooks:   return "wrench.and.screwdriver"
        }
    }

    var color: String {
        switch self {
        case .standards:  return "3B82F6"
        case .frameworks:  return "A855F7"
        case .playbooks:   return "22C55E"
        case .runbooks:     return "F97316"
        }
    }
}

import SwiftUI

// MARK: - Color Extension

extension Color {
    /// Initialize a Color from a hex string (e.g., "3B82F6" or "#3B82F6")
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

// MARK: - App Colors

struct AppColors {
    // MARK: - Backgrounds

    static let backgroundPrimary   = Color(hex: "0A0A0F")
    static let backgroundSecondary = Color(hex: "141419")
    static let backgroundTertiary  = Color(hex: "1C1C24")

    // MARK: - Accents

    static let accentElectric = Color(hex: "3B82F6")
    static let accentSuccess  = Color(hex: "22C55E")
    static let accentWarning  = Color(hex: "F59E0B")
    static let accentDanger    = Color(hex: "EF4444")
    static let accentAgent     = Color(hex: "A855F7")
    static let accentCaptain   = Color(hex: "F97316")

    // MARK: - Text

    static let textPrimary   = Color(hex: "F8FAFC")
    static let textSecondary = Color(hex: "94A3B8")
    static let textTertiary  = Color(hex: "475569")
    static let textMuted     = Color(hex: "2D3748")

    // MARK: - Borders

    static let border       = Color(hex: "1E293B")
    static let borderActive = Color(hex: "334155")
}
