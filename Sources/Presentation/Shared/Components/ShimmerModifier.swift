import SwiftUI

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 4

    @State private var phase: CGFloat = -1.0

    private let animationDuration: Double = 1.5

    func body(content: Content) -> some View {
        content
            .hidden()
            .overlay {
                GeometryReader { geometry in
                    let w = width ?? geometry.size.width
                    let h = height ?? geometry.size.height

                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .offset(x: phase * (w + geometry.size.width))
                }
            }
            .mask {
                Rectangle()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .onAppear {
                startAnimation()
            }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.gray.opacity(0.15),
                Color.gray.opacity(0.3),
                Color.gray.opacity(0.5),
                Color.gray.opacity(0.3),
                Color.gray.opacity(0.15),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func startAnimation() {
        withAnimation(
            .linear(duration: animationDuration)
            .repeatForever(autoreverses: false)
        ) {
            phase = 2.0
        }
    }
}

// MARK: - Shimmer Placeholder Views

/// Skeleton text line
struct ShimmerText: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 4

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shimmer(width: width, height: height, cornerRadius: cornerRadius)
    }
}

/// Skeleton circle placeholder
struct ShimmerCircle: View {
    var diameter: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: diameter, height: diameter)
            .shimmer(width: diameter, height: diameter, cornerRadius: diameter / 2)
    }
}

/// Skeleton rectangle placeholder
struct ShimmerRectangle: View {
    var width: CGFloat? = nil
    var height: CGFloat = 20
    var cornerRadius: CGFloat = 6

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shimmer(width: width, height: height, cornerRadius: cornerRadius)
    }
}

/// Skeleton card/row placeholder
struct ShimmerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ShimmerCircle(diameter: 40)
                VStack(alignment: .leading, spacing: 6) {
                    ShimmerText(width: 120, height: 14)
                    ShimmerText(width: 80, height: 12)
                }
                Spacer()
            }
            ShimmerText(height: 12)
            ShimmerText(width: 200, height: 12)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - View Extension

extension View {
    func shimmer(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 4
    ) -> some View {
        modifier(ShimmerModifier(width: width, height: height, cornerRadius: cornerRadius))
    }
}

#Preview {
    VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
            ShimmerText(width: 200, height: 18)
            ShimmerText(height: 14)
            ShimmerText(width: 140, height: 14)
        }

        HStack(spacing: 16) {
            ShimmerCircle(diameter: 48)
            ShimmerCircle(diameter: 36)
            ShimmerCircle(diameter: 24)
        }

        ShimmerRectangle(height: 80, cornerRadius: 12)

        ShimmerCard()
    }
    .padding()
    .background(Color.black)
}
