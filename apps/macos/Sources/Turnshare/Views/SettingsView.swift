import SwiftUI
import HotKey

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updaterController: UpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Global Hotkey
            VStack(alignment: .leading, spacing: 6) {
                Text("Global Hotkey")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HotKeyRecorderView(
                    currentCombo: HotKeyConfig.shared.keyCombo,
                    onRecord: { combo in
                        if let delegate = AppDelegate.shared {
                            delegate.updateHotKey(combo)
                        }
                    }
                )
            }

            Divider()

            // Quick-Publish Modifier
            VStack(alignment: .leading, spacing: 6) {
                Text("Session Shortcut")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Text("Modifier")
                        .font(.subheadline)
                        .foregroundColor(Theme.textMuted)

                    ModifierPicker(
                        selected: QuickPublishConfig.shared.modifier,
                        onChange: { mod in
                            QuickPublishConfig.shared.update(mod)
                            appState.quickPublishModifierChanged()
                        }
                    )

                    Text("+ 1–9")
                        .font(.subheadline)
                        .foregroundColor(Theme.textMuted)
                }
            }

            Divider()

            // Publish Behavior
            VStack(alignment: .leading, spacing: 6) {
                Text("Publish Behavior")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Toggle(isOn: Binding(
                    get: { PublishConfirmConfig.shared.isEnabled },
                    set: { newValue in
                        PublishConfirmConfig.shared.update(newValue)
                        appState.publishConfirmationChanged()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Confirm before publishing")
                            .font(.subheadline)
                        Text("Select a session first, then confirm with a Publish button")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider()

            // GitHub Account
            VStack(alignment: .leading, spacing: 6) {
                Text("GitHub")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if appState.isAuthenticated {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(Theme.accentGreen)
                        if let username = appState.githubUsername {
                            Text(username)
                                .font(.subheadline)
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                        Button("Re-authenticate") { appState.startSignIn() }
                            .font(.subheadline)
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.accentBlue)
                        Button("Sign Out") { appState.signOut() }
                            .font(.subheadline)
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.textMuted)
                    }
                } else if appState.isAuthenticating {
                    if let code = appState.authUserCode {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enter code on GitHub:")
                                .font(.subheadline)
                                .foregroundColor(Theme.textMuted)
                            Text(code)
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.bold)
                                .textSelection(.enabled)
                        }
                    } else {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Connecting to GitHub...")
                                .font(.subheadline)
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                } else {
                    HStack {
                        if let error = appState.authError {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(Theme.accentRed)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(Theme.accentRed)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Sign in with GitHub") { appState.startSignIn() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                    }
                }
            }

            Divider()

            // Updates
            VStack(alignment: .leading, spacing: 6) {
                Text("Updates")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack {
                    Text("Automatically checks for updates")
                        .font(.subheadline)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    Button("Check for Updates") {
                        updaterController.checkForUpdates()
                    }
                    .disabled(!updaterController.canCheckForUpdates)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.bgSurface)
    }
}

// MARK: - Modifier Picker (custom buttons — segmented picker doesn't work in NSPanel)

struct ModifierPicker: View {
    @State private var selected: QuickPublishConfig.Modifier
    let onChange: (QuickPublishConfig.Modifier) -> Void

    init(selected: QuickPublishConfig.Modifier, onChange: @escaping (QuickPublishConfig.Modifier) -> Void) {
        self._selected = State(initialValue: selected)
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(QuickPublishConfig.Modifier.allCases) { mod in
                Button(action: {
                    selected = mod
                    onChange(mod)
                }) {
                    Text(mod.label)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selected == mod ? Theme.accentBlue : Theme.bgElevated)
                        .foregroundColor(selected == mod ? .white : Theme.text)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
