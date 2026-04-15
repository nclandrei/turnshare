import SwiftUI
import SessionCore
import HotKey

struct SessionListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    /// Returns a properly pluralized session count label (e.g. "1 session", "3 sessions").
    static func sessionCountLabel(_ count: Int) -> String {
        count == 1 ? "1 session" : "\(count) sessions"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textMuted)
                TextField("Search sessions...", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(Theme.text)
            }
            .padding(10)
            .background(Theme.bgSurface)

            Divider()

            // Session list
            if appState.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if appState.filteredSessions.isEmpty {
                Spacer()
                Text("No sessions found")
                    .foregroundColor(Theme.textMuted)
                Spacer()
            } else {
                List {
                    ForEach(
                        Array(appState.filteredSessions.enumerated()),
                        id: \.element.id
                    ) { index, session in
                        Button {
                            appState.publishByIndex(index)
                        } label: {
                            SessionRowView(
                                session: session,
                                shortcutIndex: index < 9 ? index + 1 : nil,
                                isSelected: appState.selectedSessionIndex == index
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear { appState.loadMoreIfNeeded(currentSession: session) }
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
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
            }

            // Confirmation bar
            if let selectedIndex = appState.selectedSessionIndex,
               selectedIndex < appState.filteredSessions.count {
                Divider()
                ConfirmationBarView(session: appState.filteredSessions[selectedIndex])
            }

            Divider()

            // Publish status
            if appState.isPublishing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Publishing...")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
            } else if let url = appState.lastPublishedURL {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.accentGreen)
                        .font(.caption)
                    Text("URL copied!")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                    Text(url)
                        .font(.caption)
                        .foregroundColor(Theme.accentBlue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
            } else if let error = appState.publishError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.accentRed)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.accentRed)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
            }

            // Settings panel
            if showSettings {
                SettingsView()
                Divider()
            }

            // Footer
            FooterView(showSettings: $showSettings)
        }
        .background(Theme.bg)
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
                    .foregroundColor(showSettings ? Theme.accentBlue : Theme.textMuted)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AccessibilityID.settingsButtonLabel)

            if appState.isAuthenticated, let username = appState.githubUsername {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(Theme.accentGreen)
                    .font(.caption)
                Text(username)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            } else if appState.isAuthenticating {
                ProgressView()
                    .controlSize(.small)
                Text("Authenticating...")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            } else if !appState.isAuthenticated {
                Image(systemName: "person.circle")
                    .foregroundColor(Theme.textMuted)
                    .font(.caption)
                Text("Not signed in")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            Text(SessionListView.sessionCountLabel(appState.filteredSessions.count))
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
        .padding(10)
        .background(Theme.bgSurface)
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    @EnvironmentObject var appState: AppState
    let session: SessionSummary
    /// 1-based shortcut number (nil for items beyond 9).
    let shortcutIndex: Int?
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(agentLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(agentBgColor)
                        .foregroundColor(agentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if let project = session.projectName {
                        Text(project)
                            .font(.headline)
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                    }

                    if let branch = session.gitBranch {
                        Text(branch)
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(timeAgo)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }

                if let message = session.firstUserMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(2)
                }

                if session.turnCount > 0 {
                    Text("\(session.turnCount) turns")
                        .font(.caption2)
                        .foregroundColor(Theme.textSubtle)
                }
            }

            // Shortcut hint (⌘1, ⌥1, ⌃1, …)
            if let idx = shortcutIndex {
                Text("\(appState.quickPublishSymbol)\(idx)")
                    .font(.caption)
                    .foregroundColor(Theme.textSubtle)
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isSelected ? 4 : 0)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.accentBlue.opacity(0.12))
                : nil
        )
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.accentBlue.opacity(0.5), lineWidth: 1.5)
                : nil
        )
    }

    private var agentLabel: String {
        switch session.agent {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    private var agentBgColor: Color {
        switch session.agent {
        case .claudeCode: return Theme.claudeBg
        case .codex: return Theme.codexBg
        case .opencode: return Theme.opencodeBg
        }
    }

    private var agentColor: Color {
        switch session.agent {
        case .claudeCode: return Theme.claudeText
        case .codex: return Theme.codexText
        case .opencode: return Theme.opencodeText
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
                        .foregroundColor(Theme.textMuted)
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
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onHover { hovering in
            appState.isHoveringPreviewPanel = hovering
            if !hovering {
                appState.clearPreview()
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
                .background(agentBgColor)
                .foregroundColor(agentFgColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let project = session.projectName {
                Text(project)
                    .font(.headline)
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
            }

            if let branch = session.gitBranch {
                Text(branch)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Text(timeAgo)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
        .padding(10)
        .background(Theme.bgSurface)
    }

    private var agentLabel: String {
        switch session.agent {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    private var agentBgColor: Color {
        switch session.agent {
        case .claudeCode: return Theme.claudeBg
        case .codex: return Theme.codexBg
        case .opencode: return Theme.opencodeBg
        }
    }

    private var agentFgColor: Color {
        switch session.agent {
        case .claudeCode: return Theme.claudeText
        case .codex: return Theme.codexText
        case .opencode: return Theme.opencodeText
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

            ForEach(Array(turn.content.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Text(trimmed)
                            .font(.body)
                            .foregroundColor(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .toolUse(let toolUse):
                    ToolUsePill(toolUse: toolUse)
                case .toolResult:
                    EmptyView()
                }
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
        case .user: return Theme.userText
        case .assistant: return Theme.assistantText
        case .tool: return Theme.toolText
        }
    }
}

private struct ToolUsePill: View {
    let toolUse: ToolUse

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
            Text(toolUse.name)
                .font(.caption)
                .fontWeight(.medium)
            if let snippet = inputSnippet {
                Text(snippet)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .foregroundColor(Theme.textMuted)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var inputSnippet: String? {
        guard let input = toolUse.input, !input.isEmpty,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Extract the most meaningful field for common tools
        let value: String? =
            (json["command"] as? String) ??     // Bash
            (json["file_path"] as? String) ??   // Read, Write, Edit
            (json["pattern"] as? String) ??     // Glob, Grep
            (json["query"] as? String) ??       // WebSearch
            (json["url"] as? String)            // WebFetch

        guard let raw = value, !raw.isEmpty else { return nil }
        let clean = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(60))
    }
}

// MARK: - Confirmation Bar

struct ConfirmationBarView: View {
    @EnvironmentObject var appState: AppState
    let session: SessionSummary

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let project = session.projectName {
                    Text(project)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                if let message = session.firstUserMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("Cancel") {
                appState.cancelSelection()
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundColor(Theme.textMuted)

            Button("Publish") {
                appState.confirmPublish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bgSurface)
    }
}
