import Foundation

public struct ResolvedRequest {
    public var method: String
    public var url: URL
    public var headers: [(name: String, value: String)]
    public var body: Data?
    public var unresolved: [String]

    public init(method: String, url: URL, headers: [(name: String, value: String)], body: Data? = nil, unresolved: [String] = []) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.unresolved = unresolved
    }

    public func header(_ name: String) -> String? {
        headers.last { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var bodyText: String? {
        body.flatMap { String(data: $0, encoding: .utf8) }
    }
}

public enum RequestError: Error, LocalizedError {
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            if url.contains("{{") {
                return "The URL \"\(url)\" still has variables that are not set in the active environment."
            }
            return "\"\(url)\" is not a valid URL. Check the address and the baseUrl variable."
        }
    }
}

public enum RequestBuilder {
    public static let userAgent = "APIPilot/1.0"

    public static func build(_ draft: RequestDraft, variables: [String: String], accessToken: String? = nil) throws -> ResolvedRequest {
        var unresolved = Set<String>()
        let resolve: (String) -> String = { Interpolator.apply($0, variables: variables, unresolved: &unresolved) }

        var address = resolve(draft.url.trimmingCharacters(in: .whitespaces))
        for parameter in draft.pathParams where parameter.enabled && !parameter.key.isEmpty {
            let value = resolve(parameter.value)
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
            address = address.replacingOccurrences(of: "{\(parameter.key)}", with: encoded)
            address = address.replacingOccurrences(of: ":\(parameter.key)", with: encoded)
        }
        if !address.contains("://"), !address.isEmpty, !address.hasPrefix("{{") {
            address = (address.hasPrefix("localhost") || address.hasPrefix("127.") ? "http://" : "https://") + address
        }

        var queryItems: [URLQueryItem] = []
        for item in draft.query where item.enabled && !item.key.isEmpty {
            queryItems.append(URLQueryItem(name: resolve(item.key), value: resolve(item.value)))
        }

        var headers: [(name: String, value: String)] = []
        for header in draft.headers where header.enabled && !header.key.isEmpty {
            headers.append((resolve(header.key), resolve(header.value)))
        }

        let auth = draft.auth
        switch auth.mode {
        case .none:
            break
        case .bearer:
            headers.append(("Authorization", "Bearer " + resolve(auth.token)))
        case .basic:
            let pair = resolve(auth.username) + ":" + resolve(auth.password)
            headers.append(("Authorization", "Basic " + Data(pair.utf8).base64EncodedString()))
        case .apiKey:
            let name = resolve(auth.keyName)
            let value = resolve(auth.keyValue)
            switch auth.keyLocation {
            case "query": queryItems.append(URLQueryItem(name: name, value: value))
            case "cookie": headers.append(("Cookie", "\(name)=\(value)"))
            default: headers.append((name, value))
            }
        case .oauth2:
            if let accessToken { headers.append(("Authorization", "Bearer " + accessToken)) }
        }

        guard var components = URLComponents(string: address), components.scheme != nil, components.host != nil else {
            throw RequestError.invalidURL(address)
        }
        if !queryItems.isEmpty {
            components.percentEncodedQueryItems = (components.percentEncodedQueryItems ?? []) + queryItems.map {
                URLQueryItem(name: encodeQuery($0.name), value: $0.value.map(encodeQuery))
            }
        }
        guard let url = components.url else { throw RequestError.invalidURL(address) }

        var body: Data?
        let hasContentType = headers.contains { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
        switch draft.bodyMode {
        case .none:
            break
        case .json, .xml, .text:
            body = Data(resolve(draft.body).utf8)
            if !hasContentType, let type = draft.bodyMode.contentType { headers.append(("Content-Type", type)) }
        case .form:
            let pairs = draft.form.filter { $0.enabled && !$0.key.isEmpty }.map {
                encodeForm(resolve($0.key)) + "=" + encodeForm(resolve($0.value))
            }
            body = Data(pairs.joined(separator: "&").utf8)
            if !hasContentType { headers.append(("Content-Type", "application/x-www-form-urlencoded")) }
        case .multipart:
            let boundary = "APIPilot" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            var data = Data()
            for field in draft.form where field.enabled && !field.key.isEmpty {
                data.append(Data("--\(boundary)\r\n".utf8))
                let value = resolve(field.value)
                if value.hasPrefix("@"), let file = try? Data(contentsOf: URL(fileURLWithPath: String(value.dropFirst()))) {
                    let filename = (value as NSString).lastPathComponent
                    data.append(Data("Content-Disposition: form-data; name=\"\(resolve(field.key))\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
                    data.append(file)
                } else {
                    data.append(Data("Content-Disposition: form-data; name=\"\(resolve(field.key))\"\r\n\r\n\(value)".utf8))
                }
                data.append(Data("\r\n".utf8))
            }
            data.append(Data("--\(boundary)--\r\n".utf8))
            body = data
            headers.removeAll { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
            headers.append(("Content-Type", "multipart/form-data; boundary=\(boundary)"))
        }

        if !headers.contains(where: { $0.name.caseInsensitiveCompare("Accept") == .orderedSame }) {
            headers.append(("Accept", "*/*"))
        }
        if !headers.contains(where: { $0.name.caseInsensitiveCompare("User-Agent") == .orderedSame }) {
            headers.append(("User-Agent", userAgent))
        }

        return ResolvedRequest(
            method: draft.method.uppercased(),
            url: url,
            headers: headers,
            body: body,
            unresolved: unresolved.sorted()
        )
    }

    private static let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))
    private static let formAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._*"))

    private static func encodeQuery(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? text
    }

    private static func encodeForm(_ text: String) -> String {
        (text.addingPercentEncoding(withAllowedCharacters: formAllowed.union(.whitespaces)) ?? text)
            .replacingOccurrences(of: " ", with: "+")
    }
}
