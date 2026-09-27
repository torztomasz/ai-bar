import AIBarCore
import SwiftUI

/// Popover shown on left click: every provider's windows with reset times and forecasts, and a footer to refresh,
/// open Settings or quit.
///
/// Motion is brief and only marks a change of state: the refresh icon turns while data is on its way and confirms
/// its arrival, and values that change settle into place. With Reduce Motion on, movement is dropped and only
/// opacity fades remain.
struct UsagePopoverView: View {
    @ObservedObject var controller: UsageController
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        // Re-evaluated periodically so "resets in", "Updated … ago" and the time cursors keep moving while the
        // popover is open.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 12) {
                ForEach(controller.states) { state in
                    ProviderSection(state: state, now: context.date)
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
            RefreshButton(isRefreshing: controller.isRefreshing, hasFailed: controller.hasFailedRefresh) {
                Task { await controller.refresh() }
            }
            // ⌘, is the standard Settings shortcut; an accessory app has no menu bar to carry it, so the button does.
            Button(action: onOpenSettings) {
                FooterIcon(systemName: "gearshape", label: "Settings")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .keyboardShortcut(",", modifiers: .command)
            Menu {
                Button("Quit AI Bar", action: onQuit)
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                FooterIcon(systemName: "ellipsis.circle", label: "More")
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
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                LoadingRows()
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
            Text(UsageText.lockout(forecast, resetsAt: window.resetsAt, now: now))
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
    /// Claude reports three windows, so the placeholder has the height of the rows it stands in for.
    private static let rowCount = 3

    var body: some View {
        ForEach(0..<Self.rowCount, id: \.self) { _ in
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

/// Turns while a refresh runs and settles upright when it ends (see `RefreshSpin`), then briefly turns into a
/// checkmark if the refresh succeeded, so the user learns it worked without reading the timestamp. A failure gets no
/// checkmark: its message already shows above. With Reduce Motion on the icon stays still and dims instead of turning,
/// and the checkmark fades in and out rather than morphing.
private struct RefreshButton: View {
    let isRefreshing: Bool
    let hasFailed: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = RefreshSpin()
    @State private var showsCheck = false
    /// Counts successful refreshes, so each starts its own confirmation and cancels a previous one still showing.
    @State private var confirmations = 0

    /// Deep, because this icon is already secondary: a shallow dim would not register.
    private static let dimmedOpacity = 0.4
    /// Long enough to register at a glance, short enough not to be mistaken for a state.
    private static let checkHold: Duration = .seconds(1)
    /// A gentle spring for the checkmark's arrival; bounce is kept low, as it is only confirming.
    private static let checkArrival = Animation.spring(duration: 0.3, bounce: 0.2)
    /// Faster than the arrival: by then the checkmark is only getting out of the way.
    private static let checkDeparture = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(paused: !spin.isMoving(at: .now))) { context in
                FooterIcon(systemName: showsCheck ? "checkmark" : "arrow.clockwise", label: "Refresh",
                           emphasis: showsCheck ? .green : nil)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.downUp))
                    .rotationEffect(.degrees(spin.degrees(at: context.date)))
            }
        }
        .buttonStyle(.borderless)
        .help("Refresh")
        // Scoped to the opacity, so the fade can never animate anything else in the button.
        .animation(.easeOut(duration: 0.15)) {
            $0.opacity(reduceMotion && isRefreshing ? Self.dimmedOpacity : 1)
        }
        .onChange(of: isRefreshing, initial: true) { followRefreshing() }
        .onChange(of: isRefreshing) { wasRefreshing, refreshing in
            if refreshing {
                showsCheck = false
            } else if wasRefreshing && !hasFailed {
                confirmations += 1
            }
        }
        // Turning Reduce Motion on mid-refresh stops the spin; the dim takes over.
        .onChange(of: reduceMotion) { followRefreshing() }
        .task(id: spin) {
            // The timeline only re-reads `paused` when the view updates, so end the settle once it is over.
            guard (try? await Task.sleep(for: .seconds(RefreshSpin.settleDuration))) != nil else { return }
            spin.finishSettling(at: .now)
        }
        .task(id: confirmations) {
            guard confirmations > 0 else { return }
            await confirm()
        }
    }

    private func followRefreshing() {
        if isRefreshing && !reduceMotion {
            spin.start(at: .now)
        } else {
            spin.stop(at: .now)
        }
    }

    /// Waits for the spin to land upright first, so the checkmark never appears tilted.
    private func confirm() async {
        guard (try? await Task.sleep(for: .seconds(RefreshSpin.settleDuration))) != nil else { return }
        withAnimation(Self.checkArrival) { showsCheck = true }
        guard (try? await Task.sleep(for: Self.checkHold)) != nil else { return }
        withAnimation(Self.checkDeparture) { showsCheck = false }
    }
}

/// Footer icons stay secondary so the data above them leads, and brighten under the pointer to show they are live.
/// `label` is what VoiceOver reads instead of the symbol's name. `emphasis` replaces both colours for a moment that
/// must stand out.
private struct FooterIcon: View {
    let systemName: String
    let label: String
    var emphasis: Color?

    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16))
            // A menu label is otherwise redrawn as a template in the primary colour, whatever its foreground style.
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(foreground)
            .onHover { isHovered = $0 }
            .accessibilityLabel(label)
    }

    private var foreground: AnyShapeStyle {
        if let emphasis { return AnyShapeStyle(emphasis) }
        return isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
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
