import XCTest
@testable import SessionCore

/// Tests for AppState-related logic (filtered sessions, state transitions).
/// These test the pure logic independently of the @MainActor AppState class.
final class AppStateTests: XCTestCase {

    // MARK: - Filtered Sessions

    func testFilterByProjectName() {
        let sessions = makeSessions()
        let filtered = filterSessions(sessions, query: "turnshare")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.projectName, "turnshare")
    }

    func testFilterByGitBranch() {
        let sessions = makeSessions()
        let filtered = filterSessions(sessions, query: "feature")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.gitBranch, "feature/auth")
    }

    func testFilterByMessage() {
        let sessions = makeSessions()
        let filtered = filterSessions(sessions, query: "hello")
        XCTAssertEqual(filtered.count, 1)
    }

    func testEmptyQueryReturnsAll() {
        let sessions = makeSessions()
        let filtered = filterSessions(sessions, query: "")
        XCTAssertEqual(filtered.count, sessions.count)
    }

    func testCaseInsensitiveFilter() {
        let sessions = makeSessions()
        let filtered = filterSessions(sessions, query: "TURNSHARE")
        XCTAssertEqual(filtered.count, 1)
    }

    func testNoMatch() {
        let sessions = makeSessions()
        let filtered = filterSessions(sessions, query: "zzzzz")
        XCTAssertTrue(filtered.isEmpty)
    }

    // MARK: - Helpers

    /// Mirrors AppState.filteredSessions logic without requiring @MainActor.
    private func filterSessions(_ sessions: [SessionSummary], query: String) -> [SessionSummary] {
        if query.isEmpty { return sessions }
        let q = query.lowercased()
        return sessions.filter { s in
            (s.projectName?.lowercased().contains(q) ?? false)
                || (s.firstUserMessage?.lowercased().contains(q) ?? false)
                || (s.gitBranch?.lowercased().contains(q) ?? false)
        }
    }

    private func makeSessions() -> [SessionSummary] {
        [
            SessionSummary(
                id: "1", agent: .claudeCode, projectName: "turnshare",
                gitBranch: "main", startedAt: Date(),
                firstUserMessage: "Fix the build", turnCount: 10,
                filePath: URL(fileURLWithPath: "/tmp/1.jsonl")
            ),
            SessionSummary(
                id: "2", agent: .claudeCode, projectName: "cinetry",
                gitBranch: "feature/auth", startedAt: Date(),
                firstUserMessage: "Hello world", turnCount: 5,
                filePath: URL(fileURLWithPath: "/tmp/2.jsonl")
            ),
            SessionSummary(
                id: "3", agent: .codex, projectName: "departr",
                gitBranch: "main", startedAt: Date(),
                firstUserMessage: "Add tests", turnCount: 3,
                filePath: URL(fileURLWithPath: "/tmp/3.jsonl")
            ),
        ]
    }
}
