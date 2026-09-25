# 005 — Threshold-coloured bars, per-window estimates, capsule badge

Blocked by: 004. Base: `004-app-wiring`.

## Goal

Five user-requested visual and forecasting changes after seeing the first working build.

## Why

The first build showed grey progress bars (SwiftUI `ProgressView` renders grey when the popover window is not key), a forecast only for the 5-hour window, and a badge whose rounded rectangle does not match the shape of the system camera-indicator pill next to it in the menu bar.

## Requirements

### 1. Bar fill colour by threshold

The filled part of every bar in the popover is coloured by the value it represents: green below 70%, yellow from 70% up to 90%, red from 90% up. Put the threshold rule in `AIBarCore` as a pure function (e.g. `UsageLevel(percent:) -> .ok | .warning | .critical`) with tests at the boundaries (69.9, 70, 89.9, 90).

### 2. Estimate segment on every bar

Behind the solid fill, draw a second segment from the current percent to the projected percent at reset, clamped to 100, using the threshold colour of the **projected** value at 25% opacity. Solid segment colour follows the **current** value. No estimate segment when there is no forecast or when the projection is not above the current value.

### 3. Estimates for every window, not only the 5-hour one

Today `UsageController` records samples and forecasts only the primary (5-hour) window. Extend it so every window with a known length gets its own sample history and forecast:

- Window length by kind: `.fiveHour` → 5 h, `.weekly` and `.weeklyModel` → 7 days, `.other` → no forecast (`.unknown`, no estimate segment).
- One `SampleStore` per (provider, window id), file `samples-<providerID>-<windowID>.json` (sanitise the id for the filesystem; ids contain `:` and `·`). Keep the existing 5-hour file name working or migrate it; do not lose the current history silently.
- `DrainEstimator` already takes `windowLength`; `SessionWindow` currently hard-codes 5 h, so generalise whatever is needed. The anchor rule stays: usage is 0 at `resetsAt - windowLength`.
- Per-provider published state becomes per-window forecasts (e.g. `forecasts: [UsageWindow.ID: DrainForecast]`). The badge tint still comes from the 5-hour forecast.
- The forecast line ("On pace to last" / "Drains at …" / "Not enough data") shows under every window that has a forecast, not only the primary one. For weekly windows "Drains at" should show a date and time, not just a time.

### 4. Badge shape matches the camera pill

`tickets/005-reference-camera-pill.png` is a 2x screenshot of the menu bar showing the system camera indicator (green capsule with a camera glyph) next to the current `8%` badge. Make the badge a capsule whose height, corner radius (height / 2), and vertical placement match the camera pill 1:1. Measure the pill in the image (pixel height ÷ 2 = points) and use that height; keep horizontal padding proportional so the text sits centred with similar inset to the glyph. Keep the current font weight and the white text on green/red, neutral stays plain text.

### 5. Bars must never render grey

Replace `ProgressView` in the popover with a custom bar (a `Capsule` track with `Capsule` fills in a `GeometryReader` or `ZStack`) so the colour does not depend on the window being key. Track colour: a quiet secondary fill (`.quaternary` or similar), never the accent colour.

## Verification

- `make test` passes; new tests cover the threshold function, the estimate-segment geometry (a pure function returning solid and estimate fractions plus their levels), window length by kind, and per-window forecasting in the controller if it is testable without AppKit (move the pure part to Core if needed).
- `make run` with the live account: screenshot the popover open (`screencapture -x`) and confirm: every bar is coloured, not grey; each bar shows a translucent estimate segment beyond the solid fill where the projection exceeds the current value; the forecast line appears under every window; the badge is a capsule the same height as the camera pill (if the camera is not active, compare with the reference image). Quit the app afterwards.

## Out of scope

Badge threshold colouring (the badge stays green/red by drain outlook), new providers, settings.
