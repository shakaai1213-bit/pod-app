import SwiftUI
import SwiftData

@main
struct podApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [DMConversation.self, DMMessage.self])
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    configureAppearance()
                    Task { @MainActor in
                        await appState.attemptAutoLogin()
                    }
                    if CommandLine.arguments.contains("--auto-login") {
                        // SEC-007 remediation 2026-05-08: token sourced from
                        // OrcaSecrets.swift (gitignored) instead of hardcoded literal.
                        let testToken = OrcaSecrets.bearerToken
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
