import Foundation
import SessionCore
import ProviderClaude

@MainActor
final class AppState: ObservableObject {
    @Published var sessions: [SessionSummary] = []
    @Published var isLoading = false
    @Published var searchText = ""

    private let claudeProvider = ClaudeProvider()

    var filteredSessions: [SessionSummary] {
        if searchText.isEmpty { return sessions }
        let query = searchText.lowercased()
        return sessions.filter { session in
            (session.projectName?.lowercased().contains(query) ?? false)
                || (session.firstUserMessage?.lowercased().contains(query) ?? false)
                || (session.gitBranch?.lowercased().contains(query) ?? false)
        }
    }

    func loadSessions() {
        isLoading = true
        defer { isLoading = false }

        do {
            sessions = try claudeProvider.listSessions()
        } catch {
            print("Failed to load sessions: \(error)")
            sessions = []
        }
    }

    func fullSession(for summary: SessionSummary) throws -> Session {
        try claudeProvider.parseSession(at: summary.filePath)
    }
}
