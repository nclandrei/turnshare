import Foundation
import SessionCore

public struct ClaudeProvider {
    private let claudeDir: URL

    public init(claudeDir: URL? = nil) {
        self.claudeDir = claudeDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
    }

    /// Scan all Claude Code projects and return session summaries, sorted by most recent first.
    public func listSessions(limit: Int = 50) throws -> [SessionSummary] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeDir.path) else { return [] }

        let projectDirs = try fm.contentsOfDirectory(at: claudeDir, includingPropertiesForKeys: nil)
        var summaries: [SessionSummary] = []

        for projectDir in projectDirs {
            guard projectDir.hasDirectoryPath else { continue }

            let files = try fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey])
            let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }

            for file in jsonlFiles {
                if let summary = try? scanSessionFile(file, projectDir: projectDir) {
                    summaries.append(summary)
                }
            }
        }

        return summaries
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// Parse a full session from a JSONL file into the normalized Turnshare format.
    public func parseSession(at path: URL) throws -> Session {
        let data = try Data(contentsOf: path)
        let lines = data.split(separator: UInt8(ascii: "\n"))

        var turns: [Turn] = []
        var metadata = PartialMetadata()

        for line in lines {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                continue
            }

            guard let type = entry["type"] as? String else { continue }

            switch type {
            case "user":
                if let turn = parseUserTurn(entry) {
                    turns.append(turn)
                    if metadata.cwd == nil {
                        metadata.cwd = entry["cwd"] as? String
                        metadata.gitBranch = entry["gitBranch"] as? String
                        metadata.sessionId = entry["sessionId"] as? String
                    }
                }

            case "assistant":
                if let turn = parseAssistantTurn(entry) {
                    turns.append(turn)
                    if metadata.model == nil, let msg = entry["message"] as? [String: Any] {
                        metadata.model = msg["model"] as? String
                    }
                }

            case "tool_result":
                if let turn = parseToolResultTurn(entry) {
                    turns.append(turn)
                }

            default:
                break
            }
        }

        let sessionId = metadata.sessionId ?? path.deletingPathExtension().lastPathComponent
        let projectName = extractProjectName(from: metadata.cwd)

        let sessionMetadata = SessionMetadata(
            agent: .claudeCode,
            model: metadata.model,
            sessionId: sessionId,
            projectPath: metadata.cwd,
            projectName: projectName,
            gitBranch: metadata.gitBranch,
            startedAt: turns.first?.timestamp ?? Date(),
            endedAt: turns.last?.timestamp
        )

        return Session(metadata: sessionMetadata, turns: turns)
    }

    // MARK: - Private

    private struct PartialMetadata {
        var sessionId: String?
        var cwd: String?
        var gitBranch: String?
        var model: String?
    }

    private func scanSessionFile(_ file: URL, projectDir: URL) throws -> SessionSummary? {
        let data = try Data(contentsOf: file)
        let lines = data.split(separator: UInt8(ascii: "\n"))

        var sessionId: String?
        var cwd: String?
        var gitBranch: String?
        var model: String?
        var firstUserMessage: String?
        var startedAt: Date?
        var turnCount = 0

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in lines {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = entry["type"] as? String else { continue }

            if type == "user" || type == "assistant" || type == "tool_result" {
                turnCount += 1
            }

            if type == "user" && firstUserMessage == nil {
                if let msg = entry["message"] as? [String: Any],
                   let content = msg["content"] as? String {
                    firstUserMessage = String(content.prefix(200))
                }
                if sessionId == nil {
                    sessionId = entry["sessionId"] as? String
                    cwd = entry["cwd"] as? String
                    gitBranch = entry["gitBranch"] as? String
                }
                if startedAt == nil, let ts = entry["timestamp"] as? String {
                    startedAt = dateFormatter.date(from: ts)
                }
            }

            if type == "assistant" && model == nil {
                if let msg = entry["message"] as? [String: Any] {
                    model = msg["model"] as? String
                }
            }
        }

        guard let sid = sessionId, let start = startedAt else { return nil }

        return SessionSummary(
            id: sid,
            agent: .claudeCode,
            model: model,
            projectName: extractProjectName(from: cwd),
            gitBranch: gitBranch,
            startedAt: start,
            firstUserMessage: firstUserMessage,
            turnCount: turnCount,
            filePath: file
        )
    }

    private func parseUserTurn(_ entry: [String: Any]) -> Turn? {
        guard let msg = entry["message"] as? [String: Any],
              let content = msg["content"] as? String,
              let timestamp = parseTimestamp(entry["timestamp"]) else { return nil }

        return Turn(
            role: .user,
            content: [.text(content)],
            timestamp: timestamp
        )
    }

    private func parseAssistantTurn(_ entry: [String: Any]) -> Turn? {
        guard let msg = entry["message"] as? [String: Any],
              let contentArray = msg["content"] as? [[String: Any]],
              let timestamp = parseTimestamp(entry["timestamp"]) else { return nil }

        var blocks: [ContentBlock] = []

        for item in contentArray {
            guard let type = item["type"] as? String else { continue }

            switch type {
            case "text":
                if let text = item["text"] as? String, !text.isEmpty {
                    blocks.append(.text(text))
                }

            case "tool_use":
                if let name = item["name"] as? String, let id = item["id"] as? String {
                    var inputJSON: String?
                    if let input = item["input"] {
                        if let inputData = try? JSONSerialization.data(withJSONObject: input),
                           let inputStr = String(data: inputData, encoding: .utf8) {
                            inputJSON = inputStr
                        }
                    }
                    blocks.append(.toolUse(ToolUse(name: name, id: id, input: inputJSON)))
                }

            case "thinking":
                // Skip thinking blocks for shared sessions
                break

            default:
                break
            }
        }

        guard !blocks.isEmpty else { return nil }

        return Turn(
            role: .assistant,
            content: blocks,
            timestamp: timestamp
        )
    }

    private func parseToolResultTurn(_ entry: [String: Any]) -> Turn? {
        guard let timestamp = parseTimestamp(entry["timestamp"]) else { return nil }

        let toolUseId = (entry["toolUseID"] as? String) ?? "unknown"
        let output: String

        if let result = entry["result"] as? String {
            output = String(result.prefix(5000))
        } else if let result = entry["result"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: result),
                  let str = String(data: data, encoding: .utf8) {
            output = String(str.prefix(5000))
        } else {
            output = ""
        }

        return Turn(
            role: .tool,
            content: [.toolResult(ToolResult(toolUseId: toolUseId, output: output))],
            timestamp: timestamp
        )
    }

    private func parseTimestamp(_ value: Any?) -> Date? {
        guard let str = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str)
    }

    private func extractProjectName(from path: String?) -> String? {
        guard let path = path else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
