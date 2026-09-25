import AIBarCore
import AppKit
import os

/// Composes the app: the usage controller feeds the status item's badge and popover, and both refresh triggers
/// (right click, the popover's button) go back to the controller.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usage = UsageController(providers: [ClaudeUsageProvider()])
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = StatusItemController(popoverContent: UsagePopoverView(controller: usage) {
            NSApplication.shared.terminate(nil)
        })
        statusItem.onRefreshRequested = { [weak usage] in
            Task { await usage?.refresh() }
        }
        // One badge can only speak for one provider; v1 has just Claude, so it follows the first.
        usage.onStatesChanged = { [weak statusItem] states in
            statusItem?.show(states.first)
        }
        statusItemController = statusItem
        usage.start()
    }
}

enum Log {
    static let app = Logger(subsystem: "com.torz.aibar", category: "app")
}
