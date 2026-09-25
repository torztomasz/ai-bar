/// What the user can change in the Settings window. Launch at login is not here: the system owns that state, and
/// copying it into preferences would let the two disagree.
public struct AppSettings: Equatable, Sendable {
    /// One of `refreshIntervalChoices`.
    public var refreshInterval: Duration
    /// The window the menu bar badge shows; nil follows the provider's primary window (see
    /// `UsageSnapshot.window(for:)`).
    public var badgeWindowID: String?

    /// Short enough to follow a busy session, long enough to stay far from the endpoint's rate limits.
    public static let refreshIntervalChoices: [Duration] = [1, 2, 5, 10, 15].map { .seconds($0 * 60) }
    public static let defaultRefreshInterval: Duration = .seconds(5 * 60)

    public init(refreshInterval: Duration = defaultRefreshInterval, badgeWindowID: String? = nil) {
        self.refreshInterval = refreshInterval
        self.badgeWindowID = badgeWindowID
    }
}
