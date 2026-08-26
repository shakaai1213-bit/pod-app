import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public enum OrcaRuntimeContract: Sendable {
    public static let version = "orca.chat-runtime.v1"
    public static let schemaSHA256 = "ebeef707c500a880d15340016b6e03b772c0016d76d192491c6dabb630a1fc28"

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
            return try standard.decode(value)
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
