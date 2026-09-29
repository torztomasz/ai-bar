import Foundation

/// ChatGPT's rate-limit usage as Codex counts it, read with the session the Codex CLI already has so the user never
/// signs in twice.
///
/// Token refresh is deliberately left to Codex, which renews its auth file while in use; an expired token surfaces
/// as `ChatGPTUsageError.tokenExpired`.
public struct ChatGPTUsageProvider: UsageProvider {
    public static let providerID = ProviderID("chatgpt")
    public let id = ChatGPTUsageProvider.providerID
    public let displayName = "ChatGPT"
    private let credentials: any ChatGPTCredentialSource
    private let transport: any HTTPTransport
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// The defaults are Codex's auth file and the network; tests inject fakes.
    public init(
        credentials: any ChatGPTCredentialSource = CodexAuthFileCredentialSource(),
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.credentials = credentials
        self.transport = transport
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let session = try await loadSession()
        let body = try await requestUsage(session: session)
        return UsageSnapshot(provider: id, fetchedAt: Date(), windows: try decodeWindows(body))
    }

    /// Any credential failure reads as "not logged in": it is the one thing the user can act on.
    private func loadSession() async throws -> ChatGPTCredentials {
        do {
            return try await credentials.credentials()
        } catch {
            throw ChatGPTUsageError.notLoggedIn
        }
    }

    private func requestUsage(session: ChatGPTCredentials) async throws -> Data {
        let response: (body: Data, status: Int)
        do {
            response = try await transport.get(Self.usageURL, headers: [
                "Authorization": "Bearer \(session.accessToken)",
                // Usage is counted per workspace, and one login can belong to several.
                "ChatGPT-Account-Id": session.accountID,
                "Accept": "application/json",
            ])
        } catch {
            throw ChatGPTUsageError.network(error)
        }
        switch response.status {
        case 200..<300: return response.body
        case 401: throw ChatGPTUsageError.tokenExpired
        default: throw ChatGPTUsageError.http(status: response.status)
        }
    }

    private func decodeWindows(_ body: Data) throws -> [UsageWindow] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(ChatGPTUsageResponse.self, from: body).windows
        } catch {
            throw ChatGPTUsageError.decoding(error)
        }
    }
}

/// Why ChatGPT usage could not be fetched, phrased for the popover since the app shows `errorDescription` as is.
/// Underlying errors are kept for diagnostics, not for display.
public enum ChatGPTUsageError: Error, LocalizedError {
    /// No Codex auth file, or it holds no ChatGPT session (e.g. Codex is signed in with an API key).
    case notLoggedIn
    case tokenExpired
    case network(any Error)
    case http(status: Int)
    case decoding(any Error)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Sign in to Codex with ChatGPT to see usage."
        case .tokenExpired: "Your Codex session expired. Open Codex to renew it."
        case .network: "Can't reach ChatGPT. Check your internet connection."
        case .http(let status): "ChatGPT usage is unavailable right now (HTTP \(status)). AI Bar will try again."
        case .decoding: "AI Bar can't read ChatGPT's usage data. Update AI Bar to see usage."
        }
    }
}
