# AI Bar

A macOS menu bar app that shows how much of your AI provider rate limits you have used, and whether
you are on pace to run out before the window resets.

The first provider is Claude. It reuses the session Claude Code already has, so there is nothing to
log in to. More providers plug in behind the `UsageProvider` protocol.

## What you see

- **Menu bar pill** with the 5-hour window usage, for example `42%`.
  Green when the current pace leaves headroom until the window resets, red when it will be drained
  first, plain text when there is not enough data yet.
- **Left click** opens a popover with every limit window: 5-hour, weekly, and weekly per model.
  Each bar is green below 70%, yellow from 70%, red from 90%. A translucent segment behind the bar
  shows the projected usage at reset, and a thin cursor marks how much of the window's time has
  passed: a fill past the cursor means usage is running ahead of time. A line underneath says how
  long you will be locked out (`Locked out for ~1h 20m`, or `~2d 19h` for a day or more, in red) or
  that the window `Lasts to reset`.
- **Right click**, or the refresh icon in the popover, refreshes immediately; the pill blinks and the
  icon turns while it runs. The app also polls every 5 minutes and after the Mac wakes.
- Hover the pill for a tooltip with the reset countdown and, when you are on pace to run out, the lockout.

## How the forecast works

A rate-limit window opens at 0% on its first request, so usage is 0 at `resetsAt - windowLength`.
That anchor plus every reading taken during the window gives a least-squares line; extending it to
the reset time yields the projected usage. Readings are stored per window under
`~/Library/Application Support/AI Bar/` so the estimate survives restarts. The 5-hour window is
5 hours long, the weekly windows are 7 days.

## Settings

The gear in the popover (or ⌘, while it is open) opens Settings: launch at login, how often to refresh
(1 to 15 minutes, default 5), and which window the pill shows. Changes apply at once and are kept in the
app's user defaults (`defaults read com.torz.aibar`).

## How the data is fetched

Claude Code stores its OAuth token in the login Keychain under `Claude Code-credentials`. AI Bar
reads it with `/usr/bin/security` (the same approach other menu bar tools use, which avoids a
Keychain prompt per app) and calls `GET https://api.anthropic.com/api/oauth/usage`. The token is
never logged or written anywhere. If the token is missing or expired the pill shows `--%!` and the
popover says to sign in to Claude Code.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer (Swift 6 toolchain)
- Claude Code installed and signed in

## Build and run

```
make build   # swift build
make test    # swift test
make app     # bundle dist/AI Bar.app
make run     # build and launch the app bundle
```

To run the live end-to-end test against your own account:

```
AIBAR_LIVE_TESTS=1 swift test --filter ClaudeUsageLive
```

## Project layout

```
Sources/AIBarCore   Foundation-only library: model, Claude provider, forecasting, text and bar
                    geometry. Everything here is unit-tested without AppKit.
Sources/AIBar       The menu bar app: status item, badge rendering, popover, polling controller.
Tests/AIBarCoreTests
Support/Info.plist  Bundle metadata (LSUIElement, so no Dock icon).
tickets/            The design notes each part was built from, in dependency order.
```

## Adding a provider

Implement `UsageProvider` in `AIBarCore` (an id, a display name, and `fetchUsage()` returning a
`UsageSnapshot` with one `UsageWindow` per limit), then add it to the provider list in
`AppDelegate`. Windows of kind `.fiveHour`, `.weekly` and `.weeklyModel` get forecasts automatically.
