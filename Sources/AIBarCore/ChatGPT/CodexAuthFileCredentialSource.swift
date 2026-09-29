import Foundation

/// Reads the ChatGPT session the Codex CLI keeps in `auth.json` in its home directory (`~/.codex` unless
/// `CODEX_HOME` says otherwise).
///
/// A Codex set up to keep its credentials in the Keychain leaves no file and reads as not logged in.
/// The token is returned only to the caller; it is never logged or persisted.
public struct CodexAuthFileCredentialSource: ChatGPTCredentialSource {
    private let fileURL: URL

    /// The shape of Codex's auth file, reduced to what the app needs.
    private struct StoredAuth: Decodable {
        let tokens: Tokens?

        struct Tokens: Decodable {
            let accessToken: String?
            let accountId: String?
        }
    }

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let home = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL.homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
        fileURL = home.appending(path: "auth.json", directoryHint: .notDirectory)
    }

    public func credentials() async throws -> ChatGPTCredentials {
        guard let data = try? Data(contentsOf: fileURL) else { throw ChatGPTUsageError.notLoggedIn }
        return try Self.credentials(fromAuthJSON: data)
    }

    static func credentials(fromAuthJSON data: Data) throws -> ChatGPTCredentials {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let tokens = (try? decoder.decode(StoredAuth.self, from: data))?.tokens,
              let accessToken = tokens.accessToken, !accessToken.isEmpty,
              let accountID = tokens.accountId, !accountID.isEmpty
        else { throw ChatGPTUsageError.notLoggedIn }
        return ChatGPTCredentials(accessToken: accessToken, accountID: accountID)
    }
}
