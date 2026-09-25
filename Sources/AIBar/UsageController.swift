import AIBarCore
import AppKit

/// Owns the usage data: polls every provider, forecasts every window's drain from its recorded readings, and
/// publishes the result for the badge and the popover.
@MainActor
final class UsageController: ObservableObject {
    /// One entry per provider, in the order the popover lists them.
    @Published private(set) var states: [ProviderState] {
        didSet { onStatesChanged(states) }
    }

    /// For AppKit consumers (the status item) that cannot observe SwiftUI state.
    var onStatesChanged: ([ProviderState]) -> Void = { _ in }

    private let providers: [any UsageProvider]
    private let settingsStore: SettingsStore
    private let forecaster = WindowForecaster.inApplicationSupport()
    private var pollingTask: Task<Void, Never>?
    /// The interval `pollingTask` sleeps for, to tell a changed interval from any other settings change.
    private var pollingInterval: Duration?

    init(providers: [any UsageProvider], settingsStore: SettingsStore) {
        self.providers = providers
        self.settingsStore = settingsStore
        states = providers.map { ProviderState(id: $0.id, displayName: $0.displayName) }
    }

    /// The stalest provider's refresh time, since a single "Updated … ago" vouches for all the data shown;
    /// nil while any provider has never refreshed.
    var oldestRefresh: Date? {
        let refreshes = states.map(\.lastRefreshedAt)
        return refreshes.contains(nil) ? nil : refreshes.compactMap { $0 }.min()
    }

    var isRefreshing: Bool {
        states.contains(where: \.isRefreshing)
    }

    /// Refreshes now and every refresh interval after, and again on wake because a sleeping Mac misses polls and
    /// the reading it last showed may be hours old. Calling it again does nothing.
    func start() {
        guard pollingTask == nil else { return }
        Task { await refresh() }
        startPolling()
        // The notification center keeps the observer for the app's lifetime, which is this controller's lifetime.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// A new interval starts counting from now instead of after the old one runs out, so going from 15 minutes to 1
    /// takes effect within a minute.
    func settingsDidChange() {
        guard pollingTask != nil, settingsStore.settings.refreshInterval != pollingInterval else { return }
        startPolling()
    }

    /// Fetches every provider concurrently. A provider still busy with an earlier refresh is skipped rather than
    /// asked twice. A failed fetch keeps the previous snapshot, so the badge shows the last known reading.
    func refresh() async {
        Log.app.notice("refreshing usage")
        let due = states.indices.filter { !states[$0].isRefreshing }
        // Marked on a copy so observers redraw once, not once per provider.
        var marked = states
        for index in due {
            marked[index].isRefreshing = true
        }
        states = marked
        await withTaskGroup(of: (Int, Result<UsageSnapshot, any Error>).self) { group in
            for index in due {
                let provider = providers[index]
                group.addTask { (index, await fetchResult(from: provider)) }
            }
            for await (index, result) in group {
                apply(result, toProviderAt: index)
            }
        }
    }

    /// Each refresh runs in a task of its own, so replacing the loop cancels only its sleep, never a fetch in flight.
    private func startPolling() {
        pollingTask?.cancel()
        let interval = settingsStore.settings.refreshInterval
        pollingInterval = interval
        Log.app.notice("refreshing usage every \(interval.wholeMinutes) min")
        pollingTask = Task { [weak self] in
            // Sleep only throws on cancellation, i.e. when a restart has already started this loop's replacement.
            while (try? await Task.sleep(for: interval)) != nil {
                Task { await self?.refresh() }
            }
        }
    }

    private func apply(_ result: Result<UsageSnapshot, any Error>, toProviderAt index: Int) {
        var state = states[index]
        state.isRefreshing = false
        switch result {
        case .success(let snapshot):
            state.snapshot = snapshot
            state.forecasts = forecaster.forecasts(for: snapshot)
            state.lastError = nil
        case .failure(let error):
            state.lastError = error
            Log.app.error("""
                fetching \(state.id.rawValue, privacy: .public) usage failed: \
                \(error.localizedDescription, privacy: .public)
                """)
        }
        // One assignment so observers see a single, consistent change.
        states[index] = state
    }
}

/// What the app knows about one provider after its latest refresh.
struct ProviderState: Identifiable {
    let id: ProviderID
    let displayName: String
    /// The last successful fetch; kept through failures.
    var snapshot: UsageSnapshot?
    /// For the windows of `snapshot`; a window of unknown length has none.
    var forecasts: [UsageWindow.ID: DrainForecast] = [:]
    /// Cleared by the next successful fetch.
    var lastError: (any Error)?
    var isRefreshing = false

    /// Derived rather than stored so it can never disagree with the snapshot it describes.
    var lastRefreshedAt: Date? { snapshot?.fetchedAt }
}

private func fetchResult(from provider: any UsageProvider) async -> Result<UsageSnapshot, any Error> {
    do {
        return .success(try await provider.fetchUsage())
    } catch {
        return .failure(error)
    }
}
