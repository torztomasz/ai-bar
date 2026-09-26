import Foundation

/// Claude's rate-limit usage, read with the Claude Code OAuth session so the user never signs in twice.
///
/// Token refresh is deliberately left to Claude Code, which refreshes the Keychain item while in use;
/// an expired token surfaces as `ClaudeUsageError.tokenExpired`.
public struct ClaudeUsageProvider: UsageProvider {
    public let id = ProviderID("claude")
    public let displayName = "Claude"
    private let credentials: any CredentialSource
    private let transport: any HTTPTransport
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// The defaults are the production Keychain and network; tests inject fakes.
    public init(
        credentials: any CredentialSource = KeychainCredentialSource(),
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.credentials = credentials
        self.transport = transport
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let token = try await loadToken()
        let body = try await requestUsage(token: token)
        return UsageSnapshot(provider: id, fetchedAt: Date(), windows: try decodeWindows(body))
    }

    /// Any credential failure reads as "not logged in": it is the one thing the user can act on.
    private func loadToken() async throws -> String {
        do {
            return try await credentials.accessToken()
        } catch {
            throw ClaudeUsageError.notLoggedIn
        }
    }

    private func requestUsage(token: String) async throws -> Data {
        let response: (body: Data, status: Int)
        do {
            response = try await transport.get(Self.usageURL, headers: [
                "Authorization": "Bearer \(token)",
                // The beta flag opts OAuth tokens into this endpoint.
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
            ])
        } catch {
            throw ClaudeUsageError.network(error)
        }
        switch response.status {
        case 200..<300: return response.body
        case 401: throw ClaudeUsageError.tokenExpired
        default: throw ClaudeUsageError.http(status: response.status)
        }
    }

    private func decodeWindows(_ body: Data) throws -> [UsageWindow] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(ClaudeUsageResponse.self, from: body).windows
        } catch {
            throw ClaudeUsageError.decoding(error)
        }
    }
}

/// Why Claude usage could not be fetched, phrased for the popover since the app shows `errorDescription` as is.
/// Underlying errors are kept for diagnostics, not for display.
public enum ClaudeUsageError: Error, LocalizedError {
    /// No Claude Code credentials in the Keychain, or they could not be read.
    case notLoggedIn
    case tokenExpired
    case network(any Error)
    case http(status: Int)
    case decoding(any Error)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Sign in to Claude Code to see usage."
        case .tokenExpired: "Your Claude Code session expired. Open Claude Code to renew it."
        case .network: "Can't reach Claude. Check your internet connection."
        case .http(let status): "Claude usage is unavailable right now (HTTP \(status)). AI Bar will try again."
        case .decoding: "AI Bar can't read Claude's usage data. Update AI Bar to see usage."
        }
    }
}
