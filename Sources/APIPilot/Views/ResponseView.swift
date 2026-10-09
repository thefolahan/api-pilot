import SwiftUI
import UniformTypeIdentifiers

enum ResponseTab: String, CaseIterable, Identifiable {
    case body, headers, tests, contract, request
    var id: String { rawValue }

    var title: String {
        switch self {
        case .body: return "Body"
        case .headers: return "Headers"
        case .tests: return "Tests"
        case .contract: return "Contract"
        case .request: return "Sent"
        }
    }
}

struct ResponseView: View {
    @Environment(WorkspaceStore.self) private var store
    let session: RequestSession
    @AppStorage("responseTab") private var tab: ResponseTab = .body
    @AppStorage("prettyBody") private var pretty = true

    var body: some View {
        VStack(spacing: 0) {
            if let result = session.result {
                summary(result)
                Divider()
                content(result)
            } else if session.isSending {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = session.error {
                VStack(spacing: 10) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.orange)
                    Text("The request did not complete").font(.headline)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(symbol: "paperplane", title: "No response yet", message: "Press ⌘↩ to send. The response is checked against the spec automatically.")
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func summary(_ result: HTTPResult) -> some View {
        HStack(spacing: 12) {
            StatusPill(code: String(result.status), text: result.statusText)
            Label(result.duration.millisecondText, systemImage: "clock")
            Label(result.body.count.byteText, systemImage: "doc")
            contractBadge
            if !session.assertionResults.isEmpty {
                let failed = session.assertionResults.count - session.passedCount
                Label("\(session.passedCount)/\(session.assertionResults.count) tests",
                      systemImage: failed == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(failed == 0 ? .green : .red)
                    .onTapGesture { tab = .tests }
            }
            Spacer()
            if session.isSending { ProgressView().controlSize(.small) }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var contractBadge: some View {
        if session.schemaChecked {
            if session.schemaIssues.isEmpty {
                Label("Matches spec", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    .onTapGesture { tab = .contract }
            } else {
                Label("\(session.schemaIssues.count) spec mismatch\(session.schemaIssues.count == 1 ? "" : "es")",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .onTapGesture { tab = .contract }
            }
        }
    }

    @ViewBuilder private func content(_ result: HTTPResult) -> some View {
        HStack {
            TabStrip(tabs: ResponseTab.allCases, selection: $tab, title: \.title) { tab in
                switch tab {
                case .headers: return "\(result.headers.count)"
                case .tests: return session.assertionResults.isEmpty ? nil : "\(session.passedCount)/\(session.assertionResults.count)"
                case .contract: return session.schemaChecked ? (session.schemaIssues.isEmpty ? "✓" : "\(session.schemaIssues.count)") : nil
                default: return nil
                }
            }
            Spacer()
            if tab == .body {
                if result.json != nil {
                    Picker("", selection: $pretty) {
                        Text("Pretty").tag(true)
                        Text("Raw").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy the body")
                Button {
                    saveBody(result)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Save the body to a file")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        Divider()
        Group {
            switch tab {
            case .body: BodyViewer(result: result, pretty: pretty)
            case .headers: HeaderList(headers: result.headers)
            case .tests: TestResults(results: session.assertionResults)
            case .contract: ContractView(session: session, result: result)
            case .request: SentRequestView(request: session.resolved)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func saveBody(_ result: HTTPResult) {
        let panel = NSSavePanel()
        let ext = result.contentType.contains("json") ? "json" : result.contentType.contains("html") ? "html" : result.isImage ? (result.contentType.components(separatedBy: "/").last ?? "png") : "txt"
        panel.nameFieldStringValue = "response." + ext
        if panel.runModal() == .OK, let url = panel.url {
            try? result.body.write(to: url)
        }
    }
}

private struct BodyViewer: View {
    let result: HTTPResult
    let pretty: Bool

    var body: some View {
        if result.isImage, let image = NSImage(data: result.body) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if result.body.isEmpty {
            EmptyState(symbol: "doc", title: "Empty body")
        } else {
            CodeTextView(text: .constant(text), isEditable: false, highlights: result.json != nil || result.contentType.contains("json"))
        }
    }

    private var text: String {
        if pretty, let text = result.prettyText { return text }
        return result.text
    }
}

private struct HeaderList: View {
    let headers: [(name: String, value: String)]

    var body: some View {
        ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    GridRow {
                        Text(header.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(header.value)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TestResults: View {
    let results: [AssertionResult]

    var body: some View {
        if results.isEmpty {
            EmptyState(symbol: "checklist", title: "No tests", message: "Add assertions in the Tests tab of the request.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { result in
                        AssertionResultRow(result: result)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct AssertionResultRow: View {
    let result: AssertionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.passed ? .green : .red)
                Text(result.assertion.summary).font(.callout)
                Spacer()
                Text(result.actual)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ForEach(result.issues.prefix(20)) { issue in
                Text("\(issue.path)  \(issue.message)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
            }
        }
    }
}

private struct ContractView: View {
    @Environment(WorkspaceStore.self) private var store
    let session: RequestSession
    let result: HTTPResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let operation = store.operation(for: session.draft) {
                    let documented = operation.response(for: result.status)
                    HStack(spacing: 8) {
                        MethodBadge(method: operation.method)
                        Text(operation.path).font(.system(size: 12.5, design: .monospaced))
                        Text("returned \(result.status)").foregroundStyle(.secondary)
                    }
                    if let documented {
                        Text("Documented as \(documented.status): \(documented.description)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let note = session.schemaNote {
                        Label(note, systemImage: "info.circle").foregroundStyle(.secondary)
                    } else if session.schemaIssues.isEmpty {
                        Label("The response matches the schema in the spec.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("The response does not match the spec in \(session.schemaIssues.count) place\(session.schemaIssues.count == 1 ? "" : "s").",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(session.schemaIssues) { issue in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(issue.path)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    Text(issue.message).font(.callout).foregroundStyle(.secondary)
                                }
                                .textSelection(.enabled)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.07)))
                    }
                } else {
                    EmptyState(symbol: "seal", title: "Not linked to the spec",
                               message: "Requests opened from an endpoint in the sidebar are checked against its documented responses.")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SentRequestView: View {
    let request: ResolvedRequest?

    var body: some View {
        if let request {
            CodeTextView(text: .constant(raw(request)), isEditable: false, highlights: true)
        } else {
            EmptyState(symbol: "arrow.up.doc", title: "Nothing sent yet")
        }
    }

    private func raw(_ request: ResolvedRequest) -> String {
        var lines = ["\(request.method) \(request.url.absoluteString)"]
        lines += request.headers.map { "\($0.name): \($0.value)" }
        if let body = request.bodyText, !body.isEmpty { lines += ["", body] }
        return lines.joined(separator: "\n")
    }
}
