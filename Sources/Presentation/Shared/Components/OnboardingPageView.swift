import SwiftUI

// MARK: - OnboardingPageView

/// Reusable swipeable page view with dot indicators and optional nav buttons.
struct OnboardingPageView<Content: View>: View {

    @Binding var currentPage: Int
    let totalPages: Int
    let content: () -> Content

    // Navigation
    var showPrevNextButtons: Bool = false
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?

    // Styling
    var indicatorColor: Color = AppColors.accentElectric
    var indicatorInactiveColor: Color = AppColors.textTertiary
    var buttonBackgroundColor: Color = AppColors.accentElectric
    var buttonForegroundColor: Color = .white

    init(
        currentPage: Binding<Int>,
        totalPages: Int,
        showPrevNextButtons: Bool = false,
        indicatorColor: Color = AppColors.accentElectric,
        indicatorInactiveColor: Color = AppColors.textTertiary,
        buttonBackgroundColor: Color = AppColors.accentElectric,
        buttonForegroundColor: Color = .white,
        onPrevious: (() -> Void)? = nil,
        onNext: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._currentPage = currentPage
        self.totalPages = totalPages
        self.showPrevNextButtons = showPrevNextButtons
        self.indicatorColor = indicatorColor
        self.indicatorInactiveColor = indicatorInactiveColor
        self.buttonBackgroundColor = buttonBackgroundColor
        self.buttonForegroundColor = buttonForegroundColor
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // Swipeable page content
            TabView(selection: $currentPage) {
                content()
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            // Indicator dots
            PageControlView(
                currentPage: currentPage,
                totalPages: totalPages,
                activeColor: indicatorColor,
                inactiveColor: indicatorInactiveColor
            )
            .padding(.bottom, 8)

            // Prev / Next buttons
            if showPrevNextButtons {
                HStack(spacing: 16) {
                    // Previous
                    Button {
                        if currentPage > 0 {
                            currentPage -= 1
                            onPrevious?()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(currentPage > 0 ? AppColors.textPrimary : AppColors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppColors.backgroundSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        )
                    }
                    .disabled(currentPage == 0)
                    .opacity(currentPage == 0 ? 0.5 : 1)

                    // Next
                    Button {
                        if currentPage < totalPages - 1 {
                            currentPage += 1
                            onNext?()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    currentPage < totalPages - 1
                                        ? LinearGradient(
                                            colors: [buttonBackgroundColor, buttonBackgroundColor.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        : LinearGradient(
                                            colors: [AppColors.textTertiary, AppColors.textTertiary],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(
                            color: currentPage < totalPages - 1
                                ? buttonBackgroundColor.opacity(0.3)
                                : .clear,
                            radius: 6,
                            x: 0,
                            y: 3
                        )
                    }
                    .disabled(currentPage == totalPages - 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - PageControlView

/// Dot-style page indicator.
struct PageControlView: View {

    let currentPage: Int
    let totalPages: Int
    var activeColor: Color = AppColors.accentElectric
    var inactiveColor: Color = AppColors.textTertiary
    var dotSize: CGFloat = 8
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? activeColor : inactiveColor.opacity(0.4))
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(index == currentPage ? 1.25 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentPage)
            }
        }
    }
}

// MARK: - Preview

#Preview("OnboardingPageView with dots") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()

        OnboardingPageView(
            currentPage: .constant(0),
            totalPages: 4,
            showPrevNextButtons: true
        ) {
            VStack {
                Text("Page 1")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            .tag(0)

            VStack {
                Text("Page 2")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            .tag(1)

            VStack {
                Text("Page 3")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            .tag(2)

            VStack {
                Text("Page 4")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            .tag(3)
        }
    }
}
