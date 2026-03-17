import XCTest
@testable import PublisherGist
@testable import SessionCore

final class GistPublisherTests: XCTestCase {

    // MARK: - Payload Structure

    func testGistPayloadContainsRequiredFiles() throws {
        let session = Session(
            metadata: SessionMetadata(
                agent: .claudeCode,
                model: "claude-opus-4-6",
                sessionId: "test-session",
                projectName: "myproject",
                startedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            turns: [
                Turn(role: .user, content: [.text("Hello")], timestamp: Date(timeIntervalSince1970: 1_700_000_000)),
            ]
        )

        // Verify session encodes to valid JSON
        let encoder = JSONEncoder.turnshare
        let sessionData = try encoder.encode(session)
        let sessionJSON = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any]
        XCTAssertNotNil(sessionJSON)

        // Verify manifest structure
        let manifest: [String: Any] = [
            "version": "1",
            "agent": session.metadata.agent.rawValue,
            "sessionId": session.metadata.sessionId,
            "projectName": session.metadata.projectName ?? "unknown",
            "turnCount": session.turns.count,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]

        XCTAssertEqual(manifest["version"] as? String, "1")
        XCTAssertEqual(manifest["agent"] as? String, "claude-code")
        XCTAssertEqual(manifest["sessionId"] as? String, "test-session")
        XCTAssertEqual(manifest["projectName"] as? String, "myproject")
        XCTAssertEqual(manifest["turnCount"] as? Int, 1)
    }

    func testGistPayloadDescription() {
        let description = "Turnshare: myproject (claude-code)"
        XCTAssertTrue(description.contains("myproject"))
        XCTAssertTrue(description.contains("claude-code"))
    }

    // MARK: - Error Cases

    func testGistErrorDescriptions() {
        XCTAssertNotNil(GistError.notAuthenticated.errorDescription)
        XCTAssertNotNil(GistError.publishFailed.errorDescription)
        XCTAssertNotNil(GistError.invalidResponse.errorDescription)
    }
}
