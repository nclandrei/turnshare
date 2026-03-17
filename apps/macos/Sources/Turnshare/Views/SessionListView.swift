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

            // Footer
            HStack {
                Text("\(appState.filteredSessions.count) sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Publish") { publishSelected() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(selectedId == nil)
            }
            .padding(10)
        }
        .onAppear { appState.loadSessions() }
    }

    private func publishSelected() {
        guard let id = selectedId else { return }
        // TODO: publish the selected session
        print("Publishing session: \(id)")
    }
}

struct SessionRowView: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Agent badge
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
