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

    private func loadToken() async throws -> String {
        do {
            return try await credentials.accessToken()
        } catch {
            throw ClaudeUsageError.notLoggedIn
        }
    }

    private func requestUsage(token: String) async throws -> Data {
        let (body, status) = try await transport.get(Self.usageURL, headers: [
            "Authorization": "Bearer \(token)",
            // The usage endpoint rejects OAuth tokens without this beta flag.
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
        ])
        switch status {
        case 200..<300: return body
        case 401: throw ClaudeUsageError.tokenExpired
        default: throw ClaudeUsageError.http(status: status)
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

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
}

/// Where the Claude OAuth access token comes from. A protocol so tests need no Keychain.
public protocol CredentialSource: Sendable {
    func accessToken() async throws -> String
}

/// Why Claude usage could not be fetched, phrased for the popover since the app shows `errorDescription` as is.
public enum ClaudeUsageError: Error, LocalizedError {
    /// No Claude Code credentials in the Keychain, or they could not be read.
    case notLoggedIn
    /// The server answered 401: the stored token is no longer valid.
    case tokenExpired
    case http(status: Int)
    case decoding(any Error)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Sign in to Claude Code to see usage."
        case .tokenExpired: "Your Claude Code session expired. Open Claude Code to renew it."
        case .http(let status): "Claude usage is unavailable right now (HTTP \(status))."
        case .decoding: "Claude sent usage data AI Bar cannot read."
        }
    }
}
