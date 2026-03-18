import Foundation
import SessionCore

public struct CodexProvider {
    private let codexDir: URL

    public init(codexDir: URL? = nil) {
        self.codexDir = codexDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
    }

    /// Return all JSONL session files with modification dates, sorted most-recent first.
    /// Searches both `sessions/` (nested year/month/day) and `archived_sessions/` (flat).
    public func listSessionFilesWithDates() throws -> [(url: URL, modDate: Date)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: codexDir.path) else { return [] }

        var files: [(url: URL, modDate: Date)] = []

        // Active sessions: sessions/YYYY/MM/DD/*.jsonl
        let sessionsDir = codexDir.appendingPathComponent("sessions")
        if fm.fileExists(atPath: sessionsDir.path) {
            collectJSONLFiles(in: sessionsDir, into: &files, fm: fm)
        }

        // Archived sessions: archived_sessions/*.jsonl
        let archivedDir = codexDir.appendingPathComponent("archived_sessions")
        if fm.fileExists(atPath: archivedDir.path) {
            collectJSONLFiles(in: archivedDir, into: &files, fm: fm)
        }

        return files.sorted { $0.modDate > $1.modDate }
    }

    /// Return all JSONL session file URLs sorted by modification date (most recent first).
    public func listSessionFiles() throws -> [URL] {
        try listSessionFilesWithDates().map(\.url)
    }

    /// Scan a single JSONL file and return its summary. Returns nil if the file can't be parsed.
    public func scanSession(at file: URL) -> SessionSummary? {
        try? scanSessionFile(file)
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
            case "session_meta":
                if let payload = entry["payload"] as? [String: Any] {
                    if metadata.sessionId == nil {
                        metadata.sessionId = payload["id"] as? String
                        metadata.cwd = payload["cwd"] as? String
                        metadata.timestamp = payload["timestamp"] as? String
                    }
                }

            case "turn_context":
                if let payload = entry["payload"] as? [String: Any] {
                    if metadata.model == nil {
                        metadata.model = payload["model"] as? String
                    }
                }

            case "response_item":
                if let payload = entry["payload"] as? [String: Any],
                   let timestamp = parseTimestamp(entry["timestamp"]) {
                    if let turn = parseResponseItem(payload, timestamp: timestamp) {
                        turns.append(turn)
                    }
                }

            default:
                break
            }
        }

        let sessionId = metadata.sessionId ?? path.deletingPathExtension().lastPathComponent
        let projectName = extractProjectName(from: metadata.cwd)

        let startedAt: Date
        if let ts = metadata.timestamp {
            startedAt = parseTimestamp(ts) ?? turns.first?.timestamp ?? Date()
        } else {
            startedAt = turns.first?.timestamp ?? Date()
        }

        let sessionMetadata = SessionMetadata(
            agent: .codex,
            model: metadata.model,
            sessionId: sessionId,
            projectPath: metadata.cwd,
            projectName: projectName,
            startedAt: startedAt,
            endedAt: turns.last?.timestamp
        )

        return Session(metadata: sessionMetadata, turns: turns)
    }

    // MARK: - Private

    private struct PartialMetadata {
        var sessionId: String?
        var cwd: String?
        var model: String?
        var timestamp: String?
    }

    /// Recursively collect .jsonl files from a directory tree.
    private func collectJSONLFiles(
        in dir: URL,
        into files: inout [(url: URL, modDate: Date)],
        fm: FileManager
    ) {
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }

            let modDate = values.contentModificationDate ?? .distantPast
            files.append((fileURL, modDate))
        }
    }

    // Codex session_meta embeds the full system prompt (~16KB), so we need
    // a larger buffer than Claude sessions to reach the first user message.
    private static let scanHeaderSize = 65_536 // 64KB

    private func scanSessionFile(_ file: URL) throws -> SessionSummary? {
        let handle = try FileHandle(forReadingFrom: file)
        let header = handle.readData(ofLength: Self.scanHeaderSize)
        try handle.close()

        let lines = header.split(separator: UInt8(ascii: "\n"))

        var sessionId: String?
        var cwd: String?
        var model: String?
        var firstUserMessage: String?
        var startedAt: Date?

        for line in lines {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = entry["type"] as? String else { continue }

            switch type {
            case "session_meta":
                if let payload = entry["payload"] as? [String: Any], sessionId == nil {
                    sessionId = payload["id"] as? String
                    cwd = payload["cwd"] as? String
                    if let ts = payload["timestamp"] as? String {
                        startedAt = parseTimestamp(ts)
                    }
                }

            case "turn_context":
                if let payload = entry["payload"] as? [String: Any], model == nil {
                    model = payload["model"] as? String
                }

            case "response_item":
                if let payload = entry["payload"] as? [String: Any] {
                    let itemType = payload["type"] as? String
                    let role = payload["role"] as? String

                    // Extract first user message
                    if firstUserMessage == nil && itemType == "message" && role == "user" {
                        if let text = extractUserText(from: payload) {
                            firstUserMessage = String(text.prefix(200))
                        }
                    }
                }

            default:
                break
            }

            // Early exit once all metadata is collected
            if sessionId != nil && model != nil && firstUserMessage != nil && startedAt != nil {
                break
            }
        }

        guard let sid = sessionId, let start = startedAt else { return nil }

        return SessionSummary(
            id: sid,
            agent: .codex,
            model: model,
            projectName: extractProjectName(from: cwd),
            startedAt: start,
            firstUserMessage: firstUserMessage,
            turnCount: 0,
            filePath: file
        )
    }

    // MARK: - Response Item Parsing

    private func parseResponseItem(_ payload: [String: Any], timestamp: Date) -> Turn? {
        guard let itemType = payload["type"] as? String else { return nil }

        switch itemType {
        case "message":
            return parseMessageItem(payload, timestamp: timestamp)
        case "function_call":
            return parseFunctionCall(payload, timestamp: timestamp)
        case "function_call_output":
            return parseFunctionCallOutput(payload, timestamp: timestamp)
        default:
            return nil
        }
    }

    private func parseMessageItem(_ payload: [String: Any], timestamp: Date) -> Turn? {
        guard let role = payload["role"] as? String else { return nil }

        switch role {
        case "user":
            guard let text = extractUserText(from: payload), !text.isEmpty else { return nil }
            return Turn(role: .user, content: [.text(text)], timestamp: timestamp)

        case "assistant":
            guard let text = extractAssistantText(from: payload), !text.isEmpty else { return nil }
            return Turn(role: .assistant, content: [.text(text)], timestamp: timestamp)

        default:
            // Skip developer/system messages
            return nil
        }
    }

    private func parseFunctionCall(_ payload: [String: Any], timestamp: Date) -> Turn? {
        guard let name = payload["name"] as? String,
              let callId = payload["call_id"] as? String else { return nil }

        let input = payload["arguments"] as? String
        let toolUse = ToolUse(name: name, id: callId, input: input)
        return Turn(role: .assistant, content: [.toolUse(toolUse)], timestamp: timestamp)
    }

    private func parseFunctionCallOutput(_ payload: [String: Any], timestamp: Date) -> Turn? {
        guard let callId = payload["call_id"] as? String else { return nil }

        let output: String
        if let rawOutput = payload["output"] as? String {
            output = String(rawOutput.prefix(5000))
        } else {
            output = ""
        }

        return Turn(
            role: .tool,
            content: [.toolResult(ToolResult(toolUseId: callId, output: output))],
            timestamp: timestamp
        )
    }

    // MARK: - Text Extraction

    /// Extract the meaningful user text from a user message's content array.
    /// Filters out system/environment context blocks and returns actual user input.
    private func extractUserText(from payload: [String: Any]) -> String? {
        guard let content = payload["content"] as? [[String: Any]] else { return nil }

        var texts: [String] = []
        for block in content {
            guard block["type"] as? String == "input_text",
                  let text = block["text"] as? String else { continue }
            // Skip system/developer preambles (AGENTS.md, environment context, permissions, etc.)
            if text.hasPrefix("<permissions") || text.hasPrefix("<environment_context")
                || text.hasPrefix("# AGENTS.md") || text.hasPrefix("Response MUST end") {
                continue
            }
            texts.append(text)
        }

        let combined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    /// Extract text from an assistant message's content array.
    private func extractAssistantText(from payload: [String: Any]) -> String? {
        guard let content = payload["content"] as? [[String: Any]] else { return nil }

        var texts: [String] = []
        for block in content {
            guard block["type"] as? String == "output_text",
                  let text = block["text"] as? String, !text.isEmpty else { continue }
            texts.append(text)
        }

        let combined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    // MARK: - Utilities

    private func parseTimestamp(_ value: Any?) -> Date? {
        guard let str = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }

    private func extractProjectName(from path: String?) -> String? {
        guard let path = path else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
