import Foundation
import Testing
@testable import AIBarCore

// Method: drive `ClaudeUsageProvider` only through `fetchUsage()`, with a fake credential source and a fake
// transport standing in for the Keychain and the network. Expected values are read off the fixture by hand.
@Suite struct ClaudeUsageDecoding {
    @Test func realResponseYieldsFiveHourWeeklyAndPerModelWindowsInOrder() async throws {
        let snapshot = try await provider(answering: realUsageResponse).fetchUsage()

        #expect(snapshot.provider == ProviderID("claude"))
        #expect(snapshot.windows.map(\.id) == ["session", "weekly_all", "weekly_scoped:Fable"])
        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .weekly, .weeklyModel(name: "Fable")])
        #expect(snapshot.windows.map(\.title) == ["5-hour", "Weekly", "Weekly · Fable"])
        #expect(snapshot.windows.map(\.percentUsed) == [0, 12, 22])
    }

    // Epochs computed independently with `date -j -u`; the tolerance allows the formatter to truncate microseconds.
    @Test func resetTimesKeepTheirFractionalSeconds() async throws {
        let snapshot = try await provider(answering: realUsageResponse).fetchUsage()
        let resets = snapshot.windows.map { $0.resetsAt?.timeIntervalSince1970 ?? .nan }

        let sessionReset = 1_790_388_000.0 // 2026-09-26T02:00:00Z
        let weeklyReset = 1_790_899_199.686471 // 2026-10-01T23:59:59.686471Z
        #expect(zip(resets, [sessionReset, weeklyReset, weeklyReset]).allSatisfy { abs($0 - $1) < 0.001 })
    }

    // Legacy windows reuse the `limits` ids so a window keeps its identity whichever shape the server sends.
    @Test func fallsBackToLegacyWindowsWhenLimitsAreMissing() async throws {
        let body = #"{"five_hour":{"utilization":40.5,"resets_at":"2026-09-26T02:00:00Z"},"seven_day":{"utilization":12.0,"resets_at":null}}"#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows == [
            UsageWindow(id: "session", kind: .fiveHour, title: "5-hour", percentUsed: 40.5,
                        resetsAt: Date(timeIntervalSince1970: 1_790_388_000)),
            UsageWindow(id: "weekly_all", kind: .weekly, title: "Weekly", percentUsed: 12, resetsAt: nil),
        ])
    }

    @Test func fallsBackToLegacyWindowsWhenLimitsAreEmpty() async throws {
        let body = #"{"limits":[],"five_hour":{"utilization":7,"resets_at":null}}"#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows.map(\.kind) == [.fiveHour])
    }

    // Kinds the app does not know yet stay visible, titled by their raw kind, after every window it does know.
    @Test func keepsUnknownKindsAsOtherAfterTheKnownWindows() async throws {
        let body = #"""
        {"limits":[
          {"kind":"monthly_opus","percent":5},
          {"kind":"weekly_scoped","percent":22,"scope":{"model":{"display_name":"Fable"}}},
          {"kind":"weekly_all","percent":12},
          {"kind":"session","percent":3}
        ]}
        """#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .weekly, .weeklyModel(name: "Fable"), .other])
        #expect(snapshot.windows.last == UsageWindow(id: "monthly_opus", kind: .other, title: "monthly_opus",
                                                     percentUsed: 5, resetsAt: nil))
    }
}

private func provider(answering body: String, status: Int = 200) -> ClaudeUsageProvider {
    ClaudeUsageProvider(
        credentials: FakeCredentialSource(),
        transport: FakeTransport(body: Data(body.utf8), status: status)
    )
}

private struct FakeCredentialSource: CredentialSource {
    func accessToken() async throws -> String { "test-token" }
}

private struct FakeTransport: HTTPTransport {
    let body: Data
    let status: Int

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) { (body, status) }
}
