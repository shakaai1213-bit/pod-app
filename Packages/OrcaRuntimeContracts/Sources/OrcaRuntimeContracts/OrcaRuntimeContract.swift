import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public enum OrcaRuntimeContract: Sendable {
    public static let version = "orca.chat-runtime.v1"
    public static let schemaSHA256 = "40a298668534e87d47abc42279d4777334e1e2c9ae92dc6e291818a8a76cfbeb"

    public static func makeClient(
        serverURL: URL,
        middlewares: [any ClientMiddleware] = [],
        session: URLSession = OrcaSecureURLSession.make()
    ) -> Client {
        Client(
            serverURL: serverURL,
            configuration: .init(dateTranscoder: OrcaAPIDateTranscoder()),
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: middlewares
        )
    }
}

struct OrcaAPIDateTranscoder: DateTranscoder {
    private let standard = ISO8601DateTranscoder()
    private let fractional = ISO8601DateTranscoder(
        options: [.withInternetDateTime, .withFractionalSeconds]
    )

    func encode(_ date: Date) throws -> String {
        try fractional.encode(date)
    }

    func decode(_ value: String) throws -> Date {
        do {
            return try fractional.decode(value)
        } catch {
            do {
                return try standard.decode(value)
            } catch {
                guard value.range(
                    of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?$"#,
                    options: .regularExpression
                ) != nil else {
                    throw error
                }
                let assumedUTC = "\(value)Z"
                if value.contains(".") {
                    return try fractional.decode(assumedUTC)
                }
                return try standard.decode(assumedUTC)
            }
        }
    }
}

private final class OrcaRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(OrcaRedirectPolicy.followedRequest(for: response, proposed: request))
    }
}

public enum OrcaRedirectPolicy {
    public static func followedRequest(
        for response: HTTPURLResponse,
        proposed request: URLRequest
    ) -> URLRequest? {
        guard (300...399).contains(response.statusCode) else { return request }
        return nil
    }
}

public enum OrcaSecureURLSession {
    public static func make(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        URLSession(configuration: configuration, delegate: OrcaRedirectBlocker(), delegateQueue: nil)
    }

    public static func responseStayedOnOrigin(_ response: URLResponse, requestURL: URL) -> Bool {
        guard let finalURL = response.url else { return false }
        return normalizedOrigin(finalURL) == normalizedOrigin(requestURL)
    }

    private static func normalizedOrigin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
