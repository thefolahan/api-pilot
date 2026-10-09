import Foundation

public struct ValidationIssue: Identifiable, Equatable {
    public let id = UUID()
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public enum SchemaValidator {
    public static func validate(_ value: JSONValue, against schema: Schema) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        walk(value, schema, path: "$", depth: 0, issues: &issues)
        return issues
    }

    private static func walk(_ value: JSONValue, _ schema: Schema, path: String, depth: Int, issues: inout [ValidationIssue]) {
        guard depth < 40, issues.count < 200 else { return }
        func report(_ message: String) { issues.append(ValidationIssue(path: path, message: message)) }

        if value.isNull {
            if !schema.isNullable && schema.primaryType != nil { report("is null but the schema does not allow null") }
            return
        }

        let alternatives = schema.oneOf
        if !alternatives.isEmpty {
            let matches = alternatives.contains { candidate in
                var scratch: [ValidationIssue] = []
                walk(value, candidate, path: path, depth: depth + 1, issues: &scratch)
                return scratch.isEmpty
            }
            if !matches { report("does not match any of the \(alternatives.count) allowed schemas") }
            return
        }

        let enumValues = schema.enumValues
        if !enumValues.isEmpty, !enumValues.contains(value) {
            report("\(value.plainText) is not one of \(enumValues.map(\.plainText).joined(separator: ", "))")
        }

        let allowed = schema.types.filter { $0 != "null" }
        if !allowed.isEmpty, !allowed.contains(where: { matches(value, type: $0) }) {
            report("expected \(allowed.joined(separator: " or ")) but found \(value.typeName)")
            return
        }

        switch value {
        case .object(let members):
            let keys = Set(members.map(\.key))
            for name in schema.required.sorted() where !keys.contains(name) {
                issues.append(ValidationIssue(path: path, message: "missing required property \"\(name)\""))
            }
            let declared = Dictionary(schema.properties.map { ($0.name, $0.schema) }, uniquingKeysWith: { first, _ in first })
            for member in members {
                let childPath = path + "." + member.key
                if let property = declared[member.key] {
                    walk(member.value, property, path: childPath, depth: depth + 1, issues: &issues)
                } else if let extra = schema.additionalProperties {
                    walk(member.value, extra, path: childPath, depth: depth + 1, issues: &issues)
                } else if schema.forbidsAdditionalProperties {
                    issues.append(ValidationIssue(path: childPath, message: "is not allowed by the schema"))
                }
            }
        case .array(let items):
            if let minimum = schema.raw["minItems"]?.double, Double(items.count) < minimum {
                report("has \(items.count) items, fewer than \(minimum.formatted())")
            }
            if let maximum = schema.raw["maxItems"]?.double, Double(items.count) > maximum {
                report("has \(items.count) items, more than \(maximum.formatted())")
            }
            if let itemSchema = schema.items {
                for (offset, item) in items.prefix(500).enumerated() {
                    walk(item, itemSchema, path: "\(path)[\(offset)]", depth: depth + 1, issues: &issues)
                }
            }
        case .string(let text):
            let length = Double(text.count)
            if let minimum = schema.raw["minLength"]?.double, length < minimum { report("is shorter than \(minimum.formatted()) characters") }
            if let maximum = schema.raw["maxLength"]?.double, length > maximum { report("is longer than \(maximum.formatted()) characters") }
            if let pattern = schema.pattern, let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil {
                report("does not match the pattern \(pattern)")
            }
            if let format = schema.format, !matches(text, format: format) {
                report("\"\(text)\" is not a valid \(format)")
            }
        case .number:
            guard let number = value.double else { break }
            if let minimum = schema.raw["minimum"]?.double {
                let exclusive = schema.raw["exclusiveMinimum"]?.bool == true
                if exclusive ? number <= minimum : number < minimum { report("is below the minimum \(minimum.formatted())") }
            }
            if let minimum = schema.raw["exclusiveMinimum"]?.double, number <= minimum { report("must be above \(minimum.formatted())") }
            if let maximum = schema.raw["maximum"]?.double {
                let exclusive = schema.raw["exclusiveMaximum"]?.bool == true
                if exclusive ? number >= maximum : number > maximum { report("is above the maximum \(maximum.formatted())") }
            }
            if let maximum = schema.raw["exclusiveMaximum"]?.double, number >= maximum { report("must be below \(maximum.formatted())") }
        default:
            break
        }
    }

    private static func matches(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("number", .number):
            return true
        case ("integer", .number):
            return value.double.map { $0.rounded() == $0 } ?? false
        default:
            return false
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func matches(_ text: String, format: String) -> Bool {
        switch format {
        case "date-time":
            return isoFormatter.date(from: text) != nil || ISO8601DateFormatter().date(from: text) != nil
        case "date":
            return text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        case "uuid":
            return UUID(uuidString: text) != nil
        case "email":
            return text.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
        case "uri", "url":
            return URL(string: text)?.scheme != nil
        default:
            return true
        }
    }
}
