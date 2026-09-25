import AIBarCore
import AppKit
import SwiftUI

/// Owns the menu bar item: draws the badge, toggles the usage popover on left click,
/// and reports right click (or control-click) as a refresh request.
@MainActor
final class StatusItemController: NSObject {
    var onRefreshRequested: () -> Void = {}

    private let providerName: String
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var snapshot: UsageSnapshot?

    init(providerName: String) {
        self.providerName = providerName
        super.init()
        popover.behavior = .transient
        reloadPopoverContent()
        configureButton()
        showBadge(text: "--%", tint: .neutral)
    }

    func updatePopover(with snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        reloadPopoverContent()
    }

    func showBadge(text: String, tint: BadgeTint) {
        statusItem.button?.image = BadgeRenderer.image(text: text, tint: tint)
    }

    private func reloadPopoverContent() {
        popover.contentViewController = NSHostingController(rootView: popoverView())
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func popoverView() -> UsagePopoverView {
        UsagePopoverView(providerName: providerName, snapshot: snapshot) {
            NSApplication.shared.terminate(nil)
        }
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
