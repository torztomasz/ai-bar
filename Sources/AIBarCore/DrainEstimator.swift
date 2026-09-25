import Foundation

/// Decides whether the 5-hour window will be used up before it resets, from the usage samples seen so far.
///
/// The window opens on the first request, so usage at its start is 0% by definition. That start
/// (`resetsAt - windowLength`) serves as an implicit `(start, 0%)` anchor, which is why a single observation is
/// already enough to forecast. The pace is the slope of a least-squares line through the anchor and every sample
/// in the current window: fitting all points smooths out poll jitter instead of trusting the last two readings.
/// The forecast extends that pace from the latest sample to the reset. Samples outside the window (before its
/// start, after the reset, or after `now`) are ignored because they describe another window or a clock glitch.
public struct DrainEstimator {
    public let windowLength: TimeInterval

    public init(windowLength: TimeInterval = 5 * 3600) {
        self.windowLength = windowLength
    }

    public func forecast(samples: [UsageSample], resetsAt: Date?, now: Date) -> DrainForecast {
        guard let resetsAt else { return .unknown }
        let windowStart = resetsAt.addingTimeInterval(-windowLength)
        let inWindow = samples.filter { $0.at >= windowStart && $0.at <= min(now, resetsAt) }
        guard let latest = inWindow.max(by: { $0.at < $1.at }) else { return .unknown }

        let anchor = UsageSample(at: windowStart, percentUsed: 0)
        let rate = leastSquaresRatePerHour(through: [anchor] + inWindow)
        let projected = rate.map { latest.percentUsed + $0 * hours(from: latest.at, to: resetsAt) }

        if latest.percentUsed >= 100 {
            return DrainForecast(outlook: .willDrain(at: now), projectedPercentAtReset: projected,
                                 ratePercentPerHour: rate)
        }
        guard let rate, let projected else { return .unknown }
        // Also covers an idle or falling pace: with the latest reading below 100%, a rate <= 0 never projects past it.
        guard projected >= 100 else {
            return DrainForecast(outlook: .willLast, projectedPercentAtReset: projected, ratePercentPerHour: rate)
        }
        let drainsAt = latest.at.addingTimeInterval((100 - latest.percentUsed) / rate * 3600)
        return DrainForecast(outlook: .willDrain(at: max(drainsAt, now)), projectedPercentAtReset: projected,
                             ratePercentPerHour: rate)
    }
}

public enum DrainOutlook: Equatable, Sendable {
    /// Projected usage at reset stays below 100%.
    case willLast
    /// Projected to reach 100% at this time, before the reset; never earlier than the time asked about.
    case willDrain(at: Date)
    /// No reset time, or no sample in the current window to project from.
    case unknown
}

public struct DrainForecast: Equatable, Sendable {
    public let outlook: DrainOutlook
    public let projectedPercentAtReset: Double?
    public let ratePercentPerHour: Double?

    static let unknown = DrainForecast(outlook: .unknown, projectedPercentAtReset: nil, ratePercentPerHour: nil)
}

/// Slope of percent against hours; `nil` when all samples share one timestamp, so no line is defined.
private func leastSquaresRatePerHour(through samples: [UsageSample]) -> Double? {
    guard let origin = samples.first?.at else { return nil }
    let xs = samples.map { hours(from: origin, to: $0.at) }
    let ys = samples.map(\.percentUsed)
    let meanX = xs.reduce(0, +) / Double(xs.count)
    let meanY = ys.reduce(0, +) / Double(ys.count)
    let covariance = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
    let variance = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
    return variance > 0 ? covariance / variance : nil
}

private func hours(from start: Date, to end: Date) -> Double {
    end.timeIntervalSince(start) / 3600
}
