import Foundation
import SessionCore
import SQLite3

public struct OpenCodeProvider {
    private let dbPath: URL

    public init(dbPath: URL? = nil) {
        self.dbPath = dbPath ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
    }

    /// Return all sessions as virtual URLs with modification dates, sorted most-recent first.
    /// Each URL is `file:///path/to/opencode.db#session_id`.
    public func listSessionFilesWithDates() throws -> [(url: URL, modDate: Date)] {
        guard FileManager.default.fileExists(atPath: dbPath.path) else { return [] }

        let db = try SQLiteDB(path: dbPath.path, readOnly: true)
        defer { db.close() }

        let rows = try db.query(
            "SELECT id, time_updated FROM session ORDER BY time_updated DESC"
        )

        return rows.compactMap { row -> (url: URL, modDate: Date)? in
            guard let id = row["id"], let timeStr = row["time_updated"],
                  let timeMs = Int64(timeStr) else { return nil }
            let url = virtualURL(for: id)
            let date = Date(timeIntervalSince1970: Double(timeMs) / 1000.0)
            return (url, date)
        }
    }

    /// Return all session virtual URLs sorted by modification date (most recent first).
    public func listSessionFiles() throws -> [URL] {
        try listSessionFilesWithDates().map(\.url)
    }

    /// Scan a virtual URL and return its summary. Returns nil if the session can't be found.
    public func scanSession(at file: URL) -> SessionSummary? {
        guard let sessionId = extractSessionId(from: file) else { return nil }
        return try? scanSessionById(sessionId)
    }

    /// Parse a full session from the DB into the normalized Turnshare format.
    public func parseSession(at path: URL) throws -> Session {
        guard let sessionId = extractSessionId(from: path) else {
            throw OpenCodeError.invalidURL(path)
        }
        return try parseSessionById(sessionId)
    }

    // MARK: - Private

    private func virtualURL(for sessionId: String) -> URL {
        var components = URLComponents()
        components.scheme = dbPath.scheme ?? "file"
        components.path = dbPath.path
        components.fragment = sessionId
        return components.url!
    }

    private func extractSessionId(from url: URL) -> String? {
        let fragment = url.fragment
        guard let fragment, !fragment.isEmpty else { return nil }
        return fragment
    }

    private func scanSessionById(_ sessionId: String) throws -> SessionSummary? {
        guard FileManager.default.fileExists(atPath: dbPath.path) else { return nil }

        let db = try SQLiteDB(path: dbPath.path, readOnly: true)
        defer { db.close() }

        // Fetch session row
        let sessionRows = try db.query(
            "SELECT id, directory, time_created, time_updated, workspace_id FROM session WHERE id = ?",
            params: [sessionId]
        )
        guard let sessionRow = sessionRows.first,
              let timeCreatedStr = sessionRow["time_created"],
              let timeCreatedMs = Int64(timeCreatedStr) else { return nil }

        let startedAt = Date(timeIntervalSince1970: Double(timeCreatedMs) / 1000.0)
        let directory = sessionRow["directory"]
        let projectName = extractProjectName(from: directory)
        let workspaceId = sessionRow["workspace_id"]

        // Fetch branch from workspace
        var gitBranch: String?
        if let wsId = workspaceId, !wsId.isEmpty {
            let wsRows = try db.query(
                "SELECT branch FROM workspace WHERE id = ?",
                params: [wsId]
            )
            gitBranch = wsRows.first?["branch"]
        }

        // Fetch first user message and model from messages
        var firstUserMessage: String?
        var model: String?

        let msgRows = try db.query(
            "SELECT data FROM message WHERE session_id = ? ORDER BY time_created ASC LIMIT 10",
            params: [sessionId]
        )

        for msgRow in msgRows {
            guard let dataStr = msgRow["data"],
                  let dataBytes = dataStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: dataBytes) as? [String: Any],
                  let role = json["role"] as? String else { continue }

            if role == "user" && firstUserMessage == nil {
                // Get first text part for this message
                if let msgId = findMessageId(in: msgRows, matching: dataStr, db: db, sessionId: sessionId) {
                    let partRows = try db.query(
                        "SELECT data FROM part WHERE message_id = ? ORDER BY time_created ASC LIMIT 5",
                        params: [msgId]
                    )
                    for partRow in partRows {
                        guard let partDataStr = partRow["data"],
                              let partData = partDataStr.data(using: .utf8),
                              let partJson = try? JSONSerialization.jsonObject(with: partData) as? [String: Any],
                              partJson["type"] as? String == "text",
                              let text = partJson["text"] as? String, !text.isEmpty else { continue }
                        firstUserMessage = String(text.prefix(200))
                        break
                    }
                }
            }

            if role == "assistant" && model == nil {
                // modelID is at top level in assistant messages
                if let m = json["modelID"] as? String {
                    model = m
                }
            }

            if firstUserMessage != nil && model != nil { break }
        }

