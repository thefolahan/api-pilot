import Foundation

enum ParameterLocation: String, CaseIterable {
    case path, query, header, cookie
}

struct APIParameter: Identifiable {
    var id: String { location.rawValue + ":" + name }
    let name: String
    let location: ParameterLocation
    let required: Bool
    let deprecated: Bool
    let description: String?
    let schema: JSONValue?
    let example: JSONValue?
}

struct APIMediaType: Identifiable {
    var id: String { contentType }
    let contentType: String
    let schema: JSONValue?
    let example: JSONValue?
}

struct APIRequestBody {
    let description: String?
    let required: Bool
    let contents: [APIMediaType]

    var preferred: APIMediaType? {
        contents.first { $0.contentType.contains("json") } ?? contents.first
    }
}

struct APIResponse: Identifiable {
    var id: String { status }
    let status: String
    let description: String
    let contents: [APIMediaType]
    let headers: [(name: String, description: String?)]

    var preferred: APIMediaType? {
        contents.first { $0.contentType.contains("json") } ?? contents.first
    }

    var isSuccess: Bool { status.hasPrefix("2") }
}

struct APIOperation: Identifiable {
    var id: String { method + " " + path }
    let method: String
    let path: String
    let operationID: String?
    let summary: String?
    let description: String?
    let tags: [String]
    let deprecated: Bool
    let parameters: [APIParameter]
    let requestBody: APIRequestBody?
    let responses: [APIResponse]
    let security: [String]

    var title: String { summary ?? operationID ?? path }

    func response(for status: Int) -> APIResponse? {
        let exact = String(status)
        let range = String(exact.prefix(1)) + "XX"
        return responses.first { $0.status == exact }
            ?? responses.first { $0.status.uppercased() == range }
            ?? responses.first { $0.status == "default" }
    }
}

enum SecuritySchemeKind: String {
    case apiKey, http, oauth2, openIdConnect, mutualTLS
}

struct SecurityScheme: Identifiable {
    var id: String { name }
    let name: String
    let kind: SecuritySchemeKind
    let scheme: String?
    let bearerFormat: String?
    let parameterName: String?
    let location: String?
    let tokenURL: String?
    let authorizationURL: String?
    let scopes: [String]
    let description: String?

    var summary: String {
        switch kind {
        case .http: return (scheme ?? "http").capitalized + " authentication"
        case .apiKey: return "API key in \(location ?? "header") \(parameterName ?? "")"
        case .oauth2: return "OAuth 2.0"
        case .openIdConnect: return "OpenID Connect"
        case .mutualTLS: return "Mutual TLS"
        }
    }
}

struct APITag: Identifiable {
    var id: String { name }
    let name: String
    let description: String?
}

struct APIServer: Identifiable {
    var id: String { url }
    let url: String
    let description: String?
}

struct APISpec {
    let title: String
    let version: String
    let description: String?
    let format: String
    let servers: [APIServer]
    let tags: [APITag]
    let operations: [APIOperation]
    let securitySchemes: [SecurityScheme]
    let schemaNames: [String]
    let document: SpecDocument

    func operation(id: String) -> APIOperation? {
        operations.first { $0.id == id }
    }

    func schema(named name: String) -> JSONValue? {
        document.root["components"]?["schemas"]?[name] ?? document.root["definitions"]?[name]
    }

    var groupedOperations: [(tag: String, operations: [APIOperation])] {
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
