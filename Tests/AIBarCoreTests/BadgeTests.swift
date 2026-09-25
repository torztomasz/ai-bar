import Foundation
import Testing
@testable import AIBarCore

// Method: build the badge from hand-made windows and forecasts, the same inputs the app passes after a refresh,
// and assert on the exact text and tint the menu bar would draw.
@Suite struct BadgeTintFromForecast {
    @Test func windowThatWillLastIsGreen() {
        #expect(BadgeTint(forecast: forecast(.willLast)) == .ok)
    }

    @Test func windowThatWillDrainIsRed() {
        #expect(BadgeTint(forecast: forecast(.willDrain(at: Date(timeIntervalSince1970: 0)))) == .danger)
    }

    // Colouring a guess would mislead, so anything short of a verdict stays plain.
    @Test func unknownOrMissingForecastIsNeutral() {
        #expect(BadgeTint(forecast: forecast(.unknown)) == .neutral)
        #expect(BadgeTint(forecast: nil) == .neutral)
    }
}

private func forecast(_ outlook: DrainOutlook) -> DrainForecast {
    DrainForecast(outlook: outlook, projectedPercentAtReset: nil, ratePercentPerHour: nil)
}

@Suite struct BadgeText {
    @Test func showsThePrimaryWindowPercentRoundedToAWholeNumber() {
        #expect(UsageText.badge(primaryWindow: fiveHour(percent: 42.4), hasError: false) == "42%")
        #expect(UsageText.badge(primaryWindow: fiveHour(percent: 41.6), hasError: false) == "42%")
    }

    // Before the first successful fetch there is nothing to show, but the item must keep its place in the menu bar.
    @Test func showsPlaceholderBeforeAnyData() {
        #expect(UsageText.badge(primaryWindow: nil, hasError: false) == "--%")
    }

    @Test func marksThePlaceholderWhenFetchingFailed() {
        #expect(UsageText.badge(primaryWindow: nil, hasError: true) == "--%!")
    }

    // A failed refresh keeps the last snapshot; its percent is still the best number available.
    @Test func keepsShowingTheLastPercentWhenARefreshFailed() {
        #expect(UsageText.badge(primaryWindow: fiveHour(percent: 42), hasError: true) == "42%")
    }
}

private func fiveHour(percent: Double) -> UsageWindow {
    UsageWindow(id: "session", kind: .fiveHour, title: "5-hour", percentUsed: percent, resetsAt: nil)
}
