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

    // MARK: - Backend URL

    // iOS Simulator → proxy at 127.0.0.1:19002 → Docker backend
    // Real device (iPad) → Mac Mini Tailscale IP (both on Tailscale VPN)
    // Simulator: use proxy (e.g. 127.0.0.1:19002 → 192.168.4.243:8000)
    static let backendURL = "http://192.168.4.243:8000"

    // MARK: - Initialization

    nonisolated init() {}

    // MARK: - Authentication

    func authenticate(token: String) async {
        print("[AppState] authenticate() called with token: \(token.prefix(8))...")
        isLoading = true
        errorMessage = nil
        errorDetails = nil
        loadingMessage = "Connecting..."

        // Run auth with a reliable 10-second timeout.
        // Uses DispatchSemaphore as clock source — avoids iOS 26 Task.sleep bug.
        let authTask = Task { @MainActor in
            await performAuth(token: token)
        }

        // Reliable timeout: fires after 10 seconds, works on iOS 26
        let timedOut = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                let semaphore = DispatchSemaphore(value: 0)
                DispatchQueue.global().async { semaphore.signal() }
                _ = semaphore.wait(timeout: .now() + 10)
                continuation.resume(returning: true)
            }
        }

        if timedOut && !Task.isCancelled {
            print("[AppState] Auth timed out after 10s")
            authTask.cancel()
            isLoading = false
            loadingMessage = nil
            if !isAuthenticated {
                errorMessage = "Connection timed out"
                errorDetails = "The request took too long. Check your network and try again."
                showError = true
                UserDefaults.standard.removeObject(forKey: "orca_auth_token")
            }
        }
    }

    /// Actual auth logic — called inside the timeout wrapper.
    /// All state mutations are @MainActor by virtue of the class being @MainActor.
    private func performAuth(token: String) async {
        print("[AppState] performAuth: calling checkBackendReachable()")
        let reachable = await checkBackendReachable()
        print("[AppState] performAuth: checkBackendReachable() = \(reachable)")

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
        print("[AppState] performAuth: backend reachable, verifying token")
        let valid = await verifyTokenDirectly(token)
        print("[AppState] performAuth: verifyTokenDirectly() = \(valid)")

        if valid {
            print("[AppState] performAuth: SUCCESS")
            // Set both at once — no delay, avoids SwiftUI render timing issues
            isLoading = false
            loadingMessage = nil
            isAuthenticated = true
            currentUser = TeamMember(id: UUID(), name: "User", avatarColor: "#6B46C1")
            storeToken(token)
            Task { await APIClient.shared.setToken(token) }
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
    /// Uses /api/v1/health — the iPad confirmed this endpoint responds (even 404 is fine).
    func checkBackendReachable() async -> Bool {
        // Try /health first (confirmed working from iPad via Safari)
        if await pingEndpoint("\(Self.backendURL)/health") {
            return true
        }
        // Fallback: try /api/v1/health
        if await pingEndpoint("\(Self.backendURL)/api/v1/health") {
            return true
        }
        // Last resort: try /api/v1/agents with no auth
        if await pingEndpoint("\(Self.backendURL)/api/v1/agents") {
            return true
        }
        return false
    }

    /// Makes a HEAD request to check if an endpoint is reachable.
    /// Any HTTP response (even 404/401) = reachable. Network error = unreachable.
    private func pingEndpoint(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else {
            print("[AppState] pingEndpoint: invalid URL: \(urlString)")
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
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
        request.timeoutInterval = 5
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
