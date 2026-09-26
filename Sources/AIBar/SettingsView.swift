import AIBarCore
import SwiftUI

/// The Settings window's content. Every control writes straight through to `SettingsStore`, so a change applies
/// the moment it is made, the way macOS settings do; there is no Save button.
struct SettingsView: View {
    let settingsStore: SettingsStore
    /// Only for the titles of the windows the badge can show.
    @ObservedObject var usage: UsageController

    /// Mirrors the system's login item rather than a stored preference; re-read whenever the window appears.
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                launchAtLoginToggle
                refreshIntervalPicker
                badgeWindowPicker
            } footer: {
                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchesAtLogin = LaunchAtLogin.isEnabled }
    }

    private var launchAtLoginToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(get: { launchesAtLogin }, set: setLaunchesAtLogin))
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var refreshIntervalPicker: some View {
        Picker("Refresh every", selection: Binding(
            get: { settingsStore.settings.refreshInterval },
            set: { interval in settingsStore.update { $0.refreshInterval = interval } }
        )) {
            ForEach(AppSettings.refreshIntervalChoices, id: \.self) { interval in
                Text(minutesLabel(interval)).tag(interval)
            }
        }
    }

    /// Lists what the badge would actually show: a stored choice the snapshot no longer reports is displayed as the
    /// primary window it falls back to. Before the first snapshot only the default can be named.
    private var badgeWindowPicker: some View {
        let state = usage.states.first
        let shownWindowID = state?.badgeWindow(for: settingsStore.settings.badgeWindowID)?.id
        return Picker("Show in menu bar", selection: Binding(
            get: { shownWindowID },
            set: { windowID in settingsStore.update { $0.badgeWindowID = windowID } }
        )) {
            if shownWindowID == nil {
                Text("5-hour (default)").tag(String?.none)
            }
            ForEach(state?.snapshot?.windows ?? []) { window in
                Text(window.title).tag(String?.some(window.id))
            }
        }
    }

    /// Reads the outcome back from the system instead of trusting the request, so a refused change leaves the toggle
    /// where it was.
    private func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            let action = enabled ? "add AI Bar to" : "remove AI Bar from"
            launchAtLoginError = "Couldn't \(action) login items: \(error.localizedDescription)"
        }
        launchesAtLogin = LaunchAtLogin.isEnabled
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

private func minutesLabel(_ interval: Duration) -> String {
    interval.wholeMinutes == 1 ? "1 minute" : "\(interval.wholeMinutes) minutes"
}
