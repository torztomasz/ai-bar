import Foundation

/// Every string the menu bar item and popover show, as pure functions of the data, so wording and rounding are
/// unit-tested without AppKit and the views only lay text out.
public enum UsageText {
    /// A failed fetch with nothing to fall back on gets a `!` so it is not mistaken for "still loading".
    public static func badge(primaryWindow: UsageWindow?, hasError: Bool) -> String {
        guard let primaryWindow else { return hasError ? "--%!" : "--%" }
        return percent(primaryWindow.percentUsed)
    }

    /// E.g. "Claude 5-hour: 42% · resets in 2h 13m · projected 71% at reset"; parts without data are left out.
    /// A failed refresh is appended because the badge keeps showing the last reading, which would otherwise look
    /// current.
    public static func tooltip(providerName: String, primaryWindow: UsageWindow?, forecast: DrainForecast?,
                               errorDescription: String?, now: Date) -> String {
        guard let primaryWindow else {
            return "\(providerName): \(errorDescription ?? "no usage data yet")"
        }
        var parts = ["\(providerName) \(primaryWindow.title): \(percent(primaryWindow.percentUsed))"]
        if let resetsAt = primaryWindow.resetsAt {
            parts.append(resetsIn(resetsAt, now: now))
        }
        if let projected = forecast?.projectedPercentAtReset {
            parts.append("projected \(percent(projected)) at reset")
        }
        if let errorDescription {
            parts.append("last refresh failed: \(errorDescription)")
        }
        return parts.joined(separator: " · ")
    }

    /// Minutes precision, rounded down so the countdown never promises more time than is left.
    public static func resetsIn(_ resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else { return "—" }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return "resets now" }
        return "resets in \(duration(remaining))"
    }

    public static func updated(_ refreshedAt: Date?, now: Date) -> String {
        guard let refreshedAt else { return "Not updated yet" }
        let minutes = Int(now.timeIntervalSince(refreshedAt) / 60)
        switch minutes {
        case ..<1: return "Updated just now"
        case ..<60: return "Updated \(minutes) min ago"
        default: return "Updated \(duration(TimeInterval(minutes * 60))) ago"
        }
    }

    /// The drain time is a clock reading in the user's locale and time zone; tests pin both. A window longer than a
    /// day can drain days from now, so its drain time names the day as well. Clock and day are formatted apart and
    /// joined here, so the sentence reads the same in every locale rather than taking each locale's own joining word.
    public static func forecast(_ forecast: DrainForecast?, for kind: UsageWindow.Kind, locale: Locale = .current,
                                timeZone: TimeZone = .current) -> String {
        switch forecast?.outlook {
        case .willLast:
            return "On pace to last"
        case .willDrain(let at):
            let clock = at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                      timeZone: timeZone))
            guard kind.spansDays else { return "Drains at \(clock)" }
            let day = at.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone)
                .weekday(.abbreviated).day().month(.abbreviated))
            return "Drains at \(clock) on \(day)"
        case .unknown, nil:
            return "Not enough data"
        }
    }

    /// Whole percent, shared by badge, tooltip and popover so they never disagree on rounding.
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// `2h 13m`, `4d 3h 12m`: leading zero units are dropped, and anything under a minute reads `<1m` rather than
    /// `0m`, which would suggest the moment has passed.
    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        guard totalMinutes > 0 else { return "<1m" }
        let (days, hours, minutes) = (totalMinutes / 1440, totalMinutes / 60 % 24, totalMinutes % 60)
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

private extension UsageWindow.Kind {
    var spansDays: Bool { (length ?? 0) > RollingWindow.day }
}
