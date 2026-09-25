import AIBarCore
import AppKit
import os

/// Composes the shell: one provider feeding one status item. Uses `FakeUsageProvider` until the real
/// provider and polling land (tickets 002 and 004).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let provider: any UsageProvider = FakeUsageProvider(snapshot: .sample(fetchedAt: Date()), displayName: "Claude")
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(providerName: provider.displayName)
        controller.onRefreshRequested = { [weak self] in
            Log.app.notice("refresh requested")
            self?.loadUsage()
        }
        statusItemController = controller
        loadUsage()
    }

    private func loadUsage() {
        Task {
            do {
                statusItemController?.show(snapshot: try await provider.fetchUsage())
            } catch {
                Log.app.error("fetching usage failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

enum Log {
    static let app = Logger(subsystem: "com.torz.aibar", category: "app")
}
