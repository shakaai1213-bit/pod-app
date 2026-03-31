import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {

    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            // Dark background
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $viewModel.currentPage) {
                    WelcomePage()
                        .tag(0)

                    FeaturesPage()
                        .tag(1)

                    ConnectPage(viewModel: viewModel)
                        .tag(2)

                    ReadyPage(viewModel: viewModel)
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentPage)

                // Page indicator + navigation
                PageControlView(
                    currentPage: viewModel.currentPage,
                    totalPages: viewModel.totalPages
                )
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppColors.accentElectric, AppColors.accentElectric.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(AppColors.backgroundPrimary)
                }
                .shadow(color: AppColors.accentElectric.opacity(0.3), radius: 20, x: 0, y: 10)

                // App name
                Text("pod")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColors.accentElectric)
                    .shadow(color: AppColors.accentElectric.opacity(0.2), radius: 10, x: 0, y: 5)
            }

            Spacer()
                .frame(height: 48)

            // Tagline
            VStack(spacing: 12) {
                Text("Where the pod comes together.")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Your team's command center.")
                    .font(.body)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Page 2: Features

private struct FeaturesPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 24)

            // Title
            VStack(spacing: 8) {
                Text("Everything you need")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.textPrimary)

                Text("One app. Your whole team.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.bottom, 32)

            // Feature cards
            VStack(spacing: 16) {
                FeatureCard(
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    iconColor: AppColors.accentElectric,
                    title: "Real-time awareness",
                    description: "See your team at a glance."
                )

                FeatureCard(
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: AppColors.accentElectric,
                    title: "Unified chat",
                    description: "One place for every conversation."
                )

                FeatureCard(
                    icon: "cpu.fill",
                    iconColor: AppColors.accentAgent,
                    title: "Agent control",
                    description: "Manage your AI team, instantly."
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(iconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Page 3: Connect to ORCA MC

private struct ConnectPage: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var isTokenFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)

            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppColors.accentElectric.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.accentElectric)
                }

                Text("Connect to your team")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.textPrimary)

                Text("Sign in with your ORCA Mission Control token")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 48)

            // Token input
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 20)

                    SecureField("Enter your token", text: $viewModel.token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        .focused($isTokenFieldFocused)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppColors.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    isTokenFieldFocused ? AppColors.accentElectric : AppColors.border,
                                    lineWidth: isTokenFieldFocused ? 2 : 1
                                )
                        )
                )

                // Error message
                if let error = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.accentDanger)

                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(AppColors.accentDanger)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 32)
            .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)

            Spacer()
                .frame(height: 32)

            // Connect button
            Button {
                isTokenFieldFocused = false
                Task {
                    _ = await viewModel.connect()
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.backgroundPrimary))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }

                    Text(viewModel.isConnecting ? "Connecting..." : "Connect")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    viewModel.canProceed
                        ? LinearGradient(
                            colors: [AppColors.accentElectric, AppColors.accentElectric.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [AppColors.textTertiary, AppColors.textTertiary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(
                    color: viewModel.canProceed ? AppColors.accentElectric.opacity(0.3) : .clear,
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
            .disabled(!viewModel.canProceed)
            .padding(.horizontal, 32)

            Spacer()
                .frame(height: 24)

            // Subtext
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)

                Text("Find your token in ORCA Mission Control")
                    .font(.caption)
            }
            .foregroundColor(AppColors.textTertiary)

            // Demo mode button
            Button {
                viewModel.enterDemoMode()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                    Text("Try Demo Mode")
                }
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
            }
            .padding(.top, 8)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Page 4: Ready

private struct ReadyPage: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var showCheckmark = false
    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle()
                    .fill(AppColors.accentElectric.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .scaleEffect(showCheckmark ? 1 : 0.5)
                    .opacity(showCheckmark ? 1 : 0)

                Circle()
                    .fill(AppColors.accentElectric.opacity(0.3))
                    .frame(width: 110, height: 110)
                    .scaleEffect(showCheckmark ? 1 : 0.5)
                    .opacity(showCheckmark ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .heavy))
                    .foregroundColor(AppColors.accentElectric)
                    .scaleEffect(showCheckmark ? 1 : 0)
                    .opacity(showCheckmark ? 1 : 0)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1), value: showCheckmark)

            Spacer()
                .frame(height: 40)

            // Text content
            VStack(spacing: 12) {
                Text("You're in.")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                Text("Welcome to pod, \(viewModel.userName ?? "Captain").")
                    .font(.title3)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
            }
            .animation(.easeOut(duration: 0.5).delay(0.4), value: showContent)

            Spacer()
                .frame(height: 60)

            // Get Started button
            Button {
                viewModel.complete()
            } label: {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [AppColors.accentElectric, AppColors.accentElectric.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: AppColors.accentElectric.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(0.6), value: showContent)

            Spacer()
                .frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            showCheckmark = true
            showContent = true
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
