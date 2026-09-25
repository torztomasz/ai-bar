import Foundation

/// Returns a canned snapshot, optionally after a delay. Lives in Core rather than the test target so the app shell
/// can show placeholder data before a real provider exists, and so a delay can exercise loading states.
public struct FakeUsageProvider: UsageProvider {
    public let displayName: String
    public let snapshot: UsageSnapshot
    public let delay: Duration

    public var id: ProviderID { snapshot.provider }

    public init(snapshot: UsageSnapshot, displayName: String = "Fake", delay: Duration = .zero) {
        self.snapshot = snapshot
        self.displayName = displayName
        self.delay = delay
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return snapshot
    }
}

extension UsageSnapshot {
    /// Plausible data covering every window kind, for placeholders and previews.
    public static func sample(fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            provider: ProviderID("fake"),
            fetchedAt: fetchedAt,
            windows: [
                UsageWindow(id: "session", kind: .fiveHour, title: "5-hour", percentUsed: 37,
                            resetsAt: fetchedAt.addingTimeInterval(2 * 3600)),
                UsageWindow(id: "weekly_all", kind: .weekly, title: "Weekly", percentUsed: 12,
                            resetsAt: fetchedAt.addingTimeInterval(4 * 86_400)),
                UsageWindow(id: "weekly_scoped:Fable", kind: .weeklyModel(name: "Fable"), title: "Weekly · Fable",
                            percentUsed: 22, resetsAt: fetchedAt.addingTimeInterval(4 * 86_400)),
            ]
        )
    }
}
