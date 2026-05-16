import SwiftUI
import Observation
import AuthenticationServices

// MARK: - OnboardingPage

enum OnboardingPage: Int, CaseIterable {
    case welcome = 0
    case features = 1
    case connect = 2
    case ready = 3

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .features: return "Features"
        case .connect: return "Connect"
        case .ready: return "Ready"
        }
    }
}

// MARK: - OnboardingViewModel

@Observable
final class OnboardingViewModel {

    // MARK: - Published State

    var currentPage: Int = 0
    // SEC-007 remediation 2026-05-08: sourced from OrcaSecrets.swift (gitignored)
    // instead of hardcoded literal.
    var token: String = OrcaSecrets.bearerToken
    var isConnecting: Bool = false
    var errorMessage: String?
    var isCompleted: Bool = false
    var userName: String?
    var isDemoMode: Bool = false

    // MARK: - Computed

    var canProceed: Bool {
        switch currentPage {
        case 0, 1: return true
        case 2: return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isConnecting
        case 3: return true
        default: return false
        }
    }

    var totalPages: Int { 4 }

    var isFirstPage: Bool { currentPage == 0 }
    var isLastPage: Bool { currentPage == totalPages - 1 }

    // MARK: - ORCA MC Config

    #if targetEnvironment(simulator)
    private let baseURL = "http://127.0.0.1:19002"  // Proxy for simulator (port 19002)
    #else
    private let baseURL = "http://100.76.196.40:8000"  // Tailscale direct IP for physical device
    #endif

    // MARK: - Navigation

    func nextPage() {
        guard canProceed else { return }
        if currentPage < totalPages - 1 {
            currentPage += 1
        }
    }

    func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
        }
    }

    func goToPage(_ page: Int) {
        guard page >= 0 && page < totalPages else { return }
        currentPage = page
    }

    // MARK: - Token Connection

    func connect() async -> Bool {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            errorMessage = "Please enter a token."
            return false
        }

        await MainActor.run {
            isConnecting = true
            errorMessage = nil
        }

        do {
            guard let url = URL(string: "\(baseURL)/api/v1/agents") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ConnectionError.unauthorized
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let agentsResponse = try decoder.decode(PaginatedResponse<AgentDTO>.self, from: data)
            let preferredName = agentsResponse.items.first?.name ?? "ORCA Agent"

            await MainActor.run {
                self.userName = preferredName
                self.isConnecting = false
                self.errorMessage = nil
                self.currentPage = OnboardingPage.ready.rawValue
            }

            return true

        } catch let error as ConnectionError {
            await MainActor.run {
                self.isConnecting = false
                switch error {
                case .unauthorized:
                    self.errorMessage = "Invalid token. Please check and try again."
                }
            }
            return false
        } catch {
            await MainActor.run {
                self.isConnecting = false
                self.errorMessage = "Connection failed. Check your network and try again."
            }
            return false
        }
    }

    // MARK: - Sign in with Apple
    //
    // Calls SIWASignInService → backend `/api/v1/auth/apple/callback` →
    // stores returned access/refresh token pair in Keychain via TokenManager
    // and sets it as the active token on APIClient. Then fetches the user's
    // first agent to populate userName, and advances to the Ready page.

    @MainActor
    func signInWithApple() async {
        isConnecting = true
        errorMessage = nil

        defer { isConnecting = false }

        let service = SIWASignInService(
            tokenManager: TokenManager(),
            apiClient: APIClient.shared
        )

        do {
            let stored = try await service.signIn()
            // Make subsequent authenticated calls work
            await APIClient.shared.setToken(stored.accessToken)

            // Fetch user's name from /api/v1/agents (same shape as token-path)
            let preferredName = await fetchPreferredName(token: stored.accessToken)
            self.userName = preferredName ?? "Captain"
            self.currentPage = OnboardingPage.ready.rawValue
        } catch SIWASignInError.userCancelled {
            // No-op — user backed out of the Apple sheet
        } catch let err as SIWASignInError {
            self.errorMessage = err.errorDescription ?? "Sign in failed."
        } catch {
            self.errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
    }

    private func fetchPreferredName(token: String) async -> String? {
        guard let url = URL(string: "\(baseURL)/api/v1/agents") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let agents = try decoder.decode(PaginatedResponse<AgentDTO>.self, from: data)
            return agents.items.first?.name
        } catch {
            return nil
        }
    }

    func complete() {
        isCompleted = true
    }

    /// Enter demo mode - bypass auth and use the app with mock data
    func enterDemoMode() {
        isDemoMode = true
        isCompleted = true
    }
}

// MARK: - Connection Error

enum ConnectionError: Error {
    case unauthorized
}

// MARK: - User Response

struct UserResponse: Codable {
    let id: String?
    let name: String?
    let username: String?
    let email: String?
}
