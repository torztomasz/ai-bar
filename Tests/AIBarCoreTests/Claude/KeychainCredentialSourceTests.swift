import Foundation
import Testing
@testable import AIBarCore

// Method: parse hand-written stand-ins for what `security find-generic-password -w` prints, since the real
// Keychain item is per-machine. Anything without a token must read as "not logged in", never crash or leak.
@Suite struct KeychainCredentialsParsing {
    @Test func readsTheAccessTokenFromClaudeCodesBlob() throws {
        let stdout = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"r","expiresAt":1790388000000,"scopes":["user:inference"]}}"# + "\n"

        #expect(try KeychainCredentialSource.accessToken(fromCredentialsJSON: Data(stdout.utf8)) == "sk-ant-oat01-abc")
    }

    @Test(arguments: [
        "",
        "not json",
        #"{"someOtherTool":{}}"#,
        #"{"claudeAiOauth":{"accessToken":null}}"#,
        #"{"claudeAiOauth":{"accessToken":""}}"#,
    ])
    func blobsWithoutATokenMeanNotLoggedIn(_ stdout: String) throws {
        let error = try #require(throws: ClaudeUsageError.self) {
            try KeychainCredentialSource.accessToken(fromCredentialsJSON: Data(stdout.utf8))
        }

        guard case .notLoggedIn = error else { Issue.record("Expected .notLoggedIn, got \(error)"); return }
    }
}
