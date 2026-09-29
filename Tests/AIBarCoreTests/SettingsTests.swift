import Foundation
import Testing
@testable import AIBarCore

// Method: compare against the defaults the ticket specifies, written out as literals.
@Suite struct AppSettingsDefaults {
    @Test func pollsEveryFiveMinutesShowsThePrimaryWindowAndHasNoShortcut() {
        #expect(AppSettings() == AppSettings(refreshInterval: .seconds(5 * 60), badgeWindowID: nil,
                                             openPopoverShortcut: nil))
    }
}

// Method: every test gets its own `UserDefaults` suite, removed afterwards, so nothing leaks into the real app's
// preferences or between tests. "Survives a relaunch" is checked by opening a second store on the same suite.
@MainActor @Suite struct SettingsPersistence {
    @Test func freshPreferencesGiveTheDefaults() {
        withIsolatedDefaults { defaults in
            #expect(SettingsStore(defaults: defaults).settings == AppSettings())
        }
    }

    @Test func changesSurviveARelaunch() {
        withIsolatedDefaults { defaults in
            SettingsStore(defaults: defaults).update {
                $0.refreshInterval = .seconds(10 * 60)
                $0.badgeWindowID = "weekly_all"
            }

            #expect(SettingsStore(defaults: defaults).settings
                    == AppSettings(refreshInterval: .seconds(10 * 60), badgeWindowID: "weekly_all"))
        }
    }

    // Going back to the primary window must stick too, not resurrect the previously chosen one.
    @Test func clearingTheBadgeWindowSurvivesARelaunch() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.update { $0.badgeWindowID = "weekly_all" }
            store.update { $0.badgeWindowID = nil }

            #expect(SettingsStore(defaults: defaults).settings.badgeWindowID == nil)
        }
    }

    @Test func shortcutSurvivesARelaunch() {
        withIsolatedDefaults { defaults in
            let hyperK = GlobalShortcut(keyCode: 40, modifiers: .hyper)
            SettingsStore(defaults: defaults).update { $0.openPopoverShortcut = hyperK }

            #expect(SettingsStore(defaults: defaults).settings.openPopoverShortcut == hyperK)
        }
    }

    @Test func removingTheShortcutSurvivesARelaunch() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.update { $0.openPopoverShortcut = GlobalShortcut(keyCode: 40, modifiers: .hyper) }
            store.update { $0.openPopoverShortcut = nil }

            #expect(SettingsStore(defaults: defaults).settings.openPopoverShortcut == nil)
        }
    }

    @Test func reportsEachChange() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            var reported: [AppSettings] = []
            store.onChange = { reported.append($0) }

            store.update { $0.refreshInterval = .seconds(60) }

            #expect(reported == [AppSettings(refreshInterval: .seconds(60))])
        }
    }
}

// Method: write raw values under the store's keys, as a hand edit with `defaults write` or another app version would,
// then open a store and check it reads the defaults instead of the junk.
@MainActor @Suite struct SettingsFromBadStoredValues {
    // `Int.max` minutes would overflow if converted to a duration before being checked.
    @Test(arguments: [7, 0, -5, 600, Int.max, "ten", 2.5] as [any Sendable])
    func intervalNotOnOfferFallsBackToFiveMinutes(stored: any Sendable) {
        withIsolatedDefaults { defaults in
            defaults.set(stored, forKey: SettingsStore.Key.refreshIntervalMinutes)

            #expect(SettingsStore(defaults: defaults).settings.refreshInterval == .seconds(5 * 60))
        }
    }

    @Test func nonTextBadgeWindowFallsBackToThePrimaryWindow() {
        withIsolatedDefaults { defaults in
            defaults.set(42, forKey: SettingsStore.Key.badgeWindowID)

            #expect(SettingsStore(defaults: defaults).settings.badgeWindowID == nil)
        }
    }

    @Test(arguments: [
        "hyper-k",
        ["keyCode": 40] as [String: any Sendable],
        ["keyCode": 40, "modifiers": ["command", "fn"]] as [String: any Sendable],
        ["keyCode": 70_000, "modifiers": ["command"]] as [String: any Sendable],
        ["keyCode": -1, "modifiers": ["command"]] as [String: any Sendable],
        ["keyCode": 40, "modifiers": ["option"]] as [String: any Sendable],
    ] as [any Sendable])
    func unreadableOrUnusableShortcutFallsBackToNone(stored: any Sendable) {
        withIsolatedDefaults { defaults in
            defaults.set(stored, forKey: SettingsStore.Key.openPopoverShortcut)

            #expect(SettingsStore(defaults: defaults).settings.openPopoverShortcut == nil)
        }
    }

    @Test func updatingToAnUnusableShortcutKeepsNone() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.update { $0.openPopoverShortcut = GlobalShortcut(keyCode: 40, modifiers: []) }

            #expect(store.settings.openPopoverShortcut == nil)
        }
    }

    // Keeps the running app and the next launch in agreement: an interval that would be discarded on relaunch is
    // discarded now.
    @Test func updatingToAnIntervalNotOnOfferKeepsTheDefault() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.update { $0.refreshInterval = .seconds(7) }

            #expect(store.settings.refreshInterval == .seconds(5 * 60))
        }
    }
}

@MainActor private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
    let suiteName = "AIBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    body(defaults)
}
