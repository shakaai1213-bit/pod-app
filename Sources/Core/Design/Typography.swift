import SwiftUI

// MARK: - Typography Namespace

enum Typography {
    /// Large Title / Bold / 34pt
    static let display = FontTextStyle(.largeTitle, weight: .bold)

    /// Title / Bold / 28pt
    static let title1 = FontTextStyle(.title, weight: .bold)

    /// Title 2 / Semibold / 22pt
    static let title2 = FontTextStyle(.title2, weight: .semibold)

    /// Title 3 / Semibold / 17pt
    static let title3 = FontTextStyle(.title3, weight: .semibold)

    /// Headline / Semibold / 17pt
    static let headline = FontTextStyle(.headline, weight: .semibold)

    /// Subheadline / Regular / 15pt
    static let subheadline = FontTextStyle(.subheadline, weight: .regular)

    /// Body / Regular / 17pt
    static let body = FontTextStyle(.body, weight: .regular)

    /// Caption / Regular / 12pt
    static let caption = FontTextStyle(.caption, weight: .regular)

    /// Label / Medium / 11pt
    static let label = FontTextStyle(.caption2, weight: .medium)

    /// Monospaced / Regular / 13pt
    static var mono: FontTextStyle { .monospaced(size: 13, weight: .regular) }
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

    private init(swiftUIFont: Font, pointSize: CGFloat, weight: Font.Weight) {
        self.swiftUIFont = swiftUIFont
        self.pointSize = pointSize
        self.weight = weight
    }

    // MARK: - Monospaced

    static func monospaced(size: CGFloat, weight: Font.Weight) -> FontTextStyle {
        FontTextStyle(
            swiftUIFont: Font.system(size: size, weight: weight, design: .monospaced),
            pointSize: size,
            weight: weight
        )
    }

    // MARK: - Helpers

    /// Resolves the actual UIFont point size for a given SwiftUI text style.
    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:   return 34
        case .title:        return 28
        case .title2:       return 22
        case .title3:       return 17
        case .headline:     return 17
        case .subheadline:   return 15
        case .body:         return 17
        case .callout:      return 16
        case .footnote:     return 13
        case .caption:      return 12
        case .caption2:     return 11
        @unknown default:  return 17
        }
    }

    // MARK: - Style aliases (forwarded from Typography for convenience)

    static let display: FontTextStyle = Typography.display
    static let title1: FontTextStyle = Typography.title1
    static let title2: FontTextStyle = Typography.title2
    static let title3: FontTextStyle = Typography.title3
    static let headline: FontTextStyle = Typography.headline
    static let subheadline: FontTextStyle = Typography.subheadline
    static let body: FontTextStyle = Typography.body
    static let caption: FontTextStyle = Typography.caption
    static let label: FontTextStyle = Typography.label
}

// MARK: - View Extension

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
