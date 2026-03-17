import Foundation
import SessionCore

public struct GistPublisher {
    private var token: String?

    public init() {}

    /// Publish a session to a GitHub Gist. Returns the gist ID.
    public func publish(session: Session) async throws -> String {
        guard let token = token else {
            throw GistError.notAuthenticated
        }

        let encoder = JSONEncoder.turnshare
        let sessionData = try encoder.encode(session)
        let sessionJSON = String(data: sessionData, encoding: .utf8)!

        let manifest: [String: Any] = [
            "version": "1",
            "agent": session.metadata.agent.rawValue,
            "sessionId": session.metadata.sessionId,
            "projectName": session.metadata.projectName ?? "unknown",
            "turnCount": session.turns.count,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
        let manifestJSON = String(data: manifestData, encoding: .utf8)!

        let gistPayload: [String: Any] = [
            "description": "Turnshare: \(session.metadata.projectName ?? "session") (\(session.metadata.agent.rawValue))",
            "public": true,
            "files": [
                "session.json": ["content": sessionJSON],
                "manifest.json": ["content": manifestJSON],
            ],
        ]

        let body = try JSONSerialization.data(withJSONObject: gistPayload)

        var request = URLRequest(url: URL(string: "https://api.github.com/gists")!)
        request.httpMethod = "POST"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("turnshare", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw GistError.publishFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gistId = json["id"] as? String else {
            throw GistError.invalidResponse
        }

        return gistId
    }

    public mutating func authenticate(token: String) {
        self.token = token
    }
}

public enum GistError: Error, LocalizedError {
    case notAuthenticated
    case publishFailed
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated with GitHub"
        case .publishFailed: return "Failed to publish gist"
        case .invalidResponse: return "Invalid response from GitHub"
        }
    }
}
