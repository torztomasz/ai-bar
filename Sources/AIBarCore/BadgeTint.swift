/// The forecast a menu bar badge conveys. Lives in Core, not beside the renderer, so the mapping from
/// usage to badge can be a pure, unit-tested function without AppKit.
public enum BadgeTint: Sendable {
    case neutral
    case ok
    case danger

    /// Only a verdict gets a colour: tinting an unknown outlook would present a guess as a forecast.
    public init(forecast: DrainForecast?) {
        switch forecast?.outlook {
        case .willLast: self = .ok
        case .willDrain: self = .danger
        case .estimating, .unknown, nil: self = .neutral
        }
    }
}
