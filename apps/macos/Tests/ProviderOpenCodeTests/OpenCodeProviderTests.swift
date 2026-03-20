import XCTest
import SQLite3
@testable import ProviderOpenCode
@testable import SessionCore

final class OpenCodeProviderTests: XCTestCase {

    private var tempDir: URL!
    private var dbPath: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("turnshare-opencode-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbPath = tempDir.appendingPathComponent("opencode.db")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Listing

    func testListSessionFilesEmptyDB() throws {
        try makeTestDB(at: dbPath)
        let provider = OpenCodeProvider(dbPath: dbPath)
        let files = try provider.listSessionFiles()
        XCTAssertTrue(files.isEmpty)
    }

    func testListSessionFilesNonexistentDB() throws {
        let provider = OpenCodeProvider(dbPath: tempDir.appendingPathComponent("nope.db"))
        let files = try provider.listSessionFiles()
        XCTAssertTrue(files.isEmpty)
    }

    func testListSessionFilesReturnsVirtualURLs() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_abc123", directory: "/tmp/proj", timeCreated: 1000000, timeUpdated: 2000000),
        ])
        let provider = OpenCodeProvider(dbPath: dbPath)
        let files = try provider.listSessionFiles()

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].fragment, "ses_abc123")
        XCTAssertTrue(files[0].path.contains("opencode.db"))
    }

    func testListSessionFilesSortedByDateDesc() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_old", directory: "/tmp/a", timeCreated: 1000000, timeUpdated: 1000000),
            TestSession(id: "ses_new", directory: "/tmp/b", timeCreated: 2000000, timeUpdated: 3000000),
        ])
        let provider = OpenCodeProvider(dbPath: dbPath)
        let files = try provider.listSessionFiles()

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].fragment, "ses_new")
        XCTAssertEqual(files[1].fragment, "ses_old")
    }

    func testListSessionFilesWithDatesReturnsTuples() throws {
        let timeMs: Int64 = 1_710_000_000_000 // ~Mar 2024
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_1", directory: "/tmp/p", timeCreated: timeMs, timeUpdated: timeMs),
        ])
        let provider = OpenCodeProvider(dbPath: dbPath)
        let tuples = try provider.listSessionFilesWithDates()

        XCTAssertEqual(tuples.count, 1)
        XCTAssertEqual(tuples[0].url.fragment, "ses_1")
        let expected = Date(timeIntervalSince1970: Double(timeMs) / 1000.0)
        XCTAssertEqual(tuples[0].modDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testListSessionFilesWithDatesSortedDescending() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_old", directory: "/tmp/a", timeCreated: 1000000, timeUpdated: 1000000),
            TestSession(id: "ses_new", directory: "/tmp/b", timeCreated: 2000000, timeUpdated: 5000000),
        ])
        let provider = OpenCodeProvider(dbPath: dbPath)
        let tuples = try provider.listSessionFilesWithDates()

        XCTAssertEqual(tuples.count, 2)
        XCTAssertTrue(tuples[0].modDate >= tuples[1].modDate)
    }

    func testListSessionFilesEpochToDateConversion() throws {
        let epochMs: Int64 = 1_773_239_310_092 // 2026-03-09 approx
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_epoch", directory: "/tmp", timeCreated: epochMs, timeUpdated: epochMs),
        ])
        let provider = OpenCodeProvider(dbPath: dbPath)
        let tuples = try provider.listSessionFilesWithDates()

        let date = tuples[0].modDate
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        XCTAssertEqual(year, 2026)
    }

    // MARK: - Scanning

    func testScanSessionReturnsSummary() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_scan1", directory: "/Users/me/my-project", timeCreated: 1_700_000_000_000, timeUpdated: 1_700_001_000_000),
        ], messages: [
            TestMessage(id: "msg_1", sessionId: "ses_scan1", role: "user", modelID: nil, timeCreated: 1_700_000_000_100),
            TestMessage(id: "msg_2", sessionId: "ses_scan1", role: "assistant", modelID: "claude-3.5-sonnet", timeCreated: 1_700_000_000_200),
        ], parts: [
            TestPart(id: "prt_1", messageId: "msg_1", sessionId: "ses_scan1", type: "text", text: "Fix the bug", timeCreated: 1_700_000_000_100),
            TestPart(id: "prt_2", messageId: "msg_2", sessionId: "ses_scan1", type: "text", text: "On it!", timeCreated: 1_700_000_000_200),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let url = makeVirtualURL(dbPath: dbPath, sessionId: "ses_scan1")
        let summary = provider.scanSession(at: url)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.id, "ses_scan1")
        XCTAssertEqual(summary?.agent, .opencode)
    }

    func testScanSessionReturnsNilForUnknownId() throws {
        try makeTestDB(at: dbPath)
        let provider = OpenCodeProvider(dbPath: dbPath)
        let url = makeVirtualURL(dbPath: dbPath, sessionId: "ses_nonexistent")
        XCTAssertNil(provider.scanSession(at: url))
    }

    func testScanSessionReturnsNilForInvalidURL() throws {
        try makeTestDB(at: dbPath)
        let provider = OpenCodeProvider(dbPath: dbPath)
        // URL without fragment
        XCTAssertNil(provider.scanSession(at: dbPath))
    }

    func testScanSessionExtractsModel() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_m", directory: "/tmp/p", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_a", sessionId: "ses_m", role: "assistant", modelID: "gpt-5.4", timeCreated: 1500),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let summary = provider.scanSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_m"))
        XCTAssertEqual(summary?.model, "gpt-5.4")
    }

    func testScanSessionExtractsBranch() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_br", directory: "/tmp/p", timeCreated: 1000, timeUpdated: 2000, workspaceId: "ws_1"),
        ], workspaces: [
            TestWorkspace(id: "ws_1", branch: "feat/login", projectId: "proj_1"),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let summary = provider.scanSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_br"))
        XCTAssertEqual(summary?.gitBranch, "feat/login")
    }

    func testScanSessionExtractsProjectName() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_pn", directory: "/Users/me/code/awesome-app", timeCreated: 1000, timeUpdated: 2000),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let summary = provider.scanSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_pn"))
        XCTAssertEqual(summary?.projectName, "awesome-app")
    }

    func testScanSessionExtractsFirstUserMessage() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_um", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_u1", sessionId: "ses_um", role: "user", modelID: nil, timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_u1", messageId: "msg_u1", sessionId: "ses_um", type: "text", text: "Hello world", timeCreated: 1100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let summary = provider.scanSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_um"))
        XCTAssertEqual(summary?.firstUserMessage, "Hello world")
    }

    func testScanSessionZeroTurnCount() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_tc", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_1", sessionId: "ses_tc", role: "user", modelID: nil, timeCreated: 1100),
            TestMessage(id: "msg_2", sessionId: "ses_tc", role: "assistant", modelID: "gpt-5", timeCreated: 1200),
        ], parts: [
            TestPart(id: "prt_1", messageId: "msg_1", sessionId: "ses_tc", type: "text", text: "Hi", timeCreated: 1100),
            TestPart(id: "prt_2", messageId: "msg_2", sessionId: "ses_tc", type: "text", text: "Hey", timeCreated: 1200),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let summary = provider.scanSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_tc"))
        XCTAssertEqual(summary?.turnCount, 0)
    }

    // MARK: - Full Parsing

    func testParseSessionMetadata() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_meta", directory: "/Users/me/myapp", timeCreated: 1_700_000_000_000, timeUpdated: 1_700_001_000_000, workspaceId: "ws_m"),
        ], workspaces: [
            TestWorkspace(id: "ws_m", branch: "main", projectId: "proj_m"),
        ], messages: [
            TestMessage(id: "msg_m1", sessionId: "ses_meta", role: "assistant", modelID: "claude-3.5-sonnet", timeCreated: 1_700_000_000_100),
        ], parts: [
            TestPart(id: "prt_m1", messageId: "msg_m1", sessionId: "ses_meta", type: "text", text: "Hello", timeCreated: 1_700_000_000_100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_meta"))

        XCTAssertEqual(session.metadata.sessionId, "ses_meta")
        XCTAssertEqual(session.metadata.agent, .opencode)
        XCTAssertEqual(session.metadata.model, "claude-3.5-sonnet")
        XCTAssertEqual(session.metadata.projectName, "myapp")
        XCTAssertEqual(session.metadata.projectPath, "/Users/me/myapp")
        XCTAssertEqual(session.metadata.gitBranch, "main")
    }

    func testParseSessionUserTurn() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_ut", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_u", sessionId: "ses_ut", role: "user", modelID: nil, timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_u", messageId: "msg_u", sessionId: "ses_ut", type: "text", text: "Fix the login bug", timeCreated: 1100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_ut"))

        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.turns[0].role, .user)
        guard case .text(let text) = session.turns[0].content.first else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(text, "Fix the login bug")
    }

    func testParseSessionAssistantTurn() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_at", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_a", sessionId: "ses_at", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_a", messageId: "msg_a", sessionId: "ses_at", type: "text", text: "I'll fix that for you.", timeCreated: 1100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_at"))

        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.turns[0].role, .assistant)
        guard case .text(let text) = session.turns[0].content.first else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(text, "I'll fix that for you.")
    }

    func testParseSessionToolInvocationResultState() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_tool", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_t", sessionId: "ses_tool", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_t", messageId: "msg_t", sessionId: "ses_tool",
                     type: "tool-invocation",
                     toolInvocation: TestToolInvocation(
                        toolName: "read_file", toolCallId: "call_1",
                        args: ["path": "/tmp/file.txt"],
                        state: "result", result: "file contents here"),
                     timeCreated: 1100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_tool"))

        // tool-invocation with result → toolUse turn + toolResult turn
        XCTAssertEqual(session.turns.count, 2)
        XCTAssertEqual(session.turns[0].role, .assistant)
        XCTAssertEqual(session.turns[1].role, .tool)

        guard case .toolUse(let toolUse) = session.turns[0].content.first else {
            return XCTFail("Expected toolUse")
        }
        XCTAssertEqual(toolUse.name, "read_file")
        XCTAssertEqual(toolUse.id, "call_1")

        guard case .toolResult(let result) = session.turns[1].content.first else {
            return XCTFail("Expected toolResult")
        }
        XCTAssertEqual(result.toolUseId, "call_1")
        XCTAssertEqual(result.output, "file contents here")
    }

    func testParseSessionToolInvocationErrorState() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_err", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_e", sessionId: "ses_err", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_e", messageId: "msg_e", sessionId: "ses_err",
                     type: "tool-invocation",
                     toolInvocation: TestToolInvocation(
                        toolName: "exec_cmd", toolCallId: "call_err",
                        args: ["cmd": "rm -rf /"],
                        state: "error", result: "Permission denied"),
                     timeCreated: 1100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_err"))

        XCTAssertEqual(session.turns.count, 2)
        guard case .toolResult(let result) = session.turns[1].content.first else {
            return XCTFail("Expected toolResult")
        }
        XCTAssertEqual(result.output, "Permission denied")
    }

    func testParseSessionToolInvocationCallState() throws {
        // "call" state = pending, no result yet → only toolUse, no toolResult
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_call", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_c", sessionId: "ses_call", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_c", messageId: "msg_c", sessionId: "ses_call",
                     type: "tool-invocation",
                     toolInvocation: TestToolInvocation(
                        toolName: "read_file", toolCallId: "call_pend",
                        args: ["path": "/tmp/f.txt"],
                        state: "call", result: nil),
                     timeCreated: 1100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_call"))

        // Only toolUse turn, no toolResult for pending calls
        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.turns[0].role, .assistant)
        guard case .toolUse(let toolUse) = session.turns[0].content.first else {
            return XCTFail("Expected toolUse")
        }
        XCTAssertEqual(toolUse.name, "read_file")
    }

    func testParseSessionSkipsReasoning() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_reas", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_r", sessionId: "ses_reas", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_r1", messageId: "msg_r", sessionId: "ses_reas", type: "reasoning", text: "Let me think...", timeCreated: 1100),
            TestPart(id: "prt_r2", messageId: "msg_r", sessionId: "ses_reas", type: "text", text: "Here's the answer.", timeCreated: 1200),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_reas"))

        XCTAssertEqual(session.turns.count, 1)
        guard case .text(let text) = session.turns[0].content.first else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(text, "Here's the answer.")
    }

    func testParseSessionSkipsStepStartFinish() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_step", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_s", sessionId: "ses_step", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_s1", messageId: "msg_s", sessionId: "ses_step", type: "step-start", timeCreated: 1100),
            TestPart(id: "prt_s2", messageId: "msg_s", sessionId: "ses_step", type: "text", text: "Done", timeCreated: 1200),
            TestPart(id: "prt_s3", messageId: "msg_s", sessionId: "ses_step", type: "step-finish", timeCreated: 1300),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_step"))

        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.turns[0].role, .assistant)
    }

    func testParseSessionTimestampConversion() throws {
        let timeMs: Int64 = 1_700_000_000_000
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_ts", directory: "/tmp", timeCreated: timeMs, timeUpdated: timeMs + 60_000),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_ts"))

        let expectedStart = Date(timeIntervalSince1970: Double(timeMs) / 1000.0)
        let expectedEnd = Date(timeIntervalSince1970: Double(timeMs + 60_000) / 1000.0)
        XCTAssertEqual(session.metadata.startedAt.timeIntervalSince1970, expectedStart.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(session.metadata.endedAt!.timeIntervalSince1970, expectedEnd.timeIntervalSince1970, accuracy: 1)
    }

    func testParseSessionOutputTruncation() throws {
        let longResult = String(repeating: "x", count: 10_000)
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_trunc", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_tr", sessionId: "ses_trunc", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_tr", messageId: "msg_tr", sessionId: "ses_trunc",
                     type: "tool-invocation",
                     toolInvocation: TestToolInvocation(
                        toolName: "exec_cmd", toolCallId: "call_long",
                        args: [:], state: "result", result: longResult),
                     timeCreated: 1100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_trunc"))

        guard case .toolResult(let result) = session.turns[1].content.first else {
            return XCTFail("Expected toolResult")
        }
        XCTAssertEqual(result.output.count, 5000)
    }

    func testParseSessionMultipleToolCalls() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_mt", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_mt", sessionId: "ses_mt", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_mt1", messageId: "msg_mt", sessionId: "ses_mt",
                     type: "tool-invocation",
                     toolInvocation: TestToolInvocation(
                        toolName: "read_file", toolCallId: "call_a",
                        args: ["path": "/a.txt"], state: "result", result: "content A"),
                     timeCreated: 1100),
            TestPart(id: "prt_mt2", messageId: "msg_mt", sessionId: "ses_mt",
                     type: "tool-invocation",
                     toolInvocation: TestToolInvocation(
                        toolName: "read_file", toolCallId: "call_b",
                        args: ["path": "/b.txt"], state: "result", result: "content B"),
                     timeCreated: 1200),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_mt"))

        // 2 tool invocations × 2 turns each = 4 turns
        XCTAssertEqual(session.turns.count, 4)
        XCTAssertEqual(session.turns[0].role, .assistant)
        XCTAssertEqual(session.turns[1].role, .tool)
        XCTAssertEqual(session.turns[2].role, .assistant)
        XCTAssertEqual(session.turns[3].role, .tool)

        guard case .toolUse(let tu1) = session.turns[0].content.first,
              case .toolResult(let tr1) = session.turns[1].content.first,
              case .toolUse(let tu2) = session.turns[2].content.first,
              case .toolResult(let tr2) = session.turns[3].content.first else {
            return XCTFail("Expected tool use/result pairs")
        }
        XCTAssertEqual(tu1.id, "call_a")
        XCTAssertEqual(tr1.toolUseId, "call_a")
        XCTAssertEqual(tu2.id, "call_b")
        XCTAssertEqual(tr2.toolUseId, "call_b")
    }

    func testParseSessionEmptySession() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_empty", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_empty"))

        XCTAssertTrue(session.turns.isEmpty)
        XCTAssertEqual(session.metadata.sessionId, "ses_empty")
        XCTAssertEqual(session.metadata.agent, .opencode)
    }

    func testParseSessionMessageOrdering() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_ord", directory: "/tmp", timeCreated: 1000, timeUpdated: 3000),
        ], messages: [
            TestMessage(id: "msg_o1", sessionId: "ses_ord", role: "user", modelID: nil, timeCreated: 1100),
            TestMessage(id: "msg_o2", sessionId: "ses_ord", role: "assistant", modelID: "gpt-5", timeCreated: 1200),
            TestMessage(id: "msg_o3", sessionId: "ses_ord", role: "user", modelID: nil, timeCreated: 1300),
        ], parts: [
            TestPart(id: "prt_o1", messageId: "msg_o1", sessionId: "ses_ord", type: "text", text: "First", timeCreated: 1100),
            TestPart(id: "prt_o2", messageId: "msg_o2", sessionId: "ses_ord", type: "text", text: "Second", timeCreated: 1200),
            TestPart(id: "prt_o3", messageId: "msg_o3", sessionId: "ses_ord", type: "text", text: "Third", timeCreated: 1300),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_ord"))

        XCTAssertEqual(session.turns.count, 3)
        XCTAssertEqual(session.turns[0].role, .user)
        XCTAssertEqual(session.turns[1].role, .assistant)
        XCTAssertEqual(session.turns[2].role, .user)

        guard case .text(let t1) = session.turns[0].content.first,
              case .text(let t2) = session.turns[1].content.first,
              case .text(let t3) = session.turns[2].content.first else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(t1, "First")
        XCTAssertEqual(t2, "Second")
        XCTAssertEqual(t3, "Third")
    }

    func testParseSessionSkipsEmptyTextParts() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_et", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_et", sessionId: "ses_et", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_et1", messageId: "msg_et", sessionId: "ses_et", type: "text", text: "", timeCreated: 1100),
            TestPart(id: "prt_et2", messageId: "msg_et", sessionId: "ses_et", type: "text", text: "Real content", timeCreated: 1200),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_et"))

        XCTAssertEqual(session.turns.count, 1)
        guard case .text(let text) = session.turns[0].content.first else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(text, "Real content")
    }

    func testParseSessionNonexistentSessionThrows() throws {
        try makeTestDB(at: dbPath)
        let provider = OpenCodeProvider(dbPath: dbPath)
        XCTAssertThrowsError(try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "nope")))
    }

    func testParseSessionInvalidURLThrows() throws {
        let provider = OpenCodeProvider(dbPath: dbPath)
        // URL without fragment
        XCTAssertThrowsError(try provider.parseSession(at: dbPath))
    }

    func testParseSessionToolInvocationArgs() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_args", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_args", sessionId: "ses_args", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_args", messageId: "msg_args", sessionId: "ses_args",
                     type: "tool-invocation",
                     toolInvocation: TestToolInvocation(
                        toolName: "write_file", toolCallId: "call_w",
                        args: ["path": "/tmp/out.txt", "content": "hello"],
                        state: "result", result: "ok"),
                     timeCreated: 1100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_args"))

        guard case .toolUse(let toolUse) = session.turns[0].content.first else {
            return XCTFail("Expected toolUse")
        }
        XCTAssertNotNil(toolUse.input)
        // Args should be JSON containing both keys
        XCTAssertTrue(toolUse.input!.contains("path"))
        XCTAssertTrue(toolUse.input!.contains("content"))
    }

    func testParseSessionSkipsSourceUrlParts() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_src", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_src", sessionId: "ses_src", role: "assistant", modelID: "gpt-5", timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_src", messageId: "msg_src", sessionId: "ses_src",
                     type: "source-url", timeCreated: 1100),
            TestPart(id: "prt_txt", messageId: "msg_src", sessionId: "ses_src",
                     type: "text", text: "Here", timeCreated: 1200),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_src"))

        XCTAssertEqual(session.turns.count, 1)
        guard case .text(let text) = session.turns[0].content.first else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(text, "Here")
    }

    func testParseSessionNoBranchWithoutWorkspace() throws {
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_nows", directory: "/tmp/proj", timeCreated: 1000, timeUpdated: 2000),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let session = try provider.parseSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_nows"))

        XCTAssertNil(session.metadata.gitBranch)
    }

    func testScanSessionFirstUserMessageTruncated() throws {
        let longMessage = String(repeating: "a", count: 500)
        try makeTestDB(at: dbPath, sessions: [
            TestSession(id: "ses_long", directory: "/tmp", timeCreated: 1000, timeUpdated: 2000),
        ], messages: [
            TestMessage(id: "msg_long", sessionId: "ses_long", role: "user", modelID: nil, timeCreated: 1100),
        ], parts: [
            TestPart(id: "prt_long", messageId: "msg_long", sessionId: "ses_long", type: "text", text: longMessage, timeCreated: 1100),
        ])

        let provider = OpenCodeProvider(dbPath: dbPath)
        let summary = provider.scanSession(at: makeVirtualURL(dbPath: dbPath, sessionId: "ses_long"))
        XCTAssertEqual(summary?.firstUserMessage?.count, 200)
    }

    // MARK: - Test Helpers

    private struct TestSession {
        let id: String
        let directory: String
        let timeCreated: Int64
        let timeUpdated: Int64
        var workspaceId: String? = nil
        var projectId: String = "proj_default"
    }

    private struct TestMessage {
        let id: String
        let sessionId: String
        let role: String
        let modelID: String?
        let timeCreated: Int64
    }

    private struct TestPart {
        let id: String
        let messageId: String
        let sessionId: String
        var type: String = "text"
        var text: String? = nil
        var toolInvocation: TestToolInvocation? = nil
        let timeCreated: Int64
    }

    private struct TestToolInvocation {
        let toolName: String
        let toolCallId: String
        let args: [String: Any]
        let state: String
        let result: String?
    }

    private struct TestWorkspace {
        let id: String
        let branch: String
        let projectId: String
    }

    private func makeVirtualURL(dbPath: URL, sessionId: String) -> URL {
        var components = URLComponents()
        components.scheme = "file"
        components.path = dbPath.path
        components.fragment = sessionId
        return components.url!
    }

    private func makeTestDB(
        at path: URL,
        sessions: [TestSession] = [],
        workspaces: [TestWorkspace] = [],
        messages: [TestMessage] = [],
        parts: [TestPart] = []
    ) throws {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create test DB"])
        }
        defer { sqlite3_close(db) }

        let schema = """
        CREATE TABLE IF NOT EXISTS session (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL DEFAULT 'proj_default',
            slug TEXT NOT NULL DEFAULT '',
            directory TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            version TEXT NOT NULL DEFAULT '1',
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL,
            workspace_id TEXT
        );
        CREATE TABLE IF NOT EXISTS message (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL,
            data TEXT NOT NULL,
            FOREIGN KEY (session_id) REFERENCES session(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS part (
            id TEXT PRIMARY KEY,
            message_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL,
            data TEXT NOT NULL,
            FOREIGN KEY (message_id) REFERENCES message(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace (
            id TEXT PRIMARY KEY,
            branch TEXT,
            project_id TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'default'
        );
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, schema, nil, nil, &errMsg)
        if let errMsg {
            let msg = String(cString: errMsg)
            sqlite3_free(errMsg)
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        for s in sessions {
            let sql = "INSERT INTO session (id, project_id, slug, directory, title, version, time_created, time_updated, workspace_id) VALUES (?, ?, '', ?, '', '1', ?, ?, ?)"
            try execInsert(db: db!, sql: sql, params: [
                s.id, s.projectId, s.directory,
                String(s.timeCreated), String(s.timeUpdated),
                s.workspaceId ?? ""
            ])
        }

        for w in workspaces {
            let sql = "INSERT INTO workspace (id, branch, project_id, type) VALUES (?, ?, ?, 'default')"
            try execInsert(db: db!, sql: sql, params: [w.id, w.branch, w.projectId])
        }

        for m in messages {
            var data: [String: Any] = ["role": m.role, "time": ["created": m.timeCreated]]
            if let model = m.modelID {
                data["modelID"] = model
            }
            if m.role == "user" {
                // User messages have model nested
                if let model = m.modelID {
                    data["model"] = ["modelID": model]
                }
            }
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let jsonStr = String(data: jsonData, encoding: .utf8)!

            let sql = "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?)"
            try execInsert(db: db!, sql: sql, params: [m.id, m.sessionId, String(m.timeCreated), String(m.timeCreated), jsonStr])
        }

        for p in parts {
            var data: [String: Any] = ["type": p.type]
            if let text = p.text {
                data["text"] = text
            }
            if let inv = p.toolInvocation {
                var invDict: [String: Any] = [
                    "toolName": inv.toolName,
                    "toolCallId": inv.toolCallId,
                    "state": inv.state,
                    "args": inv.args,
                ]
                if let result = inv.result {
                    invDict["result"] = result
                }
                data["toolInvocation"] = invDict
            }
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let jsonStr = String(data: jsonData, encoding: .utf8)!

            let sql = "INSERT INTO part (id, message_id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?, ?)"
            try execInsert(db: db!, sql: sql, params: [p.id, p.messageId, p.sessionId, String(p.timeCreated), String(p.timeCreated), jsonStr])
        }
    }

    private func execInsert(db: OpaquePointer, sql: String, params: [String]) throws {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (param as NSString).utf8String, -1, nil)
        }

        let stepRc = sqlite3_step(stmt)
        guard stepRc == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "test", code: 4, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
