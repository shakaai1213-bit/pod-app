import SwiftUI
import UIKit

// MARK: - Wall Display Modifier

/// ViewModifier that enforces the wall display environment:
/// - Landscape-only orientation lock
/// - Hidden status bar
/// - Full-screen immersive presentation
/// - Brightness control via UIScreen.main.brightness
/// - Tap-to-wake gesture handling
struct WallDisplayModifier: ViewModifier {

    /// Called when the user taps to wake from dimmed state.
    let onWake: () -> Void

    /// Whether the display is currently dimmed (controls opacity).
    let isDimmed: Bool

    // MARK: - Orientation

    @State private var orientationLock = UIDeviceOrientation.landscapeLeft

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .onAppear {
                lockOrientation()
                setFullScreen(true)
                hideStatusBar(true)
            }
            .onDisappear {
                lockOrientation()
                setFullScreen(false)
                hideStatusBar(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                // Re-apply lock if orientation changed externally
                lockOrientation()
            }
            .modifier(TapToWakeModifier(onWake: onWake))
            .opacity(isDimmed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.5), value: isDimmed)
    }

    // MARK: - Orientation Lock

    private func lockOrientation() {
        #if targetEnvironment(simulator)
        // Allow all orientations in simulator for easier testing
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        requestOrientationUpdate()
        #else
        // Lock to landscape on physical device
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        requestOrientationUpdate()
        #endif
    }

    private func requestOrientationUpdate() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        windowScene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    // MARK: - Full Screen

    private func setFullScreen(_ fullScreen: Bool) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        windowScene.windows.forEach { window in
            window.backgroundColor = fullScreen ? .black : UIColor(AppColors.backgroundPrimary)
        }
    }

    // MARK: - Status Bar

    private func hideStatusBar(_ hidden: Bool) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        // Set status bar via window level
        windowScene.windows.forEach { window in
            if hidden {
                window.windowLevel = UIWindow.Level.statusBar + 1
            } else {
                window.windowLevel = UIWindow.Level.normal
            }
        }
    }
}

// MARK: - Tap to Wake Modifier

private struct TapToWakeModifier: ViewModifier {
    let onWake: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                onWake()
            }
    }
}

// MARK: - View Extension

extension View {
    func wallDisplay(onWake: @escaping () -> Void, isDimmed: Bool) -> some View {
        modifier(WallDisplayModifier(onWake: onWake, isDimmed: isDimmed))
    }
}
