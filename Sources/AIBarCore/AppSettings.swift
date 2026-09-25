/// What the user can change in the Settings window. Launch at login is not here: the system owns that state, and
/// copying it into preferences would let the two disagree.
public struct AppSettings: Equatable, Sendable {
    /// One of `refreshIntervalChoices` once stored; see `supported()`.
    public var refreshInterval: Duration
    /// The window the menu bar badge shows; nil follows the provider's primary window (see
    /// `UsageSnapshot.window(for:)`).
    public var badgeWindowID: String?

    /// Short enough to follow a busy session, long enough to stay far from the endpoint's rate limits.
    public static let refreshIntervalChoices: [Duration] = [1, 2, 5, 10, 15].map(Duration.minutes)
    public static let defaultRefreshInterval: Duration = .minutes(5)

    public init(refreshInterval: Duration = defaultRefreshInterval, badgeWindowID: String? = nil) {
        self.refreshInterval = refreshInterval
        self.badgeWindowID = badgeWindowID
    }

    /// Replaces an interval the Settings window does not offer with the default, so a value set in code behaves the
    /// same as one read back after a relaunch.
    func supported() -> AppSettings {
        var supported = self
        if !Self.refreshIntervalChoices.contains(refreshInterval) {
            supported.refreshInterval = Self.defaultRefreshInterval
        }
        return supported
    }
}

/// Intervals are chosen, stored and shown in whole minutes.
extension Duration {
    public static func minutes(_ minutes: Int) -> Duration {
        .seconds(minutes * 60)
    }

    /// Rounded down.
    public var wholeMinutes: Int {
        Int(components.seconds / 60)
    }
}
