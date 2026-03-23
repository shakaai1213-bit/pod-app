import Foundation
import SwiftUI

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
        loadStoredToken()
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
        APIClient.shared.setToken(nil)
    }

    // MARK: - Authentication

    func authenticate(token: String) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            loadingMessage = "Authenticating..."
        }

        do {
            let response = try await APIClient.shared.login(token: token)
            await MainActor.run {
                self.isAuthenticated = true
                self.currentUser = response.user
                self.isLoading = false
                self.loadingMessage = nil
                self.storeToken(token)
            }
        } catch let error as APIError {
            await MainActor.run {
                self.isAuthenticated = false
                self.currentUser = nil
                self.isLoading = false
                self.loadingMessage = nil
                self.showError(message: error.message, details: error.localizedDescription)
            }
        } catch {
            await MainActor.run {
                self.isAuthenticated = false
                self.currentUser = nil
                self.isLoading = false
                self.loadingMessage = nil
                self.showError(message: "Authentication failed", details: error.localizedDescription)
            }
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
        case .dashboard: return Theme.electricBlue
        case .projects:  return Theme.electricPurple
        case .chat:      return Theme.electricGreen
        case .knowledge: return Theme.electricOrange
        case .agents:    return Theme.primaryAccent
        }
    }
}
