import Foundation

public enum ExampleGenerator {
    public enum Purpose {
        case request, response
    }

    public static func example(for schema: Schema, purpose: Purpose, depth: Int = 0) -> JSONValue {
        if let example = schema.example { return example }
        if let value = schema.defaultValue { return value }
        if let first = schema.enumValues.first { return first }
        if let first = schema.oneOf.first { return example(for: first, purpose: purpose, depth: depth + 1) }
        if depth > 7 { return schema.primaryType == "array" ? .array([]) : .null }

        switch schema.primaryType {
        case "object":
            var members: [JSONMember] = []
            for (name, property) in schema.properties {
                if purpose == .request && property.readOnly { continue }
                if purpose == .response && property.writeOnly { continue }
                members.append(JSONMember(key: name, value: example(for: property, purpose: purpose, depth: depth + 1)))
            }
            if members.isEmpty, let extra = schema.additionalProperties {
                members.append(JSONMember(key: "key", value: example(for: extra, purpose: purpose, depth: depth + 1)))
            }
            return .object(members)
        case "array":
            guard let items = schema.items else { return .array([]) }
            return .array([example(for: items, purpose: purpose, depth: depth + 1)])
        case "integer":
            return .number(schema.raw["minimum"]?.plainText ?? "0")
        case "number":
            return .number(schema.raw["minimum"]?.plainText ?? "0.0")
        case "boolean":
            return .bool(true)
        case "string":
            return .string(sampleString(format: schema.format))
        default:
            return .null
        }
    }

    public static func sampleString(format: String?) -> String {
        switch format {
        case "date-time": return "2026-01-15T09:30:00Z"
        case "date": return "2026-01-15"
        case "time": return "09:30:00"
        case "email": return "user@example.com"
        case "uuid": return "3fa85f64-5717-4562-b3fc-2c963f66afa6"
        case "uri", "url": return "https://example.com"
        case "hostname": return "example.com"
        case "ipv4": return "192.168.0.1"
        case "ipv6": return "::1"
        case "password": return "secret"
        case "byte": return "U3BlY2xpbmU="
        default: return "string"
        }
    }

    public static func example(for media: APIMediaType, document: SpecDocument, purpose: Purpose) -> JSONValue? {
        if let example = media.example { return example }
        guard let schema = media.schema else { return nil }
        return example(for: Schema(schema, document: document), purpose: purpose)
    }
}
