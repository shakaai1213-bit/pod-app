import Foundation
import SwiftUI

// MARK: - Team Member

struct TeamMember: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var email: String?
    var role: String?
    var avatarColor: String?

    init(id: UUID = UUID(), name: String, email: String? = nil, role: String? = nil, avatarColor: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.avatarColor = avatarColor
    }
}

@Observable
final class AppState {
    // MARK: - Authentication
    var isAuthenticated: Bool = false
    var currentUser: TeamMember?

    // MARK: - Navigation
    var selectedTab: Int = 0

    // MARK: - Loading State
    var isLoading: Bool = false
    var loadingMessage: String?

    // MARK: - Error Handling
    var errorMessage: String?
    var errorDetails: String?
    var showError: Bool = false

    // MARK: - Token Storage Key
    private let tokenKey = "orca_auth_token"

    // MARK: - Initialization

    init() {
        // Don't auto-load stored token — always require explicit login to avoid stale token issues
    }

    // MARK: - Token Management

    private func loadStoredToken() {
        if let token = UserDefaults.standard.string(forKey: tokenKey) {
            Task { @MainActor in
                await self.authenticate(token: token)
            }
        }
    }

    private func storeToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        Task { await APIClient.shared.setToken(nil) }
    }

    // MARK: - Authentication

    func authenticate(token: String) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            loadingMessage = "Connecting..."
        }

        // Step 1: Can we reach the backend at all? (no auth needed)
        let reachable = await checkBackendReachable()
        guard reachable else {
            await MainActor.run {
                self.isAuthenticated = false
                self.isLoading = false
                self.loadingMessage = nil
                self.showError(
                    message: "Cannot reach ORCA MC",
                    details: "Check your network connection to the Mac Mini at 192.168.4.243."
                )
            }
            return
        }

        await MainActor.run {
            loadingMessage = "Verifying token..."
        }

        // Atomically set token and verify in one actor call
        let valid = await APIClient.shared.verifyAndSetToken(token)
        await MainActor.run {
            if valid {
                await APIClient.shared.setToken(token)
                self.isAuthenticated = true
                self.currentUser = TeamMember(id: UUID(), name: "User")
                self.isLoading = false
                self.loadingMessage = nil
                self.storeToken(token)
            } else {
                self.isAuthenticated = false
                self.isLoading = false
                self.loadingMessage = nil
                self.showError(
                    message: "Invalid token",
                    details: "Token rejected. Make sure you're using the exact token from the ORCA MC .env file (LOCAL_AUTH_TOKEN)."
                )
            }
        }
    }

    /// Tests if ORCA MC backend is reachable from this device.
    private func checkBackendReachable() async -> Bool {
        guard let url = URL(string: "http://192.168.4.243:8000/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Verifies token by making a direct URLSession call with no actor overhead.
    private func verifyTokenDirectly(_ token: String) async -> Bool {
        guard let url = URL(string: "http://192.168.4.243:8000/api/v1/agents") else { return false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            print("[AppState] verifyTokenDirectly: status=\(httpResponse.statusCode) data=\(String(data: data.prefix(100), encoding: .utf8) ?? "")")
            return httpResponse.statusCode == 200
        } catch {
            print("[AppState] verifyTokenDirectly ERROR: \(error)")
            return false
        }
    }

    func logout() {
        clearToken()
        isAuthenticated = false
        currentUser = nil
        selectedTab = 0
    }

    // MARK: - Error Handling

    func showError(message: String, details: String? = nil) {
        errorMessage = message
        errorDetails = details
        showError = true
    }

    func dismissError() {
        errorMessage = nil
        errorDetails = nil
        showError = false
    }

    // MARK: - Loading Overlay

    func withLoading<T>(
        message: String = "Loading...",
        operation: () async throws -> T
    ) async throws -> T {
        await MainActor.run {
            isLoading = true
            loadingMessage = message
        }
        defer {
            Task { @MainActor in
                isLoading = false
                loadingMessage = nil
            }
        }
        return try await operation()
    }
}

// MARK: - Tab Definition

enum AppTab: Int, CaseIterable, Identifiable {
    case dashboard = 0
    case projects
    case chat
    case knowledge
    case agents

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .projects: return "Projects"
        case .chat:     return "Chat"
        case .knowledge: return "Knowledge"
        case .agents:   return "Agents"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
        case .projects:  return "rectangle.3.group"
        case .chat:      return "bubble.left.and.bubble.right"
        case .knowledge: return "books.vertical"
        case .agents:    return "cpu"
        }
    }

    var accentColor: Color {
        switch self {
        case .dashboard: return AppTheme.electricBlue
        case .projects:  return AppTheme.electricPurple
        case .chat:      return AppTheme.electricGreen
        case .knowledge: return AppTheme.electricOrange
        case .agents:    return AppTheme.primaryAccent
        }
    }
}
