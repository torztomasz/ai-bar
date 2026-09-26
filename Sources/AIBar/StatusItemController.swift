import AIBarCore
import AppKit
import SwiftUI

/// Owns the menu bar item: draws the badge and tooltip, toggles the usage popover on left click,
/// and reports right click (or control-click) as a refresh request.
@MainActor
final class StatusItemController: NSObject {
    var onRefreshRequested: () -> Void = {}

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let settingsStore: SettingsStore
    private var shownState: ProviderState?
    private var tooltipClock: Timer?
    private lazy var refreshBlink = RefreshBlink(button: statusItem.button)

    init(popoverContent: some View, settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init()
        popover.behavior = .transient
        let hostingController = NSHostingController(rootView: popoverContent)
        // Lets the popover resize when its content changes, e.g. from an error message to the window rows.
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        configureButton()
        startTooltipClock()
        refitBadgeWhenDisplaysChange()
        render()
    }

    /// Shows `state` in the badge; nil before any provider has reported.
    func show(_ state: ProviderState?) {
        shownState = state
        render()
        refreshBlink.follow(isRefreshing: state?.isRefreshing ?? false)
    }

    func settingsDidChange() {
        render()
    }

    /// Makes way for the Settings window, which the popover would otherwise cover.
    func closePopover() {
        popover.performClose(nil)
    }

    /// Text, tint and tooltip all describe the window chosen in settings, so a weekly badge is coloured by the weekly
    /// forecast.
    private func render() {
        let window = shownState?.snapshot?.window(for: settingsStore.settings.badgeWindowID)
        let forecast = window.flatMap { shownState?.forecasts[$0.id] }
        let text = UsageText.badge(window: window, hasError: shownState?.lastError != nil)
        let height = BadgeSize.height(menuBarHeights: NSScreen.screens.map(\.menuBarHeight))
        statusItem.button?.image = BadgeRenderer.image(text: text, tint: BadgeTint(forecast: forecast), height: height)
        statusItem.button?.toolTip = shownState.map { state in
            UsageText.tooltip(providerName: state.displayName, window: window, forecast: forecast,
                              errorDescription: state.lastError?.localizedDescription, now: Date())
        }
    }

    /// The tooltip counts down to the reset in minutes, but data only changes every poll, so it is redrawn on
    /// its own to stay accurate in between.
    private func startTooltipClock() {
        tooltipClock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    /// The badge's height depends on the menu bars it appears in, which change as displays come and go.
    private func refitBadgeWhenDisplaysChange() {
        // The notification center keeps the observer for the app's lifetime, which is this controller's lifetime.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if isSecondaryClick(NSApp.currentEvent) {
            onRefreshRequested()
        } else {
            togglePopover(from: sender)
        }
    }

    // Control-click counts as right click, matching the macOS convention for one-button input.
    private func isSecondaryClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(button)
        } else {
            // An accessory app is not active by default; without activating, the transient popover
            // would not receive the outside click that should dismiss it.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

/// Dims the badge while a refresh runs, so a right-click refresh is acknowledged where the user clicked. Opacity only,
/// so it stays under Reduce Motion. The dip always finishes before the rise: a refresh faster than the dip reads as a
/// single blink instead of a flicker cut short.
@MainActor
private final class RefreshBlink {
    private weak var button: NSStatusBarButton?
    private var isRefreshing = false
    private var isDipping = false

    /// Ease-out and brief: the badge is glanced at, not watched.
    private static let duration: TimeInterval = 0.15
    private static let dimmedAlpha: CGFloat = 0.6

    /// Layer-backed so the fade runs in Core Animation; otherwise AppKit steps `alphaValue` on a timer, which stalls
    /// whenever the display is not refreshing and leaves the badge dimmed.
    init(button: NSStatusBarButton?) {
        self.button = button
        button?.wantsLayer = true
    }

    /// Reacts only to a change, since every state update passes through here.
    func follow(isRefreshing refreshing: Bool) {
        guard refreshing != isRefreshing else { return }
        isRefreshing = refreshing
        if refreshing {
            dip()
        } else if !isDipping {
            fade(to: 1)
        }
    }

    private func dip() {
        isDipping = true
        fade(to: Self.dimmedAlpha) { [weak self] in
            guard let self else { return }
            isDipping = false
            if !isRefreshing { fade(to: 1) }
        }
    }

    private func fade(to alpha: CGFloat, then completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button?.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }
}

extension NSScreen {
    /// Points between the top of the screen and its visible area; 0 while a full-screen app hides the menu bar.
    fileprivate var menuBarHeight: Double {
        Double(frame.maxY - visibleFrame.maxY)
    }
}
