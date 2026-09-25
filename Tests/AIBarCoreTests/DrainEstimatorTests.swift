import Foundation
import Testing
@testable import AIBarCore

// Method: every scenario is laid out on a fixed 5-hour window (no `Date()`), with samples placed at whole or half
// hours after the window opened, so each expected rate and projection can be worked out by hand in the test.
@Suite struct DrainForecasting {
    let estimator = DrainEstimator()

    // Anchor (0h, 0%) and (2.5h, 30%) give 12%/h; 2.5h left adds 30%.
    @Test func singleSampleAtHalfwayOnGentlePaceWillLast() {
        let forecast = estimator.forecast(samples: [sample(hours: 2.5, 30)], resetsAt: resetsAt, now: time(hours: 2.5))

        #expect(forecast.outlook == .willLast)
        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
    }

    // Anchor (0h, 0%) and (2.5h, 60%) give 24%/h, so 2.5h more adds 60%. The remaining 40% takes 40/24h = 1h40m,
    // so the line crosses 100% at 4h10m, 50 minutes before reset.
    @Test func singleSampleAtHalfwayOnSteepPaceWillDrainBeforeReset() {
        let forecast = estimator.forecast(samples: [sample(hours: 2.5, 60)], resetsAt: resetsAt, now: time(hours: 2.5))

        #expect(forecast.outlook == .willDrain(at: time(hours: 4 + 10.0 / 60)))
        #expect(forecast.ratePercentPerHour == 24)
        #expect(forecast.projectedPercentAtReset == 120)
    }

    // A burst late in the window: the last hour alone ran at 35%/h, which would reach 115% by reset, while the
    // anchor-to-latest average of 15%/h would reach 75%. The least-squares line through all four points
    // (0,0) (1,5) (2,10) (3,45) has mean (1.5h, 15%), Σdx·dy = 70 and Σdx² = 5, so slope 14%/h and a projection of
    // 45 + 14 × 2 = 73%. The regression weighs the quiet first hours and the anchor as much as the burst, so it
    // does not flag this pace; this test pins that behaviour down.
    @Test func multipleSamplesAreFittedAsOneLineThroughTheAnchor() {
        let samples = [sample(hours: 1, 5), sample(hours: 2, 10), sample(hours: 3, 45)]

        let forecast = estimator.forecast(samples: samples, resetsAt: resetsAt, now: time(hours: 3))

        #expect(forecast.ratePercentPerHour == 14)
        #expect(forecast.projectedPercentAtReset == 73)
        #expect(forecast.outlook == .willLast)
    }

    // Same line as the steep single sample (crosses 100% at 4h10m), but the forecast is asked for at 4h30m, e.g.
    // after polls failed. A drain time in the past would be meaningless to show, so it is reported as now.
    @Test func drainTimeAlreadyPassedIsReportedAsNow() {
        let now = time(hours: 4.5)

        let forecast = estimator.forecast(samples: [sample(hours: 2.5, 60)], resetsAt: resetsAt, now: now)

        #expect(forecast.outlook == .willDrain(at: now))
    }

    // The 90% sample an hour before this window opened belongs to the previous window; if it counted, the line
    // would slope downwards. Ignoring it leaves the gentle single-sample case: 12%/h, 60% at reset.
    @Test func samplesFromThePreviousWindowAreIgnored() {
        let samples = [sample(hours: -1, 90), sample(hours: 2.5, 30)]

        let forecast = estimator.forecast(samples: samples, resetsAt: resetsAt, now: time(hours: 2.5))

        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
        #expect(forecast.outlook == .willLast)
    }

    // A sample stamped after `now` (e.g. the clock moved back) cannot be trusted, so only the 30% one counts.
    @Test func samplesAfterNowAreIgnored() {
        let samples = [sample(hours: 2.5, 30), sample(hours: 3, 90)]

        let forecast = estimator.forecast(samples: samples, resetsAt: resetsAt, now: time(hours: 2.5))

        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
    }

    // A sample after the reset belongs to the next window (`resetsAt` is stale), so only the 30% one counts.
    @Test func samplesAfterTheResetAreIgnored() {
        let samples = [sample(hours: 2.5, 30), sample(hours: 5.5, 5)]

        let forecast = estimator.forecast(samples: samples, resetsAt: resetsAt, now: time(hours: 5.5))

        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
    }

    // Nothing used yet: every point, anchor included, sits at 0%, so the line is flat.
    @Test func idlePaceWillLast() {
        let samples = [sample(hours: 1, 0), sample(hours: 3, 0)]

        let forecast = estimator.forecast(samples: samples, resetsAt: resetsAt, now: time(hours: 3))

        #expect(forecast.ratePercentPerHour == 0)
        #expect(forecast.outlook == .willLast)
    }

    // Without a reset time there is no window start, so no anchor and no way to tell current samples from stale.
    @Test func unknownResetTimeGivesNoForecast() {
        let forecast = estimator.forecast(samples: [sample(hours: 2.5, 60)], resetsAt: nil, now: time(hours: 2.5))

        #expect(forecast == DrainForecast(outlook: .unknown, projectedPercentAtReset: nil, ratePercentPerHour: nil))
    }

    @Test func windowAlreadyAtItsLimitDrainsNow() {
        let now = time(hours: 4.5)

        let forecast = estimator.forecast(samples: [sample(hours: 4, 100)], resetsAt: resetsAt, now: now)

        #expect(forecast.outlook == .willDrain(at: now))
    }

    // The only sample is from the previous window, so the anchor is the sole point and there is no slope.
    @Test func anchorAloneGivesNoForecast() {
        let forecast = estimator.forecast(samples: [sample(hours: -1, 90)], resetsAt: resetsAt, now: time(hours: 1))

        #expect(forecast == DrainForecast(outlook: .unknown, projectedPercentAtReset: nil, ratePercentPerHour: nil))
    }
}

/// Reset time of the window every scenario uses; its start is 5 hours earlier.
private let resetsAt = Date(timeIntervalSince1970: 1_800_000_000)

/// A point in the window, `hours` after it opened.
private func time(hours: Double) -> Date {
    resetsAt.addingTimeInterval((hours - 5) * 3600)
}

private func sample(hours: Double, _ percentUsed: Double) -> UsageSample {
    UsageSample(at: time(hours: hours), percentUsed: percentUsed)
}
