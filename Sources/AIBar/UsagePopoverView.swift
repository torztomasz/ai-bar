import AIBarCore
import SwiftUI

/// Popover shown on left click: the provider's name and one row per usage window.
/// Takes the name separately because a snapshot only carries the provider's id, not its display name.
struct UsagePopoverView: View {
    let providerName: String
    let snapshot: UsageSnapshot?
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(providerName).font(.headline)
            if let snapshot {
                ForEach(snapshot.windows) { window in
                    WindowRow(window: window)
                }
            } else {
                Text("No usage data yet").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Spacer()
                Button("Quit", action: onQuit)
            }
        }
        .padding()
        .frame(width: 260)
    }
}

private struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        HStack {
            Text(window.title)
            Spacer()
            Text(window.percentUsed / 100, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
        }
    }
}
