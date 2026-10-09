import Foundation

enum DocsExporter {
    static func html(for spec: APISpec, examples: [String: HistoryEntry] = [:]) -> String {
        var body = ""
        body += "<header><h1>\(escape(spec.title))</h1><p class=\"meta\"><span>\(escape(spec.version))</span><span>\(escape(spec.format))</span></p>"
        if let description = spec.description { body += paragraphs(description) }
        if !spec.servers.isEmpty {
            body += "<h3>Servers</h3><ul class=\"plain\">"
            body += spec.servers.map { "<li><code>\(escape($0.url))</code> \(escape($0.description ?? ""))</li>" }.joined()
            body += "</ul>"
        }
        if !spec.securitySchemes.isEmpty {
            body += "<h3>Authentication</h3><ul class=\"plain\">"
            body += spec.securitySchemes.map { "<li><strong>\(escape($0.name))</strong> \(escape($0.summary))</li>" }.joined()
            body += "</ul>"
        }
        body += "</header>"

        var nav = ""
        for group in spec.groupedOperations {
            nav += "<h4>\(escape(group.tag))</h4><ul>"
            body += "<section><h2>\(escape(group.tag))</h2>"
            if let description = spec.tags.first(where: { $0.name == group.tag })?.description {
                body += paragraphs(description)
            }
            for operation in group.operations {
                let anchor = anchorID(operation)
                nav += "<li><a href=\"#\(anchor)\"><span class=\"m \(operation.method.lowercased())\">\(operation.method)</span>\(escape(operation.path))</a></li>"
                body += render(operation, spec: spec, anchor: anchor)
            }
            nav += "</ul>"
            body += "</section>"
        }

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(spec.title)) API reference</title>
        <style>\(style)</style>
        </head>
        <body>
        <nav>\(nav)</nav>
        <main>\(body)<footer>Generated with API Pilot.</footer></main>
        </body>
        </html>
        """
    }

    private static func render(_ operation: APIOperation, spec: APISpec, anchor: String) -> String {
        let document = spec.document
        var html = "<article id=\"\(anchor)\"\(operation.deprecated ? " class=\"deprecated\"" : "")>"
        html += "<h3><span class=\"m \(operation.method.lowercased())\">\(operation.method)</span><code>\(escape(operation.path))</code></h3>"
        if let summary = operation.summary { html += "<p class=\"summary\">\(escape(summary))</p>" }
        if let description = operation.description { html += paragraphs(description) }
        if !operation.security.isEmpty {
            html += "<p class=\"note\">Requires \(operation.security.map(escape).joined(separator: ", "))</p>"
        }
        if !operation.parameters.isEmpty {
            html += "<h4>Parameters</h4><table><tr><th>Name</th><th>In</th><th>Type</th><th>Description</th></tr>"
            for parameter in operation.parameters {
                let type = parameter.schema.map { Schema($0, document: document).typeLabel } ?? ""
                html += "<tr><td><code>\(escape(parameter.name))</code>\(parameter.required ? "<span class=\"req\">required</span>" : "")</td>"
                html += "<td>\(parameter.location.rawValue)</td><td>\(escape(type))</td><td>\(escape(parameter.description ?? ""))</td></tr>"
            }
            html += "</table>"
        }
        if let requestBody = operation.requestBody, let media = requestBody.preferred {
            html += "<h4>Request body <code class=\"type\">\(escape(media.contentType))</code></h4>"
            if let description = requestBody.description { html += paragraphs(description) }
            if let schema = media.schema { html += schemaList(Schema(schema, document: document), depth: 0) }
            if let example = ExampleGenerator.example(for: media, document: document, purpose: .request) {
                html += "<pre>\(escape(example.serialized(pretty: true)))</pre>"
            }
        }
        if !operation.responses.isEmpty {
            html += "<h4>Responses</h4>"
            for response in operation.responses {
                let kind = response.status.first.map(String.init) ?? "d"
                html += "<details\(response.isSuccess ? " open" : "")><summary><span class=\"s s\(kind)\">\(escape(response.status))</span> \(escape(response.description))</summary>"
                if let media = response.preferred {
                    if let schema = media.schema { html += schemaList(Schema(schema, document: document), depth: 0) }
                    if let example = ExampleGenerator.example(for: media, document: document, purpose: .response) {
                        html += "<pre>\(escape(example.serialized(pretty: true)))</pre>"
                    }
                }
                html += "</details>"
            }
        }
        return html + "</article>"
    }

    private static func schemaList(_ schema: Schema, depth: Int) -> String {
        var target = schema
        if schema.primaryType == "array", let items = schema.items { target = items }
        let properties = target.properties
        guard !properties.isEmpty, depth < 4 else { return "" }
        let required = target.required
        var html = "<ul class=\"schema\">"
        for (name, property) in properties {
            html += "<li><code>\(escape(name))</code> <span class=\"type\">\(escape(property.typeLabel))</span>"
            if required.contains(name) { html += "<span class=\"req\">required</span>" }
            if let description = property.description { html += "<div class=\"desc\">\(escape(description))</div>" }
            if !property.enumValues.isEmpty {
                html += "<div class=\"desc\">One of: \(property.enumValues.map { "<code>\(escape($0.plainText))</code>" }.joined(separator: " "))</div>"
            }
            html += schemaList(property, depth: depth + 1) + "</li>"
        }
        return html + "</ul>"
    }

    private static func anchorID(_ operation: APIOperation) -> String {
        operation.operationID.map(WorkspaceFiles.slug) ?? WorkspaceFiles.slug(operation.method + " " + operation.path)
    }

    private static func paragraphs(_ text: String) -> String {
        text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "<p>\(escape($0))</p>" }.joined()
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let style = """
    :root{--bg:#fbfbfd;--panel:#fff;--text:#1d1d1f;--muted:#6e6e73;--line:#e5e5ea;--code:#f2f2f7;--accent:#5b5bd6}
    @media (prefers-color-scheme:dark){:root{--bg:#161618;--panel:#1c1c1e;--text:#f5f5f7;--muted:#98989d;--line:#2c2c2e;--code:#232326;--accent:#8e8cf0}}
    *{box-sizing:border-box}body{margin:0;font:15px/1.55 -apple-system,BlinkMacSystemFont,"Inter",sans-serif;background:var(--bg);color:var(--text);display:flex}
    nav{position:sticky;top:0;height:100vh;overflow:auto;width:290px;flex:none;padding:24px 16px;border-right:1px solid var(--line);background:var(--panel)}
    nav h4{margin:18px 8px 6px;font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}
    nav ul{list-style:none;margin:0;padding:0}nav a{display:flex;gap:8px;align-items:center;padding:5px 8px;border-radius:7px;color:inherit;text-decoration:none;font:12px ui-monospace,SFMono-Regular,Menlo,monospace;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
    nav a:hover{background:var(--code)}
    main{flex:1;min-width:0;max-width:980px;padding:40px 48px}
    header h1{font-size:34px;margin:0 0 6px;letter-spacing:-.02em}.meta span{display:inline-block;margin-right:8px;padding:2px 9px;border-radius:99px;background:var(--code);color:var(--muted);font-size:12px}
    section h2{margin:48px 0 8px;font-size:24px;letter-spacing:-.01em}
    article{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:20px 24px;margin:18px 0;scroll-margin-top:16px}
    article.deprecated h3 code{text-decoration:line-through;opacity:.6}
    article h3{display:flex;gap:10px;align-items:center;margin:0 0 6px;font-size:16px}
    h4{margin:22px 0 8px;font-size:13px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}
    .summary{font-weight:600;margin:4px 0}.note{color:var(--muted);font-size:13px}
    code{font:13px ui-monospace,SFMono-Regular,Menlo,monospace}
    pre{background:var(--code);border-radius:10px;padding:14px;overflow:auto;font:12.5px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
    table{width:100%;border-collapse:collapse;font-size:14px}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{font-size:12px;color:var(--muted);font-weight:600}
    .m{display:inline-block;min-width:54px;text-align:center;padding:2px 6px;border-radius:6px;font:700 11px ui-monospace,Menlo,monospace;color:#fff;background:#8e8e93}
    .get{background:#1f9d55}.post{background:#d97706}.put{background:#2563eb}.patch{background:#7c3aed}.delete{background:#dc2626}
    .s{display:inline-block;padding:1px 8px;border-radius:6px;font:700 12px ui-monospace,Menlo,monospace;background:var(--code)}.s2{color:#1f9d55}.s3{color:#2563eb}.s4{color:#d97706}.s5{color:#dc2626}
    details{border-top:1px solid var(--line);padding:8px 0}summary{cursor:pointer}
    .req{margin-left:6px;font-size:11px;color:#dc2626}.type{color:var(--accent);font-size:12px}.desc{color:var(--muted);font-size:13px}
    ul.schema{list-style:none;padding-left:16px;border-left:2px solid var(--line);margin:6px 0}ul.schema li{margin:6px 0}ul.plain{padding-left:18px}
    footer{margin:48px 0 0;color:var(--muted);font-size:12px}
    @media (max-width:760px){nav{display:none}main{padding:24px 16px}}
    """
}
