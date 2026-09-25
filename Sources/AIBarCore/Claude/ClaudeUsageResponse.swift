import Foundation

/// The subset of `GET /api/oauth/usage` the app reads.
struct ClaudeUsageResponse: Decodable {
    /// The structured form and the source of truth when present.
    let limits: [Limit]?
    /// Older flat form, read only when `limits` is missing or empty.
    let fiveHour: LegacyWindow?
    let sevenDay: LegacyWindow?

    struct Limit: Decodable {
        let kind: String
        let percent: Double
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
        let utilization: Double
        let resetsAt: String?
    }

    var windows: [UsageWindow] {
        if let limits, !limits.isEmpty {
            return inDisplayOrder(limits.map(\.window))
        }
        return legacyWindows
    }

    private var legacyWindows: [UsageWindow] {
        [
            fiveHour.map {
                UsageWindow(id: "session", kind: .fiveHour, title: "5-hour", percentUsed: $0.utilization,
                            resetsAt: $0.resetsAt.flatMap(parseResetDate))
            },
            sevenDay.map {
                UsageWindow(id: "weekly_all", kind: .weekly, title: "Weekly", percentUsed: $0.utilization,
                            resetsAt: $0.resetsAt.flatMap(parseResetDate))
            },
        ].compactMap { $0 }
    }
}

extension ClaudeUsageResponse.Limit {
    var window: UsageWindow {
        let (id, kind, title) = identity
        return UsageWindow(id: id, kind: kind, title: title, percentUsed: percent,
                           resetsAt: resetsAt.flatMap(parseResetDate))
    }

    private var identity: (id: String, kind: UsageWindow.Kind, title: String) {
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
