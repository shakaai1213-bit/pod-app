import Foundation

// MARK: - Supporting Types

struct AuthResponse: Codable {
    let token: String
    let userId: String?
    let expiresAt: Date?
}

struct APIError: Error {
    let code: Int
    let message: String
    
    static let unknown = APIError(code: 0, message: "Unknown error")
    static let unauthorized = APIError(code: 401, message: "Unauthorized")
    static let serverError = APIError(code: 500, message: "Server error")
    static let decodingError = APIError(code: 0, message: "Decoding error")
    
    static func message(_ msg: String, code: Int?) -> APIError {
        APIError(code: code ?? 0, message: msg)
    }
}

struct EmptyResponse: Codable {}

// MARK: - API Client

actor APIClient {
    static let shared = APIClient()

    // Physical device: use Tailscale URL (shakas-mac-mini.tail82d30d.ts.net:8000) — works from anywhere
    // Simulator: use proxy (127.0.0.1:19002 → 192.168.4.243:8000)
    #if targetEnvironment(simulator)
    private let baseURL = "http://127.0.0.1:19002"
    #else
    private let baseURL = "http://shakas-mac-mini.tail82d30d.ts.net:8000"
    #endif
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var authToken: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Auth

    func setToken(_ token: String?) {
        self.authToken = token
    }

    /// Atomically sets the token and verifies it by fetching agents.
    /// Returns true if the token is valid, false otherwise.
    func verifyAndSetToken(_ token: String) async -> Bool {
        self.authToken = token
        do {
            // Try multiple endpoints to verify token
            let _: PaginatedResponse<AgentDTO> = try await request(.agents)
            return true
        } catch let error as APIError {
            print("[APIClient] verifyAndSetToken FAILED: code=\(error.code) msg=\(error.message)")
            return false
        } catch {
            print("[APIClient] verifyAndSetToken FAILED: \(error)")
            return false
        }
    }

    func login(token: String) async throws -> AuthResponse {
        let endpoint = "\(baseURL)/api/v1/auth/login"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Key")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        self.authToken = token
        return try decoder.decode(AuthResponse.self, from: data)
    }

    // MARK: - Generic Request

    func buildRequest(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        var components = URLComponents(string: "\(baseURL)\(path)")
        if let queryItems = queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw APIError(code: 0, message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Read token directly from actor state at request-build time
        let currentToken = self.authToken
        if let token = currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Api-Key")
        }

        if let body = body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 500...599:
            throw APIError.serverError
        default:
            throw APIError(code: httpResponse.statusCode, message: "Request failed with status \(httpResponse.statusCode)")
        }
    }

    // MARK: - Public API Methods

    func get<T: Decodable>(path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "GET")
        return try await perform(request)
    }

    func post<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        let request = try buildRequest(path: path, method: "POST", body: AnyEncodable(body))
        return try await perform(request)
    }

    func put<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        let request = try buildRequest(path: path, method: "PUT", body: AnyEncodable(body))
        return try await perform(request)
    }

    func patch<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        let request = try buildRequest(path: path, method: "PATCH", body: AnyEncodable(body))
        return try await perform(request)
    }

    func delete(path: String) async throws {
        let request = try buildRequest(path: path, method: "DELETE")
        let _: EmptyResponse = try await perform(request)
    }

    func postVoid(path: String, body: some Encodable) async throws {
        let request = try buildRequest(path: path, method: "POST", body: AnyEncodable(body))
        let _: EmptyResponse = try await perform(request)
    }

    func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "<\(data.count) bytes>"
            throw APIError(code: 0, message: "Decoding failed: \(error) | Response: \(body)")
        }
    }
}

// MARK: - AnyEncodable Helper

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ value: some Encodable) {
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
