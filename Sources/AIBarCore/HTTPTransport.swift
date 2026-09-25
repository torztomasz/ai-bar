import Foundation

/// The network as a provider sees it. A protocol so provider tests can answer requests with canned bodies and
/// status codes instead of reaching a real server.
public protocol HTTPTransport: Sendable {
    /// Returns the response body and HTTP status code. Throws only when no response arrived at all.
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
}
