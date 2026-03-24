import SwiftUI

// MARK: - AppState Environment Key

private struct AppStateKey: EnvironmentKey {
    static let defaultValue: AppState = AppState()
}

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}

@main
struct podApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appState, appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    configureAppearance()
                    // Auto-login if token exists in UserDefaults
                    if let savedToken = UserDefaults.standard.string(forKey: "orca_auth_token") {
                        Task { @MainActor in
                            await appState.authenticate(token: savedToken)
                        }
                    }
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    private func handleURL(_ url: URL) {
        print("[podApp] URL received: \(url)")
        // pod://connect/<token> — bypasses the login form
        guard url.scheme == "pod",
              url.host == "connect",
              let token = url.pathComponents.last,
              !token.isEmpty else { return }
        print("[podApp] Token length: \(token.count)")
        Task { @MainActor in
            print("[podApp] Authenticating via URL scheme...")
            await appState.authenticate(token: token)
            print("[podApp] Auth complete. isAuthenticated=\(appState.isAuthenticated)")
        }
    }

    private func configureAppearance() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(Theme.surface)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(Theme.surface)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.primaryText)]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.primaryText)]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }
}
