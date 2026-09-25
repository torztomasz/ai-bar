/// What a window's bar draws: a solid fill for the reading now and, behind it, a translucent estimate reaching to
/// the projected reading at reset, so a bar shows where usage is heading and not only where it is.
///
/// Both segments are measured from the bar's leading edge as fractions of its width (0...1). The estimate is drawn
/// from the leading edge too, under the fill, so only its part past the fill shows; starting it at the fill's end
/// instead would leave a notch where the fill's rounded end meets it.
public struct UsageBar: Equatable, Sendable {
    public let fill: Segment
    /// `nil` without a projection, or when the projection does not reach past the fill.
    public let estimate: Segment?

    public struct Segment: Equatable, Sendable {
        public let fraction: Double
        /// From the unclamped percent, so an overage past the end of the bar still reads as critical.
        public let level: UsageLevel

        public init(fraction: Double, level: UsageLevel) {
            self.fraction = fraction
            self.level = level
        }

        init(percent: Double) {
            self.init(fraction: min(max(percent, 0), 100) / 100, level: UsageLevel(percent: percent))
        }
    }

    public init(percentUsed: Double, projectedPercentAtReset: Double?) {
        let fill = Segment(percent: percentUsed)
        let estimate = projectedPercentAtReset.map(Segment.init(percent:))
        self.fill = fill
        self.estimate = estimate.flatMap { $0.fraction > fill.fraction ? $0 : nil }
    }
}

/// How close a reading is to its limit, which decides a bar's colour. Thresholds rather than a gradient so the
/// colour changes at points a user can learn: 70% is time to pace yourself, 90% is about to run out.
public enum UsageLevel: Equatable, Sendable {
    case ok
    case warning
    case critical

    public init(percent: Double) {
        switch percent {
        case ..<70: self = .ok
        case ..<90: self = .warning
        default: self = .critical
        }
    }
}
