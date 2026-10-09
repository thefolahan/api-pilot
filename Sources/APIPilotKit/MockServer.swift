import Foundation
import Network

public struct MockLogEntry: Identifiable {
    public let id = UUID()
    public let date = Date()
    public let method: String
    public let path: String
    public let status: Int
    public let operation: String?
    public let note: String?
}

public final class MockServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.thefolahan.apipilot.mock")
    private var spec: APISpec
    private var routes: [(operation: APIOperation, regex: NSRegularExpression)] = []
    private var basePaths: [String] = []
    public var onLog: ((MockLogEntry) -> Void)?
    public var onStateChange: ((Bool, String?) -> Void)?

    public init(spec: APISpec) {
        self.spec = spec
        rebuild()
    }

    public func update(spec: APISpec) {
        queue.async {
            self.spec = spec
            self.rebuild()
        }
    }

    private func rebuild() {
        routes = spec.operations.compactMap { operation in
            var pattern = NSRegularExpression.escapedPattern(for: operation.path)
            pattern = pattern.replacingOccurrences(of: #"\\\{[^}]+\\\}"#, with: "[^/]+", options: .regularExpression)
            pattern = pattern.replacingOccurrences(of: #"\{[^}]+\}"#, with: "[^/]+", options: .regularExpression)
            guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "/?$") else { return nil }
            return (operation, regex)
        }
        basePaths = spec.servers.compactMap { URL(string: $0.url)?.path }.filter { !$0.isEmpty && $0 != "/" }
    }

    public func start(port: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onStateChange?(true, nil)
            case .failed(let error): self?.onStateChange?(false, Self.describe(error))
            case .cancelled: self?.onStateChange?(false, nil)
            default: break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private static func describe(_ error: NWError) -> String {
        if case .posix(let code) = error { return String(cString: strerror(code.rawValue)) + "." }
        return error.localizedDescription
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = MockHTTPRequest(buffer) {
                let response = self.respond(to: request)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else if complete || error != nil || buffer.count > 10_000_000 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: MockHTTPRequest) -> Data {
        if request.method == "OPTIONS" {
            return Self.encode(status: 204, headers: [], body: Data())
        }
        let candidates = [request.path] + basePaths.compactMap { base in
            request.path.hasPrefix(base) ? String(request.path.dropFirst(base.count)) : nil
        }
        var pathMatched = false
        for path in candidates {
            let range = NSRange(path.startIndex..., in: path)
            for route in routes where route.regex.firstMatch(in: path, range: range) != nil {
                pathMatched = true
                guard route.operation.method == request.method else { continue }
                return respond(to: request, operation: route.operation)
            }
        }
        let status = pathMatched ? 405 : 404
        let message = pathMatched
            ? "\(request.method) is not documented for \(request.path)"
            : "No operation in the spec matches \(request.path)"
        log(request, status: status, operation: nil, note: message)
        return Self.json(status: status, .object([JSONMember(key: "error", value: .string(message))]))
    }

    private func respond(to request: MockHTTPRequest, operation: APIOperation) -> Data {
        if let body = operation.requestBody, let schema = body.preferred?.schema,
           body.preferred?.contentType.contains("json") == true {
            if request.body.isEmpty {
                if body.required {
                    log(request, status: 422, operation: operation, note: "Missing request body")
                    return Self.json(status: 422, .object([JSONMember(key: "error", value: .string("The request body is required."))]))
                }
            } else if let json = try? JSONParser.parse(request.body) {
                let issues = SchemaValidator.validate(json, against: Schema(schema, document: spec.document))
                if !issues.isEmpty {
                    log(request, status: 422, operation: operation, note: "\(issues.count) body problem(s)")
                    let list = JSONValue.array(issues.map { .string("\($0.path) \($0.message)") })
                    return Self.json(status: 422, .object([
                        JSONMember(key: "error", value: .string("The request body does not match the schema.")),
                        JSONMember(key: "issues", value: list)
                    ]))
                }
            } else {
                log(request, status: 400, operation: operation, note: "Body is not valid JSON")
                return Self.json(status: 400, .object([JSONMember(key: "error", value: .string("The request body is not valid JSON."))]))
            }
        }

        var chosen = operation.responses.first { $0.isSuccess && Int($0.status) != nil } ?? operation.responses.first
        if let prefer = request.header("Prefer"), let range = prefer.range(of: #"code=(\d{3})"#, options: .regularExpression) {
            let code = String(prefer[range].dropFirst(5))
            chosen = operation.responses.first { $0.status == code } ?? chosen
        }
        let status = chosen.flatMap { Int($0.status) } ?? 200
        log(request, status: status, operation: operation, note: nil)
        guard let media = chosen?.preferred,
              let example = ExampleGenerator.example(for: media, document: spec.document, purpose: .response) else {
            return Self.encode(status: status, headers: [], body: Data())
        }
        if media.contentType.contains("json") {
            return Self.encode(status: status, headers: [("Content-Type", media.contentType)], body: Data(example.serialized(pretty: true).utf8))
        }
        return Self.encode(status: status, headers: [("Content-Type", media.contentType)], body: Data(example.plainText.utf8))
    }

    private func log(_ request: MockHTTPRequest, status: Int, operation: APIOperation?, note: String?) {
        let entry = MockLogEntry(method: request.method, path: request.target, status: status, operation: operation?.id, note: note)
        DispatchQueue.main.async { self.onLog?(entry) }
    }

    private static func json(status: Int, _ value: JSONValue) -> Data {
        encode(status: status, headers: [("Content-Type", "application/json")], body: Data(value.serialized(pretty: true).utf8))
    }

    private static func encode(status: Int, headers: [(String, String)], body: Data) -> Data {
        let reason = HTTPStatus.reason(status)
        var lines = ["HTTP/1.1 \(status) \(reason)"]
        let all = headers + [
            ("Content-Length", String(body.count)),
            ("Connection", "close"),
            ("Access-Control-Allow-Origin", "*"),
            ("Access-Control-Allow-Headers", "*"),
            ("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD"),
            ("X-Powered-By", "API Pilot mock")
        ]
        lines += all.map { "\($0.0): \($0.1)" }
        var data = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        data.append(body)
        return data
    }
}

struct MockHTTPRequest {
    let method: String
    let target: String
    let path: String
    let headers: [(String, String)]
    let body: Data

    init?(_ data: Data) {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<separator.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0]).uppercased()
        target = String(parts[1])
        path = target.split(separator: "?", maxSplits: 1).first.map(String.init)?.removingPercentEncoding ?? target
        headers = lines.compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                    String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
        let length = Int(headers.first { $0.0.lowercased() == "content-length" }?.1 ?? "0") ?? 0
        let bodyStart = separator.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return nil }
        body = data[bodyStart..<(bodyStart + length)]
    }

    func header(_ name: String) -> String? {
        headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }
}
