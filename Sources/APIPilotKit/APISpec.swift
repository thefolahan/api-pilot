import Foundation

public enum ParameterLocation: String, CaseIterable {
    case path, query, header, cookie
}

public struct APIParameter: Identifiable {
    public var id: String { location.rawValue + ":" + name }
    public let name: String
    public let location: ParameterLocation
    public let required: Bool
    public let deprecated: Bool
    public let description: String?
    public let schema: JSONValue?
    public let example: JSONValue?
}

public struct APIMediaType: Identifiable {
    public var id: String { contentType }
    public let contentType: String
    public let schema: JSONValue?
    public let example: JSONValue?
}

public struct APIRequestBody {
    public let description: String?
    public let required: Bool
    public let contents: [APIMediaType]

    public var preferred: APIMediaType? {
        contents.first { $0.contentType.contains("json") } ?? contents.first
    }
}

public struct APIResponse: Identifiable {
    public var id: String { status }
    public let status: String
    public let description: String
    public let contents: [APIMediaType]
    public let headers: [(name: String, description: String?)]

    public var preferred: APIMediaType? {
        contents.first { $0.contentType.contains("json") } ?? contents.first
    }

    public var isSuccess: Bool { status.hasPrefix("2") }
}

public struct APIOperation: Identifiable {
    public var id: String { method + " " + path }
    public let method: String
    public let path: String
    public let operationID: String?
    public let summary: String?
    public let description: String?
    public let tags: [String]
    public let deprecated: Bool
    public let parameters: [APIParameter]
    public let requestBody: APIRequestBody?
    public let responses: [APIResponse]
    public let security: [String]

    public var title: String { summary ?? operationID ?? path }

    public func response(for status: Int) -> APIResponse? {
        let exact = String(status)
        let range = String(exact.prefix(1)) + "XX"
        return responses.first { $0.status == exact }
            ?? responses.first { $0.status.uppercased() == range }
            ?? responses.first { $0.status == "default" }
    }
}

public enum SecuritySchemeKind: String {
    case apiKey, http, oauth2, openIdConnect, mutualTLS
}

public struct SecurityScheme: Identifiable {
    public var id: String { name }
    public let name: String
    public let kind: SecuritySchemeKind
    public let scheme: String?
    public let bearerFormat: String?
    public let parameterName: String?
    public let location: String?
    public let tokenURL: String?
    public let authorizationURL: String?
    public let scopes: [String]
    public let description: String?

    public var summary: String {
        switch kind {
        case .http: return (scheme ?? "http").capitalized + " authentication"
        case .apiKey: return "API key in \(location ?? "header") \(parameterName ?? "")"
        case .oauth2: return "OAuth 2.0"
        case .openIdConnect: return "OpenID Connect"
        case .mutualTLS: return "Mutual TLS"
        }
    }
}

public struct APITag: Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

public struct APIServer: Identifiable {
    public var id: String { url }
    public let url: String
    public let description: String?

    public init(url: String, description: String? = nil) {
        self.url = url
        self.description = description
    }
}

public struct APISpec {
    public let title: String
    public let version: String
    public let description: String?
    public let format: String
    public let servers: [APIServer]
    public let tags: [APITag]
    public let operations: [APIOperation]
    public let securitySchemes: [SecurityScheme]
    public let schemaNames: [String]
    public let document: SpecDocument

    public func operation(id: String) -> APIOperation? {
        operations.first { $0.id == id }
    }

    public func schema(named name: String) -> JSONValue? {
        document.root["components"]?["schemas"]?[name] ?? document.root["definitions"]?[name]
    }

    public var groupedOperations: [(tag: String, operations: [APIOperation])] {
        var order: [String] = tags.map(\.name)
        var groups: [String: [APIOperation]] = [:]
        for operation in operations {
            let tag = operation.tags.first ?? "General"
            if !order.contains(tag) { order.append(tag) }
            groups[tag, default: []].append(operation)
        }
        return order.compactMap { tag in groups[tag].map { (tag, $0) } }
    }
}
