import XCTest
@testable import SessionCore

final class SessionCoreTests: XCTestCase {

    // MARK: - Session Round-Trip

    func testSessionEncodeDecode() throws {
        let session = Session(
            metadata: SessionMetadata(
                agent: .claudeCode,
                model: "claude-opus-4-6",
                sessionId: "test-123",
                projectPath: "/tmp/project",
                projectName: "project",
                gitBranch: "main",
                startedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            turns: [
                Turn(role: .user, content: [.text("Hello")], timestamp: Date(timeIntervalSince1970: 1_700_000_000)),
                Turn(role: .assistant, content: [.text("Hi")], timestamp: Date(timeIntervalSince1970: 1_700_000_001)),
            ]
        )

        let data = try JSONEncoder.turnshare.encode(session)
        let decoded = try JSONDecoder.turnshare.decode(Session.self, from: data)

        XCTAssertEqual(decoded.metadata.sessionId, "test-123")
        XCTAssertEqual(decoded.metadata.agent, .claudeCode)
        XCTAssertEqual(decoded.metadata.model, "claude-opus-4-6")
        XCTAssertEqual(decoded.metadata.projectName, "project")
        XCTAssertEqual(decoded.metadata.gitBranch, "main")
        XCTAssertEqual(decoded.turns.count, 2)
    }

    // MARK: - Turn Content Blocks

    func testTextBlockRoundTrip() throws {
        let turn = Turn(role: .user, content: [.text("Hello world")], timestamp: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder.turnshare.encode(turn)
        let decoded = try JSONDecoder.turnshare.decode(Turn.self, from: data)

        if case .text(let text) = decoded.content.first {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected text block")
        }
    }

    func testToolUseBlockRoundTrip() throws {
        let toolUse = ToolUse(name: "Read", id: "tu-1", input: "{\"path\":\"/tmp\"}")
        let turn = Turn(role: .assistant, content: [.toolUse(toolUse)], timestamp: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder.turnshare.encode(turn)
        let decoded = try JSONDecoder.turnshare.decode(Turn.self, from: data)

        if case .toolUse(let decoded) = decoded.content.first {
            XCTAssertEqual(decoded.name, "Read")
            XCTAssertEqual(decoded.id, "tu-1")
            XCTAssertEqual(decoded.input, "{\"path\":\"/tmp\"}")
        } else {
            XCTFail("Expected toolUse block")
        }
    }

    func testToolResultBlockRoundTrip() throws {
        let result = ToolResult(toolUseId: "tu-1", name: "Read", output: "file contents")
        let turn = Turn(role: .tool, content: [.toolResult(result)], timestamp: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder.turnshare.encode(turn)
        let decoded = try JSONDecoder.turnshare.decode(Turn.self, from: data)

        if case .toolResult(let decoded) = decoded.content.first {
            XCTAssertEqual(decoded.toolUseId, "tu-1")
            XCTAssertEqual(decoded.output, "file contents")
        } else {
            XCTFail("Expected toolResult block")
        }
    }

    // MARK: - Agent Enum

    func testAgentRawValues() {
        XCTAssertEqual(Agent.claudeCode.rawValue, "claude-code")
        XCTAssertEqual(Agent.codex.rawValue, "codex")
        XCTAssertEqual(Agent.opencode.rawValue, "opencode")
    }

    // MARK: - Role Enum

    func testRoleRawValues() {
        XCTAssertEqual(Role.user.rawValue, "user")
        XCTAssertEqual(Role.assistant.rawValue, "assistant")
        XCTAssertEqual(Role.tool.rawValue, "tool")
    }

    // MARK: - Session ID

    func testSessionIdFromMetadata() {
        let session = Session(
            metadata: SessionMetadata(
                agent: .claudeCode, sessionId: "abc-def",
                startedAt: Date()
            ),
            turns: []
        )
        XCTAssertEqual(session.id, "abc-def")
    }
}
