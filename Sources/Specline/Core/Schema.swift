import Foundation

struct Schema {
    let raw: JSONValue
    let referenceName: String?
    let document: SpecDocument

    init(_ value: JSONValue, document: SpecDocument) {
        self.document = document
        referenceName = SpecDocument.referenceName(value)
        raw = Schema.merge(document.resolve(value), document: document, depth: 0)
    }

    private static func merge(_ value: JSONValue, document: SpecDocument, depth: Int) -> JSONValue {
        guard let parts = value["allOf"]?.array, depth < 8 else { return value }
        var members = (value.members ?? []).filter { $0.key != "allOf" }
        var merged = JSONValue.object(members)
        var properties = value["properties"]?.members ?? []
        var required = value["required"]?.array ?? []
        for part in parts {
            let resolved = merge(document.resolve(part), document: document, depth: depth + 1)
            for property in resolved["properties"]?.members ?? [] where !properties.contains(where: { $0.key == property.key }) {
                properties.append(property)
            }
            for name in resolved["required"]?.array ?? [] where !required.contains(name) {
                required.append(name)
            }
            for member in resolved.members ?? [] where !["properties", "required"].contains(member.key) && merged[member.key] == nil {
                merged = merged.setting(member.key, to: member.value)
            }
        }
        if !properties.isEmpty { merged = merged.setting("properties", to: .object(properties)) }
        if !required.isEmpty { merged = merged.setting("required", to: .array(required)) }
        members = merged.members ?? []
        return .object(members)
    }

    private func child(_ value: JSONValue?) -> Schema? {
        value.map { Schema($0, document: document) }
    }

    var types: [String] {
        if let single = raw["type"]?.string { return [single] }
        return (raw["type"]?.array ?? []).compactMap(\.string)
    }

    var primaryType: String? {
        if let type = types.first(where: { $0 != "null" }) { return type }
        if raw["properties"] != nil { return "object" }
        if raw["items"] != nil { return "array" }
        return nil
    }

    var isNullable: Bool { raw["nullable"]?.bool == true || types.contains("null") }
    var format: String? { raw["format"]?.string }
    var title: String? { raw["title"]?.string }
    var description: String? { raw["description"]?.string }
    var pattern: String? { raw["pattern"]?.string }
    var enumValues: [JSONValue] { raw["enum"]?.array ?? (raw["const"].map { [$0] } ?? []) }
    var defaultValue: JSONValue? { raw["default"] }
    var example: JSONValue? { raw["example"] ?? raw["examples"]?.array?.first }
    var readOnly: Bool { raw["readOnly"]?.bool == true }
    var writeOnly: Bool { raw["writeOnly"]?.bool == true }
    var deprecated: Bool { raw["deprecated"]?.bool == true }
    var required: Set<String> { Set((raw["required"]?.array ?? []).compactMap(\.string)) }
    var items: Schema? { child(raw["items"]) }
    var oneOf: [Schema] { (raw["oneOf"]?.array ?? raw["anyOf"]?.array ?? []).map { Schema($0, document: document) } }

    var properties: [(name: String, schema: Schema)] {
        (raw["properties"]?.members ?? []).map { ($0.key, Schema($0.value, document: document)) }
    }

    var additionalProperties: Schema? {
        guard let value = raw["additionalProperties"], value.members != nil else { return nil }
        return child(value)
    }

    var forbidsAdditionalProperties: Bool { raw["additionalProperties"]?.bool == false }

    var constraints: [String] {
        var notes: [String] = []
        let pairs: [(String, String)] = [
            ("minimum", "min"), ("maximum", "max"), ("minLength", "min length"), ("maxLength", "max length"),
            ("minItems", "min items"), ("maxItems", "max items"), ("multipleOf", "multiple of")
        ]
        for (key, label) in pairs {
            if let value = raw[key]?.plainText { notes.append("\(label) \(value)") }
        }
        if let pattern { notes.append("pattern \(pattern)") }
        if let defaultValue { notes.append("default \(defaultValue.plainText)") }
        return notes
    }

    var typeLabel: String {
        if let referenceName, primaryType == "object" || primaryType == nil, raw["properties"] != nil || raw["allOf"] != nil {
            return referenceName
        }
        if !oneOf.isEmpty {
            return (raw["oneOf"] != nil ? "one of " : "any of ") + oneOf.map(\.typeLabel).joined(separator: " | ")
        }
        var label: String
        switch primaryType {
        case "array": label = "array<\(items?.typeLabel ?? "any")>"
        case .some(let type): label = format.map { "\(type)(\($0))" } ?? type
        case .none: label = referenceName ?? "any"
        }
        if isNullable { label += "?" }
        return label
    }
}
