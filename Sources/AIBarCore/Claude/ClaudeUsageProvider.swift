import Foundation

/// Claude's rate-limit usage, read with the Claude Code OAuth session so the user never signs in twice.
public struct ClaudeUsageProvider: UsageProvider {
    public let id = ProviderID("claude")
    public let displayName = "Claude"
    private let credentials: any CredentialSource
    private let transport: any HTTPTransport

    public init(credentials: any CredentialSource, transport: any HTTPTransport) {
        self.credentials = credentials
        self.transport = transport
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let token = try await credentials.accessToken()
        let (body, _) = try await transport.get(URL(string: "https://api.anthropic.com/api/oauth/usage")!, headers: [
            "Authorization": "Bearer \(token)",
        ])
        let response = try JSONDecoder.snakeCase.decode(ClaudeUsageResponse.self, from: body)
        return UsageSnapshot(provider: id, fetchedAt: Date(), windows: response.windows)
    }
}

/// Where the Claude OAuth access token comes from. A protocol so tests need no Keychain.
public protocol CredentialSource: Sendable {
    func accessToken() async throws -> String
}

extension JSONDecoder {
    fileprivate static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
