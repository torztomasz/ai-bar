/// The forecast a menu bar badge conveys. Lives in Core, not beside the renderer, so the mapping from
/// usage to badge can be a pure, unit-tested function without AppKit.
public enum BadgeTint: Sendable {
    case neutral
    case ok
    case danger
}
