import Foundation

/// The 5-hour window the time-based tests are laid out on. Fixed dates, so no test depends on the clock.
enum FixtureWindow {
    static let resetsAt = Date(timeIntervalSince1970: 1_800_000_000)

    /// A point `hours` after the window opened; negative values fall in the previous window.
    static func time(hours: Double) -> Date {
        resetsAt.addingTimeInterval((hours - 5) * 3600)
    }
}
