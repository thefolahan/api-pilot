import Foundation

public struct HTTPResult {
    public let status: Int
    public let headers: [(name: String, value: String)]
    public let body: Data
    public let duration: TimeInterval
    public let url: URL?
    public let date: Date
    public let json: JSONValue?
    public let prettyText: String?

    public init(status: Int, headers: [(name: String, value: String)], body: Data, duration: TimeInterval, url: URL?, date: Date) {
        self.status = status
        self.headers = headers
        self.body = body
        self.duration = duration
        self.url = url
        self.date = date
        json = body.isEmpty || body.count > 30_000_000 ? nil : try? JSONParser.parse(body)
        prettyText = json?.serialized(pretty: true)
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var contentType: String { header("Content-Type")?.lowercased() ?? "" }
    public var statusText: String { HTTPStatus.reason(status) }
    public var text: String { String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self) }
    public var isImage: Bool { contentType.hasPrefix("image/") }
}

public final class HTTPClient: NSObject, URLSessionTaskDelegate {
    private var session: URLSession!
    private var tokens: [String: (token: String, expiry: Date)] = [:]
    public var followRedirects = true

    public override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpCookieAcceptPolicy = .always
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public func send(_ request: ResolvedRequest) async throws -> HTTPResult {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for header in request.headers {
            urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
        }
        urlRequest.httpBody = request.body
        let start = Date()
        let (data, response) = try await session.data(for: urlRequest)
        let duration = Date().timeIntervalSince(start)
        guard let http = response as? HTTPURLResponse else {
            return HTTPResult(status: 0, headers: [], body: data, duration: duration, url: response.url, date: start)
        }
        let headers = http.allHeaderFields.compactMap { key, value -> (String, String)? in
            guard let name = key as? String else { return nil }
            return (name, "\(value)")
        }.sorted { $0.0.lowercased() < $1.0.lowercased() }
        return HTTPResult(status: http.statusCode, headers: headers, body: data, duration: duration, url: http.url, date: start)
    }

    public func accessToken(for auth: AuthConfig, variables: [String: String], forceRefresh: Bool = false) async throws -> String {
        let tokenURL = Interpolator.apply(auth.tokenURL, variables: variables)
        let clientID = Interpolator.apply(auth.clientID, variables: variables)
        let clientSecret = Interpolator.apply(auth.clientSecret, variables: variables)
        let scope = Interpolator.apply(auth.scope, variables: variables)
        let cacheKey = [tokenURL, clientID, scope].joined(separator: "|")
        if !forceRefresh, let cached = tokens[cacheKey], cached.expiry > Date() { return cached.token }

        guard let url = URL(string: tokenURL), url.scheme != nil else { throw OAuthError.message("Set a valid token URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credentials = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        var fields = ["grant_type=client_credentials", "client_id=\(clientID)", "client_secret=\(clientSecret)"]
        if !scope.isEmpty { fields.append("scope=" + (scope.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? scope)) }
        request.httpBody = Data(fields.joined(separator: "&").utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try? JSONParser.parse(data), let token = json["access_token"]?.string else {
            let detail = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw OAuthError.message("The token endpoint answered \(status) without an access_token. \(detail)")
        }
        let lifetime = json["expires_in"]?.double ?? 3600
        tokens[cacheKey] = (token, Date().addingTimeInterval(max(lifetime - 30, 30)))
        return token
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        followRedirects ? request : nil
    }
}

public enum OAuthError: Error, LocalizedError {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

public enum HTTPStatus {
    public static func reason(_ code: Int) -> String {
        switch code {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 413: return "Content Too Large"
        case 415: return "Unsupported Media Type"
        case 422: return "Unprocessable Content"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return HTTPURLResponse.localizedString(forStatusCode: code).capitalized
        }
    }
}
