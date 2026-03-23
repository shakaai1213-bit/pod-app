import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Theme.background
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
        .sheet(isPresented: $appState.showError) {
            errorSheet
        }
    }

    // MARK: - Tab View

    private var mainTabView: some View {
        TabView(selection: $appState.selectedTab) {
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
        .tint(Theme.primaryAccent)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: Theme.spacingMD) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Theme.primaryAccent)
                    .scaleEffect(1.4)

                if let message = appState.loadingMessage {
                    Text(message)
                        .font(.bodyMedium)
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .padding(Theme.spacingXL)
            .background(Theme.surfaceElevated)
            .cornerRadius(Theme.radiusLarge)
            .shadow(color: Theme.glowAccent, radius: 20)
        }
    }

    // MARK: - Error Sheet

    private var errorSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.spacingLG) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.error)

                Text(appState.errorMessage ?? "Something went wrong")
                    .font(.titleMedium)
                    .foregroundColor(Theme.primaryText)
                    .multilineTextAlignment(.center)

                if let details = appState.errorDetails, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Button(action: { appState.dismissError() }) {
                    Text("Dismiss")
                        .font(.bodyLarge.bold())
                        .foregroundColor(Theme.inverseText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacingSM)
                        .background(Theme.primaryAccent)
                        .cornerRadius(Theme.radiusMedium)
                }
                .padding(.horizontal, Theme.spacingXL)
            }
            .padding(Theme.spacingXL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .navigationTitle("Error")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var token: String = ""
    @FocusState private var isTokenFocused: Bool

    var body: some View {
        VStack(spacing: Theme.spacingXL) {
            Spacer()

            // Logo / Brand
            VStack(spacing: Theme.spacingSM) {
                Image(systemName: "cpu")
                    .font(.system(size: 64))
                    .foregroundColor(Theme.primaryAccent)
                    .shadow(color: Theme.glowAccent, radius: 20)

                Text("ORCA")
                    .font(.system(size: 40, weight: .bold, design: .default))
                    .foregroundColor(Theme.primaryText)

                Text("Mission Control")
                    .font(.titleSmall)
                    .foregroundColor(Theme.secondaryText)
            }

            Spacer()

            // Token input
            VStack(spacing: Theme.spacingMD) {
                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    Text("API Token")
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText)

                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(Theme.secondaryText)

                        SecureField("Paste your token", text: $token)
                            .textFieldStyle(.plain)
                            .foregroundColor(Theme.primaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isTokenFocused)
                            .submitLabel(.go)
                            .onSubmit {
                                submitToken()
                            }
                    }
                    .padding(Theme.spacingSM)
                    .background(Theme.surface)
                    .cornerRadius(Theme.radiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }

                Button(action: submitToken) {
                    HStack {
                        if appState.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Theme.inverseText)
                                .scaleEffect(0.8)
                        } else {
                            Text("Connect")
                                .font(.bodyLarge.bold())
                        }
                    }
                    .foregroundColor(Theme.inverseText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacingSM + 4)
                    .background(
                        token.isEmpty
                            ? Theme.surfaceOverlay
                            : Theme.primaryAccent
                    )
                    .cornerRadius(Theme.radiusMedium)
                    .shadow(
                        color: token.isEmpty ? .clear : Theme.glowAccent,
                        radius: 12
                    )
                }
                .disabled(token.isEmpty || appState.isLoading)
            }
            .padding(.horizontal, Theme.spacingXL)

            Spacer()

            Text("Connecting to \(URL(string: "http://192.168.4.243:8000")!.host!)")
                .font(.caption)
                .foregroundColor(Theme.tertiaryText)
                .padding(.bottom, Theme.spacingLG)
        }
        .background(Theme.background)
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
        .environmentObject(AppState())
}
