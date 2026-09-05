import Foundation

public enum OrcaEndpointPolicy {
    public static let productionOrigin = "http://100.104.72.62:8000"
    public static let simulatorOrigin = "http://127.0.0.1:19002"
    public static let production = productionOrigin

    public static var defaultAllowsLoopback: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    public static func normalizedOrigin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return nil
        }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    public static func normalized(_ url: URL) -> String? {
        normalizedOrigin(url)
    }

    public static func isApproved(
        _ url: URL,
        allowLoopback: Bool = defaultAllowsLoopback
    ) -> Bool {
        guard let origin = normalizedOrigin(url) else { return false }
        if origin == productionOrigin { return true }
        guard allowLoopback, url.scheme?.lowercased() == "http" else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "")
    }

    public static func normalizedEndpoint(
        _ raw: String,
        allowLoopback: Bool = defaultAllowsLoopback
    ) -> URL? {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if !normalized.contains("://") { normalized = "http://\(normalized)" }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              isApproved(url, allowLoopback: allowLoopback) else {
            return nil
        }
        return url
    }

    public static func responseStayedOnOrigin(_ response: URLResponse, requestURL: URL) -> Bool {
        guard let finalURL = response.url else { return false }
        return normalizedOrigin(finalURL) == normalizedOrigin(requestURL)
    }
}
