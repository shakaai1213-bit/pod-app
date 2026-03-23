import SwiftUI

// MARK: - Typography

/// Typography scale for the Pod app.
/// Each token maps to a system font with a defined size and weight.
enum Typography {

    // MARK: - Font Definitions

    /// .largeTitle / bold / 34pt
    static let display = FontTextStyle(
        .largeTitle,
        weight: .bold
    )

    /// .title / bold / 28pt
    static let title1 = FontTextStyle(
        .title,
        weight: .bold
    )

    /// .title2 / semibold / 22pt
    static let title2 = FontTextStyle(
        .title2,
        weight: .semibold
    )

    /// .headline / semibold / 17pt
    static let title3 = FontTextStyle(
        .headline,
        weight: .semibold
    )

    /// .subheadline / medium / 15pt
    static let headline = FontTextStyle(
        .subheadline,
        weight: .medium
    )

    /// .body / regular / 15pt
    static let body = FontTextStyle(
        .body,
        weight: .regular
    )

    /// .caption / regular / 13pt
    static let caption = FontTextStyle(
        .caption,
        weight: .regular
    )

    /// .caption2 / medium / 11pt
    static let label = FontTextStyle(
        .caption2,
        weight: .medium
    )

    /// Monospaced / regular / 13pt
    static let mono: FontTextStyle = .monospaced(
        size: 13,
        weight: .regular
    )
}

// MARK: - FontTextStyle

struct FontTextStyle: Equatable {
    let swiftUIFont: Font
    let pointSize: CGFloat
    let weight: Font.Weight

    // MARK: - Standard text styles

    init(_ style: Font.TextStyle, weight: Font.Weight) {
        self.swiftUIFont = Font.system(style, design: .default)
        self.pointSize = Self.pointSize(for: style)
        self.weight = weight
    }

    // MARK: - Monospaced

    static func monospaced(size: CGFloat, weight: Font.Weight) -> FontTextStyle {
        FontTextStyle(
            swiftUIFont: Font.system(size, design: .monospaced),
            pointSize: size,
            weight: weight
        )
    }

    // MARK: - Helpers

    /// Resolves the actual UIFont point size for a given SwiftUI text style.
    /// Used for modifiers like `.minimumScaleFactor` and line spacing calculations.
    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:   return 34
        case .title:        return 28
        case .title2:       return 22
        case .title3:       return 17
        case .headline:     return 17
        case .subheadline:  return 15
        case .body:         return 17
        case .callout:      return 16
        case .footnote:     return 13
        case .caption:      return 12
        case .caption2:     return 11
        @unknown default:   return 17
        }
    }
}

// MARK: - Font Extension

extension Font {
    /// Returns the Font wrapped in a FontTextStyle for consistency.
    static func pod(_ style: FontTextStyle) -> Font {
        style.swiftUIFont
    }
}

// MARK: - View Modifier

extension View {
    /// Apply a Pod typography style with an optional color.
    func podTextStyle(
        _ style: FontTextStyle,
        color: Color = AppColors.textPrimary
    ) -> some View {
        self
            .font(style.swiftUIFont)
            .foregroundStyle(color)
    }
}
