/// Where the ChatGPT session comes from. A protocol so tests need no Codex install.
public protocol ChatGPTCredentialSource: Sendable {
    func credentials() async throws -> ChatGPTCredentials
}

/// What the usage endpoint needs to know who is asking.
public struct ChatGPTCredentials: Equatable, Sendable {
    public let accessToken: String
    /// The workspace the usage is counted in.
    public let accountID: String

    public init(accessToken: String, accountID: String) {
        self.accessToken = accessToken
        self.accountID = accountID
    }
}
