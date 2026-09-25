import Foundation

/// Reads the OAuth token Claude Code keeps in the login Keychain (generic password `Claude Code-credentials`).
///
/// Goes through `/usr/bin/security` rather than the Security framework because the item's ACL is bound to
/// Claude Code's binary: reading it directly would prompt for Keychain access on every new build of this app.
/// The token is returned only to the caller; it is never logged or persisted.
public struct KeychainCredentialSource: CredentialSource {
    public init() {}

    public func accessToken() async throws -> String {
        try Self.accessToken(fromCredentialsJSON: try await Self.readKeychainItem())
    }

    static func accessToken(fromCredentialsJSON data: Data) throws -> String {
        guard let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: data),
              let token = credentials.claudeAiOauth?.accessToken, !token.isEmpty
        else { throw ClaudeUsageError.notLoggedIn }
        return token
    }

    /// The shape of Claude Code's Keychain blob, reduced to what the app needs.
    private struct StoredCredentials: Decodable {
        let claudeAiOauth: OAuth?

        struct OAuth: Decodable {
            let accessToken: String?
        }
    }

    /// Runs on a global queue because `security` blocks until it exits, which must not stall the cooperative pool.
    private static func readKeychainItem() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try runSecurityCLI() })
            }
        }
    }

    private static func runSecurityCLI() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain before waiting: a full pipe buffer would block `security` and deadlock `waitUntilExit`.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ClaudeUsageError.notLoggedIn }
        return output
    }
}
