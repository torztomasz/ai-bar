import Foundation
import Testing
@testable import AIBarCore

// Method: every scenario is laid out on the fixed 5-hour `FixtureWindow` (no `Date()`), with samples placed at whole
// or half hours after the window opened, so each expected rate and projection can be worked out by hand in the test.
@Suite struct DrainEstimatorBehavior {
    // Anchor (0h, 0%) and (2.5h, 30%) give 12%/h; 2.5h left adds 30%.
    @Test func singleSampleAtHalfwayOnGentlePaceWillLast() {
        let forecast = forecast([sample(hours: 2.5, 30)], atHour: 2.5)

        #expect(forecast.outlook == .willLast)
        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
    }

    // Anchor (0h, 0%) and (2.5h, 60%) give 24%/h, so 2.5h more adds 60%. The remaining 40% takes 40/24h = 1h40m,
    // so the line crosses 100% at 4h10m, 50 minutes before reset.
    @Test func singleSampleAtHalfwayOnSteepPaceWillDrainBeforeReset() {
        let forecast = forecast([sample(hours: 2.5, 60)], atHour: 2.5)

        #expect(forecast.outlook == .willDrain(at: time(hours: 4 + 10.0 / 60)))
        #expect(forecast.ratePercentPerHour == 24)
        #expect(forecast.projectedPercentAtReset == 120)
    }

    // A burst late in the window: the anchor-to-latest average, 59% over 3h = 19.67%/h, would reach only 98.3% by
    // reset. The least-squares line through (0h,0%) (1h,1%) (3h,59%) has mean (4/3h, 20%), Σdx·dy = 98 and
    // Σdx² = 14/3, so slope 21%/h: the near-idle first hour sits below the line and tilts it steeper. That projects
    // 59 + 21 × 2 = 101% and crosses 100% after another 41/21h, at about 4h57m, just before reset.
    @Test func multipleSamplesAreFittedAsOneLineThroughTheAnchor() throws {
        let forecast = forecast([sample(hours: 1, 1), sample(hours: 3, 59)], atHour: 3)

        let rate = try #require(forecast.ratePercentPerHour)
        let projected = try #require(forecast.projectedPercentAtReset)
        #expect(abs(rate - 21) < 1e-9)
        #expect(abs(projected - 101) < 1e-9)
        #expect(isWithinASecond(forecast.outlook, of: time(hours: 3 + 41.0 / 21)))
    }

    // Same line as the steep single sample (crosses 100% at 4h10m), but the forecast is asked for at 4h30m, e.g.
    // after polls failed. A drain time in the past would be meaningless to show, so it is reported as now.
    @Test func drainTimeAlreadyPassedIsReportedAsNow() {
        let forecast = forecast([sample(hours: 2.5, 60)], atHour: 4.5)

        #expect(forecast.outlook == .willDrain(at: time(hours: 4.5)))
    }

    // The 90% sample an hour before this window opened belongs to the previous window; if it counted, the line
    // would slope downwards. Ignoring it leaves the gentle single-sample case: 12%/h, 60% at reset.
    @Test func samplesFromThePreviousWindowAreIgnored() {
        let forecast = forecast([sample(hours: -1, 90), sample(hours: 2.5, 30)], atHour: 2.5)

        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
        #expect(forecast.outlook == .willLast)
    }

    // A sample stamped after `now` (e.g. the clock moved back) cannot be trusted, so only the 30% one counts.
    @Test func samplesAfterNowAreIgnored() {
        let forecast = forecast([sample(hours: 2.5, 30), sample(hours: 3, 90)], atHour: 2.5)

        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
    }

    // A sample after the reset belongs to the next window (`resetsAt` is stale), so only the 30% one counts.
    @Test func samplesAfterTheResetAreIgnored() {
        let forecast = forecast([sample(hours: 2.5, 30), sample(hours: 5.5, 5)], atHour: 5.5)

        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
    }

    // Nothing used yet: every point, anchor included, sits at 0%, so the line is flat.
    @Test func idlePaceWillLast() {
        let forecast = forecast([sample(hours: 1, 0), sample(hours: 3, 0)], atHour: 3)

        #expect(forecast.ratePercentPerHour == 0)
        #expect(forecast.outlook == .willLast)
    }

    // Without a reset time there is no window start, so no anchor and no way to tell current samples from stale.
    @Test func unknownResetTimeGivesNoForecast() {
        let forecast = forecast([sample(hours: 2.5, 60)], atHour: 2.5, resetsAt: nil)

        #expect(forecast == .unknown)
    }

    @Test func windowAtItsLimitDrainsNow() {
        let forecast = forecast([sample(hours: 4, 100)], atHour: 4.5)

        #expect(forecast.outlook == .willDrain(at: time(hours: 4.5)))
    }

    // The reset time only matters for projecting; a window at its limit is drained already, so the badge must say so.
    @Test func windowAtItsLimitDrainsNowEvenWithoutAResetTime() {
        let forecast = forecast([sample(hours: 4, 100)], atHour: 4.5, resetsAt: nil)

        #expect(forecast.outlook == .willDrain(at: time(hours: 4.5)))
    }

    // The only sample is from the previous window, so the anchor is the sole point and there is no slope.
    @Test func anchorAloneGivesNoForecast() {
        let forecast = forecast([sample(hours: -1, 90)], atHour: 1)

        #expect(forecast == .unknown)
    }

    /// Forecast `hours` into the fixture window, against its reset time unless one is given.
    private func forecast(_ samples: [UsageSample], atHour hours: Double,
                          resetsAt: Date? = FixtureWindow.resetsAt) -> DrainForecast {
        DrainEstimator().forecast(samples: samples, resetsAt: resetsAt, now: time(hours: hours))
    }
}

private func time(hours: Double) -> Date {
    FixtureWindow.time(hours: hours)
}

private func sample(hours: Double, _ percentUsed: Double) -> UsageSample {
    UsageSample(at: time(hours: hours), percentUsed: percentUsed)
}

/// Drain times come out of floating-point division, so they are compared to the second, the precision a user sees.
private func isWithinASecond(_ outlook: DrainOutlook, of expected: Date) -> Bool {
    guard case .willDrain(let at) = outlook else { return false }
    return abs(at.timeIntervalSince(expected)) < 1
}
