import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public enum OrcaRuntimeContract: Sendable {
    public static let version = "orca.chat-runtime.v1"
    public static let schemaSHA256 = "d117c8a422aae28bc0314a62717d89524627d251684e55c1bb66be64eb138223"

    public static func makeClient(
        serverURL: URL,
        middlewares: [any ClientMiddleware] = [],
        session: URLSession = OrcaSecureURLSession.make()
    ) -> Client {
        Client(
            serverURL: serverURL,
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: middlewares
        )
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
