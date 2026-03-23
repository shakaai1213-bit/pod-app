import SwiftUI
import LocalAuthentication

// MARK: - Wall Display Launcher View

/// Sheet presented from Settings to launch the Ambient Wall Display mode.
struct WallDisplayLauncherView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var warnBeforeStarting = true
    @State private var hasPasscode = false
    @State private var showPasscodeAlert = false
    @State private var navigateToWallDisplay = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    headerSection
                    descriptionSection
                    previewSection
                    startButton
                    exitInstructionsSection
                }
                .padding(Theme.lg)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Ambient Wall Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textTertiary)
                            .font(.system(size: 24))
                    }
                }
            }
            .onAppear {
                checkDevicePasscode()
            }
            .fullScreenCover(isPresented: $navigateToWallDisplay) {
                WallDisplayView()
            }
            .alert("Device Passcode Detected", isPresented: $showPasscodeAlert) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Start Anyway") {
                    navigateToWallDisplay = true
                }
            } message: {
                Text(
                    "This device has a passcode enabled. Wall Display will run full-screen without authentication. "
                    + "Exit by swiping down from the top edge of the screen."
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: Theme.sm) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.accentElectric)
                .frame(width: 80, height: 80)
                .background(AppColors.accentElectric.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))

            Text("Ambient Wall Display")
                .podTextStyle(.title2, color: AppColors.textPrimary)
        }
        .padding(.top, Theme.md)
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(spacing: Theme.sm) {
            Text("Display team status on iPad.")
                .podTextStyle(.body, color: AppColors.textSecondary)
            Text("Full screen, auto-dimming, no exit button.")
                .podTextStyle(.body, color: AppColors.textSecondary)

            Text(
                "Shows live agent statuses, activity feed, and system health. "
                + "Designed for dedicated wall-mounted iPad displays."
            )
            .podTextStyle(.caption, color: AppColors.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.top, Theme.xs)
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        WallDisplayPreview()
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLarge)
                    .stroke(AppColors.border, lineWidth: 1)
            )
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            handleStart()
        } label: {
            HStack(spacing: Theme.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Start Wall Display")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppColors.accentElectric)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        }
        .padding(.top, Theme.xs)
    }

    // MARK: - Exit Instructions Section

    private var exitInstructionsSection: some View {
        VStack(spacing: Theme.md) {
            Divider()
                .background(AppColors.border)

            VStack(spacing: Theme.xs) {
                Label("Exit", systemImage: "arrow.down.to.line")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text("Swipe down from the top edge of the screen to return to pod.")
                    .podTextStyle(.caption, color: AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }

            // Auto-lock warning toggle
            HStack(spacing: Theme.sm) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.accentWarning)

                Text("Warn before starting on passcode-protected devices")
                    .podTextStyle(.caption, color: AppColors.textSecondary)

                Spacer()

                Toggle("", isOn: $warnBeforeStarting)
                    .labelsHidden()
                    .tint(AppColors.accentElectric)
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
    }

    // MARK: - Helpers

    private func checkDevicePasscode() {
        let context = LAContext()
        var error: NSError?
        hasPasscode = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    private func handleStart() {
        if hasPasscode && warnBeforeStarting {
            showPasscodeAlert = true
        } else {
            navigateToWallDisplay = true
        }
    }
}

// MARK: - Wall Display Preview

private struct WallDisplayPreview: View {

    private let previewAgents = ["Maui", "Researcher", "Builder", "Analyst"]
    private let previewActivities = [
        ("checkmark.circle.fill", AppColors.accentSuccess, "PR #42 merged", "Builder"),
        ("bubble.left.fill",      AppColors.accentElectric, "New message in #projects", "Maui"),
        ("star.fill",             AppColors.accentAgent, "Sentinel milestone", "Sentinel"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top strip
            HStack {
                Text("ORCA AI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text("14:32")
                    .font(.system(size: 20, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text("Sunday, March 22")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(AppColors.backgroundSecondary)

            // Agent strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(previewAgents, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(agentColor(for: name))
                                    .frame(width: 6, height: 6)
                                Text(name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                            Text(agentTask(for: name))
                                .font(.system(size: 9))
                                .foregroundStyle(AppColors.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(8)
                        .frame(width: 110)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 70)
            .background(AppColors.backgroundSecondary)

            // Activity feed
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(previewActivities, id: \.2) { icon, color, desc, actor in
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(color.opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(color)
                            }
                            Text(desc)
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(actor)
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(AppColors.backgroundPrimary)

            // Bottom strip
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.accentElectric)
                    Text("pod")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppColors.accentSuccess)
                        .frame(width: 6, height: 6)
                    Text("All systems nominal")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(AppColors.backgroundSecondary)
        }
    }

    private func agentColor(for name: String) -> Color {
        switch name {
        case "Maui":        return AppColors.accentSuccess
        case "Researcher": return AppColors.accentWarning
        case "Builder":    return AppColors.accentSuccess
        case "Analyst":    return AppColors.textTertiary
        default:           return AppColors.textTertiary
        }
    }

    private func agentTask(for name: String) -> String {
        switch name {
        case "Maui":        return "Reviewing PR #42"
        case "Researcher": return "Analyzing data..."
        case "Builder":    return "Deploying v2.1.0"
        case "Analyst":    return "Idle"
        default:           return ""
        }
    }
}

#Preview {
    WallDisplayLauncherView()
        .preferredColorScheme(.dark)
}
