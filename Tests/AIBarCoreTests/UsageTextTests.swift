import Foundation
import Testing
@testable import AIBarCore

// Method (all suites in this file): every time is an offset from one fixed `now` (no `Date()`), written out in
// hours, minutes and seconds so the expected wording can be read straight off the offset, and each test asserts on
// the exact string the user would read.
@Suite struct ResetCountdownText {
    // Seconds are dropped, not rounded up, so the countdown never claims more time than is left.
    @Test func showsHoursAndMinutesLeft() {
        #expect(UsageText.resetsIn(after(hours: 2, minutes: 13, seconds: 50), now: now) == "resets in 2h 13m")
    }

    @Test func omitsHoursUnderAnHour() {
        #expect(UsageText.resetsIn(after(minutes: 45), now: now) == "resets in 45m")
    }

    @Test func showsDaysForWeeklyWindows() {
        #expect(UsageText.resetsIn(after(hours: 4 * 24 + 3, minutes: 12), now: now) == "resets in 4d 3h 12m")
    }

    @Test func underAMinuteIsNotShownAsZero() {
        #expect(UsageText.resetsIn(after(seconds: 20), now: now) == "resets in <1m")
    }

    // The provider has not caught up with the reset yet; a negative countdown would be nonsense.
    @Test func resetTimeInThePastReadsAsNow() {
        #expect(UsageText.resetsIn(after(minutes: -3), now: now) == "resets now")
    }

    @Test func unknownResetTimeIsADash() {
        #expect(UsageText.resetsIn(nil, now: now) == "—")
    }
}

@Suite struct LastUpdatedText {
    @Test func showsWholeMinutesSinceTheRefresh() {
        #expect(UsageText.updated(after(minutes: -3, seconds: -40), now: now) == "Updated 3 min ago")
    }

    // Right after a refresh "0 min ago" would read like a glitch.
    @Test func underAMinuteReadsAsJustNow() {
        #expect(UsageText.updated(after(seconds: -20), now: now) == "Updated just now")
    }

    // After sleep or repeated failures the age can run to hours; "95 min" is harder to read than "1h 35m".
    @Test func anHourOrMoreUsesHoursAndMinutes() {
        #expect(UsageText.updated(after(hours: -1, minutes: -35), now: now) == "Updated 1h 35m ago")
    }

    @Test func neverRefreshedSaysSo() {
        #expect(UsageText.updated(nil, now: now) == "Not updated yet")
    }
}

// `now` is 08:00 UTC; the drain time is formatted in UTC with a 24-hour locale so the expected clock reading is fixed.
@Suite struct ForecastLineText {
    @Test func windowThatWillLastSaysSo() {
        #expect(line(.willLast) == "On pace to last")
    }

    @Test func windowThatWillDrainShowsTheClockTime() {
        #expect(line(.willDrain(at: after(hours: 6, minutes: 35))) == "Drains at 14:35")
    }

    @Test func unknownOrMissingForecastAsksForPatience() {
        #expect(line(.unknown) == "Not enough data")
        #expect(UsageText.forecast(nil) == "Not enough data")
    }

    private func line(_ outlook: DrainOutlook) -> String {
        UsageText.forecast(.verdict(outlook), locale: Locale(identifier: "en_GB"), timeZone: .gmt)
    }
}

@Suite struct StatusItemTooltip {
    @Test func spellsOutPercentResetAndProjection() {
        let window = UsageWindow.fiveHour(percent: 42, resetsAt: after(hours: 2, minutes: 13))
        let forecast = DrainForecast(outlook: .willLast, projectedPercentAtReset: 71.2, ratePercentPerHour: 12)

        #expect(tooltip(window, forecast) == "Claude 5-hour: 42% · resets in 2h 13m · projected 71% at reset")
    }

    // Parts the data cannot back are left out instead of shown as placeholders.
    @Test func omitsResetAndProjectionWhenUnknown() {
        #expect(tooltip(.fiveHour(percent: 42, resetsAt: nil), nil) == "Claude 5-hour: 42%")
    }

    @Test func explainsAFailureWhenThereIsNoData() {
        let text = UsageText.tooltip(providerName: "Claude", primaryWindow: nil, forecast: nil,
                                     errorDescription: "Sign in to Claude Code to see usage.", now: now)

        #expect(text == "Claude: Sign in to Claude Code to see usage.")
    }

    // The badge keeps the last reading after a failed refresh, so the tooltip is where the user learns it is stale.
    @Test func flagsAFailedRefreshAfterTheLastReading() {
        let text = UsageText.tooltip(providerName: "Claude", primaryWindow: .fiveHour(percent: 42), forecast: nil,
                                     errorDescription: "Can't reach Claude.", now: now)

        #expect(text == "Claude 5-hour: 42% · last refresh failed: Can't reach Claude.")
    }

    @Test func saysWhenThereIsNoDataYet() {
        #expect(tooltip(nil, nil) == "Claude: no usage data yet")
    }

    private func tooltip(_ window: UsageWindow?, _ forecast: DrainForecast?) -> String {
        UsageText.tooltip(providerName: "Claude", primaryWindow: window, forecast: forecast, errorDescription: nil,
                          now: now)
    }
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func after(hours: Double = 0, minutes: Double = 0, seconds: Double = 0) -> Date {
    now.addingTimeInterval(hours * 3600 + minutes * 60 + seconds)
}
