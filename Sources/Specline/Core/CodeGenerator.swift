import Foundation

enum CodeLanguage: String, CaseIterable, Identifiable {
    case curl, httpie, fetch, python, swift, go

    var id: String { rawValue }

    var label: String {
        switch self {
        case .curl: return "cURL"
        case .httpie: return "HTTPie"
        case .fetch: return "JavaScript"
        case .python: return "Python"
        case .swift: return "Swift"
        case .go: return "Go"
        }
    }
}

enum CodeGenerator {
    static func code(for request: ResolvedRequest, language: CodeLanguage) -> String {
        let headers = request.headers.filter { $0.name != "User-Agent" || $0.value != RequestBuilder.userAgent }
        let body = request.bodyText
        let url = request.url.absoluteString
        switch language {
        case .curl:
            var lines = ["curl -X \(request.method) \(shell(url))"]
            lines += headers.map { "  -H \(shell("\($0.name): \($0.value)"))" }
            if let body, !body.isEmpty { lines.append("  --data-raw \(shell(body))") }
            return lines.joined(separator: " \\\n")
        case .httpie:
            var parts = ["http \(request.method) \(shell(url))"]
            parts += headers.map { shell("\($0.name):\($0.value)") }
            let command = parts.joined(separator: " \\\n  ")
            if let body, !body.isEmpty { return "printf %s \(shell(body)) | " + command }
            return command
        case .fetch:
            var options = ["  method: \(js(request.method))"]
            if !headers.isEmpty {
                options.append("  headers: {\n" + headers.map { "    \(js($0.name)): \(js($0.value))" }.joined(separator: ",\n") + "\n  }")
            }
            if let body, !body.isEmpty { options.append("  body: \(js(body))") }
            return """
            const response = await fetch(\(js(url)), {
            \(options.joined(separator: ",\n"))
            });
            const data = await response.text();
            console.log(response.status, data);
            """
        case .python:
            var lines = ["import requests", "", "response = requests.request(", "    \(py(request.method)),", "    \(py(url)),"]
            if !headers.isEmpty {
                lines.append("    headers={")
                lines += headers.map { "        \(py($0.name)): \(py($0.value))," }
                lines.append("    },")
            }
            if let body, !body.isEmpty { lines.append("    data=\(py(body)).encode(\"utf-8\"),") }
            lines += [")", "print(response.status_code, response.text)"]
            return lines.joined(separator: "\n")
        case .swift:
            var lines = [
                "var request = URLRequest(url: URL(string: \(swift(url)))!)",
                "request.httpMethod = \(swift(request.method))"
            ]
            lines += headers.map { "request.setValue(\(swift($0.value)), forHTTPHeaderField: \(swift($0.name)))" }
            if let body, !body.isEmpty { lines.append("request.httpBody = Data(\(swift(body)).utf8)") }
            lines += [
                "",
                "let (data, response) = try await URLSession.shared.data(for: request)",
                "print((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))"
            ]
            return lines.joined(separator: "\n")
        case .go:
            let hasBody = !(body ?? "").isEmpty
            var lines = [
                "package main", "", "import (", "\t\"fmt\"", "\t\"io\"", "\t\"net/http\""
            ]
            if hasBody { lines.append("\t\"strings\"") }
            lines += [")", "", "func main() {"]
            lines.append(hasBody
                ? "\tbody := strings.NewReader(\(go(body ?? "")))\n\treq, _ := http.NewRequest(\(go(request.method)), \(go(url)), body)"
                : "\treq, _ := http.NewRequest(\(go(request.method)), \(go(url)), nil)")
            lines += headers.map { "\treq.Header.Set(\(go($0.name)), \(go($0.value)))" }
            lines += [
                "\tres, err := http.DefaultClient.Do(req)",
                "\tif err != nil {", "\t\tpanic(err)", "\t}",
                "\tdefer res.Body.Close()",
                "\tdata, _ := io.ReadAll(res.Body)",
                "\tfmt.Println(res.StatusCode, string(data))",
                "}"
            ]
            return lines.joined(separator: "\n")
        }
    }

    private static func shell(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func js(_ text: String) -> String { JSONValue.quote(text) }
    private static func py(_ text: String) -> String { JSONValue.quote(text) }
    private static func go(_ text: String) -> String { JSONValue.quote(text) }

    private static func swift(_ text: String) -> String {
        JSONValue.quote(text).replacingOccurrences(of: "\\/", with: "/")
    }
}
