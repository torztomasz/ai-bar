# 004 — Wire the app: polling, badge colour, popover, refresh

Blocked by: 002 (`ClaudeUsageProvider`) and 003 (`DrainEstimator`, `SampleStore`). Base: `003-drain-estimator` after it is rebased onto `002-claude-provider`.

## Goal

Turn the shell from 001 into the working product: the menu bar badge shows the Claude 5-hour usage percent with a green or red background depending on the drain forecast, the left-click popover lists every window, right click refreshes, and the app polls on its own.

## Why

This is the ticket that delivers the user-visible feature. Everything below it is tested in isolation; this one is about composition, lifecycle, and the manual check that it actually looks right in the menu bar.

## Requirements

### `UsageController` (in `AIBar`, `@MainActor`, `ObservableObject`)

- Holds `[UsageProvider]` (v1: `[ClaudeUsageProvider()]`), one `SampleStore` per provider, a `DrainEstimator`.
- Published state per provider: `snapshot: UsageSnapshot?`, `forecast: DrainForecast?`, `lastError: Error?`, `lastRefreshedAt: Date?`, `isRefreshing: Bool`.
- `refresh()` fetches every provider concurrently, appends the primary window percent to the provider's `SampleStore`, runs the estimator on the primary window, and publishes. A failed fetch keeps the previous snapshot and sets `lastError`.
- Polls every 5 minutes with a `Timer` (or `Task.sleep` loop); refreshes immediately on launch and when the Mac wakes from sleep (`NSWorkspace.didWakeNotification`).

### Badge

- Text: primary window percent, rounded to an integer, e.g. `42%`. `--%` when there is no snapshot yet; `!` suffix or a warning glyph when `lastError` is set and there is no snapshot.
- Tint from `DrainOutlook`: `.willLast` → `.ok` (green), `.willDrain` → `.danger` (red), `.unknown` → `.neutral`.
- Tooltip on the status item: "Claude 5-hour: 42% · resets in 2h 13m · projected 71% at reset".

### Popover (`UsagePopoverView`)

For each provider: name header, then one row per window in snapshot order: title, a progress bar, percent, and "resets in …" (relative, minutes precision; "—" when nil). For the primary window also show the forecast line ("On pace to last" / "Drains at 14:35" / "Not enough data"). Footer: "Updated 3 min ago", a Refresh button, and Quit. Error state: show the `errorDescription` (e.g. not logged in) in place of the rows. Keep it native and plain (system fonts, `ProgressView`, no custom chrome).

### Refresh triggers

- Right click on the status item → `refresh()`.
- Refresh button in the popover → `refresh()`.
- The badge tint must update without reopening the popover.

### Cleanup from earlier tickets

Remove the `FakeUsageProvider` wiring from the app entry point (keep the type in Core for tests). Delete any placeholder code the shell no longer needs.

## Verification

- `make test` passes (existing suites; add tests for the badge text and tint mapping, which should live in a small pure function so they can be tested without AppKit; put that function in `AIBarCore`).
- `make run` launches the bundled app. Confirm in the menu bar: a percentage appears within a few seconds, has a green or red background, left click shows the three Claude windows (5-hour, Weekly, Weekly · Fable) with reset times, right click triggers a refresh (watch "Updated … ago" reset). Take a screenshot of the menu bar and popover (`screencapture -x /tmp/aibar.png`) and mention what you saw in the report. Quit the app when done.

## Out of scope

Additional providers, launch-at-login, settings UI, notifications.
