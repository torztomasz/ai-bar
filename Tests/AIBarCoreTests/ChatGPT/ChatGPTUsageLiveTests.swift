import Foundation
import Testing
@testable import AIBarCore

// Method: hit the real endpoint with this machine's Codex session. Skipped by default because it needs a signed-in
// Codex and the network; run with `AIBAR_LIVE_TESTS=1 swift test --filter ChatGPTUsageLive`.
// Only window shapes are printed, never the token.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AIBAR_LIVE_TESTS"] == "1"))
struct ChatGPTUsageLive {
    @Test func fetchesAFiveHourWindowFromTheRealEndpoint() async throws {
        let snapshot = try await ChatGPTUsageProvider().fetchUsage()

        for window in snapshot.windows {
            print("live window:", window.id, window.title, window.percentUsed, window.resetsAt as Any)
        }
        #expect(snapshot.primaryWindow != nil)
    }
}
