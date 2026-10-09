import Foundation

enum DraftFactory {
    static func make(from operation: APIOperation, spec: APISpec) -> RequestDraft {
        let document = spec.document
        var draft = RequestDraft()
        draft.name = operation.title
        draft.operationID = operation.id
        draft.method = operation.method
        draft.url = "{{baseUrl}}" + operation.path

        for parameter in operation.parameters where !parameter.deprecated || parameter.required {
            let value = sampleValue(for: parameter, document: document)
            let row = KeyValue(key: parameter.name, value: value, enabled: parameter.required, note: parameter.description)
            switch parameter.location {
            case .path:
                var pathRow = row
                pathRow.enabled = true
                draft.pathParams.append(pathRow)
            case .query: draft.query.append(row)
            case .header: draft.headers.append(row)
            case .cookie: draft.headers.append(KeyValue(key: "Cookie", value: "\(parameter.name)=\(value)", enabled: parameter.required))
            }
        }

        if let accept = operation.responses.first(where: \.isSuccess)?.preferred?.contentType {
            draft.headers.append(KeyValue(key: "Accept", value: accept))
        }

        if let body = operation.requestBody, let media = body.preferred {
            let example = ExampleGenerator.example(for: media, document: document, purpose: .request)
            let type = media.contentType.lowercased()
            if type.contains("json") {
                draft.bodyMode = .json
                draft.body = example?.serialized(pretty: true) ?? "{}"
            } else if type.contains("x-www-form-urlencoded") || type.contains("multipart") {
                draft.bodyMode = type.contains("multipart") ? .multipart : .form
                draft.form = (example?.members ?? []).map { KeyValue(key: $0.key, value: $0.value.plainText) }
            } else if type.contains("xml") {
                draft.bodyMode = .xml
                draft.body = example?.string ?? ""
            } else {
                draft.bodyMode = .text
                draft.body = example?.plainText ?? ""
            }
            if !type.contains("multipart") {
                draft.headers.append(KeyValue(key: "Content-Type", value: media.contentType))
            }
        }

        if let scheme = operation.security.lazy.compactMap({ name in spec.securitySchemes.first { $0.name == name } }).first {
            draft.auth = auth(for: scheme)
        }

        if let success = operation.responses.first(where: { $0.isSuccess && Int($0.status) != nil }) {
            draft.assertions.append(Assertion(source: .status, comparison: .equals, expected: success.status))
            if success.preferred?.schema != nil {
                draft.assertions.append(Assertion(source: .schema))
            }
        }
        return draft
    }

    static func auth(for scheme: SecurityScheme) -> AuthConfig {
        var auth = AuthConfig()
        switch scheme.kind {
        case .http where scheme.scheme == "basic":
            auth.mode = .basic
            auth.username = "{{username}}"
            auth.password = "{{password}}"
        case .apiKey:
            auth.mode = .apiKey
            auth.keyName = scheme.parameterName ?? "X-API-Key"
            auth.keyLocation = scheme.location ?? "header"
            auth.keyValue = "{{apiKey}}"
        case .oauth2 where scheme.tokenURL != nil:
            auth.mode = .oauth2
            auth.tokenURL = scheme.tokenURL ?? ""
            auth.clientID = "{{clientId}}"
            auth.clientSecret = "{{clientSecret}}"
            auth.scope = scheme.scopes.joined(separator: " ")
        default:
            auth.mode = .bearer
            auth.token = "{{token}}"
        }
        return auth
    }

    static func secretNames(for spec: APISpec) -> [String] {
        var names: [String] = []
        for scheme in spec.securitySchemes {
            let auth = auth(for: scheme)
            let referenced: [String]
            switch auth.mode {
            case .basic: referenced = ["username", "password"]
            case .apiKey: referenced = ["apiKey"]
            case .oauth2: referenced = ["clientId", "clientSecret"]
            default: referenced = ["token"]
            }
            for name in referenced where !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static func sampleValue(for parameter: APIParameter, document: SpecDocument) -> String {
        if let example = parameter.example { return example.plainText }
        guard let raw = parameter.schema else { return "" }
        let schema = Schema(raw, document: document)
        if let value = schema.example ?? schema.defaultValue ?? schema.enumValues.first { return value.plainText }
        switch schema.primaryType {
        case "integer", "number": return parameter.location == .path ? "1" : ""
        case "boolean": return "true"
        case "string":
            if let format = schema.format { return ExampleGenerator.sampleString(format: format) }
            return parameter.location == .path ? "1" : ""
        default: return ""
        }
    }
}
