import SwiftUI
import SessionCore

struct SessionListView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sessions...", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { publishSelected() }
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
                List(appState.filteredSessions, selection: $selectedId) { session in
                    SessionRowView(session: session)
                        .tag(session.id)
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

            // Auth / footer
            FooterView(selectedId: selectedId, onPublish: publishSelected)
        }
        .onAppear {
            appState.loadSessions()
            appState.restoreAuth()
        }
    }

    private func publishSelected() {
        guard let id = selectedId else { return }
        appState.publish(sessionId: id)
    }
}

// MARK: - Footer

struct FooterView: View {
    @EnvironmentObject var appState: AppState
    let selectedId: String?
    let onPublish: () -> Void

    var body: some View {
        HStack {
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

                Button("Publish") { onPublish() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(selectedId == nil || appState.isPublishing)
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

    var body: some View {
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
