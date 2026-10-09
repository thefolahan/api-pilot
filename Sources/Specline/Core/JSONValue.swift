import Foundation

struct JSONMember: Equatable {
    var key: String
    var value: JSONValue
}

indirect enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([JSONMember])

    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let items) = self, items.indices.contains(index) else { return nil }
        return items[index]
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var double: Double? {
        if case .number(let value) = self { return Double(value) }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var members: [JSONMember]? {
        if case .object(let members) = self { return members }
        return nil
    }

    var keys: [String] { members?.map(\.key) ?? [] }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var typeName: String {
        switch self {
        case .null: return "null"
        case .bool: return "boolean"
        case .number(let raw): return raw.contains(where: { ".eE".contains($0) }) ? "number" : "integer"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }

    var plainText: String {
        switch self {
        case .string(let value): return value
        case .number(let raw): return raw
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        default: return serialized(pretty: false)
        }
    }

    init(_ any: Any) {
        switch any {
        case let value as String: self = .string(value)
        case let value as Bool: self = .bool(value)
        case let value as Int: self = .number(String(value))
        case let value as Double: self = .number(JSONValue.format(value))
        case let value as [Any]: self = .array(value.map(JSONValue.init))
        case let value as [String: Any]:
            self = .object(value.keys.sorted().map { JSONMember(key: $0, value: JSONValue(value[$0]!)) })
        default: self = .null
        }
    }

    static func format(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 { return String(Int64(number)) }
        return String(number)
    }

    func setting(_ key: String, to value: JSONValue) -> JSONValue {
        guard case .object(var members) = self else { return self }
        if let index = members.firstIndex(where: { $0.key == key }) {
            members[index].value = value
        } else {
            members.append(JSONMember(key: key, value: value))
        }
        return .object(members)
    }
}

extension JSONValue {
    func serialized(pretty: Bool, indent: String = "  ") -> String {
        var out = ""
        write(into: &out, pretty: pretty, indent: indent, level: 0)
        return out
    }

    private func write(into out: inout String, pretty: Bool, indent: String, level: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .number(let raw): out += raw
        case .string(let value): out += JSONValue.quote(value)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "["
            for (offset, item) in items.enumerated() {
                if offset > 0 { out += "," }
                if pretty { out += "\n" + String(repeating: indent, count: level + 1) }
                item.write(into: &out, pretty: pretty, indent: indent, level: level + 1)
            }
            if pretty { out += "\n" + String(repeating: indent, count: level) }
            out += "]"
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{"
            for (offset, member) in members.enumerated() {
                if offset > 0 { out += "," }
                if pretty { out += "\n" + String(repeating: indent, count: level + 1) }
                out += JSONValue.quote(member.key) + (pretty ? ": " : ":")
                member.value.write(into: &out, pretty: pretty, indent: indent, level: level + 1)
            }
            if pretty { out += "\n" + String(repeating: indent, count: level) }
            out += "}"
        }
    }

    static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

struct JSONParseError: Error, LocalizedError {
    let message: String
    let offset: Int
    var errorDescription: String? { "\(message) at byte \(offset)" }
}

struct JSONParser {
    private let bytes: [UInt8]
    private var index = 0
    private var depth = 0

    static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONParser(bytes: [UInt8](data))
        if parser.bytes.starts(with: [0xEF, 0xBB, 0xBF]) { parser.index = 3 }
        parser.skipWhitespace()
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw parser.error("Unexpected trailing content") }
        return value
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private func error(_ message: String) -> JSONParseError {
        JSONParseError(message: message, offset: index)
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) { index += 1 }
    }

    private mutating func parseValue() throws -> JSONValue {
        guard index < bytes.count else { throw error("Unexpected end of input") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        default: return try parseNumber()
        }
    }

    private mutating func expect(_ word: String) throws {
        let utf8 = Array(word.utf8)
        guard index + utf8.count <= bytes.count, Array(bytes[index..<index + utf8.count]) == utf8 else {
            throw error("Invalid literal")
        }
        index += utf8.count
    }

    private mutating func nest() throws {
        depth += 1
        if depth > 512 { throw error("Nesting is too deep") }
    }

    private mutating func parseObject() throws -> JSONValue {
        try nest()
        defer { depth -= 1 }
        index += 1
        var members: [JSONMember] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw error("Expected a key") }
            let key = try parseString()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw error("Expected ':'") }
            index += 1
            skipWhitespace()
            members.append(JSONMember(key: key, value: try parseValue()))
            skipWhitespace()
            guard index < bytes.count else { throw error("Unterminated object") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            throw error("Expected ',' or '}'")
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        try nest()
        defer { depth -= 1 }
        index += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
        while true {
            skipWhitespace()
            items.append(try parseValue())
            skipWhitespace()
            guard index < bytes.count else { throw error("Unterminated array") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            throw error("Expected ',' or ']'")
        }
    }

    private mutating func parseString() throws -> String {
        index += 1
        var buffer: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index += 1
                return String(decoding: buffer, as: UTF8.self)
            }
            if byte == UInt8(ascii: "\\") {
                index += 1
                guard index < bytes.count else { break }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "n"): buffer.append(0x0A)
                case UInt8(ascii: "t"): buffer.append(0x09)
                case UInt8(ascii: "r"): buffer.append(0x0D)
                case UInt8(ascii: "b"): buffer.append(0x08)
                case UInt8(ascii: "f"): buffer.append(0x0C)
                case UInt8(ascii: "u"):
                    var code = try parseHex()
                    if (0xD800..<0xDC00).contains(code), index + 1 < bytes.count,
                       bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                        index += 2
                        let low = try parseHex()
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
                    buffer.append(contentsOf: Array(String(scalar).utf8))
                default: buffer.append(escape)
                }
                continue
            }
            buffer.append(byte)
            index += 1
        }
        throw error("Unterminated string")
    }

    private mutating func parseHex() throws -> UInt32 {
        guard index + 4 <= bytes.count,
              let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else {
            throw error("Invalid unicode escape")
        }
        index += 4
        return value
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = index
        while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
        let raw = String(decoding: bytes[start..<index], as: UTF8.self)
        guard !raw.isEmpty, Double(raw) != nil else { throw error("Invalid value") }
        return .number(raw)
    }
}
