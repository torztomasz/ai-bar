import Foundation

/// Timing of the rolling session window, kept in one place so the estimator and the sample store agree on which
/// samples belong to the current window.
public enum SessionWindow {
    /// Claude's session limit resets 5 hours after the request that opened the window.
    public static let defaultLength: TimeInterval = 5 * secondsPerHour

    static let secondsPerHour: TimeInterval = 3600

    static func start(resetsAt: Date, length: TimeInterval) -> Date {
        resetsAt.addingTimeInterval(-length)
    }
}
