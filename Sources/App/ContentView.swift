import SwiftUI

struct ContentView: View {
    @Environment(\.appState) private var appState: AppState

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            if appState.isAuthenticated {
                mainTabView
            } else {
                LoginView()
            }

            // Global loading overlay
            if appState.isLoading {
                loadingOverlay
            }
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
                .tag(AppTab.dashboard.rawValue)

            ProjectsView()
                .tabItem {
                    Label(AppTab.projects.title, systemImage: AppTab.projects.icon)
                }
                .tag(AppTab.projects.rawValue)

            ChatView()
                .tabItem {
                    Label(AppTab.chat.title, systemImage: AppTab.chat.icon)
                }
                .tag(AppTab.chat.rawValue)

            KnowledgeView()
                .tabItem {
                    Label(AppTab.knowledge.title, systemImage: AppTab.knowledge.icon)
                }
                .tag(AppTab.knowledge.rawValue)

            AgentsView()
                .tabItem {
                    Label(AppTab.agents.title, systemImage: AppTab.agents.icon)
                }
                .tag(AppTab.agents.rawValue)
        }
        .tint(AppTheme.primaryAccent)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: AppTheme.spacingMD) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.primaryAccent)
                    .scaleEffect(1.4)

                if let message = appState.loadingMessage {
                    Text(message)
                        .font(.body)
                        .foregroundColor(AppTheme.secondaryText)
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
                    Text("API Token")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)

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
                                submitToken()
                            }
                    }
                    .padding(AppTheme.spacingSM)
                    .background(AppTheme.surface)
                    .cornerRadius(AppTheme.radiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMedium)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                }

                Button(action: submitToken) {
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
                    .background(
                        token.isEmpty
                            ? AppTheme.surfaceOverlay
                            : AppTheme.primaryAccent
                    )
                    .cornerRadius(AppTheme.radiusMedium)
                    .shadow(
                        color: token.isEmpty ? .clear : AppTheme.glowAccent,
                        radius: 12
                    )
                }
                .disabled(token.isEmpty || appState.isLoading)
            }
            .padding(.horizontal, AppTheme.spacingXL)

            Spacer()

            Text("Connecting to \(URL(string: "http://192.168.4.243:8000")!.host!)")
                .font(.caption)
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.bottom, AppTheme.spacingLG)
        }
        .background(AppTheme.background)
    }

    private func submitToken() {
        guard !token.isEmpty else { return }
        Task {
            await appState.authenticate(token: token)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.appState, AppState())
}
