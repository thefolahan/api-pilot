import Foundation

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

public struct KeyValue: Codable, Identifiable, Equatable, Hashable {
    public var id = UUID()
    public var enabled = true
    public var key = ""
    public var value = ""
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case enabled, key, value, note
    }

    public init(key: String = "", value: String = "", enabled: Bool = true, note: String? = nil) {
        self.key = key
        self.value = value
        self.enabled = enabled
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = container.value(.enabled, or: true)
        key = container.value(.key, or: "")
        value = container.value(.value, or: "")
        note = container.value(.note, or: nil)
    }

    public var isBlank: Bool { key.isEmpty && value.isEmpty }
}

public enum BodyMode: String, Codable, CaseIterable, Identifiable {
    case none, json, xml, text, form, multipart

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "None"
        case .json: return "JSON"
        case .xml: return "XML"
        case .text: return "Text"
        case .form: return "Form"
        case .multipart: return "Multipart"
        }
    }

    public var contentType: String? {
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

public struct AuthConfig: Codable, Equatable {
    public enum Mode: String, Codable, CaseIterable, Identifiable {
        case none, bearer, basic, apiKey, oauth2

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .none: return "No auth"
            case .bearer: return "Bearer token"
            case .basic: return "Basic auth"
            case .apiKey: return "API key"
            case .oauth2: return "OAuth 2.0 client credentials"
            }
        }
    }

    public var mode: Mode = .none
    public var token = ""
    public var username = ""
    public var password = ""
    public var keyName = "X-API-Key"
    public var keyValue = ""
    public var keyLocation = "header"
    public var tokenURL = ""
    public var clientID = ""
    public var clientSecret = ""
    public var scope = ""

    enum CodingKeys: String, CodingKey {
        case mode, token, username, password, keyName, keyValue, keyLocation, tokenURL, clientID, clientSecret, scope
    }

    public init() {}

    public init(from decoder: Decoder) throws {
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

public struct Assertion: Codable, Identifiable, Equatable {
    public enum Source: String, Codable, CaseIterable, Identifiable {
        case status, jsonPath, header, responseTime, body, schema

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .status: return "Status code"
            case .jsonPath: return "JSON value"
            case .header: return "Header"
            case .responseTime: return "Time (ms)"
            case .body: return "Body text"
            case .schema: return "Matches schema"
            }
        }

        public var needsTarget: Bool { self == .jsonPath || self == .header }
        public var needsComparison: Bool { self != .schema }
    }

    public enum Comparison: String, Codable, CaseIterable, Identifiable {
        case equals, notEquals, contains, lessThan, greaterThan, exists, matches

        public var id: String { rawValue }

        public var label: String {
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

    public var id = UUID()
    public var enabled = true
    public var source: Source = .status
    public var target = ""
    public var comparison: Comparison = .equals
    public var expected = ""

    enum CodingKeys: String, CodingKey {
        case enabled, source, target, comparison, expected
    }

    public init(source: Source = .status, target: String = "", comparison: Comparison = .equals, expected: String = "") {
        self.source = source
        self.target = target
        self.comparison = comparison
        self.expected = expected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = container.value(.enabled, or: true)
        source = container.value(.source, or: .status)
        target = container.value(.target, or: "")
        comparison = container.value(.comparison, or: .equals)
        expected = container.value(.expected, or: "")
    }

    public var summary: String {
        switch source {
        case .schema: return "Response matches the documented schema"
        case .status, .responseTime, .body:
            return "\(source.label) \(comparison.label)" + (comparison == .exists ? "" : " \(expected)")
        case .jsonPath, .header:
            return "\(source.label) \(target) \(comparison.label)" + (comparison == .exists ? "" : " \(expected)")
        }
    }
}

public struct Capture: Codable, Identifiable, Equatable {
    public enum Source: String, Codable, CaseIterable, Identifiable {
        case jsonPath, header

        public var id: String { rawValue }
        public var label: String { self == .jsonPath ? "JSON value" : "Header" }
    }

    public var id = UUID()
    public var enabled = true
    public var variable = ""
    public var source: Source = .jsonPath
    public var path = ""

    enum CodingKeys: String, CodingKey {
        case enabled, variable, source, path
    }

    public init(variable: String = "", source: Source = .jsonPath, path: String = "") {
        self.variable = variable
        self.source = source
        self.path = path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = container.value(.enabled, or: true)
        variable = container.value(.variable, or: "")
        source = container.value(.source, or: .jsonPath)
        path = container.value(.path, or: "")
    }
}

public struct RequestDraft: Codable, Equatable {
    public var name = ""
    public var operationID: String?
    public var method = "GET"
    public var url = ""
    public var pathParams: [KeyValue] = []
    public var query: [KeyValue] = []
    public var headers: [KeyValue] = []
    public var bodyMode: BodyMode = .none
    public var body = ""
    public var form: [KeyValue] = []
    public var auth = AuthConfig()
    public var assertions: [Assertion] = []
    public var captures: [Capture] = []

    enum CodingKeys: String, CodingKey {
        case name, operationID, method, url, pathParams, query, headers, bodyMode, body, form, auth, assertions, captures
    }

    public init() {}

    public init(from decoder: Decoder) throws {
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

    public var cleaned: RequestDraft {
        var copy = self
        copy.pathParams.removeAll(where: \.isBlank)
        copy.query.removeAll(where: \.isBlank)
        copy.headers.removeAll(where: \.isBlank)
        copy.form.removeAll(where: \.isBlank)
        return copy
    }
}

public struct SavedRequest: Identifiable, Equatable {
    public let id: String
    public var draft: RequestDraft

    public init(id: String, draft: RequestDraft) {
        self.id = id
        self.draft = draft
    }
}
