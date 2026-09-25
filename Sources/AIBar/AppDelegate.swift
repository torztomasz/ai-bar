import AIBarCore
import AppKit
import os

/// Composes the shell: one provider feeding one status item. The fake provider supplies placeholder data
/// until a real one exists.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let provider: any UsageProvider = FakeUsageProvider(snapshot: .sample(fetchedAt: Date()))
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(providerName: provider.displayName)
        controller.onRefreshRequested = {
            Log.app.notice("refresh requested")
        }
        statusItemController = controller
        loadUsage()
    }

    private func loadUsage() {
        Task {
            do {
                statusItemController?.updatePopover(with: try await provider.fetchUsage())
            } catch {
                Log.app.error("fetching usage failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

enum Log {
    static let app = Logger(subsystem: "com.torz.aibar", category: "app")
}
