import Foundation

/// The network as a provider sees it. A protocol so provider tests can answer requests with canned bodies and
/// status codes instead of reaching a real server.
public protocol HTTPTransport: Sendable {
    /// Returns the response body and HTTP status code. Throws only when no response arrived at all.
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
}

/// The production transport.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }
}
