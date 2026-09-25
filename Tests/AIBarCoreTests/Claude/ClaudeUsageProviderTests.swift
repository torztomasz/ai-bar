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

    // `UsageWindow` is `Identifiable` and SwiftUI lists break on repeated ids, which these entries would produce.
    @Test func givesRepeatedWindowsDistinctIDs() async throws {
        let body = #"""
        {"limits":[
          {"kind":"weekly_scoped","percent":1,"scope":{"model":null,"surface":"web"}},
          {"kind":"weekly_scoped","percent":2,"scope":{"model":null,"surface":"cli"}},
          {"kind":"monthly_opus","percent":3},
          {"kind":"monthly_opus","percent":4}
        ]}
        """#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows.map(\.id) == ["weekly_scoped", "weekly_scoped#2", "monthly_opus", "monthly_opus#2"])
    }
}

// Method: feed bodies with nulls where the app needs a value; one incomplete window must not hide the others.
@Suite struct ClaudeUsageNullTolerance {
    @Test func skipsLimitsWithoutAKindOrPercent() async throws {
        let body = #"""
        {"limits":[
          {"kind":null,"percent":50},
          {"kind":"weekly_all","percent":null},
          {"kind":"session","percent":3,"resets_at":null,"scope":null}
        ]}
        """#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows == [
            UsageWindow(id: "session", kind: .fiveHour, title: "5-hour", percentUsed: 3, resetsAt: nil),
        ])
    }

    @Test func skipsLegacyWindowsWithoutUtilization() async throws {
        let body = #"{"limits":null,"five_hour":{"utilization":null,"resets_at":null},"seven_day":{"utilization":9}}"#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows.map(\.id) == ["weekly_all"])
    }

    @Test func fallsBackToLegacyWindowsWhenNoLimitIsUsable() async throws {
        let body = #"{"limits":[{"kind":"session","percent":null}],"five_hour":{"utilization":8}}"#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows.map(\.percentUsed) == [8])
    }
}

// Method: make one seam misbehave (credential source throws, transport fails, answers with an error status or
// garbage) and check which `ClaudeUsageError` case comes out, since the app picks its message from the case.
@Suite struct ClaudeUsageFailures {
    @Test func missingCredentialsMeanNotLoggedIn() async throws {
        let provider = ClaudeUsageProvider(
            credentials: FakeCredentialSource(result: .failure(CocoaError(.fileNoSuchFile))),
            transport: FakeTransport(body: Data(realUsageResponse.utf8), status: 200)
        )

        #expect(try await failure(of: provider).isSameCase(as: .notLoggedIn))
    }

    @Test func unreachableServerIsANetworkError() async throws {
        let provider = ClaudeUsageProvider(credentials: FakeCredentialSource(result: .success("test-token")),
                                           transport: OfflineTransport())

        #expect(try await failure(of: provider).isSameCase(as: .network(URLError(.notConnectedToInternet))))
    }

    @Test func unauthorizedMeansTheTokenExpired() async throws {
        let provider = provider(answering: #"{"error":"unauthorized"}"#, status: 401)

        #expect(try await failure(of: provider).isSameCase(as: .tokenExpired))
    }

    @Test func otherErrorStatusesCarryTheStatusCode() async throws {
        let provider = provider(answering: "Internal Server Error", status: 500)

        #expect(try await failure(of: provider).isSameCase(as: .http(status: 500)))
    }

    @Test func unreadableBodyIsADecodingError() async throws {
        let provider = provider(answering: "<html>maintenance</html>")

        #expect(try await failure(of: provider).isSameCase(as: .decoding(CocoaError(.coderReadCorrupt))))
    }

    // The app shows `errorDescription` verbatim, so every case must have one.
    @Test(arguments: [
        ClaudeUsageError.notLoggedIn, .tokenExpired, .http(status: 503), .decoding(CocoaError(.coderReadCorrupt)),
        .network(URLError(.timedOut)),
    ])
    func everyErrorHasAUserFacingMessage(_ error: ClaudeUsageError) {
        #expect(error.errorDescription?.isEmpty == false)
    }
}

// Method: record what the provider hands to the transport; these are the headers the endpoint was verified with.
@Suite struct ClaudeUsageRequest {
    @Test func callsTheOAuthUsageEndpointWithTheBearerTokenAndBetaHeader() async throws {
        let transport = RecordingTransport()
        let provider = ClaudeUsageProvider(credentials: FakeCredentialSource(result: .success("secret-token")),
                                           transport: transport)

        _ = try await provider.fetchUsage()

        let request = try #require(transport.requests.first)
        #expect(request.url == URL(string: "https://api.anthropic.com/api/oauth/usage"))
        #expect(request.headers == [
            "Authorization": "Bearer secret-token",
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
        ])
    }
}

private func provider(answering body: String, status: Int = 200) -> ClaudeUsageProvider {
    ClaudeUsageProvider(
        credentials: FakeCredentialSource(result: .success("test-token")),
        transport: FakeTransport(body: Data(body.utf8), status: status)
    )
}

private func failure(of provider: ClaudeUsageProvider) async throws -> ClaudeUsageError {
    try await #require(throws: ClaudeUsageError.self) { try await provider.fetchUsage() }
}

private struct FakeCredentialSource: CredentialSource {
    let result: Result<String, any Error>

    func accessToken() async throws -> String { try result.get() }
}

private struct OfflineTransport: HTTPTransport {
    func get(_ url: URL, headers: [String: String]) async throws -> (body: Data, status: Int) {
        throw URLError(.notConnectedToInternet)
    }
}

private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(url: URL, headers: [String: String])] = []

    var requests: [(url: URL, headers: [String: String])] { lock.withLock { recorded } }

    func get(_ url: URL, headers: [String: String]) async throws -> (body: Data, status: Int) {
        lock.withLock { recorded.append((url, headers)) }
        return (Data(realUsageResponse.utf8), 200)
    }
}

private struct FakeTransport: HTTPTransport {
    let body: Data
    let status: Int

    func get(_ url: URL, headers: [String: String]) async throws -> (body: Data, status: Int) { (body, status) }
}
