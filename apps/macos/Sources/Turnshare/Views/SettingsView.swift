import SwiftUI
import HotKey

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

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
                        .foregroundColor(.secondary)

                    ModifierPicker(
                        selected: QuickPublishConfig.shared.modifier,
                        onChange: { mod in
                            QuickPublishConfig.shared.update(mod)
                            appState.quickPublishModifierChanged()
                        }
                    )

                    Text("+ 1–9")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
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
                            .foregroundColor(.green)
                        if let username = appState.githubUsername {
                            Text(username)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Re-authenticate") { appState.startSignIn() }
                            .font(.subheadline)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        Button("Sign Out") { appState.signOut() }
                            .font(.subheadline)
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                    }
                } else if appState.isAuthenticating {
                    if let code = appState.authUserCode {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enter code on GitHub:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    HStack {
                        if let error = appState.authError {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Sign in with GitHub") { appState.startSignIn() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                        .background(selected == mod ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundColor(selected == mod ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
