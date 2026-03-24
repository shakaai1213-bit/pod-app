import SwiftUI

struct ContentView: View {
    @Environment(\.appState) private var appState: AppState
    // Force SwiftUI to recompose when auth state changes — breaks view identity
    // so LoginView is fully torn down before mainTabView appears
    @State private var authStateKey: Int = 0

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            // Use authStateKey to force SwiftUI to treat as new identity on change
            // This prevents the LoginView from "sticking" during render cycles
            if appState.isAuthenticated {
                mainTabView
                    .id("main-\(authStateKey)")
            } else {
                LoginView()
                    .id("login-\(authStateKey)")
            }

            // Global loading overlay — separate from auth state
            if appState.isLoading {
                loadingOverlay
            }
        }
        .onChange(of: appState.isAuthenticated) { _, newValue in
            // Bump the key to force fresh view identity when auth changes
            authStateKey += 1
            print("[ContentView] auth state changed to \(newValue), key now \(authStateKey)")
        }
        .sheet(isPresented: Binding(
            get: { appState.showError },
            set: { appState.showError = $0 }
        )) {
            errorSheet
        }
    }

    // MARK: - Tab View

    private var mainTabView: some View {
        TabView(selection: Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )) {
            DashboardView()
                .tabItem {
                    Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.icon)
                }
                .tag(AppTab.dashboard)

            ProjectsView()
                .tabItem {
                    Label(AppTab.projects.title, systemImage: AppTab.projects.icon)
                }
                .tag(AppTab.projects)

            ChatView()
                .tabItem {
                    Label(AppTab.chat.title, systemImage: AppTab.chat.icon)
                }
                .tag(AppTab.chat)

            KnowledgeView()
                .tabItem {
                    Label(AppTab.knowledge.title, systemImage: AppTab.knowledge.icon)
                }
                .tag(AppTab.knowledge)

            AgentsView()
                .tabItem {
                    Label(AppTab.agents.title, systemImage: AppTab.agents.icon)
                }
                .tag(AppTab.agents)
        }
        .tint(AppTheme.primaryAccent)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: AppTheme.spacingLG) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.primaryAccent)
                    .scaleEffect(1.4)

                if let message = appState.loadingMessage {
                    Text(message)
                        .font(.body)
                        .foregroundColor(AppTheme.secondaryText)
                }

                // Escape hatch so user is never locked out
                Button {
                    appState.isLoading = false
                    appState.showError = false
                    appState.isAuthenticated = false
                } label: {
                    Text("Reset / Retry")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                        .underline()
                }
            }
            .padding(AppTheme.spacingXL)
            .background(AppTheme.surfaceElevated)
            .cornerRadius(AppTheme.radiusLarge)
            .shadow(color: AppTheme.glowAccent, radius: 20)
        }
    }

    // MARK: - Error Sheet

    private var errorSheet: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacingLG) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppTheme.error)

                Text(appState.errorMessage ?? "Something went wrong")
                    .font(.title2)
                    .foregroundColor(AppTheme.primaryText)
                    .multilineTextAlignment(.center)

                if let details = appState.errorDetails, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Button(action: { appState.dismissError() }) {
                    Text("Dismiss")
                        .font(.body.bold())
                        .foregroundColor(AppTheme.inverseText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacingSM)
                        .background(AppTheme.primaryAccent)
                        .cornerRadius(AppTheme.radiusMedium)
                }
                .padding(.horizontal, AppTheme.spacingXL)
            }
            .padding(AppTheme.spacingXL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.surface)
            .navigationTitle("Error")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Login View

struct LoginView: View {
    @Environment(\.appState) private var appState: AppState
    @State private var token: String = ""
    @State private var networkStatus: String = ""   // live network diagnostic
    @FocusState private var isTokenFocused: Bool

    var body: some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            // Logo / Brand
            VStack(spacing: AppTheme.spacingSM) {
                Image(systemName: "cpu")
                    .font(.system(size: 64))
                    .foregroundColor(AppTheme.primaryAccent)
                    .shadow(color: AppTheme.glowAccent, radius: 20)

                Text("ORCA")
                    .font(.system(size: 40, weight: .bold, design: .default))
                    .foregroundColor(AppTheme.primaryText)

                Text("Mission Control")
                    .font(.title3)
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()

            // Token input
            VStack(spacing: AppTheme.spacingMD) {
                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    HStack {
                        Text("API Token")
                            .font(.caption)
                            .foregroundColor(AppTheme.secondaryText)
                        Spacer()
                        if !token.isEmpty {
                            Text("\(token.count) chars")
                                .font(.caption2)
                                .foregroundColor(AppTheme.primaryAccent)
                        }
                    }

                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(AppTheme.secondaryText)

                        SecureField("Paste your token", text: $token)
                            .textFieldStyle(.plain)
                            .foregroundColor(AppTheme.primaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isTokenFocused)
                            .submitLabel(.go)
                            .onSubmit {
                                Task { await submitToken() }
                            }
                    }
                    .padding(AppTheme.spacingSM)
                    .background(AppTheme.surface)
                    .cornerRadius(AppTheme.radiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMedium)
                            .stroke(token.isEmpty ? AppTheme.border : AppTheme.primaryAccent, lineWidth: 1)
                    )
                }

                // Live network status
                if !networkStatus.isEmpty {
                    Text(networkStatus)
                        .font(.caption.monospaced())
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.spacingSM)
                        .background(AppTheme.surface)
                        .cornerRadius(AppTheme.radiusMedium)
                }

                Button {
                    Task {
                        await submitToken()
                    }
                } label: {
                    HStack {
                        if appState.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(AppTheme.inverseText)
                                .scaleEffect(0.8)
                        } else {
                            Text("Connect")
                                .font(.body.bold())
                        }
                    }
                    .foregroundColor(AppTheme.inverseText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingSM + 4)
                    .background(AppTheme.primaryAccent)
                    .cornerRadius(AppTheme.radiusMedium)
                }
                .buttonStyle(.plain)
                .disabled(appState.isLoading || token.isEmpty)
            }
            .padding(.horizontal, AppTheme.spacingXL)

            Spacer()

            Text("Connecting via localhost.cloud:8000")
                .font(.caption)
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.bottom, AppTheme.spacingLG)
        }
        .background(AppTheme.background)
        .onAppear {
            // Run quick network check on appear
            Task {
                await checkNetwork()
            }
        }
    }

    // MARK: - Network Check

    @MainActor
    private func checkNetwork() async {
        networkStatus = "Checking network..."
        guard let url = URL(string: "\(AppState.backendURL)/health") else {
            networkStatus = "❌ Invalid URL"
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                networkStatus = "✅ Backend reachable (HTTP \(http.statusCode))"
            } else {
                networkStatus = "✅ Backend responded"
            }
        } catch {
            networkStatus = "❌ Cannot reach backend: \(error.localizedDescription)"
        }
    }

    // MARK: - Auth

    @MainActor
    private func submitToken() async {
        guard !token.isEmpty else { return }
        networkStatus = "Authenticating..."
        // authenticate() sets isAuthenticated=true on success
        await appState.authenticate(token: token)
        // After authenticate() returns, SwiftUI will re-render because AppState is @MainActor @Published
        if appState.isAuthenticated {
            networkStatus = "✅ Authenticated! Loading..."
        } else if let err = appState.errorMessage {
            networkStatus = "❌ \(err)"
        } else {
            networkStatus = "Auth complete"
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.appState, AppState())
}
