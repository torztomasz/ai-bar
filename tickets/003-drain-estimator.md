# 003 — Drain estimator and sample store

Blocked by: 001 (needs `UsageWindow`). Base: `001-scaffold`.

## Goal

Pure logic in `AIBarCore` that decides whether the 5-hour window will be drained (reach 100%) before it resets, given the usage samples observed so far, plus a small persistent store for those samples so the estimate survives app restarts.

## Why

The menu bar badge is red when the current pace will exhaust the window before it resets and green when it will not. This is the one piece of judgement in the app, so it must be deterministic and unit-tested, and it must not depend on AppKit or the network.

## Requirements

### Types

```swift
public struct UsageSample: Codable, Equatable, Sendable {
    public let at: Date
    public let percentUsed: Double
}

public enum DrainOutlook: Equatable, Sendable {
    case willLast            // projected usage at reset < 100%
    case willDrain(at: Date) // projected to hit 100% at this time, before reset
    case unknown             // no reset time or nothing to project from
}

public struct DrainForecast: Equatable, Sendable {
    public let outlook: DrainOutlook
    public let projectedPercentAtReset: Double?
    public let ratePercentPerHour: Double?
}

public struct DrainEstimator {
    public init(windowLength: TimeInterval = 5 * 3600)
    public func forecast(samples: [UsageSample], resetsAt: Date?, now: Date) -> DrainForecast
}
```

### Method

- The window started at `resetsAt - windowLength`. That gives an implicit anchor sample `(windowStart, 0%)`, so a forecast is possible from the very first observation. Rationale: Claude's 5-hour window opens on the first request, so usage at the window start is 0 by definition.
- Only samples inside the current window (`at >= windowStart`) count. Older samples belong to a previous window and are ignored.
- Rate = slope of a least-squares line through the anchor plus in-window samples (percent vs. hours). If only the anchor exists (no samples), outlook is `.unknown`.
- Projection at reset = latest percent + rate × hours until reset. `>= 100` → `.willDrain(at:)` where `at` is when the line crosses 100 (clamped to no earlier than `now`); else `.willLast`.
- Rate `<= 0` (idle) → `.willLast` unless latest percent is already `>= 100`, which is `.willDrain(at: now)`.
- `resetsAt == nil` → `.unknown`. Percent already `>= 100` → `.willDrain(at: now)` regardless.
- Guard against a `now` earlier than the last sample or samples after `resetsAt`: treat them as outside the window.

Document the method in a short doc comment on `DrainEstimator` (what and why, not a restatement of the code).

### Sample store

`public final class SampleStore` (actor or `@unchecked Sendable` with a lock, your call):
- `init(fileURL: URL)` and a convenience `static func defaultStore()` under `~/Library/Application Support/AI Bar/samples-<providerID>.json` (create directories).
- `func append(_ sample: UsageSample, resetsAt: Date?)`, `func samples() -> [UsageSample]`, `func clear()`.
- Prunes samples older than the window length, so the file never grows unbounded. Persist as JSON via `Codable`. Persist failures are logged, not thrown, because losing history must never break the app.

## Verification

Unit tests, using fixed `Date` values (no `Date()` in tests):
- Single sample halfway through the window at 30% → `.willLast`, projected 60%.
- Single sample halfway through at 60% → `.willDrain`, projected 120%, drain time before reset.
- Multiple samples where recent slope is steep enough to drain even though the average from the anchor would not (regression uses all points; assert on the numbers you compute, and state in the test why they are what they are).
- Samples from a previous window are ignored.
- Zero rate → `.willLast`; `resetsAt == nil` → `.unknown`; percent 100 → `.willDrain(at: now)`.
- `SampleStore` round-trips through a temp file and prunes old samples.

## Out of scope

Fetching data, UI, colors. 004 maps `DrainOutlook` to badge tint.
