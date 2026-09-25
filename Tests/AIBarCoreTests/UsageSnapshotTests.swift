import Foundation
import Testing
@testable import AIBarCore

// Method: build snapshots by hand with windows in varied orders and assert on which one the badge would show.
@Suite struct PrimaryWindowSelection {
    @Test func picksTheFiveHourWindowEvenWhenItIsNotFirst() {
        let weekly = window("weekly_all", kind: .weekly)
        let fiveHour = window("session", kind: .fiveHour)
        let snapshot = snapshot(windows: [weekly, fiveHour])

        #expect(snapshot.primaryWindow == fiveHour)
    }

    @Test func isNilWhenTheProviderReportsNoFiveHourWindow() {
        let snapshot = snapshot(windows: [
            window("weekly_all", kind: .weekly),
            window("weekly_scoped:Fable", kind: .weeklyModel(name: "Fable")),
            window("mystery", kind: .other),
        ])

        #expect(snapshot.primaryWindow == nil)
    }
}

private func window(_ id: String, kind: UsageWindow.Kind, percent: Double = 10) -> UsageWindow {
    UsageWindow(id: id, kind: kind, title: id, percentUsed: percent, resetsAt: nil)
}

private func snapshot(windows: [UsageWindow]) -> UsageSnapshot {
    UsageSnapshot(provider: ProviderID("test"), fetchedAt: Date(timeIntervalSince1970: 0), windows: windows)
}
