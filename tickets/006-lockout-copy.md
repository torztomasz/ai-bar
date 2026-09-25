# 006 — Say how long you will be locked out, not when it drains

Blocked by: nothing. Base: `main`.

## Goal

The user does not care at what time a window drains. The one question the forecast must answer is
"for how long will I be without this provider?" Every forecast string becomes a lockout duration.

## Why

"Drains at 6:13 on Tue, 29 Sep" makes the reader do date arithmetic. "Locked out for ~2d 4h" is the
answer they wanted, and it is what should drive the colour of the line.

## Requirements

### Core (`AIBarCore`)

- Add to `DrainForecast` a computed `lockout(resetsAt: Date?) -> TimeInterval?`: for `.willDrain(at:)`
  it is `resetsAt - at` clamped to zero or more; nil for `.willLast`, `.unknown`, or when `resetsAt`
  is nil. Document why (the reset ends the lockout).
- `UsageText.forecast` is replaced by `UsageText.lockout(_ forecast: DrainForecast?, resetsAt: Date?) -> String`:
  - `.willDrain` with a lockout → `"Locked out for ~2d 4h"` using the existing `duration` formatter
    (so `~1h 20m`, `~45m`, `~<1m`).
  - `.willDrain` with no reset time → `"Locked out"`.
  - `.willLast` → `"Lasts to reset"`.
  - `.unknown` or nil → `"No estimate yet"`.
  - Remove the locale/timezone parameters and the `spansDays` helper; nothing formats a clock any more.
- `UsageText.tooltip` replaces "projected 71% at reset" with the lockout string when there is one
  (e.g. `Claude 5-hour: 42% · resets in 2h 13m · locked out for ~1h 20m`), and with nothing when the
  window lasts. Keep the failed-refresh suffix.
- A `UsageText.lockoutIsSevere`-style helper is not needed; the view can check `lockout != nil`.

### App (`AIBar`)

- `WindowRow` shows the lockout line where the forecast line was. When a lockout exists, colour the
  line with the bar's critical colour and use `.semibold`; otherwise keep it secondary. Keep the
  `ViewThatFits` fallback.
- Nothing else in the layout changes; ticket 008 does the visual pass.

## Verification

- Tests for `lockout(resetsAt:)` (drain before reset, drain after reset clamps to 0, willLast nil,
  nil reset nil) and for every `UsageText.lockout` branch, plus the tooltip with and without lockout.
  Delete the old forecast-wording tests, including the locale-dependent one.
- `make test` green. `make run` once and confirm the popover shows lockout lines (screenshot or a
  clear description). Quit the app.

## Out of scope

Settings, animation, bar redesign (007, 008).
