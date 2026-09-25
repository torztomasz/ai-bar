import Foundation
import Testing
@testable import AIBarCore

// Method (both suites): build the badge from hand-made windows and forecasts, the same inputs the app passes after a
// refresh, and assert on the exact text and tint the menu bar would draw.
@Suite struct BadgeTintFromForecast {
    @Test func windowThatWillLastIsGreen() {
        #expect(BadgeTint(forecast: .verdict(.willLast)) == .ok)
    }

    @Test func windowThatWillDrainIsRed() {
        #expect(BadgeTint(forecast: .verdict(.willDrain(at: Date(timeIntervalSince1970: 0)))) == .danger)
    }

    // Colouring a guess would mislead, so anything short of a verdict stays plain.
    @Test func unknownOrMissingForecastIsNeutral() {
        #expect(BadgeTint(forecast: .verdict(.unknown)) == .neutral)
        #expect(BadgeTint(forecast: nil) == .neutral)
    }
}

@Suite struct BadgeText {
    @Test func showsThePrimaryWindowPercentRoundedToAWholeNumber() {
        #expect(UsageText.badge(primaryWindow: .fiveHour(percent: 42.4), hasError: false) == "42%")
        #expect(UsageText.badge(primaryWindow: .fiveHour(percent: 41.6), hasError: false) == "42%")
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
        #expect(UsageText.badge(primaryWindow: .fiveHour(percent: 42), hasError: true) == "42%")
    }
}

// Method: menu bar heights are the ones macOS reports (points between a screen's top and its visible frame); each
// test says which display they stand for. The expected heights follow from the camera pill's 24 pt and a 2 pt
// margin above and below.
@Suite struct BadgeHeightForMenuBars {
    // An external display (30 pt bar) and a notched built-in one (33 pt): both leave room for the full pill height.
    @Test func matchesTheCameraPillWhereTheMenuBarHasRoom() {
        #expect(BadgeSize.height(menuBarHeights: [30, 33]) == 24)
    }

    // A 24 pt bar on a non-notched display would be filled edge to edge, so the badge shrinks to keep its margins.
    @Test func shrinksToKeepAMarginOnAShortMenuBar() {
        #expect(BadgeSize.height(menuBarHeights: [24]) == 20)
    }

    // One image is shown on every display's menu bar, so it has to fit the shortest.
    @Test func fitsTheShortestMenuBarWhenDisplaysDiffer() {
        #expect(BadgeSize.height(menuBarHeights: [24, 33]) == 20)
    }

    // A menu bar hidden by a full-screen app reports no height; it is no reason to shrink the badge.
    @Test func ignoresHiddenMenuBars() {
        #expect(BadgeSize.height(menuBarHeights: [0, 30]) == 24)
        #expect(BadgeSize.height(menuBarHeights: []) == 24)
    }
}
