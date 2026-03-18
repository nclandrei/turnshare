import XCTest
@testable import ProviderCodex
@testable import SessionCore

final class CodexProviderTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("turnshare-codex-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Session File Listing

    func testListSessionFilesEmptyDir() throws {
        let provider = CodexProvider(codexDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertTrue(files.isEmpty)
    }

    func testListSessionFilesNonexistentDir() throws {
        let provider = CodexProvider(codexDir: tempDir.appendingPathComponent("does-not-exist"))
        let files = try provider.listSessionFiles()
        XCTAssertTrue(files.isEmpty)
    }

    func testListSessionFilesFindsArchivedSessions() throws {
        let archivedDir = tempDir.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)

        let file = archivedDir.appendingPathComponent("rollout-2026-03-01T10-00-00-abc123.jsonl")
        try makeMinimalCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files.first!.lastPathComponent.contains("rollout"))
    }

    func testListSessionFilesFindsNestedSessions() throws {
        let dayDir = tempDir
            .appendingPathComponent("sessions")
            .appendingPathComponent("2026")
            .appendingPathComponent("03")
            .appendingPathComponent("15")
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        let file = dayDir.appendingPathComponent("rollout-2026-03-15T10-00-00-def456.jsonl")
        try makeMinimalCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertEqual(files.count, 1)
    }

    func testListSessionFilesCombinesActiveAndArchived() throws {
        // Archived session
        let archivedDir = tempDir.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)
        let archived = archivedDir.appendingPathComponent("archived.jsonl")
        try makeMinimalCodexJSONL(sessionId: "archived-1").write(to: archived, atomically: true, encoding: .utf8)

        // Active session
        let dayDir = tempDir.appendingPathComponent("sessions").appendingPathComponent("2026").appendingPathComponent("03").appendingPathComponent("15")
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        let active = dayDir.appendingPathComponent("active.jsonl")
        try makeMinimalCodexJSONL(sessionId: "active-1").write(to: active, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertEqual(files.count, 2)
    }

    func testListSessionFilesSortedByModDateDescending() throws {
        let archivedDir = tempDir.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)

        let older = archivedDir.appendingPathComponent("older.jsonl")
        try makeMinimalCodexJSONL(sessionId: "old").write(to: older, atomically: true, encoding: .utf8)

        Thread.sleep(forTimeInterval: 0.05)

        let newer = archivedDir.appendingPathComponent("newer.jsonl")
        try makeMinimalCodexJSONL(sessionId: "new").write(to: newer, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files.first?.lastPathComponent, "newer.jsonl")
    }

    func testListSessionFilesIgnoresNonJSONL() throws {
        let archivedDir = tempDir.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)

        try "not a session".write(
            to: archivedDir.appendingPathComponent("readme.txt"),
            atomically: true, encoding: .utf8
        )
        try makeMinimalCodexJSONL().write(
            to: archivedDir.appendingPathComponent("real.jsonl"),
            atomically: true, encoding: .utf8
        )

        let provider = CodexProvider(codexDir: tempDir)
        let files = try provider.listSessionFiles()
        XCTAssertEqual(files.count, 1)
    }

    func testListSessionFilesWithDatesReturnsTuples() throws {
        let archivedDir = tempDir.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)

        let file = archivedDir.appendingPathComponent("test.jsonl")
        try makeMinimalCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let tuples = try provider.listSessionFilesWithDates()
        XCTAssertEqual(tuples.count, 1)
        XCTAssertEqual(tuples.first?.url.lastPathComponent, "test.jsonl")
        XCTAssertNotEqual(tuples.first?.modDate, .distantPast)
    }

    func testListSessionFilesWithDatesSortedDescending() throws {
        let archivedDir = tempDir.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)

        let older = archivedDir.appendingPathComponent("older.jsonl")
        try makeMinimalCodexJSONL(sessionId: "old").write(to: older, atomically: true, encoding: .utf8)

        Thread.sleep(forTimeInterval: 0.05)

        let newer = archivedDir.appendingPathComponent("newer.jsonl")
        try makeMinimalCodexJSONL(sessionId: "new").write(to: newer, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let tuples = try provider.listSessionFilesWithDates()
        XCTAssertEqual(tuples.count, 2)
        XCTAssertEqual(tuples[0].url.lastPathComponent, "newer.jsonl")
        XCTAssertTrue(tuples[0].modDate >= tuples[1].modDate)
    }

    // MARK: - Session Scanning

    func testScanSessionReturnsSummary() throws {
        let file = tempDir.appendingPathComponent("test.jsonl")
        try makeMinimalCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let summary = provider.scanSession(at: file)
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.id, "sess-codex-1")
        XCTAssertEqual(summary?.agent, .codex)
        XCTAssertEqual(summary?.model, "gpt-5.3-codex")
        XCTAssertEqual(summary?.projectName, "my-project")
    }

    func testScanSessionReturnsNilForInvalidFile() throws {
        let file = tempDir.appendingPathComponent("bad.jsonl")
        try "not valid json".write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        XCTAssertNil(provider.scanSession(at: file))
    }

    func testScanSessionReturnsNilForMissingMeta() throws {
        // No session_meta entry → can't extract sessionId/timestamp → nil
        let file = tempDir.appendingPathComponent("no-meta.jsonl")
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hello"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        XCTAssertNil(provider.scanSession(at: file))
    }

    func testScanSessionReturnZeroTurnCount() throws {
        let file = tempDir.appendingPathComponent("turns.jsonl")
        try makeFullCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let summary = provider.scanSession(at: file)
        XCTAssertNotNil(summary)
        // Partial-read scan does not count turns
        XCTAssertEqual(summary?.turnCount, 0)
    }

    func testScanSessionExtractsFirstUserMessage() throws {
        let file = tempDir.appendingPathComponent("user-msg.jsonl")
        try makeFullCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let summary = provider.scanSession(at: file)
        XCTAssertEqual(summary?.firstUserMessage, "Fix the login bug")
    }

    func testScanSessionSkipsSystemUserContent() throws {
        // User message with only system content should not count as first user message
        let file = tempDir.appendingPathComponent("system.jsonl")
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"sys-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/proj"}}
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5"}}
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"<permissions instructions>sandbox</permissions instructions>"}]}}
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for the project"}]}}
        {"timestamp":"2026-01-01T00:00:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Real user question here"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let summary = provider.scanSession(at: file)
        XCTAssertEqual(summary?.firstUserMessage, "Real user question here")
    }

    // MARK: - Full Parsing

    func testParseSessionFromJSONL() throws {
        let file = tempDir.appendingPathComponent("full.jsonl")
        try makeFullCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.metadata.sessionId, "sess-codex-1")
        XCTAssertEqual(session.metadata.agent, .codex)
        XCTAssertEqual(session.metadata.model, "gpt-5.3-codex")
        XCTAssertEqual(session.metadata.projectName, "my-project")
        XCTAssertEqual(session.metadata.projectPath, "/tmp/my-project")
    }

    func testParseSessionTurnRoles() throws {
        let file = tempDir.appendingPathComponent("roles.jsonl")
        try makeFullCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.turns.count, 4)
        XCTAssertEqual(session.turns[0].role, .user)
        XCTAssertEqual(session.turns[1].role, .assistant)
        XCTAssertEqual(session.turns[2].role, .assistant) // function_call → assistant with toolUse
        XCTAssertEqual(session.turns[3].role, .tool)       // function_call_output → tool
    }

    func testParseSessionUserContent() throws {
        let file = tempDir.appendingPathComponent("user.jsonl")
        try makeFullCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        guard case .text(let text) = session.turns[0].content.first else {
            return XCTFail("Expected text content block")
        }
        XCTAssertEqual(text, "Fix the login bug")
    }

    func testParseSessionAssistantContent() throws {
        let file = tempDir.appendingPathComponent("assistant.jsonl")
        try makeFullCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        guard case .text(let text) = session.turns[1].content.first else {
            return XCTFail("Expected text content block")
        }
        XCTAssertEqual(text, "I'll look into the login issue.")
    }

    func testParseSessionFunctionCall() throws {
        let file = tempDir.appendingPathComponent("func.jsonl")
        try makeFullCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        guard case .toolUse(let toolUse) = session.turns[2].content.first else {
            return XCTFail("Expected toolUse content block")
        }
        XCTAssertEqual(toolUse.name, "exec_command")
        XCTAssertEqual(toolUse.id, "call_abc123")
        XCTAssertEqual(toolUse.input, #"{"cmd":"cat auth.swift"}"#)
    }

    func testParseSessionFunctionCallOutput() throws {
        let file = tempDir.appendingPathComponent("output.jsonl")
        try makeFullCodexJSONL().write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        guard case .toolResult(let result) = session.turns[3].content.first else {
            return XCTFail("Expected toolResult content block")
        }
        XCTAssertEqual(result.toolUseId, "call_abc123")
        XCTAssertTrue(result.output.contains("func login()"))
    }

    func testParseSessionSkipsDeveloperMessages() throws {
        let file = tempDir.appendingPathComponent("dev.jsonl")
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"dev-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/proj"}}
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5"}}
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"System instructions here"}]}}
        {"timestamp":"2026-01-01T00:00:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        // Developer message should be skipped
        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.turns[0].role, .user)
    }

    func testParseSessionSkipsReasoningEntries() throws {
        let file = tempDir.appendingPathComponent("reasoning.jsonl")
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"r-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/proj"}}
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"response_item","payload":{"type":"reasoning"}}
        {"timestamp":"2026-01-01T00:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.turns[0].role, .assistant)
    }

    func testParseSessionSkipsInvalidLines() throws {
        let file = tempDir.appendingPathComponent("invalid.jsonl")
        let jsonl = """
        not-json-at-all
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"inv-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/proj"}}
        {"broken json
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hi"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.metadata.sessionId, "inv-1")
    }

    func testParseSessionSkipsEventMsgEntries() throws {
        let file = tempDir.appendingPathComponent("events.jsonl")
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"ev-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/proj"}}
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}
        {"timestamp":"2026-01-01T00:00:02.000Z","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"2026-01-01T00:00:03.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        {"timestamp":"2026-01-01T00:00:04.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hi"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        // Only the assistant message should be a turn; event_msg entries are skipped
        XCTAssertEqual(session.turns.count, 1)
    }

    func testParseSessionTimestamps() throws {
        let file = tempDir.appendingPathComponent("ts.jsonl")
        let jsonl = """
        {"timestamp":"2026-03-15T10:30:00.000Z","type":"session_meta","payload":{"id":"ts-1","timestamp":"2026-03-15T10:30:00.000Z","cwd":"/tmp/proj"}}
        {"timestamp":"2026-03-15T10:30:01.500Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}
        {"timestamp":"2026-03-15T10:30:05.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hi"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        // startedAt should come from session_meta timestamp
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = formatter.date(from: "2026-03-15T10:30:00.000Z")!
        XCTAssertEqual(session.metadata.startedAt, expected)
        // endedAt should be last turn's timestamp
        let expectedEnd = formatter.date(from: "2026-03-15T10:30:05.000Z")!
        XCTAssertEqual(session.metadata.endedAt, expectedEnd)
    }

    func testParseSessionFallsBackToFilenameForSessionId() throws {
        // No session_meta → sessionId from filename
        let file = tempDir.appendingPathComponent("rollout-2026-abc.jsonl")
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hi"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.metadata.sessionId, "rollout-2026-abc")
    }

    func testParseSessionTimestampWithoutFractionalSeconds() throws {
        let file = tempDir.appendingPathComponent("nofrac.jsonl")
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00Z","type":"session_meta","payload":{"id":"nf-1","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp/proj"}}
        {"timestamp":"2026-01-01T00:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hi"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.metadata.sessionId, "nf-1")
    }

    func testParseSessionFiltersSystemUserContent() throws {
        let file = tempDir.appendingPathComponent("filter.jsonl")
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"f-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/proj"}}
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for the project"},{"type":"input_text","text":"<environment_context>cwd: /tmp</environment_context>"},{"type":"input_text","text":"Please fix the bug"}]}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertEqual(session.turns.count, 1)
        guard case .text(let text) = session.turns[0].content.first else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(text, "Please fix the bug")
    }

    func testParseSessionEmptyFile() throws {
        let file = tempDir.appendingPathComponent("empty.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        XCTAssertTrue(session.turns.isEmpty)
        XCTAssertEqual(session.metadata.sessionId, "empty")
        XCTAssertEqual(session.metadata.agent, .codex)
    }

    func testParseSessionMultipleFunctionCalls() throws {
        let file = tempDir.appendingPathComponent("multi-func.jsonl")
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"mf-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/proj"}}
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Check files"}]}}
        {"timestamp":"2026-01-01T00:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Checking..."}]}}
        {"timestamp":"2026-01-01T00:00:03.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"ls\\"}","call_id":"call_1"}}
        {"timestamp":"2026-01-01T00:00:03.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"pwd\\"}","call_id":"call_2"}}
        {"timestamp":"2026-01-01T00:00:04.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call_1","output":"file1.txt\\nfile2.txt"}}
        {"timestamp":"2026-01-01T00:00:04.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call_2","output":"/tmp/proj"}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        // user + assistant + 2 function_calls + 2 function_call_outputs = 6
        XCTAssertEqual(session.turns.count, 6)
        XCTAssertEqual(session.turns[2].role, .assistant)
        XCTAssertEqual(session.turns[3].role, .assistant)
        XCTAssertEqual(session.turns[4].role, .tool)
        XCTAssertEqual(session.turns[5].role, .tool)

        // Verify call IDs match
        guard case .toolUse(let tu1) = session.turns[2].content.first,
              case .toolResult(let tr1) = session.turns[4].content.first else {
            return XCTFail("Expected tool use and result")
        }
        XCTAssertEqual(tu1.id, "call_1")
        XCTAssertEqual(tr1.toolUseId, "call_1")
    }

    func testParseSessionOutputTruncation() throws {
        let file = tempDir.appendingPathComponent("truncate.jsonl")
        let longOutput = String(repeating: "x", count: 10000)
        let jsonl = """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"tr-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/proj"}}
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call_long","output":"\(longOutput)"}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexProvider(codexDir: tempDir)
        let session = try provider.parseSession(at: file)

        guard case .toolResult(let result) = session.turns.first?.content.first else {
            return XCTFail("Expected tool result")
        }
        XCTAssertEqual(result.output.count, 5000)
    }

    // MARK: - Helpers

    private func makeMinimalCodexJSONL(sessionId: String = "sess-codex-1", timestamp: String = "2026-01-01T00:00:00.000Z") -> String {
        return """
        {"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(sessionId)","timestamp":"\(timestamp)","cwd":"/tmp/my-project","model_provider":"openai"}}
        {"timestamp":"\(timestamp)","type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5.3-codex"}}
        {"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}
        {"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hi there"}]}}
        """
    }

    private func makeFullCodexJSONL() -> String {
        return """
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"session_meta","payload":{"id":"sess-codex-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp/my-project","model_provider":"openai","cli_version":"0.115.0"}}
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"turn_context","payload":{"turn_id":"t1","cwd":"/tmp/my-project","model":"gpt-5.3-codex"}}
        {"timestamp":"2026-01-01T00:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}
        {"timestamp":"2026-01-01T00:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Fix the login bug"}]}}
        {"timestamp":"2026-01-01T00:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"I'll look into the login issue."}]}}
        {"timestamp":"2026-01-01T00:00:03.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"cat auth.swift\\"}","call_id":"call_abc123"}}
        {"timestamp":"2026-01-01T00:00:04.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call_abc123","output":"func login() { /* code */ }"}}
        {"timestamp":"2026-01-01T00:00:05.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        """
    }
}
