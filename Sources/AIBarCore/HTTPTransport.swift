import Foundation

/// The network as a provider sees it. A protocol so provider tests can answer requests with canned bodies and
/// status codes instead of reaching a real server.
public protocol HTTPTransport: Sendable {
    /// Throws only when no response arrived at all; error statuses are returned for the provider to interpret.
    func get(_ url: URL, headers: [String: String]) async throws -> (body: Data, status: Int)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func get(_ url: URL, headers: [String: String]) async throws -> (body: Data, status: Int) {
        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }
}
