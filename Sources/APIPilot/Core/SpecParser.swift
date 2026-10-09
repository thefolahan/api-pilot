import Foundation

enum SpecParser {
    static let methods = ["get", "put", "post", "delete", "options", "head", "patch", "trace"]

    static func parse(data: Data, sourceURL: URL? = nil) throws -> APISpec {
        let root = try SpecLoader.parse(data)
        guard root.members != nil else { throw SpecError.invalid("This file is not an OpenAPI document.") }
        if let version = root["swagger"]?.plainText {
            return parseSwagger(root, version: version, sourceURL: sourceURL)
        }
        guard let version = root["openapi"]?.plainText else {
            throw SpecError.invalid("No \"openapi\" or \"swagger\" version field was found.")
        }
        return parseOpenAPI(root, version: version, sourceURL: sourceURL)
    }

    private static func parseOpenAPI(_ root: JSONValue, version: String, sourceURL: URL?) -> APISpec {
        let document = SpecDocument(root: root)
        var servers = (root["servers"]?.array ?? []).compactMap { raw -> APIServer? in
            guard var url = raw["url"]?.string else { return nil }
            for member in raw["variables"]?.members ?? [] {
                url = url.replacingOccurrences(of: "{\(member.key)}", with: member.value["default"]?.plainText ?? "")
            }
            return APIServer(url: absolute(url, relativeTo: sourceURL), description: raw["description"]?.string)
        }
        if servers.isEmpty, let sourceURL, sourceURL.scheme?.hasPrefix("http") == true {
            servers = [APIServer(url: absolute("/", relativeTo: sourceURL), description: nil)]
        }

        let globalSecurity = securityNames(root["security"])
        var operations: [APIOperation] = []
        for pathMember in root["paths"]?.members ?? [] {
            let pathItem = document.resolve(pathMember.value)
            let shared = pathItem["parameters"]?.array ?? []
            for method in methods {
                guard let raw = pathItem[method] else { continue }
                let parameters = mergeParameters(shared, raw["parameters"]?.array ?? [], document: document)
                    .compactMap { parameter(from: $0, document: document) }
                var body: APIRequestBody?
                if let rawBody = raw["requestBody"].map(document.resolve) {
                    body = APIRequestBody(
                        description: rawBody["description"]?.string,
                        required: rawBody["required"]?.bool ?? false,
                        contents: mediaTypes(rawBody["content"], document: document)
                    )
                }
                let responses = (raw["responses"]?.members ?? []).map { member -> APIResponse in
                    let response = document.resolve(member.value)
                    return APIResponse(
                        status: member.key,
                        description: response["description"]?.string ?? "",
                        contents: mediaTypes(response["content"], document: document),
                        headers: (response["headers"]?.members ?? []).map {
                            ($0.key, document.resolve($0.value)["description"]?.string)
                        }
                    )
                }
                operations.append(APIOperation(
                    method: method.uppercased(),
                    path: pathMember.key,
                    operationID: raw["operationId"]?.string,
                    summary: raw["summary"]?.string,
                    description: raw["description"]?.string,
                    tags: (raw["tags"]?.array ?? []).compactMap(\.string),
                    deprecated: raw["deprecated"]?.bool ?? false,
                    parameters: parameters,
                    requestBody: body,
                    responses: responses,
                    security: raw["security"] != nil ? securityNames(raw["security"]) : globalSecurity
                ))
            }
        }

        let schemes = (root["components"]?["securitySchemes"]?.members ?? []).map { member -> SecurityScheme in
            let raw = document.resolve(member.value)
            let flows = raw["flows"]?.members ?? []
            let flow = flows.first { $0.key == "clientCredentials" }?.value ?? flows.first?.value
            return SecurityScheme(
                name: member.key,
                kind: SecuritySchemeKind(rawValue: raw["type"]?.string ?? "") ?? .http,
                scheme: raw["scheme"]?.string?.lowercased(),
                bearerFormat: raw["bearerFormat"]?.string,
                parameterName: raw["name"]?.string,
                location: raw["in"]?.string,
                tokenURL: flow?["tokenUrl"]?.string.map { absolute($0, relativeTo: sourceURL) },
                authorizationURL: flow?["authorizationUrl"]?.string,
                scopes: flow?["scopes"]?.keys ?? [],
                description: raw["description"]?.string
            )
        }

        return APISpec(
            title: root["info"]?["title"]?.string ?? "Untitled API",
            version: root["info"]?["version"]?.plainText ?? "",
            description: root["info"]?["description"]?.string,
            format: "OpenAPI \(version)",
            servers: servers,
            tags: tags(root),
            operations: operations,
            securitySchemes: schemes,
            schemaNames: root["components"]?["schemas"]?.keys ?? [],
            document: document
        )
    }

