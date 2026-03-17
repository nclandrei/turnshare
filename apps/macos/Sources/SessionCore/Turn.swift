import Foundation

// MARK: - Turn

public struct Turn: Codable, Identifiable {
    public let id: String
    public let role: Role
    public let content: [ContentBlock]
    public let timestamp: Date

    public init(id: String = UUID().uuidString, role: Role, content: [ContentBlock], timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public enum Role: String, Codable {
    case user
    case assistant
    case tool
}

// MARK: - Content Blocks

public enum ContentBlock: Codable {
    case text(String)
    case toolUse(ToolUse)
    case toolResult(ToolResult)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let wrapper = try TextBlock(from: decoder)
            self = .text(wrapper.text)
        case "tool_use":
            self = .toolUse(try ToolUse(from: decoder))
        case "tool_result":
            self = .toolResult(try ToolResult(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown content block type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            try TextBlock(type: "text", text: text).encode(to: encoder)
        case .toolUse(let toolUse):
            try toolUse.encode(to: encoder)
        case .toolResult(let result):
            try result.encode(to: encoder)
        }
    }
}

private struct TextBlock: Codable {
    let type: String
    let text: String
}

public struct ToolUse: Codable {
    public let type: String
    public let name: String
    public let id: String
    public let input: String?

    public init(name: String, id: String, input: String? = nil) {
        self.type = "tool_use"
        self.name = name
        self.id = id
        self.input = input
    }
}

public struct ToolResult: Codable {
    public let type: String
    public let toolUseId: String
    public let name: String?
    public let output: String

    public init(toolUseId: String, name: String? = nil, output: String) {
        self.type = "tool_result"
        self.toolUseId = toolUseId
        self.name = name
        self.output = output
    }
}

// MARK: - JSON Encoder/Decoder with ISO8601 dates

public extension JSONEncoder {
    static var turnshare: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var turnshare: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
