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
                }
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
