import Foundation

struct EnvironmentVariable: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var key = ""
    var value = ""
    var secret = false

    enum CodingKeys: String, CodingKey {
        case enabled, key, value, secret
    }

    init(key: String = "", value: String = "", secret: Bool = false) {
        self.key = key
        self.value = value
        self.secret = secret
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = container.value(.enabled, or: true)
        key = container.value(.key, or: "")
        value = container.value(.value, or: "")
        secret = container.value(.secret, or: false)
    }
}

struct APIEnvironment: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var variables: [EnvironmentVariable]

    enum CodingKeys: String, CodingKey {
        case name, variables
    }

    init(id: String, name: String, variables: [EnvironmentVariable]) {
        self.id = id
        self.name = name
        self.variables = variables
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = ""
        name = container.value(.name, or: "Untitled")
        variables = container.value(.variables, or: [])
    }

    var values: [String: String] {
        var result: [String: String] = [:]
        for variable in variables where variable.enabled && !variable.key.isEmpty {
            result[variable.key] = variable.value
        }
        return result
    }

    mutating func set(_ key: String, to value: String) {
        if let index = variables.firstIndex(where: { $0.key == key }) {
            variables[index].value = value
            variables[index].enabled = true
        } else {
            variables.append(EnvironmentVariable(key: key, value: value))
        }
    }
}

enum Interpolator {
    private static let pattern = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)

    static func references(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func apply(_ text: String, variables: [String: String], unresolved: inout Set<String>) -> String {
        guard text.contains("{{") else { return text }
        var result = text
        var passes = 0
        while passes < 4, result.contains("{{") {
            passes += 1
            let snapshot = result
            let range = NSRange(snapshot.startIndex..., in: snapshot)
            var changed = false
            for match in pattern.matches(in: snapshot, range: range).reversed() {
                guard let whole = Range(match.range, in: result), let nameRange = Range(match.range(at: 1), in: snapshot) else { continue }
                let name = String(snapshot[nameRange])
                if let value = dynamic(name) ?? variables[name] {
                    result.replaceSubrange(whole, with: value)
                    changed = true
                } else {
                    unresolved.insert(name)
                }
            }
            if !changed { break }
        }
        return result
    }

    static func apply(_ text: String, variables: [String: String]) -> String {
        var ignored = Set<String>()
        return apply(text, variables: variables, unresolved: &ignored)
    }

    private static func dynamic(_ name: String) -> String? {
        switch name {
        case "$uuid", "$guid", "$randomUUID": return UUID().uuidString.lowercased()
        case "$timestamp": return String(Int(Date().timeIntervalSince1970))
        case "$isoTimestamp": return ISO8601DateFormatter().string(from: Date())
        case "$randomInt": return String(Int.random(in: 0...1000))
        case "$randomEmail": return "user\(Int.random(in: 1000...9999))@example.com"
        default: return nil
        }
    }
}
