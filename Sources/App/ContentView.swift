import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    // Persistent ViewModels — survive tab switches
    @State private var directChatViewModel = DirectChatViewModel()
    @State private var voiceViewModel = VoiceCompanionViewModel()
    // Use @State to track selected tab - force SwiftUI to see changes
    @State private var selectedTab: AppTab = .dashboard
    // Observation token to force refresh
    @State private var tabChangeCounter: Int = 0
    // Force SwiftUI to recompose when auth state changes
    @State private var authStateKey: Int = 0
    // Hide tab bar when keyboard is visible
    @State private var isKeyboardVisible = false

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
            // Hidden when error is shown so the error sheet can be interacted with
            if appState.isLoading && !appState.showError {
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
        ZStack(alignment: .bottom) {
            // Tab content — ignore container safe areas (notch/home indicator) but NOT keyboard
            tabContent
                .ignoresSafeArea(.container, edges: [.top, .horizontal])

            // Custom tab bar — hidden when keyboard is up
            if !isKeyboardVisible {
                customTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                withAnimation(.easeOut(duration: 0.25)) { isKeyboardVisible = true }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification) {
                withAnimation(.easeOut(duration: 0.25)) { isKeyboardVisible = false }
            }
        }
        .onChange(of: appState.pendingDirectChatAgentId) { _, agentId in
            guard let agentId, let agentInfo = AgentInfo.find(agentId) else {
                appState.pendingDirectChatAgentId = nil
                return
            }
            // Path B per Shaka 2026-05-07: deep-links to unreachable agents land on
            // the chat tab but don't push into a dead conversation view.
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = .chat }
            if agentInfo.isReachable {
                directChatViewModel.navigationPath.append(agentInfo)
            }
            appState.pendingDirectChatAgentId = nil
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == .dashboard {
            DashboardView()
        } else if selectedTab == .projects {
            ProjectsView()
        } else if selectedTab == .chat {
            DirectChatView(viewModel: directChatViewModel)
        } else if selectedTab == .tickets {
            TicketsView()
        } else if selectedTab == .agents {
            AgentsView()
        } else if selectedTab == .knowledge {
            KnowledgeView()
        } else if selectedTab == .voice {
            VoiceCompanionView(viewModel: voiceViewModel)
        } else if selectedTab == .trading {
            TradingView()
        } else {
            Color.clear
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                tabBarButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 24) // Safe area bottom padding
        .background(AppColors.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private var visibleTabs: [AppTab] {
        [.dashboard, .chat, .tickets, .agents, .projects, .voice, .trading]
    }

    private func tabBarButton(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AppColors.accentElectric : AppColors.textSecondary)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AppColors.accentElectric : AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppColors.accentElectric.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
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

                // Escape hatch — dismiss spinner AND show the error so user knows what happened
                Button {
                    appState.isLoading = false
                    // Keep isAuthenticated=false and showError=true so the error sheet appears
                    // and explains WHY the connection failed
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
                    ScrollView {
                        Text(details)
                            .font(.caption)
                            .foregroundColor(AppTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
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
    @EnvironmentObject private var appState: AppState
    // SEC-007 remediation 2026-05-08: default sourced from OrcaSecrets.swift
    // (gitignored) instead of hardcoded literal.
    @State private var token: String = UserDefaults.standard.string(forKey: "orca_auth_token") ?? OrcaSecrets.bearerToken
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
                if !networkStatus.isEmpty || !appState.authDiagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !networkStatus.isEmpty {
                            Text(networkStatus)
                                .font(.caption.monospaced())
                                .foregroundColor(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !appState.authDiagnostics.isEmpty {
                            Divider()
                                .overlay(AppTheme.border)
                            ForEach(Array(appState.authDiagnostics.suffix(6).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(AppTheme.tertiaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
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

            Text("Connecting via Tailscale: 100.76.196.40:8000")
                .font(.caption)
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.bottom, AppTheme.spacingLG)
        }
        .background(AppTheme.background)
        .onAppear {
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
        .environmentObject(AppState())
}
