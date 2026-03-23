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

    static let backendURL = "http://192.168.4.243:8000"

    // MARK: - Initialization

    nonisolated init() {}

    // MARK: - Authentication

    func authenticate(token: String) async {
        isLoading = true
        errorMessage = nil
        errorDetails = nil
        loadingMessage = "Connecting..."

        // Check if backend is reachable (5 second timeout)
        let reachable = await checkBackendReachable()
        if !reachable {
            isAuthenticated = false
            isLoading = false
            loadingMessage = nil
            errorMessage = "Cannot reach ORCA MC"
            errorDetails = "Check your network connection to the Mac Mini."
            showError = true
            return
        }

        loadingMessage = "Verifying token..."

        // Verify token with direct URLSession (10 second timeout)
        let valid = await verifyTokenDirectly(token)
        if valid {
            isAuthenticated = true
            currentUser = TeamMember(id: UUID(), name: "User", avatarColor: "#6B46C1")
            isLoading = false
            loadingMessage = nil
            storeToken(token)
            Task { await APIClient.shared.setToken(token) }
        } else {
            isAuthenticated = false
            isLoading = false
            loadingMessage = nil
            errorMessage = "Invalid token"
            errorDetails = "Token rejected. Make sure you're using the exact token from the ORCA MC .env file."
            showError = true
        }
    }

    /// Tests if the ORCA MC backend is reachable. 5 second timeout.
    private func checkBackendReachable() async -> Bool {
        guard let url = URL(string: "\(Self.backendURL)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Verifies token by fetching agents. 10 second timeout.
    private func verifyTokenDirectly(_ token: String) async -> Bool {
        guard let url = URL(string: "\(Self.backendURL)/api/v1/agents") else { return false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
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
        case .agentError(let agentId):
            selectedTab = .agents
            navigationState = .agents(agentId: agentId)
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
