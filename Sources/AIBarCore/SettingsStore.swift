import Foundation
import Observation

/// Keeps `AppSettings` in `UserDefaults`, so choices survive relaunches, and announces every change so the app can
/// act on it at once. Observable so the Settings window redraws from the same source of truth it writes to.
///
/// Main-actor bound because its readers (the Settings window, the status item, the poller) all live there.
@MainActor @Observable
public final class SettingsStore {
    /// Always what a fresh store on the same defaults would read, so the app never runs on a value it could not
    /// restore after a relaunch.
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
        Self.write(changed, to: defaults)
        settings = Self.read(from: defaults)
        onChange(settings)
    }

    /// A stored value this version does not offer, e.g. hand-edited or from a future version, reads as the default
    /// rather than failing.
    private static func read(from defaults: UserDefaults) -> AppSettings {
        let storedMinutes = defaults.object(forKey: Key.refreshIntervalMinutes) as? Int
        let storedInterval = storedMinutes.map { Duration.seconds($0 * 60) }
        return AppSettings(
            refreshInterval: storedInterval.filter(AppSettings.refreshIntervalChoices.contains)
                ?? AppSettings.defaultRefreshInterval,
            badgeWindowID: defaults.object(forKey: Key.badgeWindowID) as? String)
    }

    private static func write(_ settings: AppSettings, to defaults: UserDefaults) {
        defaults.set(Int(settings.refreshInterval.components.seconds / 60), forKey: Key.refreshIntervalMinutes)
        defaults.set(settings.badgeWindowID, forKey: Key.badgeWindowID)
    }
}

extension Optional {
    fileprivate func filter(_ isIncluded: (Wrapped) -> Bool) -> Wrapped? {
        flatMap { isIncluded($0) ? $0 : nil }
    }
}
