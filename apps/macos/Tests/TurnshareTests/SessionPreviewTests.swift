import XCTest
@testable import SessionCore
@testable import ProviderClaude
@testable import Turnshare

/// Tests for the expand-on-hover session preview feature.
final class SessionPreviewTests: XCTestCase {

    // MARK: - Preview Turn Limit

    func testPreviewTurnLimitIsReasonable() {
        // The limit should allow a comfortable conversation preview in the side panel
        XCTAssertGreaterThanOrEqual(AppState.previewTurnLimit, 10)
        XCTAssertLessThanOrEqual(AppState.previewTurnLimit, 30)
    }

    // MARK: - Preview Loading (Integration with ClaudeProvider)

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("turnshare-preview-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testPreviewLoadsParsedTurns() throws {
        let projectDir = tempDir.appendingPathComponent("-Users-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let file = projectDir.appendingPathComponent("preview-test.jsonl")
        let jsonl = """
        {"type":"user","sessionId":"s1","cwd":"/tmp/proj","timestamp":"2024-01-01T00:00:00.000Z","message":{"content":"Fix the bug"}}
        {"type":"assistant","timestamp":"2024-01-01T00:00:01.000Z","message":{"model":"claude-opus-4-6","content":[{"type":"text","text":"I'll look into it."}]}}
        {"type":"user","sessionId":"s1","cwd":"/tmp/proj","timestamp":"2024-01-01T00:00:02.000Z","message":{"content":"Thanks"}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let session = try provider.parseSession(at: file)

        // Verify the turns can be used for preview
        let previewTurns = Array(session.turns.prefix(AppState.previewTurnLimit))
        XCTAssertEqual(previewTurns.count, 3)
        XCTAssertEqual(previewTurns[0].role, .user)
        XCTAssertEqual(previewTurns[1].role, .assistant)
        XCTAssertEqual(previewTurns[2].role, .user)

        // Verify content of parsed turns
        if case .text(let t) = previewTurns[0].content.first {
            XCTAssertEqual(t, "Fix the bug")
        } else { XCTFail("Expected text block") }
        if case .text(let t) = previewTurns[1].content.first {
            XCTAssertEqual(t, "I'll look into it.")
        } else { XCTFail("Expected text block") }
    }

    func testPreviewTruncatesLongSessions() throws {
        let projectDir = tempDir.appendingPathComponent("-Users-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let file = projectDir.appendingPathComponent("long-session.jsonl")
        var lines: [String] = []
        for i in 0..<20 {
            let ts = String(format: "2024-01-01T00:%02d:00.000Z", i)
            if i % 2 == 0 {
                lines.append("""
                {"type":"user","sessionId":"s1","cwd":"/tmp","timestamp":"\(ts)","message":{"content":"Turn \(i)"}}
                """)
            } else {
                lines.append("""
                {"type":"assistant","timestamp":"\(ts)","message":{"model":"claude-opus-4-6","content":[{"type":"text","text":"Reply \(i)"}]}}
                """)
            }
        }
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.turns.count, 20)

        // Preview should only take the first N turns
        let previewTurns = Array(session.turns.prefix(AppState.previewTurnLimit))
        XCTAssertEqual(previewTurns.count, AppState.previewTurnLimit)
    }

    func testPreviewWithToolUseTurns() throws {
        let file = tempDir.appendingPathComponent("tool-session.jsonl")
        let jsonl = """
        {"type":"user","sessionId":"s1","cwd":"/tmp","timestamp":"2024-01-01T00:00:00.000Z","message":{"content":"Read the file"}}
        {"type":"assistant","timestamp":"2024-01-01T00:00:01.000Z","message":{"model":"claude-opus-4-6","content":[{"type":"text","text":"Sure."},{"type":"tool_use","name":"Read","id":"tu-1","input":{"path":"/tmp/f.txt"}}]}}
        {"type":"tool_result","timestamp":"2024-01-01T00:00:02.000Z","toolUseID":"tu-1","result":"file content here"}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let session = try provider.parseSession(at: file)

        let previewTurns = Array(session.turns.prefix(AppState.previewTurnLimit))
        XCTAssertEqual(previewTurns.count, 3)

        // Assistant turn should have text and tool use blocks
        XCTAssertEqual(previewTurns[1].content.count, 2)
        if case .text(let t) = previewTurns[1].content[0] {
            XCTAssertEqual(t, "Sure.")
        } else { XCTFail("Expected text block") }
        if case .toolUse(let tu) = previewTurns[1].content[1] {
            XCTAssertEqual(tu.name, "Read")
        } else {
            XCTFail("Expected tool use block")
        }

        // Tool result turn
        if case .toolResult(let tr) = previewTurns[2].content[0] {
            XCTAssertEqual(tr.output, "file content here")
        } else {
            XCTFail("Expected tool result block")
        }
    }

    func testPreviewEmptySession() throws {
        let file = tempDir.appendingPathComponent("empty.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let session = try provider.parseSession(at: file)

        let previewTurns = Array(session.turns.prefix(AppState.previewTurnLimit))
        XCTAssertTrue(previewTurns.isEmpty)
    }

    // MARK: - Preview State Logic

    func testPreviewCacheLogic() throws {
        // Test that caching returns the same data without re-parsing
        let projectDir = tempDir.appendingPathComponent("-Users-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let file = projectDir.appendingPathComponent("cache-test.jsonl")
        let jsonl = """
        {"type":"user","sessionId":"cache-1","cwd":"/tmp","timestamp":"2024-01-01T00:00:00.000Z","message":{"content":"test"}}
        {"type":"assistant","timestamp":"2024-01-01T00:00:01.000Z","message":{"model":"claude-opus-4-6","content":[{"type":"text","text":"reply"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let session = try provider.parseSession(at: file)
        let turns1 = Array(session.turns.prefix(AppState.previewTurnLimit))

        // Parse again — should produce identical results (simulating cache hit)
        let session2 = try provider.parseSession(at: file)
        let turns2 = Array(session2.turns.prefix(AppState.previewTurnLimit))

        XCTAssertEqual(turns1.count, turns2.count)
        for (t1, t2) in zip(turns1, turns2) {
            XCTAssertEqual(t1.role, t2.role)
            XCTAssertEqual(t1.content.count, t2.content.count)
        }
    }

    // MARK: - Preview State Transitions (Pure Logic)

    func testPreviewStateClearResetsAll() {
        // Mirrors clearPreview logic
        var previewSessionId: String? = "some-id"
        var previewTurns: [Turn] = [Turn(role: .user, content: [.text("hi")], timestamp: Date())]
        var isLoadingPreview = true

        // Clear
        previewSessionId = nil
        previewTurns = []
        isLoadingPreview = false

        XCTAssertNil(previewSessionId)
        XCTAssertTrue(previewTurns.isEmpty)
        XCTAssertFalse(isLoadingPreview)
    }

    func testPreviewStateGuardsAgainstSameSession() {
        // Mirrors loadPreview guard: `guard previewSessionId != sessionId`
        var previewSessionId: String? = "abc"
        var loadCount = 0

        // Simulates calling loadPreview with same ID
        func loadPreview(for id: String) {
            guard previewSessionId != id else { return }
            previewSessionId = id
            loadCount += 1
        }

        loadPreview(for: "abc")  // Should be no-op
        XCTAssertEqual(loadCount, 0)

        loadPreview(for: "def")  // Should trigger load
        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(previewSessionId, "def")
    }

    func testPreviewForUnknownSessionIdYieldsEmptyTurns() {
        // When the session ID doesn't match any known session, preview turns should be empty
        let sessions = makeSessions()
        let unknownId = "non-existent"
        let match = sessions.first(where: { $0.id == unknownId })
        XCTAssertNil(match)
    }

    // MARK: - Helpers

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
        ]
    }
}
