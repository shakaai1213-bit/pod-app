import Foundation
import OrcaRuntimeContracts
import SwiftUI

enum AppConfig {
    static let canonicalBackendURL = "http://100.104.72.62:8000"

    #if targetEnvironment(simulator)
    static let backendURL = "http://127.0.0.1:19002"
    static let computeURL = "http://127.0.0.1:8890"
    #else
    static let backendURL = canonicalBackendURL
    static let computeURL = "http://100.76.196.40:8890"
    #endif
}

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var loadingMessage: String?
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var errorDetails: String?
    @Published var authDiagnostics: [String] = []
    @Published var currentUser: TeamMember?
    @Published var selectedTab: AppTab = .dashboard
    @Published var navigationState: NavigationState = .dashboard
    @Published var showApprovalSheet = false
    @Published var pendingApprovalId: UUID?
    @Published var pendingNotification: NotificationAction?
    @Published var pendingDirectChatAgentId: String?
    @Published var pendingDirectChatTicketId: String?
    @Published var pendingDirectChatTicketTitle: String?
    @Published var pendingDirectChatChannelId: String?
    @Published var voiceCoordinator = VoiceCoordinator()

    // MARK: - Auth Manager (Keychain-backed)

    let authManager: AuthManager

    // MARK: - Backend URL

    static let backendURL = AppConfig.backendURL

    static func localBearerTokenFallback() -> String? {
        nil
    }

    // MARK: - Initialization

    init() {
        // Force re-auth: clear stale tokens (UserDefaults + Keychain) from previous backend config
        let resetKey = "token_reset_v3"
        if !UserDefaults.standard.bool(forKey: resetKey) {
            UserDefaults.standard.removeObject(forKey: "orca_auth_token")
            UserDefaults.standard.removeObject(forKey: "stored_user_ids")
            // Nuke all Keychain items for this app
            let secClasses = [kSecClassGenericPassword, kSecClassInternetPassword]
            for secClass in secClasses {
                let query: [String: Any] = [kSecClass as String: secClass]
                SecItemDelete(query as CFDictionary)
            }
            UserDefaults.standard.set(true, forKey: resetKey)
            print("[AppState] Cleared ALL stale auth tokens (UserDefaults + Keychain)")
        }
        self.authManager = AuthManager(backendURL: Self.backendURL)

        #if DEBUG
        if let argumentIndex = CommandLine.arguments.firstIndex(of: "--start-tab"),
           CommandLine.arguments.indices.contains(argumentIndex + 1),
           let tab = AppTab(rawValue: CommandLine.arguments[argumentIndex + 1]) {
            selectedTab = tab
        }
        #endif
    }

    // MARK: - Auto Login

    /// Loads the device-bound agent credential before agent-scoped surfaces start.
    /// A signed deployment may provide POD_AGENT_TOKEN once; subsequent launches
    /// read only the Keychain copy.
    func prepareRuntimeCredentials() async {
        let manager = AgentTokenManager()
        let bootstrap = ProcessInfo.processInfo.environment["POD_AGENT_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let bootstrap, !bootstrap.isEmpty {
                try await manager.storeToken(bootstrap)
                await APIClient.shared.setAgentToken(bootstrap)
            } else if let stored = try await manager.getToken() {
                await APIClient.shared.setAgentToken(stored)
            }
        } catch {
            print("[AppState] Agent credential unavailable: \(error)")
        }
    }

    /// Attempts to auto-login using stored Keychain token. Call on app launch.
    func attemptAutoLogin() async {
        let success = await authManager.attemptAutoLogin()
        if success, let user = authManager.currentUser {
            // Bridge the Keychain token into APIClient so all ViewModels can make authenticated requests
            if let token = await authManager.getActiveAccessToken() {
                await APIClient.shared.setToken(token)
            }
            currentUser = TeamMember(id: user.id, name: user.name, avatarColor: "#6B46C1")
            isAuthenticated = true
            await fetchCurrentUser()
            await prepareNotifications()
            print("[AppState] Auto-login successful")
        } else {
            print("[AppState] Auto-login skipped or failed; native sign-in required")
        }
    }

    // MARK: - Authentication

    func authenticate(token: String) async {
        print("[AppState] authenticate() called")
        authDiagnostics.removeAll()
        appendDiagnostic("Starting auth against \(Self.backendURL)")
        appendDiagnostic("Token length: \(token.count)")
        isLoading = true
        errorMessage = nil
        errorDetails = nil
        loadingMessage = "Connecting..."
        await performAuth(token: token)
    }

    /// Actual auth logic — called inside the timeout wrapper.
    /// All state mutations are @MainActor by virtue of the class being @MainActor.
    private func performAuth(token: String) async {
        print("[AppState] performAuth: START backendURL=\(Self.backendURL)")
        appendDiagnostic("Checking backend reachability")

        // Retry reachability check with internet test for iOS Simulator
        var reachable = await checkBackendReachable()
        print("[AppState] performAuth: checkBackendReachable() = \(reachable)")
        
        #if targetEnvironment(simulator)
        if !reachable {
            // Task.sleep is broken on iOS 26 — use async dispatch delays instead.
            await asyncDelay(seconds: 2)
            reachable = await checkBackendReachable()
            print("[AppState] performAuth: checkBackendReachable() retry = \(reachable)")
            appendDiagnostic("Reachability retry 1: \(reachable ? "ok" : "failed")")
            if !reachable {
                await asyncDelay(seconds: 3)
                reachable = await checkBackendReachable()
                print("[AppState] performAuth: checkBackendReachable() retry2 = \(reachable)")
                appendDiagnostic("Reachability retry 2: \(reachable ? "ok" : "failed")")
            }
        }
        #endif

        if !reachable {
            appendDiagnostic("Backend unreachable")
            isAuthenticated = false
            isLoading = false
            loadingMessage = nil
            errorMessage = "Cannot reach ORCA MC"
            errorDetails = "Check your network connection to the Mac Mini. Both devices must be on the same WiFi network. Backend URL: \(Self.backendURL)"
            showError = true
            print("[AppState] performAuth: backend unreachable, error shown")
            return
        }

        loadingMessage = "Verifying token..."
        appendDiagnostic("Verifying token via /api/v1/agents")
        var valid = await verifyTokenDirectly(token)
        print("[AppState] performAuth: verifyTokenDirectly() = \(valid)")
        
        #if targetEnvironment(simulator)
        if !valid {
            // Task.sleep is broken on iOS 26 — use async dispatch delays instead.
            await asyncDelay(seconds: 2)
            valid = await verifyTokenDirectly(token)
            print("[AppState] performAuth: verifyTokenDirectly() retry = \(valid)")
            appendDiagnostic("Token retry 1: \(valid ? "accepted" : "rejected")")
            if !valid {
                await asyncDelay(seconds: 3)
                valid = await verifyTokenDirectly(token)
                print("[AppState] performAuth: verifyTokenDirectly() retry2 = \(valid)")
                appendDiagnostic("Token retry 2: \(valid ? "accepted" : "rejected")")
            }
        }
        #endif

        if valid {
            print("[AppState] performAuth: SUCCESS")
            appendDiagnostic("Token accepted")
            // Set both at once — no delay, avoids SwiftUI render timing issues
            // Set the token before publishing authenticated state so data loads can start safely.
            await APIClient.shared.setToken(token)
            isLoading = false
            loadingMessage = nil
            isAuthenticated = true
            // Store in Keychain and fetch user profile in background — don't block auth
            Task {
                do {
                    _ = try await authManager.signInWithToken(token)
                } catch {
                    print("[AppState] Keychain store failed (non-fatal): \(error)")
                }
                await fetchCurrentUser()
                await prepareNotifications()
            }
            appendDiagnostic("Auth flow completed")
            print("[AppState] performAuth: DONE — isAuthenticated=\(isAuthenticated)")
        } else {
            appendDiagnostic("Token rejected by backend")
            isAuthenticated = false
            isLoading = false
            loadingMessage = nil
            errorMessage = "Invalid token"
            errorDetails = "Token rejected. Make sure you're using the exact token from the ORCA MC .env file.\n\nDiagnostics:\n\(authDiagnostics.joined(separator: "\n"))"
            showError = true
            UserDefaults.standard.removeObject(forKey: "orca_auth_token")
            print("[AppState] performAuth: invalid token, error shown")
        }
    }

    /// Tests if the ORCA MC backend is reachable. 8 second timeout. Public for diagnostics.
    /// Uses /health — confirmed working without auth. Also checks /api/v1/ (returns 404 but proves API is up).
    func checkBackendReachable() async -> Bool {
        print("[AppState] checkBackendReachable: trying \(Self.backendURL)/health")
        if await pingEndpoint("\(Self.backendURL)/health") {
            print("[AppState] checkBackendReachable: /health → reachable!")
            appendDiagnostic("/health reachable")
            return true
        }
        // Fallback: try /api/v1/ — 404 means API is running, which is "reachable"
        if await pingEndpoint("\(Self.backendURL)/api/v1/") {
            print("[AppState] checkBackendReachable: /api/v1/ → reachable!")
            appendDiagnostic("/api/v1/ reachable")
            return true
        }
        print("[AppState] checkBackendReachable: UNREACHABLE!")
        return false
    }

    /// Makes a GET request to check if an endpoint is reachable.
    /// Any HTTP response (even 404/401) = reachable. Network error = unreachable.
    /// NOTE: Uses GET instead of HEAD because the ORCA MC backend doesn't support HEAD.
    private func pingEndpoint(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else {
            print("[AppState] pingEndpoint: invalid URL: \(urlString)")
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8   // 8s: Tailscale cold-handshake on device exceeds 3s (Maui 2026-06-17)
        print("[AppState] pingEndpoint: \(urlString)")
        do {
            let (_, response) = try await OrcaSecureURLSession.make().data(for: request)
            guard OrcaSecureURLSession.responseStayedOnOrigin(response, requestURL: url) else { return false }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[AppState] pingEndpoint: status=\(status)")
            return true  // Any HTTP response = reachable
        } catch {
            print("[AppState] pingEndpoint: ERROR = \(error.localizedDescription)")
            return false
        }
    }

    /// Public diagnostic: verify a token and return true/false without changing auth state.
    func checkTokenValid(_ token: String) async -> Bool {
        await verifyTokenDirectly(token)
    }

    /// Verifies token by fetching agents. 10 second timeout.
    private func verifyTokenDirectly(_ token: String) async -> Bool {
        guard let url = URL(string: "\(Self.backendURL)/api/v1/agents") else {
            print("[AppState] verifyTokenDirectly: invalid URL")
            return false
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(OrcaDeviceIdentity.current(), forHTTPHeaderField: "X-ORCA-Device-ID")
        if token.split(separator: ".", omittingEmptySubsequences: false).count == 3,
           let proof = try? OrcaDeviceIdentity.requestProofHeaders(
               method: "GET",
               target: url.path(percentEncoded: true),
               body: Data(),
               token: token
           ) {
            for (name, value) in proof { request.setValue(value, forHTTPHeaderField: name) }
        }
        request.timeoutInterval = 15
        print("[AppState] verifyTokenDirectly: GET \(url.absoluteString)")

        do {
            let (data, response) = try await OrcaSecureURLSession.make().data(for: request)
            guard OrcaSecureURLSession.responseStayedOnOrigin(response, requestURL: url) else { return false }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[AppState] verifyTokenDirectly: status=\(statusCode), body=\(body.prefix(200))")

            appendDiagnostic("/api/v1/agents status: \(statusCode)")
            if statusCode == 401 {
                print("[AppState] verifyTokenDirectly: TOKEN REJECTED — check if token matches backend LOCAL_AUTH_TOKEN")
                return false
            }
            return statusCode == 200
        } catch {
            print("[AppState] verifyTokenDirectly: ERROR = \(error.localizedDescription)")
            appendDiagnostic("Token verification error: \(error.localizedDescription)")
            return false
        }
    }

    private func prepareNotifications() async {
        let service = PushNotificationService.shared
        await service.checkAuthorizationStatus()
        guard service.isAuthorized else { return }
        service.registerForRemoteNotifications()
    }

    private func appendDiagnostic(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        authDiagnostics.append("[\(stamp)] \(message)")
        if authDiagnostics.count > 20 {
            authDiagnostics.removeFirst(authDiagnostics.count - 20)
        }
    }

    private func asyncDelay(seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                continuation.resume()
            }
        }
    }

    // MARK: - User Profile

    /// Fetches the authenticated user's profile from the backend and updates currentUser.
    private func fetchCurrentUser() async {
        do {
            let dto: UserDTO = try await APIClient.shared.get(path: Endpoint.me.path)
            currentUser = TeamMember(
                id: UUID(uuidString: dto.id) ?? UUID(),
                name: dto.preferredName ?? dto.name,
                avatarColor: dto.avatarColor ?? "#6B46C1"
            )
            // Persist the display name for the greeting
            UserDefaults.standard.set(dto.preferredName ?? dto.name, forKey: "orca_display_name")
            print("[AppState] fetchCurrentUser: got '\(dto.preferredName ?? dto.name)'")
        } catch {
            print("[AppState] fetchCurrentUser: FALLBACK to placeholder — \(error.localizedDescription)")
            currentUser = TeamMember(id: UUID(), name: "Captain", avatarColor: "#6B46C1")
        }
    }

    // MARK: - Navigation

    func navigateTo(_ state: NavigationState) {
        switch state {
        case .dashboard: selectedTab = .dashboard
        case .chat: selectedTab = .work
        case .projects: selectedTab = .work
        case .knowledge: selectedTab = .knowledge
        case .agents: selectedTab = .crew  // agents folded into Crew (L1 revamp)
        case .settings: selectedTab = .dashboard
        }
        navigationState = state
    }

    func navigateTo(_ tab: AppTab) {
        // Pod Chat is a capability inside Work. Keep the old enum case for
        // deep-link compatibility, but never restore the duplicate room shell.
        selectedTab = tab == .chat ? .work : tab
        switch tab {
        case .dashboard: navigationState = .dashboard
        case .runtime: navigationState = .dashboard
        case .system: navigationState = .dashboard
        case .chat: navigationState = .chat(channelId: nil)
        case .work: navigationState = .projects(taskId: nil)
        case .fund: navigationState = .dashboard
        case .captainsLog: navigationState = .dashboard  // legacy alias
        case .lab: navigationState = .dashboard
        case .crew: navigationState = .agents(agentId: nil)  // Crew = merged Agents+Arms
        case .arms: navigationState = .agents(agentId: nil)  // legacy alias
        case .knowledge: navigationState = .knowledge(standardId: nil)
        case .agents: navigationState = .agents(agentId: nil)  // legacy alias
        case .maker: navigationState = .dashboard
        }
    }

    func route(_ action: NotificationAction) {
        switch action {
        case .newMessage(let channelId, _):
            selectedTab = .work
            navigationState = .chat(channelId: channelId)
            pendingDirectChatChannelId = channelId.uuidString
        case .taskAssigned(let taskId, _):
            selectedTab = .work
            navigationState = .projects(taskId: taskId)
        case .approvalRequested(let approvalId, _):
            selectedTab = .dashboard
            pendingApprovalId = approvalId
            showApprovalSheet = true
            navigationState = .dashboard
        case .agentError(agentId: let agentId, error: _):
            selectedTab = .crew  // agents folded into Crew (L1 revamp)
            navigationState = .agents(agentId: agentId)
        case .unknown:
            break
        }
    }

    func logout() async {
        do {
            try await authManager.signOut()
        } catch {
            showError = true
            errorMessage = "ORCA could not revoke this session. Your credentials remain secured on this device."
            errorDetails = error.localizedDescription
            return
        }
        clearToken()
        isAuthenticated = false
        currentUser = nil
        selectedTab = .dashboard
        navigationState = .dashboard
        pendingNotification = nil
        showApprovalSheet = false
        pendingApprovalId = nil
    }

    func dismissError() {
        showError = false
        errorMessage = nil
        errorDetails = nil
    }

    // MARK: - Token Storage

    private func clearToken() {
        // Migration cleanup only. New bearer tokens are persisted in Keychain.
        UserDefaults.standard.removeObject(forKey: "orca_auth_token")
        Task { await APIClient.shared.setToken(nil) }
    }
}
