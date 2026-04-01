import SwiftUI

// MARK: - AppState Environment Key

@MainActor private func makeDefaultAppState() -> AppState {
    AppState()
}

private struct AppStateKey: EnvironmentKey {
    @MainActor static let defaultValue: AppState = makeDefaultAppState()
}

extension EnvironmentValues {
    @MainActor var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}

@main
struct podApp: App {
    @StateObject private var appState = AppState()

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
                    // TEST MODE: If launched with --auto-login argument, auto-submit the hardcoded token.
                    // This bypasses the UI automation problem on iOS Simulator (Metal renders outside macOS accessibility).
                    if CommandLine.arguments.contains("--auto-login") {
                        let testToken = "ebe9a0fdfaf9b7674f4e2b9d0149f881d46111730b780d9e508ad94023c03051"
                        print("[podApp] TEST MODE: auto-submitting token via --auto-login")
                        Task { @MainActor in
                            await appState.authenticate(token: testToken)
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
