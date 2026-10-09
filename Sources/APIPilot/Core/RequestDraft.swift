import Foundation

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

struct KeyValue: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var enabled = true
    var key = ""
    var value = ""
    var note: String?

    enum CodingKeys: String, CodingKey {
        case enabled, key, value, note
    }

    init(key: String = "", value: String = "", enabled: Bool = true, note: String? = nil) {
        self.key = key
        self.value = value
        self.enabled = enabled
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = container.value(.enabled, or: true)
        key = container.value(.key, or: "")
        value = container.value(.value, or: "")
        note = container.value(.note, or: nil)
    }

    var isBlank: Bool { key.isEmpty && value.isEmpty }
}

enum BodyMode: String, Codable, CaseIterable, Identifiable {
    case none, json, xml, text, form, multipart

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .json: return "JSON"
        case .xml: return "XML"
        case .text: return "Text"
        case .form: return "Form"
        case .multipart: return "Multipart"
        }
    }

    var contentType: String? {
        switch self {
        case .none: return nil
        case .json: return "application/json"
        case .xml: return "application/xml"
        case .text: return "text/plain"
        case .form: return "application/x-www-form-urlencoded"
        case .multipart: return "multipart/form-data"
        }
    }
}

struct AuthConfig: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case none, bearer, basic, apiKey, oauth2

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "No auth"
            case .bearer: return "Bearer token"
            case .basic: return "Basic auth"
            case .apiKey: return "API key"
            case .oauth2: return "OAuth 2.0 client credentials"
            }
        }
    }

    var mode: Mode = .none
    var token = ""
    var username = ""
    var password = ""
    var keyName = "X-API-Key"
    var keyValue = ""
    var keyLocation = "header"
    var tokenURL = ""
    var clientID = ""
    var clientSecret = ""
    var scope = ""

    enum CodingKeys: String, CodingKey {
        case mode, token, username, password, keyName, keyValue, keyLocation, tokenURL, clientID, clientSecret, scope
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = container.value(.mode, or: .none)
        token = container.value(.token, or: "")
        username = container.value(.username, or: "")
        password = container.value(.password, or: "")
        keyName = container.value(.keyName, or: "X-API-Key")
        keyValue = container.value(.keyValue, or: "")
        keyLocation = container.value(.keyLocation, or: "header")
        tokenURL = container.value(.tokenURL, or: "")
        clientID = container.value(.clientID, or: "")
        clientSecret = container.value(.clientSecret, or: "")
        scope = container.value(.scope, or: "")
    }
}

struct Assertion: Codable, Identifiable, Equatable {
    enum Source: String, Codable, CaseIterable, Identifiable {
        case status, jsonPath, header, responseTime, body, schema

        var id: String { rawValue }

        var label: String {
            switch self {
            case .status: return "Status code"
            case .jsonPath: return "JSON value"
            case .header: return "Header"
            case .responseTime: return "Time (ms)"
            case .body: return "Body text"
            case .schema: return "Matches schema"
            }
        }

        var needsTarget: Bool { self == .jsonPath || self == .header }
        var needsComparison: Bool { self != .schema }
    }

    enum Comparison: String, Codable, CaseIterable, Identifiable {
        case equals, notEquals, contains, lessThan, greaterThan, exists, matches

        var id: String { rawValue }

        var label: String {
            switch self {
            case .equals: return "equals"
            case .notEquals: return "does not equal"
            case .contains: return "contains"
            case .lessThan: return "is less than"
            case .greaterThan: return "is greater than"
            case .exists: return "exists"
            case .matches: return "matches regex"
            }
        }
    }

    var id = UUID()
    var enabled = true
    var source: Source = .status
    var target = ""
    var comparison: Comparison = .equals
    var expected = ""

    enum CodingKeys: String, CodingKey {
        case enabled, source, target, comparison, expected
    }

    init(source: Source = .status, target: String = "", comparison: Comparison = .equals, expected: String = "") {
        self.source = source
        self.target = target
        self.comparison = comparison
        self.expected = expected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = container.value(.enabled, or: true)
        source = container.value(.source, or: .status)
        target = container.value(.target, or: "")
        comparison = container.value(.comparison, or: .equals)
        expected = container.value(.expected, or: "")
    }

    var summary: String {
        switch source {
        case .schema: return "Response matches the documented schema"
        case .status, .responseTime, .body:
            return "\(source.label) \(comparison.label)" + (comparison == .exists ? "" : " \(expected)")
        case .jsonPath, .header:
            return "\(source.label) \(target) \(comparison.label)" + (comparison == .exists ? "" : " \(expected)")
        }
    }
}

struct Capture: Codable, Identifiable, Equatable {
    enum Source: String, Codable, CaseIterable, Identifiable {
        case jsonPath, header

        var id: String { rawValue }
        var label: String { self == .jsonPath ? "JSON value" : "Header" }
    }

    var id = UUID()
    var enabled = true
    var variable = ""
    var source: Source = .jsonPath
    var path = ""

    enum CodingKeys: String, CodingKey {
        case enabled, variable, source, path
    }

    init(variable: String = "", source: Source = .jsonPath, path: String = "") {
        self.variable = variable
        self.source = source
        self.path = path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = container.value(.enabled, or: true)
        variable = container.value(.variable, or: "")
        source = container.value(.source, or: .jsonPath)
        path = container.value(.path, or: "")
    }
}

struct RequestDraft: Codable, Equatable {
    var name = ""
    var operationID: String?
    var method = "GET"
    var url = ""
    var pathParams: [KeyValue] = []
    var query: [KeyValue] = []
    var headers: [KeyValue] = []
    var bodyMode: BodyMode = .none
    var body = ""
    var form: [KeyValue] = []
    var auth = AuthConfig()
    var assertions: [Assertion] = []
    var captures: [Capture] = []

    enum CodingKeys: String, CodingKey {
        case name, operationID, method, url, pathParams, query, headers, bodyMode, body, form, auth, assertions, captures
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.value(.name, or: "")
        operationID = container.value(.operationID, or: nil)
        method = container.value(.method, or: "GET")
        url = container.value(.url, or: "")
        pathParams = container.value(.pathParams, or: [])
        query = container.value(.query, or: [])
        headers = container.value(.headers, or: [])
        bodyMode = container.value(.bodyMode, or: .none)
        body = container.value(.body, or: "")
        form = container.value(.form, or: [])
        auth = container.value(.auth, or: AuthConfig())
        assertions = container.value(.assertions, or: [])
        captures = container.value(.captures, or: [])
    }

    var cleaned: RequestDraft {
        var copy = self
        copy.pathParams.removeAll(where: \.isBlank)
        copy.query.removeAll(where: \.isBlank)
        copy.headers.removeAll(where: \.isBlank)
        copy.form.removeAll(where: \.isBlank)
        return copy
    }
}

struct SavedRequest: Identifiable, Equatable {
    let id: String
    var draft: RequestDraft
}
