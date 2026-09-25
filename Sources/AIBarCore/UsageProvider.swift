import Foundation

/// A source of rate-limit usage, one per AI service. The app polls every provider and renders whatever they return,
/// so adding a service means adding a conformance, not touching the UI.
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    func fetchUsage() async throws -> UsageSnapshot
}
