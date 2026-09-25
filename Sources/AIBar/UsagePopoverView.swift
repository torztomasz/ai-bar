import AIBarCore
import SwiftUI

/// Popover shown on left click: every provider's windows with reset times, the 5-hour forecast, and a footer to
/// refresh or quit.
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
            Text(UsageText.updated(oldestRefresh, now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if isRefreshing {
                ProgressView().controlSize(.small)
            }
            Button("Refresh") {
                Task { await controller.refresh() }
            }
            .disabled(isRefreshing)
            Button("Quit", action: onQuit)
        }
    }

    /// The footer vouches for all the data shown, so it reports the stalest provider; nil if one never refreshed.
    private var oldestRefresh: Date? {
        let refreshes = controller.states.map(\.lastRefreshedAt)
        return refreshes.contains(nil) ? nil : refreshes.compactMap { $0 }.min()
    }

    private var isRefreshing: Bool {
        controller.states.contains(where: \.isRefreshing)
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
                    WindowRow(window: window, forecastLine: forecastLine(for: window, in: snapshot), now: now)
                }
            } else if state.lastError == nil {
                Text("Loading usage…").foregroundStyle(.secondary)
            }
        }
    }

    /// Only the primary window is forecast.
    private func forecastLine(for window: UsageWindow, in snapshot: UsageSnapshot) -> String? {
        window.id == snapshot.primaryWindow?.id ? UsageText.forecast(state.forecast) : nil
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let forecastLine: String?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.title)
                Spacer()
                Text(UsageText.percent(window.percentUsed)).monospacedDigit()
            }
            // Clamped because a provider may report overage above 100%, which ProgressView cannot draw.
            ProgressView(value: min(max(window.percentUsed, 0), 100), total: 100)
            HStack {
                Text(UsageText.resetsIn(window.resetsAt, now: now))
                Spacer()
                if let forecastLine {
                    Text(forecastLine)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
