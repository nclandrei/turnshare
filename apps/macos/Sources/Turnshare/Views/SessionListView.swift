import SwiftUI
import SessionCore
import HotKey

struct SessionListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sessions...", text: $appState.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(.ultraThinMaterial)

            Divider()

            // Session list
            if appState.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if appState.filteredSessions.isEmpty {
                Spacer()
                Text("No sessions found")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(
                        Array(appState.filteredSessions.enumerated()),
                        id: \.element.id
                    ) { index, session in
                        SessionRowView(
                            session: session,
                            shortcutIndex: index < 9 ? index + 1 : nil
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { appState.publishByIndex(index) }
                        .onHover { hovering in
                            if hovering {
                                appState.loadPreview(for: session.id)
                            } else {
                                appState.clearPreview()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Publish status
            if appState.isPublishing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Publishing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
            } else if let url = appState.lastPublishedURL {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("URL copied!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(url)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
            } else if let error = appState.publishError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
            }

            // Settings row
            if showSettings {
                HStack {
                    HotKeyRecorderView(
                        currentCombo: HotKeyConfig.shared.keyCombo,
                        onRecord: { combo in
                            if let delegate = NSApp.delegate as? AppDelegate {
                                delegate.updateHotKey(combo)
                            }
                        }
                    )
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
            }

            // Auth / footer
            FooterView(showSettings: $showSettings)
        }
        .onAppear {
            appState.loadSessions()
            appState.restoreAuth()
        }
    }

}

// MARK: - Footer

struct FooterView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .foregroundColor(showSettings ? .accentColor : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)

            if appState.isAuthenticated {
                // Signed in
                if let username = appState.githubUsername {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(username)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Sign Out") { appState.signOut() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            } else if appState.isAuthenticating {
                // Device flow in progress
                if let code = appState.authUserCode {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enter code on GitHub:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(code)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting to GitHub...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                // Not signed in
                if let error = appState.authError {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                    Spacer()
                }

                Text("\(appState.filteredSessions.count) sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Sign in with GitHub") { appState.startSignIn() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: SessionSummary
    /// 1-based shortcut number (nil for items beyond 9).
    let shortcutIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(agentLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(agentColor.opacity(0.15))
                        .foregroundColor(agentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if let project = session.projectName {
                        Text(project)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    if let branch = session.gitBranch {
                        Text(branch)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(timeAgo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let message = session.firstUserMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text("\(session.turnCount) turns")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Shortcut hint (⌘1, ⌘2, …)
            if let idx = shortcutIndex {
                Text("⌘\(idx)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private var agentLabel: String {
        switch session.agent {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    private var agentColor: Color {
        switch session.agent {
        case .claudeCode: return .orange
        case .codex: return .green
        case .opencode: return .blue
        }
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.startedAt, relativeTo: Date())
    }
}

// MARK: - Preview Panel (side panel shown on hover)

struct PreviewPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session = currentSession {
                // Header
                PreviewHeaderView(session: session)
                Divider()

                // Conversation body
                if appState.isLoadingPreview {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    Spacer()
                } else if appState.previewTurns.isEmpty {
                    Spacer()
                    Text("No conversation data")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(appState.previewTurns) { turn in
                                PreviewTurnView(turn: turn)
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
    }

    private var currentSession: SessionSummary? {
        guard let id = appState.previewSessionId else { return nil }
        return appState.sessions.first { $0.id == id }
    }
}

private struct PreviewHeaderView: View {
    let session: SessionSummary

    var body: some View {
        HStack {
            Text(agentLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(agentColor.opacity(0.15))
                .foregroundColor(agentColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let project = session.projectName {
                Text(project)
                    .font(.headline)
                    .lineLimit(1)
            }

            if let branch = session.gitBranch {
                Text(branch)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(timeAgo)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
    }

    private var agentLabel: String {
        switch session.agent {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    private var agentColor: Color {
        switch session.agent {
        case .claudeCode: return .orange
        case .codex: return .green
        case .opencode: return .blue
        }
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.startedAt, relativeTo: Date())
    }
}

struct PreviewTurnView: View {
    let turn: Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(roleLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(roleColor)

            if turn.role == .tool {
                // Tool turns: just show tool name, dimmed
                Text(turnText)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text(turnText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var roleLabel: String {
        switch turn.role {
        case .user: return "User"
        case .assistant: return "Assistant"
        case .tool: return "Tool"
        }
    }

    private var roleColor: Color {
        switch turn.role {
        case .user: return .blue
        case .assistant: return .orange
        case .tool: return .gray
        }
    }

    private var turnText: String {
        Self.extractText(from: turn)
    }

    /// Extract a human-readable summary from a turn's content blocks.
    static func extractText(from turn: Turn) -> String {
        let texts = turn.content.compactMap { block -> String? in
            switch block {
            case .text(let text):
                return text
            case .toolUse(let toolUse):
                return "[\(toolUse.name)]"
            case .toolResult(let result):
                return result.output.isEmpty ? nil : String(result.output.prefix(100))
            }
        }
        return texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
