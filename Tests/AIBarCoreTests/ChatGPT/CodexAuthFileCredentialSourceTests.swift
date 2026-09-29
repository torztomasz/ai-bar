import Foundation
import Testing
@testable import AIBarCore

// Method: parse hand-written stand-ins for Codex's `auth.json`, since the real file is per-machine. Anything
// without both a token and an account must read as "not logged in", never crash or leak.
@Suite struct CodexAuthFileParsing {
    @Test func readsTheAccessTokenAndAccountFromCodexsFile() throws {
        let file = #"""
        {"auth_mode":"chatgpt","OPENAI_API_KEY":null,
         "tokens":{"id_token":"i","access_token":"eyJ-abc","refresh_token":"r","account_id":"account-1"},
         "last_refresh":"2026-09-24T07:14:49.193886Z"}
        """#

        #expect(try CodexAuthFileCredentialSource.credentials(fromAuthJSON: Data(file.utf8))
                == ChatGPTCredentials(accessToken: "eyJ-abc", accountID: "account-1"))
    }

    // The third is Codex signed in with an API key, which has no ChatGPT plan to report usage for.
    @Test(arguments: [
        "",
        "not json",
        #"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-abc","tokens":null}"#,
        #"{"tokens":{"access_token":"eyJ-abc"}}"#,
        #"{"tokens":{"access_token":"","account_id":"account-1"}}"#,
        #"{"tokens":{"access_token":"eyJ-abc","account_id":""}}"#,
    ])
    func filesWithoutASessionMeanNotLoggedIn(_ file: String) throws {
        let error = try #require(throws: ChatGPTUsageError.self) {
            try CodexAuthFileCredentialSource.credentials(fromAuthJSON: Data(file.utf8))
        }

        #expect(error.isSameCase(as: .notLoggedIn))
    }
}

// Method: point the source at a temporary directory through `CODEX_HOME`, the variable Codex itself honours, and
// read through `credentials()` as the provider does.
@Suite struct CodexAuthFileLocation {
    @Test func readsTheFileInCodexHome() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "AIBarCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(#"{"tokens":{"access_token":"eyJ-abc","account_id":"account-1"}}"#.utf8)
            .write(to: home.appending(path: "auth.json"))
        let source = CodexAuthFileCredentialSource(environment: ["CODEX_HOME": home.path(percentEncoded: false)])

        #expect(try await source.credentials() == ChatGPTCredentials(accessToken: "eyJ-abc", accountID: "account-1"))
    }

    @Test func aMissingFileMeansNotLoggedIn() async throws {
        let source = CodexAuthFileCredentialSource(environment: ["CODEX_HOME": "/nonexistent/AIBarCoreTests"])

        let error = try await #require(throws: ChatGPTUsageError.self) { try await source.credentials() }

        #expect(error.isSameCase(as: .notLoggedIn))
    }
}