    private static func parseSwagger(_ root: JSONValue, version: String, sourceURL: URL?) -> APISpec {
        let document = SpecDocument(root: root)
        let schemes = (root["schemes"]?.array ?? []).compactMap(\.string)
        let host = root["host"]?.string ?? sourceURL?.host.map { host in
            sourceURL?.port.map { "\(host):\($0)" } ?? host
        }
        var servers: [APIServer] = []
        if let host {
            let basePath = root["basePath"]?.string ?? ""
            for scheme in schemes.isEmpty ? ["https"] : schemes {
                servers.append(APIServer(url: "\(scheme)://\(host)\(basePath)", description: nil))
            }
        }
        let globalConsumes = (root["consumes"]?.array ?? []).compactMap(\.string)
        let globalProduces = (root["produces"]?.array ?? []).compactMap(\.string)
        let globalSecurity = securityNames(root["security"])

        var operations: [APIOperation] = []
        for pathMember in root["paths"]?.members ?? [] {
            let pathItem = document.resolve(pathMember.value)
            let shared = pathItem["parameters"]?.array ?? []
            for method in methods {
                guard let raw = pathItem[method] else { continue }
                let consumes = (raw["consumes"]?.array?.compactMap(\.string)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (globalConsumes.isEmpty ? ["application/json"] : globalConsumes)
                let produces = (raw["produces"]?.array?.compactMap(\.string)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (globalProduces.isEmpty ? ["application/json"] : globalProduces)
                let all = mergeParameters(shared, raw["parameters"]?.array ?? [], document: document)

                var parameters: [APIParameter] = []
                var body: APIRequestBody?
                var formProperties: [JSONMember] = []
                var formRequired: [JSONValue] = []
                for item in all {
                    switch item["in"]?.string {
                    case "body":
                        body = APIRequestBody(
                            description: item["description"]?.string,
                            required: item["required"]?.bool ?? false,
                            contents: consumes.map { APIMediaType(contentType: $0, schema: item["schema"], example: nil) }
                        )
                    case "formData":
                        let name = item["name"]?.string ?? ""
                        var schema = JSONValue.object([])
                        for key in ["type", "format", "description", "enum", "default", "items"] {
                            if let value = item[key] { schema = schema.setting(key, to: value) }
                        }
                        formProperties.append(JSONMember(key: name, value: schema))
                        if item["required"]?.bool == true { formRequired.append(.string(name)) }
                    default:
                        var adapted = item
                        if item["schema"] == nil {
                            var schema = JSONValue.object([])
                            for key in ["type", "format", "enum", "default", "items", "minimum", "maximum", "pattern"] {
                                if let value = item[key] { schema = schema.setting(key, to: value) }
                            }
                            adapted = adapted.setting("schema", to: schema)
                        }
                        if let parameter = parameter(from: adapted, document: document) { parameters.append(parameter) }
                    }
                }
                if !formProperties.isEmpty {
                    let schema = JSONValue.object([
                        JSONMember(key: "type", value: .string("object")),
                        JSONMember(key: "properties", value: .object(formProperties)),
                        JSONMember(key: "required", value: .array(formRequired))
                    ])
                    let types = consumes.filter { $0.contains("form") }
                    body = APIRequestBody(
                        description: nil,
                        required: !formRequired.isEmpty,
                        contents: (types.isEmpty ? ["application/x-www-form-urlencoded"] : types)
                            .map { APIMediaType(contentType: $0, schema: schema, example: nil) }
                    )
                }

                let responses = (raw["responses"]?.members ?? []).map { member -> APIResponse in
                    let response = document.resolve(member.value)
                    let examples = response["examples"]
                    let contents: [APIMediaType] = response["schema"] == nil ? [] : produces.map {
                        APIMediaType(contentType: $0, schema: response["schema"], example: examples?[$0])
                    }
                    return APIResponse(
                        status: member.key,
                        description: response["description"]?.string ?? "",
                        contents: contents,
                        headers: (response["headers"]?.members ?? []).map { ($0.key, $0.value["description"]?.string) }
                    )
                }

                operations.append(APIOperation(
                    method: method.uppercased(),
                    path: pathMember.key,
                    operationID: raw["operationId"]?.string,
                    summary: raw["summary"]?.string,
                    description: raw["description"]?.string,
                    tags: (raw["tags"]?.array ?? []).compactMap(\.string),
                    deprecated: raw["deprecated"]?.bool ?? false,
                    parameters: parameters,
                    requestBody: body,
                    responses: responses,
                    security: raw["security"] != nil ? securityNames(raw["security"]) : globalSecurity
                ))
            }
        }

        let securitySchemes = (root["securityDefinitions"]?.members ?? []).map { member -> SecurityScheme in
            let raw = member.value
            let type = raw["type"]?.string ?? ""
            return SecurityScheme(
                name: member.key,
                kind: type == "basic" ? .http : (SecuritySchemeKind(rawValue: type) ?? .apiKey),
                scheme: type == "basic" ? "basic" : nil,
                bearerFormat: nil,
                parameterName: raw["name"]?.string,
                location: raw["in"]?.string,
                tokenURL: raw["tokenUrl"]?.string,
                authorizationURL: raw["authorizationUrl"]?.string,
                scopes: raw["scopes"]?.keys ?? [],
                description: raw["description"]?.string
            )
        }

        return APISpec(
            title: root["info"]?["title"]?.string ?? "Untitled API",
            version: root["info"]?["version"]?.plainText ?? "",
            description: root["info"]?["description"]?.string,
            format: "Swagger \(version)",
            servers: servers,
            tags: tags(root),
            operations: operations,
            securitySchemes: securitySchemes,
            schemaNames: root["definitions"]?.keys ?? [],
            document: document
        )
    }

    private static func tags(_ root: JSONValue) -> [APITag] {
        (root["tags"]?.array ?? []).compactMap { raw in
            raw["name"]?.string.map { APITag(name: $0, description: raw["description"]?.string) }
        }
    }

    private static func securityNames(_ value: JSONValue?) -> [String] {
        var names: [String] = []
        for requirement in value?.array ?? [] {
            for key in requirement.keys where !names.contains(key) { names.append(key) }
        }
        return names
    }

    private static func mergeParameters(_ shared: [JSONValue], _ own: [JSONValue], document: SpecDocument) -> [JSONValue] {
        let ownResolved = own.map(document.resolve)
        let key: (JSONValue) -> String = { ($0["in"]?.string ?? "") + ":" + ($0["name"]?.string ?? "") }
        let ownKeys = Set(ownResolved.map(key))
        return shared.map(document.resolve).filter { !ownKeys.contains(key($0)) } + ownResolved
    }

    private static func parameter(from raw: JSONValue, document: SpecDocument) -> APIParameter? {
        guard let name = raw["name"]?.string,
              let location = ParameterLocation(rawValue: raw["in"]?.string ?? "") else { return nil }
        var schema = raw["schema"]
        if schema == nil, let content = raw["content"]?.members?.first?.value {
            schema = content["schema"]
        }
        let example = raw["example"] ?? raw["examples"]?.members?.first.map { document.resolve($0.value)["value"] ?? .null }
        return APIParameter(
            name: name,
            location: location,
            required: location == .path || raw["required"]?.bool == true,
            deprecated: raw["deprecated"]?.bool ?? false,
            description: raw["description"]?.string,
            schema: schema,
            example: example
        )
    }

    private static func mediaTypes(_ content: JSONValue?, document: SpecDocument) -> [APIMediaType] {
        (content?.members ?? []).map { member in
            let raw = member.value
            var example = raw["example"]
            if example == nil, let first = raw["examples"]?.members?.first {
                example = document.resolve(first.value)["value"]
            }
            return APIMediaType(contentType: member.key, schema: raw["schema"], example: example)
        }
    }

    static func absolute(_ url: String, relativeTo source: URL?) -> String {
        if url.contains("://") { return url.hasSuffix("/") ? String(url.dropLast()) : url }
        guard let source, source.scheme?.hasPrefix("http") == true,
              let resolved = URL(string: url, relativeTo: source)?.absoluteString else { return url }
        return resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    }
}
