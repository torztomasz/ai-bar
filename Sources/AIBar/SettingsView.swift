import AIBarCore
import SwiftUI

/// The Settings window's content. Every control writes straight through to `SettingsStore`, so a change applies
/// the moment it is made, the way macOS settings do; there is no Save button.
struct SettingsView: View {
    let settingsStore: SettingsStore
    /// For the providers on offer and the titles of the windows the badge can show.
    @ObservedObject var usage: UsageController
    /// Only to report a shortcut the system refused, and to stand it down while a new one is recorded.
    let hotKey: PopoverHotKey

    /// Mirrors the system's login item rather than a stored preference; re-read whenever the window appears.
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    launchAtLoginToggle
                    refreshIntervalPicker
                    openShortcutRecorder
                }
                ForEach(usage.providers, id: \.id) { provider in
                    providerSection(provider)
                }
            }
            .formStyle(.grouped)
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchesAtLogin = LaunchAtLogin.isEnabled }
    }

    private var launchAtLoginToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            // A closure rather than the method itself, which crashes the Swift 6.2 compiler as a binding's setter.
            Toggle("Launch at login", isOn: Binding(get: { launchesAtLogin }, set: { setLaunchesAtLogin($0) }))
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

    /// The menu bar window is only asked for while the provider is shown, when the choice has an effect.
    private func providerSection(_ provider: any UsageProvider) -> some View {
        Section(provider.displayName) {
            providerToggle(provider)
            if settingsStore.settings.isEnabled(provider.id) {
                badgeWindowPicker(for: provider.id)
            }
        }
    }

    /// The last provider still on cannot be turned off: the menu bar item would have nothing left to show.
    private func providerToggle(_ provider: any UsageProvider) -> some View {
        let isEnabled = settingsStore.settings.isEnabled(provider.id)
        let isLastEnabled = isEnabled && usage.states.count == 1
        return Toggle("Show usage", isOn: Binding(
            get: { isEnabled },
            set: { enabled in settingsStore.update { $0.setEnabled(enabled, for: provider.id) } }
        ))
        .disabled(isLastEnabled)
        .help(isLastEnabled ? "At least one provider stays on" : "")
    }

    /// Lists what the badge would actually show: a stored choice the snapshot no longer reports is displayed as the
    /// primary window it falls back to. Before the first snapshot only the default can be named.
    private func badgeWindowPicker(for provider: ProviderID) -> some View {
        let state = usage.states.first { $0.id == provider }
        let shownWindowID = state?.badgeWindow(for: settingsStore.settings.badgeWindowIDs[provider])?.id
        return Picker("Show in menu bar", selection: Binding(
            get: { shownWindowID },
            set: { windowID in settingsStore.update { $0.badgeWindowIDs[provider] = windowID } }
        )) {
            if shownWindowID == nil {
                Text("5-hour (default)").tag(String?.none)
            }
            ForEach(state?.snapshot?.windows ?? []) { window in
                Text(window.title).tag(String?.some(window.id))
            }
        }
    }

    private var openShortcutRecorder: some View {
        LabeledContent {
            ShortcutRecorder(
                shortcut: settingsStore.settings.openPopoverShortcut,
                onChange: { shortcut in settingsStore.update { $0.openPopoverShortcut = shortcut } },
                onRecordingChange: hotKey.setPaused)
        } label: {
            Text("Open AI Bar")
            if let failure = hotKey.failure {
                Text(failure)
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
