import SwiftUI

/// A horizontal flow layout that wraps items left-to-right, top-to-bottom.
/// Configurable spacing between items and between rows.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = compute(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return result.bounds
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = compute(in: bounds.width, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func compute(in maxWidth: CGFloat, subviews: Subviews) -> FlowResult {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
            maxX = max(maxX, x)
        }

        let bounds = CGSize(width: max(0, maxX - horizontalSpacing), height: y + rowHeight)
        return FlowResult(bounds: bounds, positions: positions)
    }

    struct FlowResult {
        let bounds: CGSize
        let positions: [CGPoint]
    }
}

// MARK: - Convenience layout types

/// Standard tag flow layout with 6pt spacing
struct TagFlowLayout: Layout {
    private let inner: FlowLayout

    init() {
        self.inner = FlowLayout(horizontalSpacing: 6, verticalSpacing: 6)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        inner.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        inner.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}

/// Compact flow layout with zero spacing
struct CompactFlowLayout: Layout {
    private let inner: FlowLayout

    init() {
        self.inner = FlowLayout(horizontalSpacing: 0, verticalSpacing: 0)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        inner.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        inner.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}

// MARK: - Tag Pill View (designed for use with FlowLayout)

struct TagPill: View {
    let text: String
    var color: Color = .accentColor
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.15))
            )
            .contentShape(Capsule())
            .onTapGesture { onTap?() }
    }
}

#Preview {
    struct PreviewWrapper: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Tags")
                    .font(.headline)
                    .foregroundStyle(.white)

                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(["SwiftUI", "iOS 17", "Swift 5.9", "Combine", "async/await", "Observation", "SwiftData", "WidgetKit", "App Intents"], id: \.self) { tag in
                        TagPill(text: tag, color: .blue)
                    }
                }

                Divider()

                Text("Agent Pills")
                    .font(.headline)
                    .foregroundStyle(.white)

                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(["Maui", "Researcher", "Builder", "Analyst", "Sentinel"], id: \.self) { agent in
                        TagPill(text: agent, color: .purple, isSelected: agent == "Maui" || agent == "Sentinel")
                    }
                }

                Divider()

                Text("Skill Chips")
                    .font(.headline)
                    .foregroundStyle(.white)

                CompactFlowLayout {
                    ForEach(["Swift", "Python", "Rust", "TypeScript", "Go"], id: \.self) { skill in
                        TagPill(text: skill, color: .orange)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black)
        }
    }

    return PreviewWrapper()
}
