# 008 — Motion and polish: time cursor, refresh animation, footer

Blocked by: 006, 007. Base: `007-settings` after it is rebased onto `006-lockout-copy`.

## Goal

Keep the native macOS look and add one memorable element (a time cursor on every bar) and
purposeful motion for refresh. Everything else gets quieter and more deliberate.

## Why

The popover opens tens of times a day and refreshes happen in the background dozens of times, so
motion must be brief, ease-out, and mean something. The one bold element is the bar: with a time
cursor it shows at a glance whether usage is ahead of time, which is the whole forecast in a
picture.

## Design tokens

- Colours: system semantic colours only (`.green`, `.yellow`, `.red`, `.primary`, `.secondary`,
  `.quaternary`, popover material). No custom hex.
- Type: system font. Window title `.body`; percent `.body.weight(.semibold).monospacedDigit()`;
  meta lines `.caption` secondary. Provider name `.headline`.
- Spacing: 12 between windows, 4 inside a row, 16 padding. Width 280.
- Easing: entrances and settles ease-out; in-flight rotation linear; value changes
  `.smooth(duration: 0.3)`; nothing over 300 ms except the in-flight spin.

## Requirements

### Time cursor on every bar (`UsageBar` + `UsageBarView`)

- `UsageBar` gains `elapsedFraction: Double?` = `(now - windowStart) / windowLength`, clamped 0...1,
  computed in Core from `resetsAt`, the kind's length and `now`; nil when unknown. Tested.
- `UsageBarView` draws a 1.5 pt wide, full-height rounded marker at `elapsedFraction` in `.primary`
  at 45% opacity, on top of the fills. It is the only element on the bar that is not a capsule fill,
  so it reads as a cursor.
- When the solid fill is ahead of the cursor (usage faster than time), nothing extra is drawn: the
  colour thresholds and the lockout line already say it. Restraint.

### Refresh motion

- Popover footer: replace the "Refresh" text button with an icon button (`arrow.clockwise`,
  `.borderless`, help "Refresh"). While `isRefreshing` the icon rotates continuously (linear,
  0.8 s per turn, `repeatForever`). When refreshing ends, it completes to the next full turn with
  ease-out over 250 ms rather than stopping mid-way. Remove the small `ProgressView`.
- Values: percent texts use `.contentTransition(.numericText())` and bars animate their widths with
  `.animation(.smooth(duration: 0.3), value: bar)`. "Updated just now" crossfades
  (`.contentTransition(.opacity)`).
- Menu bar pill: on refresh start, animate the status button's `alphaValue` to 0.6 over 150 ms
  (ease-out, `NSAnimationContext`); on finish back to 1.0 over 150 ms. If the refresh takes under
  150 ms the dip still completes before the rise, so a fast refresh reads as a single blink.
- Reduced motion (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` or SwiftUI
  `accessibilityReduceMotion`): no rotation, no width animation; keep the opacity fades.

### Footer and header

- Footer, left to right: "Updated 3 min ago" (caption, secondary), `Spacer`, refresh icon, gear icon
  (from 007), then a `Menu` with an `ellipsis.circle` icon containing "Quit AI Bar" (⌘Q). Icons
  `.borderless`, 16 pt symbols, `.secondary` foreground, `.primary` on hover via `.onHover`.
- Header: provider name `.headline` with, on the right, a small `.caption2` secondary text of the
  badge window's "resets in …" so the most important countdown is visible at the top.
- Error state: keep the message, set it in the interface's voice ("Sign in to Claude Code to see
  usage." style, sentence case, no apology).
- Popover open/close: leave the system animation alone.

### Empty and loading states

- "Loading usage…" becomes a skeleton: three rows of a title placeholder, a bar in `.quaternary`, and
  a caption placeholder, with `.redacted(reason: .placeholder)`, no shimmer.

## Verification

- Tests: `elapsedFraction` (start, middle, past reset clamps to 1, nil without reset), and the bar
  still reports fill and estimate as before.
- `make test` green. `make run`: screenshot the popover with live data showing the cursor on each bar
  and the icon footer. Trigger a refresh and describe the motion (spin, settle, pill dip). Toggle
  reduced motion in System Settings > Accessibility > Display if practical and confirm the spin is
  gone; if not practical, say so. Quit the app.

## Out of scope

New providers, notifications, custom colours.
