import AIBarCore
import AppKit

/// Owns the usage data: polls every provider, records the 5-hour readings, forecasts the drain, and publishes
/// the result for the badge and the popover.
@MainActor
final class UsageController: ObservableObject {
    /// Often enough that the badge tracks a busy session, rare enough to stay far from the endpoint's rate limits.
    private static let pollInterval: Duration = .seconds(5 * 60)

    /// One entry per provider, in the order the popover lists them.
    @Published private(set) var states: [ProviderState] {
        didSet { onStatesChanged(states) }
    }

    /// For AppKit consumers (the status item) that cannot observe SwiftUI state.
    var onStatesChanged: ([ProviderState]) -> Void = { _ in }

    private let providers: [any UsageProvider]
    private let sampleStores: [ProviderID: SampleStore]
    private let estimator = DrainEstimator()
    private var pollingTask: Task<Void, Never>?

    init(providers: [any UsageProvider]) {
        self.providers = providers
        sampleStores = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, SampleStore.defaultStore(for: $0.id)) })
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

    /// Refreshes now and every poll interval after, and again on wake because a sleeping Mac misses polls and
    /// the reading it last showed may be hours old. Calling it again does nothing.
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        // The notification center keeps the observer for the app's lifetime, which is this controller's lifetime.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// Fetches every provider concurrently. A provider still busy with an earlier refresh is skipped rather than
    /// asked twice. A failed fetch keeps the previous snapshot, so the badge shows the last known reading.
    func refresh() async {
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

    private func apply(_ result: Result<UsageSnapshot, any Error>, toProviderAt index: Int) {
        var state = states[index]
        state.isRefreshing = false
        switch result {
        case .success(let snapshot):
            state.snapshot = snapshot
            state.forecast = forecastPrimaryWindow(of: snapshot, store: sampleStores[state.id])
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

    /// Records the reading before forecasting so the estimate includes it.
    private func forecastPrimaryWindow(of snapshot: UsageSnapshot, store: SampleStore?) -> DrainForecast? {
        guard let primary = snapshot.primaryWindow, let store else { return nil }
        store.record(primary, at: snapshot.fetchedAt)
        return estimator.forecast(for: primary, samples: store.samples(), now: snapshot.fetchedAt)
    }
}

/// What the app knows about one provider after its latest refresh.
struct ProviderState: Identifiable {
    let id: ProviderID
    let displayName: String
    /// The last successful fetch; kept through failures.
    var snapshot: UsageSnapshot?
    /// For the primary window of `snapshot`; nil when it has none.
    var forecast: DrainForecast?
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
