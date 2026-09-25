@testable import AIBarCore

extension ClaudeUsageError {
    /// Tests assert which failure the user sees, not the wrapped underlying error, so payloads are ignored.
    func isSameCase(as other: ClaudeUsageError) -> Bool {
        switch (self, other) {
        case (.notLoggedIn, .notLoggedIn), (.tokenExpired, .tokenExpired), (.network, .network), (.decoding, .decoding):
            true
        case let (.http(status), .http(otherStatus)):
            status == otherStatus
        default:
            false
        }
    }
}
