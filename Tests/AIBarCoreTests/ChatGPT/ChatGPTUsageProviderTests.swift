import Foundation
import Testing
@testable import AIBarCore

// Method: drive `ChatGPTUsageProvider` only through `fetchUsage()`, with a fake credential source and a fake
// transport standing in for Codex's auth file and the network. Expected values are read off the fixture by hand.
@Suite struct ChatGPTUsageDecoding {
    @Test func realResponseYieldsTheFiveHourAndWeeklyWindows() async throws {
        let snapshot = try await provider(answering: realChatGPTUsageResponse).fetchUsage()

        #expect(snapshot.provider == ProviderID("chatgpt"))
        #expect(snapshot.windows == [
            UsageWindow(id: "five_hour", kind: .fiveHour, title: "5-hour", percentUsed: 0,
                        resetsAt: Date(timeIntervalSince1970: 1_790_703_140)),
            UsageWindow(id: "weekly", kind: .weekly, title: "Weekly", percentUsed: 21,
                        resetsAt: Date(timeIntervalSince1970: 1_791_020_875)),
        ])
    }

    // The badge follows the 5-hour window by default, so it must be found whichever slot carries it.
    @Test func windowsAreNamedAfterTheirLengthNotTheirSlot() async throws {
        let body = #"""
        {"rate_limit":{
          "primary_window":{"used_percent":21,"limit_window_seconds":604800},
          "secondary_window":{"used_percent":3,"limit_window_seconds":18000}
        }}
        """#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows.map(\.id) == ["weekly", "five_hour"])
        #expect(snapshot.primaryWindow?.percentUsed == 3)
    }

    // Lengths the app does not know yet stay visible, titled by how long they run: 3 hours and 30 days here.
    @Test func keepsWindowsOfUnknownLengthAsOther() async throws {
        let body = #"""
        {"rate_limit":{
          "primary_window":{"used_percent":5,"limit_window_seconds":10800},
          "secondary_window":{"used_percent":6,"limit_window_seconds":2592000}
        }}
        """#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows == [
            UsageWindow(id: "window_10800s", kind: .other, title: "3-hour", percentUsed: 5, resetsAt: nil),
            UsageWindow(id: "window_2592000s", kind: .other, title: "30-day", percentUsed: 6, resetsAt: nil),
        ])
    }
}

// Method: feed bodies with nulls or gaps where the app needs a value; one incomplete window must not hide the other.
@Suite struct ChatGPTUsageNullTolerance {
    @Test func skipsWindowsWithoutAPercentOrLength() async throws {
        let body = #"""
        {"rate_limit":{
          "primary_window":{"used_percent":null,"limit_window_seconds":18000},
          "secondary_window":{"used_percent":21,"limit_window_seconds":604800,"reset_at":null}
        }}
        """#

        let snapshot = try await provider(answering: body).fetchUsage()

        #expect(snapshot.windows == [
            UsageWindow(id: "weekly", kind: .weekly, title: "Weekly", percentUsed: 21, resetsAt: nil),
        ])
    }

    @Test(arguments: [
        #"{"rate_limit":null}"#,
        #"{"rate_limit":{"primary_window":null,"secondary_window":null}}"#,
        #"{"plan_type":"free"}"#,
    ])
    func noRateLimitMeansNoWindows(_ body: String) async throws {
        #expect(try await provider(answering: body).fetchUsage().windows.isEmpty)
    }
}

// Method: make one seam misbehave (credential source throws, transport fails, answers with an error status or
// garbage) and check which `ChatGPTUsageError` case comes out, since the app picks its message from the case.
@Suite struct ChatGPTUsageFailures {
    @Test func missingCredentialsMeanNotLoggedIn() async throws {
        let provider = ChatGPTUsageProvider(
            credentials: FakeCredentialSource(result: .failure(CocoaError(.fileNoSuchFile))),
            transport: FakeTransport(body: Data(realChatGPTUsageResponse.utf8), status: 200)
        )

        #expect(try await failure(of: provider).isSameCase(as: .notLoggedIn))
    }

    @Test func unreachableServerIsANetworkError() async throws {
        let provider = ChatGPTUsageProvider(credentials: FakeCredentialSource(result: .success(testSession)),
                                            transport: OfflineTransport())

        #expect(try await failure(of: provider).isSameCase(as: .network(URLError(.notConnectedToInternet))))
    }

    @Test func unauthorizedMeansTheTokenExpired() async throws {
        let provider = provider(answering: #"{"detail":"unauthorized"}"#, status: 401)

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
        ChatGPTUsageError.notLoggedIn, .tokenExpired, .http(status: 503), .decoding(CocoaError(.coderReadCorrupt)),
        .network(URLError(.timedOut)),
    ])
    func everyErrorHasAUserFacingMessage(_ error: ChatGPTUsageError) {
        #expect(error.errorDescription?.isEmpty == false)
    }
}

// Method: record what the provider hands to the transport; these are the headers the endpoint was verified with.
@Suite struct ChatGPTUsageRequest {
    @Test func callsTheUsageEndpointWithTheBearerTokenAndTheAccount() async throws {
        let transport = RecordingTransport()
        let session = ChatGPTCredentials(accessToken: "secret-token", accountID: "account-1")
        let provider = ChatGPTUsageProvider(credentials: FakeCredentialSource(result: .success(session)),
                                            transport: transport)

        _ = try await provider.fetchUsage()

        let request = try #require(transport.requests.first)
        #expect(request.url == URL(string: "https://chatgpt.com/backend-api/wham/usage"))
        #expect(request.headers == [
            "Authorization": "Bearer secret-token",
            "ChatGPT-Account-Id": "account-1",
            "Accept": "application/json",
        ])
    }
}

private let testSession = ChatGPTCredentials(accessToken: "test-token", accountID: "test-account")

private func provider(answering body: String, status: Int = 200) -> ChatGPTUsageProvider {
    ChatGPTUsageProvider(
        credentials: FakeCredentialSource(result: .success(testSession)),
        transport: FakeTransport(body: Data(body.utf8), status: status)
    )
}

private func failure(of provider: ChatGPTUsageProvider) async throws -> ChatGPTUsageError {
    try await #require(throws: ChatGPTUsageError.self) { try await provider.fetchUsage() }
}

private struct FakeCredentialSource: ChatGPTCredentialSource {
    let result: Result<ChatGPTCredentials, any Error>

    func credentials() async throws -> ChatGPTCredentials { try result.get() }
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
        return (Data(realChatGPTUsageResponse.utf8), 200)
    }
}

private struct FakeTransport: HTTPTransport {
    let body: Data
    let status: Int

    func get(_ url: URL, headers: [String: String]) async throws -> (body: Data, status: Int) { (body, status) }
}
