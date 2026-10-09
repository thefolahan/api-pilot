import SwiftUI

struct RequestView: View {
    @Environment(WorkspaceStore.self) private var store
    @Bindable var session: RequestSession
    @State private var savingName: String?

    var body: some View {
        VStack(spacing: 0) {
            URLBar(session: session, onSave: save)
            Divider()
            VSplitView {
                RequestEditor(session: session)
                    .frame(minHeight: 170, idealHeight: 300)
                ResponseView(session: session)
                    .frame(minHeight: 180, idealHeight: 380)
            }
        }
        .sheet(isPresented: Binding(get: { savingName != nil }, set: { if !$0 { savingName = nil } })) {
            NameSheet(title: "Save request", prompt: "Saved requests live in .apipilot/requests so you can commit them with your code.",
                      name: savingName ?? "", action: "Save") { name in
                store.save(session, as: name)
            }
        }
    }

    private func save() {
        if session.savedID != nil {
            store.save(session)
        } else {
            savingName = session.draft.name
        }
    }
}

private struct URLBar: View {
    @Environment(WorkspaceStore.self) private var store
    @Bindable var session: RequestSession
    let onSave: () -> Void
    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Menu {
                        ForEach(methods, id: \.self) { method in
                            Button(method) { session.draft.method = method }
                        }
                    } label: {
                        Text(session.draft.method)
                            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Palette.method(session.draft.method))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    Divider().frame(height: 18)
                    TextField("https://api.example.com/resource", text: $session.draft.url)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .onSubmit { store.send(session) }
                }
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))

                if session.isSending {
                    Button {
                        store.cancel(session)
                    } label: {
                        Text("Cancel").frame(width: 64)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Button {
                        store.send(session)
                    } label: {
                        Label("Send", systemImage: "paperplane.fill").frame(width: 64)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Send the request (⌘↩)")
                }
                Button(action: onSave) {
                    Image(systemName: session.isDirty ? "square.and.arrow.down.fill" : "square.and.arrow.down")
                }
                .controlSize(.large)
                .keyboardShortcut("s", modifiers: .command)
                .help(session.savedID == nil ? "Save as a request in this workspace (⌘S)" : "Save changes (⌘S)")
            }
            HStack(spacing: 6) {
                if let preview = store.resolvedPreview(session.draft) {
                    Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(preview.url.absoluteString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if !preview.unresolved.isEmpty {
                        Label("Not set: " + preview.unresolved.joined(separator: ", "), systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                } else {
                    let missing = Interpolator.references(in: session.draft.url).filter { store.variables[$0] == nil }
                    Label(missing.isEmpty ? "The URL is not complete yet" : "Set \(missing.joined(separator: ", ")) in the environment",
                          systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if session.isDirty {
                    Text("Edited").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

enum RequestTab: String, CaseIterable, Identifiable {
    case params, headers, body, auth, tests, code
    var id: String { rawValue }

    var title: String {
        switch self {
        case .params: return "Params"
        case .headers: return "Headers"
        case .body: return "Body"
        case .auth: return "Auth"
        case .tests: return "Tests"
        case .code: return "Code"
        }
    }
}

private struct RequestEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @Bindable var session: RequestSession
    @AppStorage("requestTab") private var tab: RequestTab = .params

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TabStrip(tabs: RequestTab.allCases, selection: $tab, title: \.title) { tab in
                    let draft = session.draft
                    switch tab {
                    case .params:
                        let count = draft.query.filter { $0.enabled && !$0.key.isEmpty }.count + draft.pathParams.count
                        return count > 0 ? "\(count)" : nil
                    case .headers:
                        let count = draft.headers.filter { $0.enabled && !$0.key.isEmpty }.count
                        return count > 0 ? "\(count)" : nil
                    case .body: return draft.bodyMode == .none ? nil : draft.bodyMode.label
                    case .auth: return draft.auth.mode == .none ? nil : "•"
                    case .tests:
                        let count = draft.assertions.filter(\.enabled).count
                        return count > 0 ? "\(count)" : nil
                    case .code: return nil
                    }
                }
                Spacer()
                if store.operation(for: session.draft) != nil {
                    Button("Reset from spec") { store.resetDraft(session) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("Rebuild this request from the current spec, with fresh examples")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            Group {
                switch tab {
                case .params: ParamsTab(draft: $session.draft)
                case .headers:
                    ScrollView {
                        KeyValueEditor(rows: $session.draft.headers, keyPlaceholder: "Header", valuePlaceholder: "Value")
                    }
                case .body: BodyTab(session: session)
                case .auth: AuthTab(auth: $session.draft.auth)
                case .tests: TestsTab(draft: $session.draft)
                case .code: CodeTab(draft: session.draft)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct ParamsTab: View {
    @Binding var draft: RequestDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !draft.pathParams.isEmpty {
                    SectionLabel("Path").padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
                    KeyValueEditor(rows: $draft.pathParams, lockedKeys: true)
                }
                SectionLabel("Query").padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
                KeyValueEditor(rows: $draft.query, keyPlaceholder: "Parameter", valuePlaceholder: "Value")
            }
        }
    }
}

private struct BodyTab: View {
    @Environment(WorkspaceStore.self) private var store
    @Bindable var session: RequestSession
    @State private var formatError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $session.draft.bodyMode) {
                    ForEach(BodyMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if let formatError {
                    Text(formatError).font(.caption).foregroundStyle(.orange).lineLimit(1)
                }
                if session.draft.bodyMode == .json {
                    Button("Format") { format() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .keyboardShortcut("f", modifiers: [.command, .shift])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            switch session.draft.bodyMode {
            case .none:
                EmptyState(symbol: "doc", title: "This request has no body")
            case .form, .multipart:
                ScrollView {
                    KeyValueEditor(rows: $session.draft.form, keyPlaceholder: "Field",
                                   valuePlaceholder: session.draft.bodyMode == .multipart ? "Value, or @/path/to/file" : "Value")
                }
            case .json, .xml, .text:
                CodeTextView(text: $session.draft.body, highlights: session.draft.bodyMode == .json)
            }
        }
        .onChange(of: session.draft.body) { formatError = nil }
    }

    private func format() {
        do {
            let value = try JSONParser.parse(session.draft.body)
            session.draft.body = value.serialized(pretty: true)
            formatError = nil
        } catch {
            formatError = "Not valid JSON: \(error.localizedDescription)"
        }
    }
}

private struct AuthTab: View {
    @Binding var auth: AuthConfig

    var body: some View {
        ScrollView {
            Form {
                Picker("Type", selection: $auth.mode) {
                    ForEach(AuthConfig.Mode.allCases) { Text($0.label).tag($0) }
                }
                switch auth.mode {
                case .none:
                    Text("No credentials are sent with this request.").foregroundStyle(.secondary)
                case .bearer:
                    TextField("Token", text: $auth.token)
                case .basic:
                    TextField("Username", text: $auth.username)
                    TextField("Password", text: $auth.password)
                case .apiKey:
                    TextField("Key name", text: $auth.keyName)
                    TextField("Value", text: $auth.keyValue)
                    Picker("Send in", selection: $auth.keyLocation) {
                        Text("Header").tag("header")
                        Text("Query").tag("query")
                        Text("Cookie").tag("cookie")
                    }
                case .oauth2:
                    TextField("Token URL", text: $auth.tokenURL)
                    TextField("Client ID", text: $auth.clientID)
                    TextField("Client secret", text: $auth.clientSecret)
                    TextField("Scope", text: $auth.scope)
                    Text("API Pilot fetches a token with the client credentials grant before sending, and reuses it until it expires.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if auth.mode != .none {
                    Text("Use {{variables}} for secrets and keep the values in an environment, where secret variables are stored in your Keychain instead of the repository.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .font(.system(size: 12.5, design: .monospaced))
            .frame(maxWidth: 620)
        }
    }
}

private struct TestsTab: View {
    @Binding var draft: RequestDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("Assertions")
                    Spacer()
                    Button {
                        draft.assertions.append(Assertion(source: .jsonPath, target: "$.id", comparison: .exists))
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                ForEach($draft.assertions) { $assertion in
                    AssertionRow(assertion: $assertion) {
                        draft.assertions.removeAll { $0.id == assertion.id }
                    }
                }
                if draft.assertions.isEmpty {
                    Text("Assertions run after every send and in the collection runner.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    SectionLabel("Save to environment")
                    Spacer()
                    Button {
                        draft.captures.append(Capture(variable: "token", path: "$.token"))
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.top, 14)
                ForEach($draft.captures) { $capture in
                    HStack(spacing: 8) {
                        Toggle("", isOn: $capture.enabled).labelsHidden()
                        TextField("variable", text: $capture.variable).frame(width: 130)
                        Text("from").foregroundStyle(.secondary)
                        Picker("", selection: $capture.source) {
                            ForEach(Capture.Source.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        TextField(capture.source == .jsonPath ? "$.data.token" : "Header name", text: $capture.path)
                        Button {
                            draft.captures.removeAll { $0.id == capture.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                }
                if draft.captures.isEmpty {
                    Text("Copy a value from the response into a variable, such as a login token, so the next request can use it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }
}

private struct AssertionRow: View {
    @Binding var assertion: Assertion
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $assertion.enabled).labelsHidden()
            Picker("", selection: $assertion.source) {
                ForEach(Assertion.Source.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 140)
            if assertion.source.needsTarget {
                TextField(assertion.source == .jsonPath ? "$.items[0].id" : "Header name", text: $assertion.target)
                    .frame(minWidth: 120)
            }
            if assertion.source.needsComparison {
                Picker("", selection: $assertion.comparison) {
                    ForEach(Assertion.Comparison.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
                if assertion.comparison != .exists {
                    TextField("Expected", text: $assertion.expected)
                }
            } else {
                Text("Checks the body against the response schema in the spec")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12, design: .monospaced))
        .opacity(assertion.enabled ? 1 : 0.55)
    }
}

private struct CodeTab: View {
    @Environment(WorkspaceStore.self) private var store
    let draft: RequestDraft
    @AppStorage("codeLanguage") private var language: CodeLanguage = .curl
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $language) {
                    ForEach(CodeLanguage.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            CodeTextView(text: .constant(code), isEditable: false, highlights: false)
        }
    }

    private var code: String {
        guard let request = store.resolvedPreview(draft) else {
            return "Complete the URL and set its variables to generate code."
        }
        return CodeGenerator.code(for: request, language: language)
    }
}

struct NameSheet: View {
    let title: String
    var prompt: String?
    @State var name: String
    let action: String
    let onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(title: String, prompt: String? = nil, name: String, action: String, onCommit: @escaping (String) -> Void) {
        self.title = title
        self.prompt = prompt
        _name = State(initialValue: name)
        self.action = action
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if let prompt {
                Text(prompt).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}
