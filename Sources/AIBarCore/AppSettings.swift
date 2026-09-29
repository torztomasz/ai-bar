/// What the user can change in the Settings window. Launch at login is not here: the system owns that state, and
/// copying it into preferences would let the two disagree.
public struct AppSettings: Equatable, Sendable {
    /// One of `refreshIntervalChoices` once stored; see `supported()`.
    public var refreshInterval: Duration
    /// The window the menu bar badge shows for each provider; a provider without an entry shows its primary window
    /// (see `UsageSnapshot.window(for:)`). Per provider because window ids are each provider's own.
    public var badgeWindowIDs: [ProviderID: String]
    /// Providers the user turned off. Stored as the exceptions, so a provider added by an update starts out shown.
    public var disabledProviders: Set<ProviderID>
    /// Toggles the usage popover from any app. Off by default: every global shortcut is taken from every other app,
    /// so it is the user's to claim.
    public var openPopoverShortcut: GlobalShortcut?

    /// Short enough to follow a busy session, long enough to stay far from the endpoint's rate limits.
    public static let refreshIntervalChoices: [Duration] = [1, 2, 5, 10, 15].map(Duration.minutes)
    public static let defaultRefreshInterval: Duration = .minutes(5)

    public init(refreshInterval: Duration = defaultRefreshInterval, badgeWindowIDs: [ProviderID: String] = [:],
                disabledProviders: Set<ProviderID> = [], openPopoverShortcut: GlobalShortcut? = nil) {
        self.refreshInterval = refreshInterval
        self.badgeWindowIDs = badgeWindowIDs
        self.disabledProviders = disabledProviders
        self.openPopoverShortcut = openPopoverShortcut
    }

    public func isEnabled(_ provider: ProviderID) -> Bool {
        !disabledProviders.contains(provider)
    }

    public mutating func setEnabled(_ enabled: Bool, for provider: ProviderID) {
        if enabled {
            disabledProviders.remove(provider)
        } else {
            disabledProviders.insert(provider)
        }
    }

    /// Replaces an interval the Settings window does not offer with the default, and drops a shortcut that could
    /// never fire, so a value set in code behaves the same as one read back after a relaunch.
    func supported() -> AppSettings {
        var supported = self
        if !Self.refreshIntervalChoices.contains(refreshInterval) {
            supported.refreshInterval = Self.defaultRefreshInterval
        }
        if openPopoverShortcut?.isUsable == false {
            supported.openPopoverShortcut = nil
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
