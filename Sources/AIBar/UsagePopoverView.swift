import AIBarCore
import SwiftUI

/// Popover shown on left click: every provider's windows with reset times and forecasts, and a footer to refresh,
/// open Settings or quit.
///
/// Motion is brief and only marks a change of state: the refresh icon turns while data is on its way, and values
/// that change settle into place. With Reduce Motion on, movement is dropped and only opacity fades remain.
struct UsagePopoverView: View {
    @ObservedObject var controller: UsageController
    /// Only for which window's reset the header counts down to.
    let settingsStore: SettingsStore
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        // Re-evaluated periodically so "resets in", "Updated … ago" and the time cursors keep moving while the
        // popover is open.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 12) {
                ForEach(controller.states) { state in
                    ProviderSection(state: state, badgeWindowID: settingsStore.settings.badgeWindowID,
                                    now: context.date)
                }
                footer(now: context.date)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(width: 280)
        }
    }

    private func footer(now: Date) -> some View {
        HStack(spacing: 10) {
            let updated = UsageText.updated(controller.oldestRefresh, now: now)
            Text(updated)
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: updated)
            Spacer()
            RefreshButton(isRefreshing: controller.isRefreshing) {
                Task { await controller.refresh() }
            }
            // ⌘, is the standard Settings shortcut; an accessory app has no menu bar to carry it, so the button does.
            Button(action: onOpenSettings) {
                FooterIcon(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .keyboardShortcut(",", modifiers: .command)
            Menu {
                Button("Quit AI Bar", action: onQuit)
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                FooterIcon(systemName: "ellipsis.circle")
            }
            // Plain keeps the label at the size of its neighbours; borderless menu styles shrink it.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
    }
}

/// One provider: its name with the badge window's reset countdown, then its windows. An error with no data to fall
/// back on takes the rows' place; with an older snapshot it is shown above the rows, which are still the best
/// information available.
private struct ProviderSection: View {
    let state: ProviderState
    let badgeWindowID: String?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
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
                LoadingRows()
            }
        }
    }

    /// The countdown the menu bar badge stands for is the one most worth seeing first.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.displayName).font(.headline)
            Spacer()
            if let resetsAt = state.snapshot?.window(for: badgeWindowID)?.resetsAt {
                Text(UsageText.resetsIn(resetsAt, now: now))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let forecast: DrainForecast?
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                Spacer()
                Text(UsageText.percent(window.percentUsed))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: window.percentUsed))
                    .animation(.smooth(duration: 0.3), value: window.percentUsed)
            }
            UsageBarView(bar: UsageBar(window: window, forecast: forecast, now: now))
            // A long reset countdown next to a lockout may not fit on one row; the lockout then goes on its own line
            // instead of wrapping mid-duration.
            ViewThatFits(in: .horizontal) {
                HStack {
                    resetsLine
                    Spacer()
                    lockoutLine
                }
                VStack(alignment: .leading, spacing: 2) {
                    resetsLine
                    lockoutLine
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var resetsLine: some View {
        Text(UsageText.resetsIn(window.resetsAt, now: now)).fixedSize()
    }

    @ViewBuilder private var lockoutLine: some View {
        if let forecast {
            Text(UsageText.lockout(forecast, resetsAt: window.resetsAt))
                .fontWeight(isLockedOut ? .semibold : nil)
                .foregroundStyle(isLockedOut ? AnyShapeStyle(UsageLevel.critical.color) : AnyShapeStyle(.secondary))
                .fixedSize()
        }
    }

    /// Being locked out is the one thing the row must not let the user miss, so it takes the bar's critical colour.
    /// That includes a drained window with no reset time: its line still says "Locked out" and the badge is red.
    private var isLockedOut: Bool {
        if case .willDrain = forecast?.outlook { true } else { false }
    }
}

/// Stands in for window rows until the first reading arrives, in their shape, so the popover does not jump when the
/// data lands. Static rather than shimmering: loading takes about a second and needs no attention drawn to it.
private struct LoadingRows: View {
    var body: some View {
        ForEach(0..<3, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly · Model")
                Capsule().fill(.quaternary).frame(height: UsageBarView.height)
                Text("resets in 0h 00m").font(.caption)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading usage")
    }
}

/// Drawn by hand rather than with `ProgressView`, which turns grey whenever the popover is not the key window and so
/// would hide the threshold colour exactly when the user glances at it.
private struct UsageBarView: View {
    let bar: UsageBar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 8
    /// Faint enough that the solid fill stays the obvious reading, visible enough to notice where usage is heading.
    private static let estimateOpacity = 0.25
    private static let cursorWidth: CGFloat = 1.5
    /// Present on fills of every colour and on the empty track, without competing with the fill for attention.
    private static let cursorOpacity = 0.45

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
                if let elapsed = bar.elapsedFraction {
                    timeCursor(at: elapsed, barWidth: geometry.size.width)
                }
            }
        }
        .frame(height: Self.height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: bar)
    }

    /// The only mark on the bar that is not a fill, so it reads as "now" against the usage: a fill reaching past it
    /// is usage outpacing time. Kept inside the bar at either end rather than half cut off.
    private func timeCursor(at fraction: Double, barWidth: CGFloat) -> some View {
        let travel = max(barWidth - Self.cursorWidth, 0)
        return Capsule()
            .fill(.primary.opacity(Self.cursorOpacity))
            .frame(width: Self.cursorWidth)
            .offset(x: travel * fraction)
    }
}

/// Turns while a refresh runs and settles upright when it ends (see `RefreshSpin`). With Reduce Motion on it stays
/// still and dims instead, so the state still shows.
private struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = RefreshSpin()

    private static let dimmedOpacity = 0.4

    var body: some View {
        Button(action: action) {
            TimelineView(SpinSchedule(spin: spin)) { context in
                FooterIcon(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(spin.degrees(at: context.date)))
            }
        }
        .buttonStyle(.borderless)
        .help("Refresh")
        // Scoped to the opacity, so the fade can never animate anything else in the button.
        .animation(.easeOut(duration: 0.15)) {
            $0.opacity(reduceMotion && isRefreshing ? Self.dimmedOpacity : 1)
        }
        .onChange(of: isRefreshing, initial: true) { _, refreshing in
            if refreshing && !reduceMotion {
                spin.start(at: .now)
            } else {
                spin.stop(at: .now)
            }
        }
    }
}

/// Frames at display rate for as long as the spin moves, then none, so an idle icon costs nothing to draw.
private struct SpinSchedule: TimelineSchedule {
    let spin: RefreshSpin

    private static let frameInterval: TimeInterval = 1.0 / 120

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> some Sequence<Date> {
        // One frame past the end of the motion, so the last one drawn is the resting angle.
        sequence(first: startDate) { date in
            spin.isMoving(at: date) ? date.addingTimeInterval(Self.frameInterval) : nil
        }
    }
}

/// Footer icons stay secondary so the data above them leads, and brighten under the pointer to show they are live.
private struct FooterIcon: View {
    let systemName: String

    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16))
            // A menu label is otherwise redrawn as a template in the primary colour, whatever its foreground style.
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isHovered ? .primary : .secondary)
            .onHover { isHovered = $0 }
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
