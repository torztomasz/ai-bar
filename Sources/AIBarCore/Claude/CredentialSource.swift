/// Where the Claude OAuth access token comes from. A protocol so tests need no Keychain.
public protocol CredentialSource: Sendable {
    func accessToken() async throws -> String
}
