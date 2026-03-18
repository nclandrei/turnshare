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

    // MARK: - Publish by Index

    func testPublishByIndexReturnsCorrectSession() {
        let sessions = makeSessions()
        // Index 0 → first session
        let target = sessionAtIndex(0, sessions: sessions, query: "")
        XCTAssertEqual(target?.id, "1")
        // Index 2 → third session
        let target2 = sessionAtIndex(2, sessions: sessions, query: "")
        XCTAssertEqual(target2?.id, "3")
    }

    func testPublishByIndexOutOfBoundsReturnsNil() {
        let sessions = makeSessions()
        XCTAssertNil(sessionAtIndex(-1, sessions: sessions, query: ""))
        XCTAssertNil(sessionAtIndex(3, sessions: sessions, query: ""))
        XCTAssertNil(sessionAtIndex(99, sessions: sessions, query: ""))
    }

    func testPublishByIndexRespectsFilter() {
        let sessions = makeSessions()
        // Filter to "cinetry" → only session id "2"
        let target = sessionAtIndex(0, sessions: sessions, query: "cinetry")
        XCTAssertEqual(target?.id, "2")
        // Index 1 is out of bounds after filtering
        XCTAssertNil(sessionAtIndex(1, sessions: sessions, query: "cinetry"))
    }

    func testPublishByIndexWithEmptyListReturnsNil() {
        let sessions: [SessionSummary] = []
        XCTAssertNil(sessionAtIndex(0, sessions: sessions, query: ""))
    }

    func testShortcutIndexAssignment() {
        let sessions = makeSessions()
        // First 9 items get shortcut indices 1-9, the rest get nil
        for i in 0..<min(9, sessions.count) {
            XCTAssertEqual(shortcutIndex(for: i), i + 1)
        }
        // Items beyond index 8 get nil
        XCTAssertNil(shortcutIndex(for: 9))
        XCTAssertNil(shortcutIndex(for: 100))
    }

    // MARK: - Shortcut Hint Display

    func testShortcutHintFormatWithCommandModifier() {
        let symbol = "\u{2318}"
        let hint = shortcutHint(symbol: symbol, index: 1)
        XCTAssertEqual(hint, "\u{2318}1")
    }

    func testShortcutHintFormatWithOptionModifier() {
        let symbol = "\u{2325}"
        let hint = shortcutHint(symbol: symbol, index: 3)
        XCTAssertEqual(hint, "\u{2325}3")
    }

    func testShortcutHintFormatWithControlModifier() {
        let symbol = "\u{2303}"
        let hint = shortcutHint(symbol: symbol, index: 9)
        XCTAssertEqual(hint, "\u{2303}9")
    }

    func testShortcutHintNilForIndexBeyond9() {
        // Items at index >= 9 should not get a shortcut hint
        XCTAssertNil(shortcutIndex(for: 9))
        XCTAssertNil(shortcutIndex(for: 10))
    }

    func testShortcutHintCoversRange1Through9() {
        for i in 0..<9 {
            let idx = shortcutIndex(for: i)
            XCTAssertNotNil(idx)
            XCTAssertEqual(idx, i + 1)
            // Hint should be symbol + number
            let hint = shortcutHint(symbol: "\u{2318}", index: idx!)
            XCTAssertEqual(hint, "\u{2318}\(i + 1)")
        }
    }

    // MARK: - Helpers

    /// Mirrors the shortcut index assignment logic: items 0-8 get 1-9, rest get nil.
    private func shortcutIndex(for index: Int) -> Int? {
        index < 9 ? index + 1 : nil
    }

    /// Mirrors the shortcut hint format: modifier symbol + index number.
    private func shortcutHint(symbol: String, index: Int) -> String {
        "\(symbol)\(index)"
    }

    /// Mirrors AppState.publishByIndex — resolves the session at a given index
    /// in the filtered list, returning nil for out-of-bounds.
    private func sessionAtIndex(_ index: Int, sessions: [SessionSummary], query: String) -> SessionSummary? {
        let list = filterSessions(sessions, query: query)
        guard index >= 0, index < list.count else { return nil }
        return list[index]
    }

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
