import Foundation

// MARK: - Supporting Types

struct AuthResponse: Codable {
    let token: String
    let userId: String?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
        case expiresAt = "expires_at"
    }
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

    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let keychainTokenProvider: @Sendable () async -> String?
    private let keychainAgentTokenProvider: @Sendable () async -> String?

    private var authToken: String?
    private var agentToken: String?

    init(
        baseURL: String = AppConfig.backendURL,
        session: URLSession? = nil,
        keychainTokenProvider: @escaping @Sendable () async -> String? = {
            let tokenManager = TokenManager()
            do {
                return try tokenManager.getActiveToken()?.token.accessToken
            } catch {
                return nil
            }
        },
        keychainAgentTokenProvider: @escaping @Sendable () async -> String? = {
            let tokenManager = AgentTokenManager()
            do {
                return try tokenManager.getToken()
            } catch {
                return nil
            }
        }
    ) {
        self.baseURL = baseURL
        self.keychainTokenProvider = keychainTokenProvider
        self.keychainAgentTokenProvider = keychainAgentTokenProvider
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            try Self.decodeORCADate(from: decoder)
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Auth

    func setToken(_ token: String?) {
        self.authToken = token
    }

    func setAgentToken(_ token: String?) {
        self.agentToken = token
    }

    func currentToken() async -> String? {
        if let authToken { return authToken }
        return await keychainTokenProvider()
    }

    func currentAgentToken() async -> String? {
        if let agentToken { return agentToken }
        return await keychainAgentTokenProvider()
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
        request.setValue(OrcaDeviceIdentity.current(), forHTTPHeaderField: "X-ORCA-Device-ID")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        self.authToken = token
        return try decoder.decode(AuthResponse.self, from: data)
    }

    // MARK: - Generic Request

    func buildRequest(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil,
        includeAgentToken: Bool = false
    ) async throws -> URLRequest {
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

        if includeAgentToken {
            // Strict agent routes receive only the named-agent credential.
            let currentAgentToken: String?
            if let agentToken = self.agentToken {
                currentAgentToken = agentToken
            } else {
                currentAgentToken = await keychainAgentTokenProvider()
            }
            if let token = currentAgentToken {
                request.setValue(token, forHTTPHeaderField: "X-Agent-Token")
            }
        } else {
            // Persisted bearer credentials come only from Keychain via TokenManager.
            let currentToken: String?
            if let authToken = self.authToken {
                currentToken = authToken
            } else {
                currentToken = await keychainTokenProvider()
            }
            if let token = currentToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue(OrcaDeviceIdentity.current(), forHTTPHeaderField: "X-ORCA-Device-ID")
            }
        }

        if let body = body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        guard !(200...299).contains(httpResponse.statusCode) else { return }
        let fallback: String
        switch httpResponse.statusCode {
        case 401: fallback = APIError.unauthorized.message
        case 500...599: fallback = APIError.serverError.message
        default: fallback = "Request failed with status \(httpResponse.statusCode)"
        }
        throw APIError(
            code: httpResponse.statusCode,
            message: Self.serverErrorMessage(from: data) ?? fallback
        )
    }

    static func serverErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["detail", "message", "error"] {
                if let value = object[key] as? String, !value.isEmpty { return value }
            }
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty {
                return message
            }
        }
        let text = String(data: data.prefix(500), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    // MARK: - Public API Methods

    func get<T: Decodable>(path: String, includeAgentToken: Bool = false) async throws -> T {
        let request = try await buildRequest(path: path, method: "GET", includeAgentToken: includeAgentToken)
        return try await perform(request)
    }

    func post<T: Decodable>(path: String, body: some Encodable, includeAgentToken: Bool = false) async throws -> T {
        let request = try await buildRequest(path: path, method: "POST", body: AnyEncodable(body), includeAgentToken: includeAgentToken)
        return try await perform(request)
    }

    /// POST without injecting an Authorization header. Used by
    /// the SIWA exchange flow (`/auth/apple/callback`) which is the very
    /// call that mints the bearer token, so it must run unauthenticated.
    func unauthenticatedPost<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        let components = URLComponents(string: "\(baseURL)\(path)")
        guard let url = components?.url else {
            throw APIError(code: 0, message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(AnyEncodable(body))

        return try await perform(request)
    }

    func put<T: Decodable>(path: String, body: some Encodable, includeAgentToken: Bool = false) async throws -> T {
        let request = try await buildRequest(path: path, method: "PUT", body: AnyEncodable(body), includeAgentToken: includeAgentToken)
        return try await perform(request)
    }

    func patch<T: Decodable>(path: String, body: some Encodable, includeAgentToken: Bool = false) async throws -> T {
        let request = try await buildRequest(path: path, method: "PATCH", body: AnyEncodable(body), includeAgentToken: includeAgentToken)
        return try await perform(request)
    }

    func delete(path: String) async throws {
        let request = try await buildRequest(path: path, method: "DELETE")
        let _: EmptyResponse = try await perform(request)
    }

    func postVoid(path: String, body: some Encodable) async throws {
        let request = try await buildRequest(path: path, method: "POST", body: AnyEncodable(body))
        let _: EmptyResponse = try await perform(request)
    }

    func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        if data.isEmpty, T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "<\(data.count) bytes>"
            throw APIError(code: 0, message: "Decoding failed: \(error) | Response: \(body)")
        }
    }

    private static func decodeORCADate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let isoWithTimezone = ISO8601DateFormatter()
        isoWithTimezone.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithTimezone.date(from: value) {
            return date
        }

        let isoWithoutFraction = ISO8601DateFormatter()
        isoWithoutFraction.formatOptions = [.withInternetDateTime]
        if let date = isoWithoutFraction.date(from: value) {
            return date
        }

        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ORCA date: \(value)"
        )
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
