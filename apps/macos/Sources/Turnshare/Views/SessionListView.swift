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

            // Settings panel
            if showSettings {
                SettingsView()
                Divider()
            }

            // Footer
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

            if appState.isAuthenticated, let username = appState.githubUsername {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text(username)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if appState.isAuthenticating {
                ProgressView()
                    .controlSize(.small)
                Text("Authenticating...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !appState.isAuthenticated {
                Image(systemName: "person.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Not signed in")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(appState.filteredSessions.count) sessions")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
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

                if session.turnCount > 0 {
                    Text("\(session.turnCount) turns")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Shortcut hint (⌘1, ⌥1, ⌃1, …)
            if let idx = shortcutIndex {
                Text("\(appState.quickPublishSymbol)\(idx)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isSelected ? 4 : 0)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
                : nil
        )
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
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
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            ForEach(Array(turn.content.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Text(trimmed)
                            .font(.body)
                            .foregroundColor(.primary)
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
        case .user: return .blue
        case .assistant: return .orange
        case .tool: return .gray
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
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1))
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
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("Cancel") {
                appState.cancelSelection()
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundColor(.secondary)

            Button("Publish") {
                appState.confirmPublish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
