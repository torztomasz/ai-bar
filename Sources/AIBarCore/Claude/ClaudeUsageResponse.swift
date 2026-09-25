import Foundation

/// The subset of `GET /api/oauth/usage` the app reads.
///
/// Every field is optional because the endpoint is undocumented and sends `null` freely: a window missing what
/// the app needs is skipped instead of failing the whole response.
struct ClaudeUsageResponse: Decodable {
    /// The structured form and the source of truth when present.
    let limits: [Limit]?
    /// Older flat form, read only when `limits` is missing or empty.
    let fiveHour: LegacyWindow?
    let sevenDay: LegacyWindow?

    struct Limit: Decodable {
        let kind: String?
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?
    }

    struct Scope: Decodable {
        let model: Model?
    }

    struct Model: Decodable {
        let displayName: String?
    }

    struct LegacyWindow: Decodable {
        let utilization: Double?
        let resetsAt: String?
    }

    var windows: [UsageWindow] {
        if let limits, !limits.isEmpty {
            return inDisplayOrder(limits.compactMap(\.window))
        }
        return legacyWindows
    }

    private var legacyWindows: [UsageWindow] {
        [
            fiveHour?.window(id: "session", kind: .fiveHour, title: "5-hour"),
            sevenDay?.window(id: "weekly_all", kind: .weekly, title: "Weekly"),
        ].compactMap { $0 }
    }
}

extension ClaudeUsageResponse.Limit {
    var window: UsageWindow? {
        guard let kind, let percent else { return nil }
        let (id, windowKind, title) = identity(kind: kind)
        return UsageWindow(id: id, kind: windowKind, title: title, percentUsed: percent,
                           resetsAt: resetsAt.flatMap(parseResetDate))
    }

    private func identity(kind: String) -> (id: String, kind: UsageWindow.Kind, title: String) {
        switch (kind, scope?.model?.displayName) {
        case ("session", _):
            ("session", .fiveHour, "5-hour")
        case ("weekly_all", _):
            ("weekly_all", .weekly, "Weekly")
        case ("weekly_scoped", let model?):
            ("weekly_scoped:\(model)", .weeklyModel(name: model), "Weekly · \(model)")
        default:
            (kind, .other, kind)
        }
    }
}

extension ClaudeUsageResponse.LegacyWindow {
    /// Legacy windows take the ids of their `limits` counterparts so a window keeps its identity
    /// whichever shape the server sends.
    func window(id: String, kind: UsageWindow.Kind, title: String) -> UsageWindow? {
        guard let utilization else { return nil }
        return UsageWindow(id: id, kind: kind, title: title, percentUsed: utilization,
                           resetsAt: resetsAt.flatMap(parseResetDate))
    }
}

/// Most urgent first: the 5-hour window is the one users hit mid-session. Ties keep the server's order.
private func inDisplayOrder(_ windows: [UsageWindow]) -> [UsageWindow] {
    windows.enumerated()
        .sorted { ($0.element.kind.displayRank, $0.offset) < ($1.element.kind.displayRank, $1.offset) }
        .map(\.element)
}

extension UsageWindow.Kind {
    fileprivate var displayRank: Int {
        switch self {
        case .fiveHour: 0
        case .weekly: 1
        case .weeklyModel: 2
        case .other: 3
        }
    }
}

/// The server sends microsecond fractions (`2026-10-01T23:59:59.686471+00:00`), but a whole-second timestamp is
/// equally valid ISO-8601, so both are accepted rather than dropping the reset time.
func parseResetDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}
