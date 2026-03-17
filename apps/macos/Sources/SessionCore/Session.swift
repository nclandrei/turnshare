import Foundation

// MARK: - Session

public struct Session: Codable, Identifiable {
    public let version: String
    public let metadata: SessionMetadata
    public let turns: [Turn]

    public var id: String { metadata.sessionId }

    public init(version: String = "1", metadata: SessionMetadata, turns: [Turn]) {
        self.version = version
        self.metadata = metadata
        self.turns = turns
    }
}

// MARK: - Metadata

public struct SessionMetadata: Codable {
    public let agent: Agent
    public let model: String?
    public let sessionId: String
    public let projectPath: String?
    public let projectName: String?
    public let gitBranch: String?
    public let startedAt: Date
    public let endedAt: Date?

    public init(
        agent: Agent,
        model: String? = nil,
        sessionId: String,
        projectPath: String? = nil,
        projectName: String? = nil,
        gitBranch: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil
    ) {
        self.agent = agent
        self.model = model
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.projectName = projectName
        self.gitBranch = gitBranch
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum Agent: String, Codable {
    case claudeCode = "claude-code"
    case codex
    case opencode
}

// MARK: - Session Summary (for list display without loading full turns)

public struct SessionSummary: Identifiable {
    public let id: String
    public let agent: Agent
    public let model: String?
    public let projectName: String?
    public let gitBranch: String?
    public let startedAt: Date
    public let firstUserMessage: String?
    public let turnCount: Int
    public let filePath: URL

    public init(
        id: String,
        agent: Agent,
        model: String? = nil,
        projectName: String? = nil,
        gitBranch: String? = nil,
        startedAt: Date,
        firstUserMessage: String? = nil,
        turnCount: Int,
        filePath: URL
    ) {
        self.id = id
        self.agent = agent
        self.model = model
        self.projectName = projectName
        self.gitBranch = gitBranch
        self.startedAt = startedAt
        self.firstUserMessage = firstUserMessage
        self.turnCount = turnCount
        self.filePath = filePath
    }
}
