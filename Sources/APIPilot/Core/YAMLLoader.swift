import Foundation
import Yams

enum SpecLoader {
    static func parse(_ data: Data) throws -> JSONValue {
        let text = String(decoding: data, as: UTF8.self)
        let trimmed = text.drop { $0.isWhitespace || $0 == "\u{FEFF}" }
        if trimmed.first == "{" || trimmed.first == "[" {
            return try JSONParser.parse(data)
        }
        guard let node = try Yams.compose(yaml: text) else {
            throw SpecError.invalid("The file is empty.")
        }
        return convert(node)
    }

    private static func convert(_ node: Node) -> JSONValue {
        switch node {
        case .mapping(let mapping):
            return .object(mapping.map { JSONMember(key: $0.key.string ?? "", value: convert($0.value)) })
        case .sequence(let sequence):
            return .array(sequence.map(convert))
        case .scalar(let scalar):
            switch Tag.Name(rawValue: node.tag.rawValue) {
            case .null: return .null
            case .bool: return .bool(node.bool ?? false)
            case .int: return .number(node.int.map(String.init) ?? scalar.string)
            case .float: return node.float.map { .number(JSONValue.format($0)) } ?? .string(scalar.string)
            default: return .string(scalar.string)
            }
        case .alias:
            return .null
        }
    }
}

enum SpecError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}
