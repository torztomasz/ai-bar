# 007 — Settings window: launch at login, refresh interval, badge window

Blocked by: nothing. Base: `main`.

## Goal

A small native Settings window with the three settings a menu bar utility needs, persisted in
`UserDefaults`, plus launch-at-login through `SMAppService`.

## Why

Today the poll interval is a constant, the badge always shows the 5-hour window, and the app must be
started by hand after every login.

## Requirements

### Settings model (`AIBarCore`)

- `public struct AppSettings: Equatable, Sendable` with:
  - `refreshInterval: Duration` — allowed values 1, 2, 5, 10, 15 minutes; default 5.
  - `badgeWindowID: String?` — id of the window the pill shows; nil means the provider's primary
    (5-hour) window. Falls back to primary when the id is not in the snapshot.
- `public final class SettingsStore` (`@MainActor` or lock-protected): `init(defaults: UserDefaults)`,
  `var settings: AppSettings`, `func update(_ mutate: (inout AppSettings) -> Void)`, and a change
  callback or `AsyncStream` so the controller reacts. Keys are string constants in one place.
  Unknown or out-of-range stored values fall back to defaults rather than crashing.
- `UsageSnapshot.window(for id: String?) -> UsageWindow?` returning the badge window with the primary
  fallback, tested.

### Launch at login (`AIBar`)

- `LaunchAtLogin` wrapper over `SMAppService.mainApp`: `isEnabled` (from `.status == .enabled`),
  `setEnabled(_:) throws`. Registration only works from a real bundle; when it throws (e.g. run via
  `swift run`), the toggle reverts and the window shows the error's `localizedDescription` under it
  in the interface's voice ("Couldn't add AI Bar to login items: …").

### Settings window (`AIBar`)

- `SettingsWindowController` owning one `NSWindow` (titled "AI Bar Settings", `.titled, .closable`,
  not resizable, released on close = false so it can reopen). Content is a SwiftUI `Form` with
  `.formStyle(.grouped)`, width about 360.
- Controls, in this order:
  1. Toggle "Launch at login".
  2. Picker "Refresh every" with 1, 2, 5, 10, 15 minutes.
  3. Picker "Show in menu bar" listing the windows of the first provider's current snapshot by title
     (and "5-hour (default)" when there is no snapshot yet).
  4. A footer line with the app version from the bundle (`CFBundleShortVersionString`, "dev" when
     absent); set the version in `Support/Info.plist` to 0.1.0.
- Open it from a gear `Button` in the popover footer (system image `gear`, `.buttonStyle(.borderless)`,
  help text "Settings") and with ⌘, while the popover is open. Opening brings the app forward
  (`NSApp.activate`), closing the window does not quit the app.

### Wiring

- `UsageController` reads the interval from `SettingsStore` and restarts its polling loop when it
  changes (do not wait out the old interval).
- `StatusItemController` shows the badge window chosen in settings; the tint still comes from that
  window's forecast (`forecasts[window.id]`), so a weekly badge is coloured by the weekly forecast.
- Tooltip and badge text use the chosen window's title.

## Verification

- Tests: `AppSettings` defaults and clamping of bad stored values, `SettingsStore` round-trip through
  an isolated `UserDefaults(suiteName:)`, `window(for:)` fallback.
- `make test` green. `make app` then launch `dist/AI Bar.app`, open Settings from the popover, toggle
  launch at login on and off (confirm with `sfltool dumpbtm | grep -i "ai bar"` or System Settings >
  Login Items), change the interval and confirm the next refresh timing in the log, switch the badge
  to Weekly and confirm the pill changes. Leave launch at login OFF. Quit the app.

## Out of scope

Animation and visual polish (008). Per-provider settings.
