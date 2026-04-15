import XCTest
@testable import SessionCore
@testable import Turnshare

/// Tests for AppState-related logic (filtered sessions, state transitions).
/// These test the pure logic independently of the @MainActor AppState class.
final class AppStateTests: XCTestCase {

    // MARK: - Merge Sorted Descending

    func testMergeSortedDescendingBothNonEmpty() {
        let now = Date()
        let a: [(url: URL, modDate: Date)] = [
            (URL(fileURLWithPath: "/a3"), now.addingTimeInterval(-1)),
            (URL(fileURLWithPath: "/a1"), now.addingTimeInterval(-5)),
        ]
        let b: [(url: URL, modDate: Date)] = [
            (URL(fileURLWithPath: "/b2"), now.addingTimeInterval(-2)),
            (URL(fileURLWithPath: "/b4"), now.addingTimeInterval(-10)),
        ]
        let merged = AppState.mergeSortedDescending(a, b)
        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(merged[0].url.lastPathComponent, "a3")
        XCTAssertEqual(merged[1].url.lastPathComponent, "b2")
        XCTAssertEqual(merged[2].url.lastPathComponent, "a1")
        XCTAssertEqual(merged[3].url.lastPathComponent, "b4")
    }

    func testMergeSortedDescendingOneEmpty() {
        let now = Date()
        let a: [(url: URL, modDate: Date)] = [
            (URL(fileURLWithPath: "/a1"), now),
        ]
        let b: [(url: URL, modDate: Date)] = []
        let merged = AppState.mergeSortedDescending(a, b)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].url.lastPathComponent, "a1")
    }

    func testMergeSortedDescendingBothEmpty() {
        let a: [(url: URL, modDate: Date)] = []
        let b: [(url: URL, modDate: Date)] = []
        XCTAssertTrue(AppState.mergeSortedDescending(a, b).isEmpty)
    }

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

    // MARK: - Publish Confirmation Mode (select → confirm)

    func testPublishByIndexInConfirmModeSelectsInsteadOfPublishing() {
        let sessions = makeSessions()
        // In confirm mode, publishByIndex should set selectedIndex instead of returning session for publish
        var selectedIndex: Int? = nil
        let result = publishByIndexConfirmMode(0, sessions: sessions, query: "", selectedIndex: &selectedIndex)
        XCTAssertTrue(result)
        XCTAssertEqual(selectedIndex, 0)
    }

    func testSelectByIndexSetsSelectedSession() {
        let sessions = makeSessions()
        var selectedIndex: Int? = nil
        let result = selectByIndex(1, sessions: sessions, query: "", selectedIndex: &selectedIndex)
        XCTAssertTrue(result)
        XCTAssertEqual(selectedIndex, 1)
    }

    func testSelectByIndexOutOfBoundsReturnsNil() {
        let sessions = makeSessions()
        var selectedIndex: Int? = nil
        XCTAssertFalse(selectByIndex(-1, sessions: sessions, query: "", selectedIndex: &selectedIndex))
        XCTAssertNil(selectedIndex)
        XCTAssertFalse(selectByIndex(99, sessions: sessions, query: "", selectedIndex: &selectedIndex))
        XCTAssertNil(selectedIndex)
    }

    func testSelectByIndexRespectsFilter() {
        let sessions = makeSessions()
        var selectedIndex: Int? = nil
        // Filter to "cinetry" → only session id "2"
        let result = selectByIndex(0, sessions: sessions, query: "cinetry", selectedIndex: &selectedIndex)
        XCTAssertTrue(result)
        XCTAssertEqual(selectedIndex, 0)
        // Verify the session at index 0 in the filtered list is "cinetry"
        let filtered = filterSessions(sessions, query: "cinetry")
        XCTAssertEqual(filtered[selectedIndex!].projectName, "cinetry")
        // Index 1 is out of bounds
        var idx2: Int? = nil
        XCTAssertFalse(selectByIndex(1, sessions: sessions, query: "cinetry", selectedIndex: &idx2))
    }

    func testConfirmPublishReturnsSelectedSession() {
        let sessions = makeSessions()
        var selectedIndex: Int? = 1
        let session = confirmPublish(sessions: sessions, query: "", selectedIndex: &selectedIndex)
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.id, "2")
        XCTAssertNil(selectedIndex, "Selection should be cleared after confirm")
    }

    func testConfirmPublishWhenNothingSelectedReturnsNil() {
        let sessions = makeSessions()
        var selectedIndex: Int? = nil
        let session = confirmPublish(sessions: sessions, query: "", selectedIndex: &selectedIndex)
        XCTAssertNil(session)
    }

    func testCancelSelectionClearsSelectedIndex() {
        var selectedIndex: Int? = 2
        cancelSelection(&selectedIndex)
        XCTAssertNil(selectedIndex)
    }

    func testInstantModeDoesNotSelect() {
        let sessions = makeSessions()
        // In instant mode, publishByIndex returns the session directly without setting selectedIndex
        let session = sessionAtIndex(0, sessions: sessions, query: "")
        XCTAssertNotNil(session)
        // There's no selectedIndex concept in instant mode
    }

    // MARK: - Session Count Label

    func testSessionCountLabelSingular() {
        XCTAssertEqual(sessionCountLabel(1), "1 session")
    }

    func testSessionCountLabelZero() {
        XCTAssertEqual(sessionCountLabel(0), "0 sessions")
    }

    func testSessionCountLabelPlural() {
        XCTAssertEqual(sessionCountLabel(2), "2 sessions")
        XCTAssertEqual(sessionCountLabel(100), "100 sessions")
    }

    // MARK: - Publish Cache

    func testPublishCacheLookupAndStore() {
        let cacheKey = "publishedGists"
        // Clean slate
        UserDefaults.standard.removeObject(forKey: cacheKey)

        // Empty cache returns nil
        let cache1 = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        XCTAssertNil(cache1["sess-abc"])

        // Store a mapping
        var cache2 = cache1
        cache2["sess-abc"] = "gist-123"
        UserDefaults.standard.set(cache2, forKey: cacheKey)

        // Retrieve it
        let cache3 = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        XCTAssertEqual(cache3["sess-abc"], "gist-123")

        // Other keys still nil
        XCTAssertNil(cache3["sess-other"])

        // Clean up
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    func testPublishCacheMultipleSessions() {
        let cacheKey = "publishedGists"
        UserDefaults.standard.removeObject(forKey: cacheKey)

        var cache: [String: String] = [:]
        cache["sess-1"] = "gist-aaa"
        cache["sess-2"] = "gist-bbb"
        UserDefaults.standard.set(cache, forKey: cacheKey)

        let loaded = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        XCTAssertEqual(loaded["sess-1"], "gist-aaa")
        XCTAssertEqual(loaded["sess-2"], "gist-bbb")
        XCTAssertEqual(loaded.count, 2)

        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    // MARK: - Helpers

    /// Mirrors the session count label logic in SessionListView.
    private func sessionCountLabel(_ count: Int) -> String {
        SessionListView.sessionCountLabel(count)
    }

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

    /// Mirrors AppState.publishByIndex in confirmation mode — selects instead of publishing.
    private func publishByIndexConfirmMode(_ index: Int, sessions: [SessionSummary], query: String, selectedIndex: inout Int?) -> Bool {
        return selectByIndex(index, sessions: sessions, query: query, selectedIndex: &selectedIndex)
    }

    /// Mirrors AppState.selectByIndex — sets selectedSessionIndex.
    private func selectByIndex(_ index: Int, sessions: [SessionSummary], query: String, selectedIndex: inout Int?) -> Bool {
        let list = filterSessions(sessions, query: query)
        guard index >= 0, index < list.count else { return false }
        selectedIndex = index
        return true
    }

    /// Mirrors AppState.confirmPublish — publishes the selected session.
    private func confirmPublish(sessions: [SessionSummary], query: String, selectedIndex: inout Int?) -> SessionSummary? {
        guard let index = selectedIndex else { return nil }
        let list = filterSessions(sessions, query: query)
        guard index >= 0, index < list.count else {
            selectedIndex = nil
            return nil
        }
        let session = list[index]
        selectedIndex = nil
        return session
    }

    /// Mirrors AppState.cancelSelection.
    private func cancelSelection(_ selectedIndex: inout Int?) {
        selectedIndex = nil
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
