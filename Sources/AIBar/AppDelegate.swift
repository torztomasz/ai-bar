import AIBarCore
import AppKit
import os

/// Composes the app: the usage controller feeds the status item's badge and popover, and both refresh triggers
/// (right click, the popover's button) go back to the controller. Settings changes reach the poller and the badge
/// as soon as they are made.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore(defaults: .standard)
    private lazy var usage = UsageController(providers: [ClaudeUsageProvider()], settingsStore: settingsStore)
    private lazy var settingsWindow = SettingsWindowController(
        content: SettingsView(settingsStore: settingsStore, usage: usage))
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let popover = UsagePopoverView(controller: usage, settingsStore: settingsStore, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onQuit: {
            NSApplication.shared.terminate(nil)
        })
        let statusItem = StatusItemController(popoverContent: popover, settingsStore: settingsStore)
        statusItem.onRefreshRequested = { [weak usage] in
            Task { await usage?.refresh() }
        }
        // One badge can only speak for one provider; v1 has just Claude, so it follows the first.
        usage.onStatesChanged = { [weak statusItem] states in
            statusItem?.show(states.first)
        }
        settingsStore.onChange = { [weak usage, weak statusItem] _ in
            usage?.settingsDidChange()
            statusItem?.settingsDidChange()
        }
        statusItemController = statusItem
        usage.start()
    }

    private func openSettings() {
        statusItemController?.closePopover()
        settingsWindow.show()
    }
}

enum Log {
    static let app = Logger(subsystem: "com.torz.aibar", category: "app")
}
