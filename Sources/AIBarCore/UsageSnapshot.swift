import Foundation

/// One provider's usage at a point in time: every rate-limit window it reports.
public struct UsageSnapshot: Equatable, Sendable {
    public let provider: ProviderID
    public let fetchedAt: Date
    /// In the order the provider wants them displayed.
    public let windows: [UsageWindow]

    public init(provider: ProviderID, fetchedAt: Date, windows: [UsageWindow]) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.windows = windows
    }

    /// The window the menu bar badge shows: the 5-hour one, because it is the limit a user runs into mid-session.
    public var primaryWindow: UsageWindow? {
        windows.first { $0.kind == .fiveHour }
    }
}

/// Identifies a usage provider, e.g. `"claude"`. A wrapper rather than a bare `String` so a provider key
/// cannot be passed where a display name is expected, or vice versa.
public struct ProviderID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}
