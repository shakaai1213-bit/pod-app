import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var loadingMessage: String?
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var errorDetails: String?
    @Published var currentUser: TeamMember?
    @Published var selectedTab: AppTab = .dashboard
    @Published var navigationState: NavigationState = .dashboard
    @Published var showApprovalSheet = false
    @Published var pendingApprovalId: UUID?
    @Published var pendingNotification: NotificationAction?

    // MARK: - Auth Manager (Keychain-backed)

    let authManager: AuthManager

    // MARK: - Backend URL

    // Simulator can still use the local proxy when available, but must authenticate honestly.
    #if targetEnvironment(simulator)
    static let backendURL = "http://192.168.4.243:19005"
    #else
    static let backendURL = "http://shakas-mac-mini.tail82d30d.ts.net:8000"
    #endif

    // MARK: - Initialization

    init() {
        self.authManager = AuthManager(backendURL: Self.backendURL)
    }

    // MARK: - Auto Login

    /// Attempts to auto-login using stored Keychain token. Call on app launch.
    func attemptAutoLogin() async {
        let success = await authManager.attemptAutoLogin()
        if success, let user = authManager.currentUser {
            currentUser = TeamMember(id: user.id, name: user.name, avatarColor: "#6B46C1")
            isAuthenticated = true
            await fetchCurrentUser()
            print("[AppState] Auto-login successful")
        } else {
            print("[AppState] Auto-login skipped or failed")
        }
    }

    // MARK: - Authentication

    func authenticate(token: String) async {
        print("[AppState] authenticate() called with token: \(token.prefix(8))...")
        isLoading = true
        errorMessage = nil
        errorDetails = nil
        loadingMessage = "Connecting..."

        // Run auth with a reliable timeout. Uses DispatchSemaphore as clock source — avoids iOS 26 Task.sleep bug.
        // Wrapping in Task { } so we can cancel it if timeout fires, but run on same actor to avoid race conditions.
        let authTask = Task { @MainActor in
            await performAuth(token: token)
        }

        // Timeout fires after 60s — enough time for proxy retries + simulator bypass to complete
        let timedOut = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                let semaphore = DispatchSemaphore(value: 0)
                DispatchQueue.global().async { semaphore.signal() }
                _ = semaphore.wait(timeout: .now() + 60)
                continuation.resume(returning: true)
            }
        }

        if timedOut {
            if !isAuthenticated {
                // Timeout fired before auth completed — cancel and show error
                authTask.cancel()
                print("[AppState] Auth timed out after 60s — cancelling and showing error")
                isLoading = false
                loadingMessage = nil
                errorMessage = "Connection timed out"
                errorDetails = "The request took too long. Check your network and try again."
                showError = true
                UserDefaults.standard.removeObject(forKey: "orca_auth_token")
            } else {
                // Auth completed successfully just as timeout fired — clean up loading state
                print("[AppState] Auth completed successfully (slow but OK)")
                isLoading = false
                loadingMessage = nil
            }
        }
    }

    /// Actual auth logic — called inside the timeout wrapper.
    /// All state mutations are @MainActor by virtue of the class being @MainActor.
    private func performAuth(token: String) async {
        print("[AppState] performAuth: START token=\(token.prefix(8))... backendURL=\(Self.backendURL)")
        
        // Retry reachability check with internet test for iOS Simulator
        var reachable = await checkBackendReachable()
        print("[AppState] performAuth: checkBackendReachable() = \(reachable)")
        
        #if targetEnvironment(simulator)
        if !reachable {
            // Task.sleep is broken on iOS 26 — use DispatchSemaphore for reliable delays
            let s1 = DispatchSemaphore(value: 0)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { s1.signal() }
            _ = s1.wait(timeout: .now() + 3)
            reachable = await checkBackendReachable()
            print("[AppState] performAuth: checkBackendReachable() retry = \(reachable)")
            if !reachable {
                let s2 = DispatchSemaphore(value: 0)
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { s2.signal() }
                _ = s2.wait(timeout: .now() + 4)
                reachable = await checkBackendReachable()
                print("[AppState] performAuth: checkBackendReachable() retry2 = \(reachable)")
            }
        }
        #endif

        if !reachable {
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
        var valid = await verifyTokenDirectly(token)
        print("[AppState] performAuth: verifyTokenDirectly() = \(valid)")
        
        #if targetEnvironment(simulator)
        if !valid {
            // Task.sleep is broken on iOS 26 — use DispatchSemaphore for reliable delays
            let s1 = DispatchSemaphore(value: 0)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { s1.signal() }
            _ = s1.wait(timeout: .now() + 3)
            valid = await verifyTokenDirectly(token)
            print("[AppState] performAuth: verifyTokenDirectly() retry = \(valid)")
            if !valid {
                let s2 = DispatchSemaphore(value: 0)
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { s2.signal() }
                _ = s2.wait(timeout: .now() + 4)
                valid = await verifyTokenDirectly(token)
                print("[AppState] performAuth: verifyTokenDirectly() retry2 = \(valid)")
            }
        }
        #endif

        if valid {
            print("[AppState] performAuth: SUCCESS")
            // Set both at once — no delay, avoids SwiftUI render timing issues
            isLoading = false
            loadingMessage = nil
            isAuthenticated = true
            // Store in UserDefaults for auto-login on next launch
            UserDefaults.standard.set(token, forKey: "orca_auth_token")
            // Store in Keychain via AuthManager
            do {
                _ = try await authManager.signInWithToken(token)
            } catch {
                print("[AppState] Failed to store token in Keychain: \(error)")
            }
            Task { await APIClient.shared.setToken(token) }
            // Fetch real user profile from backend
            await fetchCurrentUser()
            print("[AppState] performAuth: DONE — isAuthenticated=\(isAuthenticated)")
        } else {
            isAuthenticated = false
            isLoading = false
            loadingMessage = nil
            errorMessage = "Invalid token"
            errorDetails = "Token rejected. Make sure you're using the exact token from the ORCA MC .env file."
            showError = true
            UserDefaults.standard.removeObject(forKey: "orca_auth_token")
            print("[AppState] performAuth: invalid token, error shown")
        }
    }

    /// Tests if the ORCA MC backend is reachable. 5 second timeout. Public for diagnostics.
    /// Uses /health — confirmed working without auth. Also checks /api/v1/ (returns 404 but proves API is up).
    func checkBackendReachable() async -> Bool {
        print("[AppState] checkBackendReachable: trying \(Self.backendURL)/health")
        if await pingEndpoint("\(Self.backendURL)/health") {
            print("[AppState] checkBackendReachable: /health → reachable!")
            return true
        }
        // Fallback: try /api/v1/ — 404 means API is running, which is "reachable"
        if await pingEndpoint("\(Self.backendURL)/api/v1/") {
            print("[AppState] checkBackendReachable: /api/v1/ → reachable!")
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
        request.timeoutInterval = 3
        print("[AppState] pingEndpoint: \(urlString)")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
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
        request.setValue(token, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 15
        print("[AppState] verifyTokenDirectly: GET \(url.absoluteString) Bearer=\(token.prefix(8))...")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[AppState] verifyTokenDirectly: status=\(statusCode), body=\(body.prefix(200))")

            if statusCode == 401 {
                print("[AppState] verifyTokenDirectly: TOKEN REJECTED — check if token matches backend LOCAL_AUTH_TOKEN")
                return false
            }
            return statusCode == 200
        } catch {
            print("[AppState] verifyTokenDirectly: ERROR = \(error.localizedDescription)")
            return false
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
        case .chat: selectedTab = .chat
        case .projects: selectedTab = .projects
        case .knowledge: selectedTab = .knowledge
        case .agents: selectedTab = .agents
        case .settings: selectedTab = .dashboard
        }
        navigationState = state
    }

    func navigateTo(_ tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .dashboard: navigationState = .dashboard
        case .chat: navigationState = .chat(channelId: nil)
        case .projects: navigationState = .projects(taskId: nil)
        case .knowledge: navigationState = .knowledge(standardId: nil)
        case .agents: navigationState = .agents(agentId: nil)
        case .wallDisplay: break
        }
    }

    func route(_ action: NotificationAction) {
        switch action {
        case .newMessage(let channelId, _):
            selectedTab = .chat
            navigationState = .chat(channelId: channelId)
        case .taskAssigned(let taskId, _):
            selectedTab = .projects
            navigationState = .projects(taskId: taskId)
        case .approvalRequested(let approvalId, _):
            selectedTab = .dashboard
            pendingApprovalId = approvalId
            showApprovalSheet = true
            navigationState = .dashboard
        case .agentError(agentId: let agentId, error: _):
            selectedTab = .agents
            navigationState = .agents(agentId: agentId)
        case .unknown:
            break
        }
    }

    func logout() {
        authManager.signOut()
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

    private let tokenKey = "orca_auth_token"

    private func storeToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    private func loadStoredToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    private func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        Task { await APIClient.shared.setToken(nil) }
    }
}
