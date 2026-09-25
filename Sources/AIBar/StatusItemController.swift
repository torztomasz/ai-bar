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
    private var shownState: ProviderState?
    private var tooltipClock: Timer?

    init(popoverContent: some View) {
        super.init()
        popover.behavior = .transient
        let hostingController = NSHostingController(rootView: popoverContent)
        // Lets the popover resize when its content changes, e.g. from an error message to the window rows.
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        configureButton()
        startTooltipClock()
        render()
    }

    /// Shows `state` in the badge; nil before any provider has reported.
    func show(_ state: ProviderState?) {
        shownState = state
        render()
    }

    private func render() {
        let primaryWindow = shownState?.snapshot?.primaryWindow
        let text = UsageText.badge(primaryWindow: primaryWindow, hasError: shownState?.lastError != nil)
        let tint = BadgeTint(forecast: shownState?.primaryForecast)
        statusItem.button?.image = BadgeRenderer.image(text: text, tint: tint)
        statusItem.button?.toolTip = shownState.map { state in
            UsageText.tooltip(providerName: state.displayName, primaryWindow: primaryWindow,
                              forecast: state.primaryForecast,
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
