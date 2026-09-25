import AIBarCore
import SwiftUI

/// Popover shown on left click: every provider's windows with reset times and forecasts, and a footer to refresh or
/// quit.
struct UsagePopoverView: View {
    @ObservedObject var controller: UsageController
    let onQuit: () -> Void

    var body: some View {
        // Re-evaluated periodically so "resets in" and "Updated … ago" keep counting while the popover is open.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 12) {
                ForEach(controller.states) { state in
                    ProviderSection(state: state, now: context.date)
                }
                Divider()
                footer(now: context.date)
            }
            .padding()
            .frame(width: 280)
        }
    }

    private func footer(now: Date) -> some View {
        HStack {
            Text(UsageText.updated(controller.oldestRefresh, now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if controller.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Button("Refresh") {
                Task { await controller.refresh() }
            }
            .disabled(controller.isRefreshing)
            Button("Quit", action: onQuit)
        }
    }
}

/// One provider: its name, then its windows. An error with no data to fall back on takes the rows' place;
/// with an older snapshot it is shown above the rows, which are still the best information available.
private struct ProviderSection: View {
    let state: ProviderState
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.displayName).font(.headline)
            if let error = state.lastError {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    WindowRow(window: window, forecast: state.forecasts[window.id], now: now)
                }
            } else if state.lastError == nil {
                Text("Loading usage…").foregroundStyle(.secondary)
            }
        }
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let forecast: DrainForecast?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.title)
                Spacer()
                Text(UsageText.percent(window.percentUsed)).monospacedDigit()
            }
            UsageBarView(bar: UsageBar(percentUsed: window.percentUsed,
                                       projectedPercentAtReset: forecast?.projectedPercentAtReset))
            // A weekly drain line names the day and can be too long to share the row; it then goes on its own
            // line instead of wrapping mid-date.
            ViewThatFits(in: .horizontal) {
                HStack {
                    resetsLine
                    Spacer()
                    forecastLine
                }
                VStack(alignment: .leading, spacing: 2) {
                    resetsLine
                    forecastLine
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var resetsLine: some View {
        Text(UsageText.resetsIn(window.resetsAt, now: now)).fixedSize()
    }

    @ViewBuilder private var forecastLine: some View {
        if let forecast {
            Text(UsageText.forecast(forecast, for: window.kind)).fixedSize()
        }
    }
}

/// Drawn by hand rather than with `ProgressView`, which turns grey whenever the popover is not the key window and so
/// would hide the threshold colour exactly when the user glances at it.
private struct UsageBarView: View {
    let bar: UsageBar

    /// Faint enough that the solid fill stays the obvious reading, visible enough to notice where usage is heading.
    private static let estimateOpacity = 0.25
    private static let height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let estimate = bar.estimate {
                    Capsule()
                        .fill(estimate.level.color.opacity(Self.estimateOpacity))
                        .frame(width: geometry.size.width * estimate.fraction)
                }
                Capsule()
                    .fill(bar.fill.level.color)
                    .frame(width: geometry.size.width * bar.fill.fraction)
            }
        }
        .frame(height: Self.height)
    }
}

extension UsageLevel {
    fileprivate var color: Color {
        switch self {
        case .ok: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}
