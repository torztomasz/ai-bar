# 001 — Project scaffold, core model, and menu bar shell

Blocked by: nothing. Base: `main`.

## Goal

A Swift Package that builds a macOS menu bar app with a placeholder badge, a left-click popover, a right-click refresh hook, and the shared domain model that later tickets build on. No networking, no real data yet.

## Why

Tickets 002 (Claude provider) and 003 (drain estimator) run in parallel and both need the same model types and the same package layout. Defining them here up front avoids two divergent versions.

## Requirements

### Package layout

- `Package.swift`, swift-tools-version 5.10 or newer, platform `.macOS(.v14)`.
- Library target `AIBarCore` (pure Swift, Foundation only, no AppKit): domain model and protocols. Everything unit-testable lives here.
- Executable target `AIBar` (AppKit + SwiftUI): the menu bar app. Depends on `AIBarCore`.
- Test target `AIBarCoreTests` using XCTest (or Swift Testing, your call, but be consistent).
- `Makefile` with targets:
  - `build`: `swift build`
  - `test`: `swift test`
  - `app`: builds release and assembles `dist/AI Bar.app` with `Contents/MacOS/AIBar`, `Contents/Info.plist` (CFBundleIdentifier `com.torz.aibar`, CFBundleName `AI Bar`, `LSUIElement` = true so the app has no Dock icon, `NSHighResolutionCapable` = true, `LSMinimumSystemVersion` 14.0).
  - `run`: `app` then `open "dist/AI Bar.app"`.
- `.gitignore` already exists; extend it if needed.

### Core model (in `AIBarCore`)

```swift
public struct ProviderID: Hashable, Sendable, RawRepresentable { public let rawValue: String }

public struct UsageWindow: Equatable, Sendable, Identifiable {
    public let id: String          // stable key from the provider, e.g. "session", "weekly_all", "weekly_scoped:Fable"
    public let title: String       // human label, e.g. "5-hour", "Weekly", "Weekly · Fable"
    public let percentUsed: Double // 0...100 (may exceed 100 if the provider reports it)
    public let resetsAt: Date?     // nil when the provider does not report a reset time
}

public struct UsageSnapshot: Equatable, Sendable {
    public let provider: ProviderID
    public let fetchedAt: Date
    public let windows: [UsageWindow]
    public var primaryWindow: UsageWindow? { get } // the window shown in the menu bar badge: the 5-hour one
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    func fetchUsage() async throws -> UsageSnapshot
}
```

Decide how `primaryWindow` is selected (a `kind` enum on `UsageWindow`, or a convention on `id`). Prefer an explicit `UsageWindow.Kind` enum: `.fiveHour`, `.weekly`, `.weeklyModel(name: String)`, `.other`. Document the choice in a doc comment on the type.

Provide a `FakeUsageProvider` in `AIBarCore` (not the test target) that returns a canned snapshot after an optional delay, so the app shell and later tests can use it.

### App shell (in `AIBar`)

- `main.swift` or `@main` AppDelegate. Set `NSApplication.shared.setActivationPolicy(.accessory)` so the app runs without a Dock icon even when launched via `swift run` (the Info.plist `LSUIElement` covers the bundled case).
- `StatusItemController`: owns an `NSStatusItem` with variable length. Renders a badge with text `--%` for now. Left click toggles an `NSPopover` (behavior `.transient`) whose content is a SwiftUI view. Right click (or control-click) calls an `onRefreshRequested` closure. Implement click discrimination via `NSStatusBarButton.sendAction(on: [.leftMouseUp, .rightMouseUp])` and checking `NSApp.currentEvent?.type`.
- Popover content: a SwiftUI `UsagePopoverView` that takes a `UsageSnapshot?` and renders provider name and one row per window with the percent. Placeholder data from `FakeUsageProvider` is fine. Include a "Quit" button.
- Badge rendering: a `BadgeRenderer` that produces an `NSImage` from `(text: String, tint: BadgeTint)` where `BadgeTint` is `.neutral`, `.ok`, `.danger`. Draw a rounded rect background (`.ok` green, `.danger` red, `.neutral` none) with the text in a monospaced-digit system font. Neutral is what the shell uses now; 004 will pass `.ok`/`.danger`. Mark the image `isTemplate = false` so colors survive.

### Verification

- `make build` and `make test` succeed (tests for `primaryWindow` selection and `FakeUsageProvider`).
- `make app` produces a launchable bundle; launch it, confirm a `--%` item appears in the menu bar, left click opens the popover, right click prints/logs "refresh requested". Quit it afterwards (`pkill -f "AI Bar"` or via the Quit button).

## Out of scope

Networking, Keychain, persistence, forecast colors. Those are tickets 002–004.
