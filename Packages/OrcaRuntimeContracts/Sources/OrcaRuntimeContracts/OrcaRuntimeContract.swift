import Foundation
import OpenAPIURLSession

public enum OrcaRuntimeContract: Sendable {
    public static let version = "orca.chat-runtime.v1"
    public static let schemaSHA256 = "7e867ff94398b39827dd2bc210505266f0dd08ea0892e28fa19128e392cfe74f"

    public static func makeClient(serverURL: URL) -> Client {
        Client(
            serverURL: serverURL,
            transport: URLSessionTransport()
        )
    }
}
