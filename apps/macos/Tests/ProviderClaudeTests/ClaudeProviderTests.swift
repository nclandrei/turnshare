import XCTest
@testable import ProviderClaude
@testable import SessionCore

final class ClaudeProviderTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("turnshare-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Session File Listing

    func testListSessionFilesEmptyDir() throws {
        let provider = ClaudeProvider(claudeDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertTrue(files.isEmpty)
    }

    func testListSessionFilesFindsJSONLFiles() throws {
        let projectDir = tempDir.appendingPathComponent("-Users-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let sessionFile = projectDir.appendingPathComponent("abc-123.jsonl")
        let jsonl = makeMinimalJSONL()
        try jsonl.write(to: sessionFile, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.lastPathComponent, "abc-123.jsonl")
    }

    func testListSessionFilesReturnsAll() throws {
        let projectDir = tempDir.appendingPathComponent("-Users-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        for i in 0..<5 {
            let file = projectDir.appendingPathComponent("session-\(i).jsonl")
            let jsonl = makeMinimalJSONL(sessionId: "sess-\(i)", timestamp: "2024-01-0\(i + 1)T00:00:00.000Z")
            try jsonl.write(to: file, atomically: true, encoding: .utf8)
        }

        let provider = ClaudeProvider(claudeDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertEqual(files.count, 5)
    }

    func testListSessionFilesSortedByModDateDescending() throws {
        let projectDir = tempDir.appendingPathComponent("-Users-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Create files with different modification dates
        let older = projectDir.appendingPathComponent("older.jsonl")
        try makeMinimalJSONL(sessionId: "old").write(to: older, atomically: true, encoding: .utf8)

        // Small delay so mod dates differ
        Thread.sleep(forTimeInterval: 0.05)

        let newer = projectDir.appendingPathComponent("newer.jsonl")
        try makeMinimalJSONL(sessionId: "new").write(to: newer, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files.first?.lastPathComponent, "newer.jsonl")
    }

    // MARK: - Session Scanning

    func testScanSessionReturnsSummary() throws {
        let projectDir = tempDir.appendingPathComponent("-Users-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let file = projectDir.appendingPathComponent("abc-123.jsonl")
        try makeMinimalJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let summary = provider.scanSession(at: file)
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.id, "sess-1")
        XCTAssertEqual(summary?.agent, .claudeCode)
    }

    func testScanSessionReturnsNilForInvalidFile() throws {
        let file = tempDir.appendingPathComponent("bad.jsonl")
        try "not valid json".write(to: file, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        XCTAssertNil(provider.scanSession(at: file))
    }

    // MARK: - JSONL Parsing

    func testParseSessionFromJSONL() throws {
        let projectDir = tempDir.appendingPathComponent("-Users-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let file = projectDir.appendingPathComponent("test.jsonl")
        let jsonl = """
        {"type":"user","sessionId":"sess-1","cwd":"/tmp/project","gitBranch":"main","timestamp":"2024-01-01T00:00:00.000Z","message":{"content":"Hello"}}
        {"type":"assistant","timestamp":"2024-01-01T00:00:01.000Z","message":{"model":"claude-opus-4-6","content":[{"type":"text","text":"Hi there"}]}}
        {"type":"tool_result","timestamp":"2024-01-01T00:00:02.000Z","toolUseID":"tu-1","result":"output"}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.metadata.sessionId, "sess-1")
        XCTAssertEqual(session.metadata.agent, .claudeCode)
        XCTAssertEqual(session.metadata.model, "claude-opus-4-6")
        XCTAssertEqual(session.metadata.gitBranch, "main")
        XCTAssertEqual(session.metadata.projectName, "project")
        XCTAssertEqual(session.turns.count, 3)
        XCTAssertEqual(session.turns[0].role, .user)
        XCTAssertEqual(session.turns[1].role, .assistant)
        XCTAssertEqual(session.turns[2].role, .tool)
    }

    func testParseSessionSkipsInvalidLines() throws {
        let file = tempDir.appendingPathComponent("bad.jsonl")
        let jsonl = """
        not-json
        {"type":"user","sessionId":"s1","cwd":"/tmp","timestamp":"2024-01-01T00:00:00.000Z","message":{"content":"Hi"}}
        {"type":"unknown","timestamp":"2024-01-01T00:00:01.000Z"}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = ClaudeProvider(claudeDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.turns.count, 1)
    }

    // MARK: - Helpers

    private func makeMinimalJSONL(sessionId: String = "sess-1", timestamp: String = "2024-01-01T00:00:00.000Z") -> String {
        return """
        {"type":"user","sessionId":"\(sessionId)","cwd":"/tmp/project","timestamp":"\(timestamp)","message":{"content":"Hello"}}
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-opus-4-6","content":[{"type":"text","text":"Hi"}]}}
        """
    }
}
