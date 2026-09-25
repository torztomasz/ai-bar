import Foundation
import Observation

/// Keeps `AppSettings` in `UserDefaults`, so choices survive relaunches, and announces every change so the app can
/// act on it at once. Observable so the Settings window redraws from the same source of truth it writes to.
///
/// Main-actor bound because its readers (the Settings window, the status item, the poller) all live there.
@MainActor @Observable
public final class SettingsStore {
    /// Always what a fresh store on the same defaults would read, so the app never runs on a value a relaunch would
    /// discard.
    public private(set) var settings: AppSettings
    /// For AppKit consumers that cannot observe; called after every `update`.
    @ObservationIgnored public var onChange: (AppSettings) -> Void = { _ in }

    @ObservationIgnored private let defaults: UserDefaults

    /// The persisted form is primitive (whole minutes, a plain string) so it stays readable with `defaults read`.
    enum Key {
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let badgeWindowID = "badgeWindowID"
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = Self.read(from: defaults)
    }

    public func update(_ mutate: (inout AppSettings) -> Void) {
        var changed = settings
        mutate(&changed)
        settings = changed.supported()
        Self.write(settings, to: defaults)
        onChange(settings)
    }

    /// A stored value this version does not offer, e.g. hand-edited or from a future version, reads as the default
    /// rather than failing. Stored minutes are matched against the choices, never converted, so no value can overflow.
    private static func read(from defaults: UserDefaults) -> AppSettings {
        let storedMinutes = defaults.object(forKey: Key.refreshIntervalMinutes) as? Int
        return AppSettings(
            refreshInterval: AppSettings.refreshIntervalChoices.first { $0.wholeMinutes == storedMinutes }
                ?? AppSettings.defaultRefreshInterval,
            badgeWindowID: defaults.object(forKey: Key.badgeWindowID) as? String)
    }

    private static func write(_ settings: AppSettings, to defaults: UserDefaults) {
        defaults.set(settings.refreshInterval.wholeMinutes, forKey: Key.refreshIntervalMinutes)
        defaults.set(settings.badgeWindowID, forKey: Key.badgeWindowID)
    }
}
