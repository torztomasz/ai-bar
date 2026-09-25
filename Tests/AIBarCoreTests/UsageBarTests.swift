import Foundation
import Testing
@testable import AIBarCore

// Method: each threshold is probed on both sides of its boundary (69.9/70, 89.9/90), since an off-by-one in `<`
// versus `<=` is the likely mistake and only shows at the exact boundary.
@Suite struct UsageLevelThresholds {
    @Test func belowSeventyPercentIsOK() {
        #expect(UsageLevel(percent: 0) == .ok)
        #expect(UsageLevel(percent: 69.9) == .ok)
    }

    @Test func fromSeventyUpToNinetyIsAWarning() {
        #expect(UsageLevel(percent: 70) == .warning)
        #expect(UsageLevel(percent: 89.9) == .warning)
    }

    // Overage above 100% is still critical, not something the thresholds forget about.
    @Test func fromNinetyUpIsCritical() {
        #expect(UsageLevel(percent: 90) == .critical)
        #expect(UsageLevel(percent: 130) == .critical)
    }
}

// Method: build bars from a reading and a projection the way the popover does, and assert on the fractions of the
// bar's width and the levels that colour them. Fractions are hand-picked percents divided by 100.
@Suite struct UsageBarGeometry {
    // The fill speaks for now (60%, green); the estimate for the reset (95%, red), so a bar warns ahead of time.
    @Test func fillFollowsTheReadingAndEstimateFollowsTheProjection() {
        let bar = UsageBar(percentUsed: 60, projectedPercentAtReset: 95)

        #expect(bar.fill == UsageBar.Segment(fraction: 0.6, level: .ok))
        #expect(bar.estimate == UsageBar.Segment(fraction: 0.95, level: .critical))
    }

    // A bar cannot extend past its end, but a projected overage is still critical.
    @Test func estimateBeyondTheLimitStopsAtTheEndOfTheBar() {
        let bar = UsageBar(percentUsed: 80, projectedPercentAtReset: 140)

        #expect(bar.fill == UsageBar.Segment(fraction: 0.8, level: .warning))
        #expect(bar.estimate == UsageBar.Segment(fraction: 1, level: .critical))
    }

    @Test func noProjectionMeansNoEstimate() {
        #expect(UsageBar(percentUsed: 40, projectedPercentAtReset: nil).estimate == nil)
    }

    // A flat or falling pace projects nothing beyond the fill, so there is nothing to draw.
    @Test func projectionNotAboveTheReadingMeansNoEstimate() {
        #expect(UsageBar(percentUsed: 40, projectedPercentAtReset: 40).estimate == nil)
        #expect(UsageBar(percentUsed: 40, projectedPercentAtReset: 30).estimate == nil)
    }

    // A provider may report overage: the fill is full, and a higher projection has no room left to show.
    @Test func overageFillsTheBarWithNoRoomForAnEstimate() {
        let bar = UsageBar(percentUsed: 110, projectedPercentAtReset: 150)

        #expect(bar.fill == UsageBar.Segment(fraction: 1, level: .critical))
        #expect(bar.estimate == nil)
    }
}
