import SwiftUI
import Observation

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
    var token: String = "ebe9a0fdfaf9b7674f4e2b9d0149f881d46111730b780d9e508ad94023c03051"
    var isConnecting: Bool = false
    var errorMessage: String?
    var isCompleted: Bool = false
    var userName: String?

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
    private let baseURL = "http://shakas-mac-mini.tail82d30d.ts.net:8000"  // Tailscale URL for physical device (works from anywhere)
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
            guard let url = URL(string: "\(baseURL)/api/v1/users/me") else {
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

            let userResponse = try decoder.decode(UserResponse.self, from: data)

            await MainActor.run {
                self.userName = userResponse.name ?? userResponse.username ?? "Captain"
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

    func complete() {
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