        return SessionSummary(
            id: sessionId,
            agent: .opencode,
            model: model,
            projectName: projectName,
            gitBranch: gitBranch,
            startedAt: startedAt,
            firstUserMessage: firstUserMessage,
            turnCount: 0,
            filePath: virtualURL(for: sessionId)
        )
    }

    /// Find message ID by querying messages table directly (scan uses data for matching).
    private func findMessageId(in msgRows: [[String: String]], matching dataStr: String, db: SQLiteDB, sessionId: String) -> String? {
        // Re-query to get message IDs
        let rows = try? db.query(
            "SELECT id, data FROM message WHERE session_id = ? ORDER BY time_created ASC LIMIT 10",
            params: [sessionId]
        )
        return rows?.first(where: { $0["data"] == dataStr })?["id"]
    }

    private func parseSessionById(_ sessionId: String) throws -> Session {
        guard FileManager.default.fileExists(atPath: dbPath.path) else {
            throw OpenCodeError.databaseNotFound(dbPath)
        }

        let db = try SQLiteDB(path: dbPath.path, readOnly: true)
        defer { db.close() }

        // Fetch session
        let sessionRows = try db.query(
            "SELECT id, directory, time_created, time_updated, workspace_id FROM session WHERE id = ?",
            params: [sessionId]
        )
        guard let sessionRow = sessionRows.first else {
            throw OpenCodeError.sessionNotFound(sessionId)
        }

        let timeCreatedMs = Int64(sessionRow["time_created"] ?? "0") ?? 0
        let timeUpdatedMs = Int64(sessionRow["time_updated"] ?? "0") ?? 0
        let startedAt = Date(timeIntervalSince1970: Double(timeCreatedMs) / 1000.0)
        let endedAt = Date(timeIntervalSince1970: Double(timeUpdatedMs) / 1000.0)
        let directory = sessionRow["directory"]
        let projectName = extractProjectName(from: directory)
        let workspaceId = sessionRow["workspace_id"]

        // Fetch branch
        var gitBranch: String?
        if let wsId = workspaceId, !wsId.isEmpty {
            let wsRows = try db.query(
                "SELECT branch FROM workspace WHERE id = ?",
                params: [wsId]
            )
            gitBranch = wsRows.first?["branch"]
        }

        // Fetch messages ordered by creation time
        let msgRows = try db.query(
            "SELECT id, data FROM message WHERE session_id = ? ORDER BY time_created ASC",
            params: [sessionId]
        )

        var turns: [Turn] = []
        var model: String?

        for msgRow in msgRows {
            guard let msgId = msgRow["id"],
                  let dataStr = msgRow["data"],
                  let dataBytes = dataStr.data(using: .utf8),
                  let msgJson = try? JSONSerialization.jsonObject(with: dataBytes) as? [String: Any],
                  let role = msgJson["role"] as? String else { continue }

            // Extract model from first assistant message
            if role == "assistant" && model == nil {
                model = msgJson["modelID"] as? String
            }

            // Get message timestamp
            let msgTimeMs: Int64
            if let timeDict = msgJson["time"] as? [String: Any],
               let created = timeDict["created"] as? Int64 {
                msgTimeMs = created
            } else if let created = msgJson["time"] as? Int64 {
                msgTimeMs = created
            } else {
                msgTimeMs = timeCreatedMs
            }
            // Fetch parts for this message
            let partRows = try db.query(
                "SELECT data, time_created FROM part WHERE message_id = ? ORDER BY time_created ASC",
                params: [msgId]
            )

            for partRow in partRows {
                guard let partDataStr = partRow["data"],
                      let partData = partDataStr.data(using: .utf8),
                      let partJson = try? JSONSerialization.jsonObject(with: partData) as? [String: Any],
                      let partType = partJson["type"] as? String else { continue }

                let partTimeMs = Int64(partRow["time_created"] ?? "0") ?? msgTimeMs
                let partTimestamp = Date(timeIntervalSince1970: Double(partTimeMs) / 1000.0)

                switch partType {
                case "text":
                    guard let text = partJson["text"] as? String, !text.isEmpty else { continue }
                    let turnRole: Role = role == "user" ? .user : .assistant
                    turns.append(Turn(role: turnRole, content: [.text(text)], timestamp: partTimestamp))

                case "tool-invocation":
                    guard let invocation = partJson["toolInvocation"] as? [String: Any],
                          let toolName = invocation["toolName"] as? String,
                          let toolCallId = invocation["toolCallId"] as? String else { continue }

                    let state = invocation["state"] as? String ?? "call"

                    // Build input from args
                    var inputJSON: String?
                    if let args = invocation["args"] {
                        if let argsData = try? JSONSerialization.data(withJSONObject: args),
                           let argsStr = String(data: argsData, encoding: .utf8) {
                            inputJSON = argsStr
                        }
                    }

                    // Always emit the tool use turn
                    turns.append(Turn(
                        role: .assistant,
                        content: [.toolUse(ToolUse(name: toolName, id: toolCallId, input: inputJSON))],
                        timestamp: partTimestamp
                    ))

                    // Emit tool result if state is "result" or "error"
                    if state == "result" || state == "error" {
                        let output: String
                        if let result = invocation["result"] as? String {
                            output = String(result.prefix(5000))
                        } else if let result = invocation["result"] {
                            if let resultData = try? JSONSerialization.data(withJSONObject: result),
                               let resultStr = String(data: resultData, encoding: .utf8) {
                                output = String(resultStr.prefix(5000))
                            } else {
                                output = ""
                            }
                        } else {
                            output = state == "error" ? "Error" : ""
                        }
                        turns.append(Turn(
                            role: .tool,
                            content: [.toolResult(ToolResult(toolUseId: toolCallId, output: output))],
                            timestamp: partTimestamp
                        ))
                    }

                case "reasoning", "step-start", "step-finish", "file", "source-url":
                    // Skip non-content parts
                    continue

                default:
                    continue
                }
            }
        }

        let metadata = SessionMetadata(
            agent: .opencode,
            model: model,
            sessionId: sessionId,
            projectPath: directory,
            projectName: projectName,
            gitBranch: gitBranch,
            startedAt: startedAt,
            endedAt: endedAt
        )

        return Session(metadata: metadata, turns: turns)
    }

    private func extractProjectName(from path: String?) -> String? {
        guard let path = path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

// MARK: - Errors

public enum OpenCodeError: LocalizedError {
    case invalidURL(URL)
    case databaseNotFound(URL)
    case sessionNotFound(String)
    case sqliteError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid OpenCode session URL: \(url)"
        case .databaseNotFound(let path): return "OpenCode database not found at \(path.path)"
        case .sessionNotFound(let id): return "Session not found: \(id)"
        case .sqliteError(let msg): return "SQLite error: \(msg)"
        }
    }
}

// MARK: - Thin SQLite Wrapper

final class SQLiteDB {
    private var db: OpaquePointer?

    init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let rc = sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw OpenCodeError.sqliteError(msg)
        }
    }

    func close() {
        if let db { sqlite3_close(db) }
        db = nil
    }

    func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw OpenCodeError.sqliteError(msg)
        }
    }

    func query(_ sql: String, params: [String] = []) throws -> [[String: String]] {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw OpenCodeError.sqliteError(msg)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (param as NSString).utf8String, -1, nil)
        }

        var results: [[String: String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let colCount = sqlite3_column_count(stmt)
            var row: [String: String] = [:]
            for col in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, col))
                if let text = sqlite3_column_text(stmt, col) {
                    row[name] = String(cString: text)
                }
            }
            results.append(row)
        }
        return results
    }

    deinit {
        close()
    }
}
