import AppKit
import Observation

@Observable
@MainActor
final class WorkspaceStore {
    static let mockEnvironmentID = "__mock__"

    let files: WorkspaceFiles
    private(set) var spec: APISpec
    var specError: String?
    var selection: SidebarSelection? = .overview {
        didSet { prepareSession() }
    }
    var environments: [APIEnvironment] = []
    var activeEnvironmentID: String? {
        didSet { UserDefaults.standard.set(activeEnvironmentID, forKey: "environment:" + files.specURL.path) }
    }
    private(set) var savedRequests: [SavedRequest] = []
    private(set) var history: [HistoryEntry] = []
    private(set) var sessions: [SidebarSelection: RequestSession] = [:]
    var notice: String?

    var mockPort: UInt16 = UInt16(UserDefaults.standard.integer(forKey: "mockPort")).nonZero ?? 4010
    private(set) var mockRunning = false
    var mockError: String?
    private(set) var mockLog: [MockLogEntry] = []
    private var mock: MockServer?

    var runner: RunnerState?
    let client = HTTPClient()
    private var specModified: Date?
    private var watcher: Timer?

    init(files: WorkspaceFiles, spec: APISpec) {
        self.files = files
        self.spec = spec
        environments = files.loadEnvironments()
        if environments.isEmpty { createDefaultEnvironments() }
        let remembered = UserDefaults.standard.string(forKey: "environment:" + files.specURL.path)
        activeEnvironmentID = environments.contains { $0.id == remembered } ? remembered : environments.first?.id
        savedRequests = files.loadRequests().sorted { $0.draft.name.localizedStandardCompare($1.draft.name) == .orderedAscending }
        history = files.loadHistory()
        specModified = modificationDate()
        watcher = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForSpecChanges() }
        }
    }

    func close() {
        watcher?.invalidate()
        mock?.stop()
        runner?.task?.cancel()
        for session in sessions.values { session.task?.cancel() }
    }

    // MARK: Spec

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: files.specURL.path))?[.modificationDate] as? Date
    }

    private func checkForSpecChanges() {
        let current = modificationDate()
        guard current != specModified else { return }
        specModified = current
        reloadSpec(fromDisk: true)
    }

    func reloadSpec(fromDisk: Bool = false) {
        if !fromDisk, let source = files.config.source, let url = URL(string: source) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    _ = try SpecParser.parse(data: data, sourceURL: url)
                    try data.write(to: files.specURL, options: .atomic)
                    reloadSpec(fromDisk: true)
                } catch {
                    specError = "The spec could not be downloaded again. \(error.localizedDescription)"
                }
            }
            return
        }
        do {
            let data = try Data(contentsOf: files.specURL)
            spec = try SpecParser.parse(data: data, sourceURL: files.config.source.flatMap(URL.init(string:)))
            specError = nil
            specModified = modificationDate()
            mock?.update(spec: spec)
            flash("Spec reloaded. \(spec.operations.count) endpoints.")
        } catch {
            specError = "The spec has an error and the last good version is still shown. \(error.localizedDescription)"
        }
    }

    func operation(for draft: RequestDraft) -> APIOperation? {
        draft.operationID.flatMap { spec.operation(id: $0) }
    }

    // MARK: Sessions

    var currentSession: RequestSession? {
        selection.flatMap { sessions[$0] }
    }

    private func prepareSession() {
        guard let selection, sessions[selection] == nil else { return }
        switch selection {
        case .operation(let id):
            if let operation = spec.operation(id: id) {
                sessions[selection] = RequestSession(draft: DraftFactory.make(from: operation, spec: spec))
            }
        case .saved(let id):
            if let saved = savedRequests.first(where: { $0.id == id }) {
                sessions[selection] = RequestSession(draft: saved.draft, savedID: id)
            }
        case .history(let id):
            if let entry = history.first(where: { $0.id == id }) {
                sessions[selection] = RequestSession(draft: entry.draft)
            }
        case .overview, .schema:
            break
        }
    }

    func resetDraft(_ session: RequestSession) {
        guard let operation = operation(for: session.draft) else { return }
        var fresh = DraftFactory.make(from: operation, spec: spec)
        if session.savedID != nil { fresh.name = session.draft.name }
        session.draft = fresh
    }

    // MARK: Environments

    var activeEnvironment: APIEnvironment? {
        if activeEnvironmentID == Self.mockEnvironmentID { return mockEnvironment }
        return environments.first { $0.id == activeEnvironmentID }
    }

    var mockEnvironment: APIEnvironment {
        var base = environments.first?.variables ?? []
        base.removeAll { $0.key == "baseUrl" }
        return APIEnvironment(
            id: Self.mockEnvironmentID,
            name: "Mock server",
            variables: [EnvironmentVariable(key: "baseUrl", value: "http://127.0.0.1:\(mockPort)")] + base
        )
    }

    var variables: [String: String] { activeEnvironment?.values ?? [:] }

    private func createDefaultEnvironments() {
        let secrets = DraftFactory.secretNames(for: spec).map { EnvironmentVariable(key: $0, value: "", secret: true) }
        var servers = spec.servers
        if servers.isEmpty { servers = [APIServer(url: "http://localhost:8080", description: "Local")] }
        var used = Set<String>()
        for server in servers.prefix(4) {
            var url = server.url
            if !url.contains("://") { url = "http://localhost:8080" + (url.hasPrefix("/") ? url : "/" + url) }
            let name = server.description ?? URL(string: url)?.host ?? "Default"
            let id = files.uniqueID(for: name, existing: used)
            used.insert(id)
            let environment = APIEnvironment(id: id, name: name, variables: [EnvironmentVariable(key: "baseUrl", value: url)] + secrets)
            environments.append(environment)
            try? files.save(environment)
        }
    }

    func save(environment: APIEnvironment) {
        guard environment.id != Self.mockEnvironmentID else { return }
        if let index = environments.firstIndex(where: { $0.id == environment.id }) {
            environments[index] = environment
        } else {
            environments.append(environment)
        }
        do {
            try files.save(environment)
        } catch {
            flash("The environment could not be saved. \(error.localizedDescription)")
        }
    }

    func addEnvironment(named name: String) -> APIEnvironment {
        let id = files.uniqueID(for: name, existing: Set(environments.map(\.id)))
        let template = environments.first?.variables.map { EnvironmentVariable(key: $0.key, value: $0.secret ? "" : $0.value, secret: $0.secret) }
        let environment = APIEnvironment(id: id, name: name, variables: template ?? [EnvironmentVariable(key: "baseUrl", value: "")])
        save(environment: environment)
        return environment
    }

    func delete(environment: APIEnvironment) {
        files.delete(environment: environment)
        environments.removeAll { $0.id == environment.id }
        if activeEnvironmentID == environment.id { activeEnvironmentID = environments.first?.id }
    }

    private func applyCaptures(_ values: [String: String]) {
        guard !values.isEmpty, var environment = activeEnvironment, environment.id != Self.mockEnvironmentID else { return }
        for (key, value) in values { environment.set(key, to: value) }
        save(environment: environment)
        flash("Saved \(values.keys.sorted().joined(separator: ", ")) to \(environment.name).")
    }

    // MARK: Sending

    func send(_ session: RequestSession) {
        session.task?.cancel()
        session.isSending = true
        session.error = nil
        let draft = session.draft
        let operation = operation(for: draft)
        session.task = Task {
            defer { session.isSending = false }
            do {
                let outcome = try await perform(draft)
                session.resolved = outcome.request
                session.result = outcome.result
                session.assertionResults = AssertionEngine.evaluate(draft.assertions, result: outcome.result, operation: operation, spec: spec)
                let check = AssertionEngine.schemaIssues(result: outcome.result, operation: operation, spec: spec)
                session.schemaChecked = check.checked
                session.schemaIssues = check.issues
                session.schemaNote = check.note.isEmpty ? nil : check.note
                applyCaptures(AssertionEngine.captures(draft.captures, result: outcome.result))
                record(draft, url: outcome.request.url.absoluteString, result: outcome.result)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                session.result = nil
                session.error = error.localizedDescription
                record(draft, url: Interpolator.apply(draft.url, variables: variables), result: nil)
            }
        }
    }

    func cancel(_ session: RequestSession) {
        session.task?.cancel()
        session.isSending = false
    }

    private func perform(_ draft: RequestDraft) async throws -> (request: ResolvedRequest, result: HTTPResult) {
        let values = variables
        var token: String?
        if draft.auth.mode == .oauth2 {
            token = try await client.accessToken(for: draft.auth, variables: values)
        }
        let request = try RequestBuilder.build(draft, variables: values, accessToken: token)
        return (request, try await client.send(request))
    }

    func resolvedPreview(_ draft: RequestDraft) -> ResolvedRequest? {
        try? RequestBuilder.build(draft, variables: variables, accessToken: draft.auth.mode == .oauth2 ? "<access token>" : nil)
    }

    private func record(_ draft: RequestDraft, url: String, result: HTTPResult?) {
        let entry = HistoryEntry(date: Date(), url: url, status: result?.status, duration: result?.duration, draft: draft.cleaned)
        history.insert(entry, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        files.save(history: history)
    }

    func clearHistory() {
        history.removeAll()
        files.save(history: history)
        sessions = sessions.filter { key, _ in
            if case .history = key { return false }
            return true
        }
        if case .history = selection { selection = .overview }
    }

    // MARK: Saved requests

    func save(_ session: RequestSession, as name: String? = nil) {
        if let id = session.savedID, name == nil {
            let request = SavedRequest(id: id, draft: session.draft)
            write(request)
            session.baseline = session.draft
            return
        }
        var draft = session.draft
        draft.name = (name ?? draft.name).trimmingCharacters(in: .whitespaces)
        if draft.name.isEmpty { draft.name = "Untitled request" }
        let id = files.uniqueID(for: draft.name, existing: Set(savedRequests.map(\.id)))
        let request = SavedRequest(id: id, draft: draft)
        write(request)
        session.draft = draft
        session.baseline = draft
        session.savedID = id
        let key = SidebarSelection.saved(id)
        if let previous = selection, sessions[previous] === session {
            sessions[previous] = nil
        }
        sessions[key] = session
        selection = key
        flash("Saved \(draft.name) to .apipilot/requests/\(id).json")
    }

    private func write(_ request: SavedRequest) {
        do {
            try files.save(request)
            if let index = savedRequests.firstIndex(where: { $0.id == request.id }) {
                savedRequests[index] = request
            } else {
                savedRequests.append(request)
                savedRequests.sort { $0.draft.name.localizedStandardCompare($1.draft.name) == .orderedAscending }
            }
        } catch {
            flash("The request could not be saved. \(error.localizedDescription)")
        }
    }

    func rename(_ request: SavedRequest, to name: String) {
        var updated = request
        updated.draft.name = name
        write(updated)
        sessions[.saved(request.id)]?.draft.name = name
        sessions[.saved(request.id)]?.baseline.name = name
    }

    func duplicate(_ request: SavedRequest) {
        var draft = request.draft
        draft.name += " copy"
        let id = files.uniqueID(for: draft.name, existing: Set(savedRequests.map(\.id)))
        write(SavedRequest(id: id, draft: draft))
        selection = .saved(id)
    }

    func delete(_ request: SavedRequest) {
        files.delete(request: request)
        savedRequests.removeAll { $0.id == request.id }
        sessions[.saved(request.id)] = nil
        if selection == .saved(request.id) { selection = .overview }
    }

    // MARK: Runner

    func startRunner() {
        let state = runner ?? RunnerState(requests: savedRequests)
        runner = state
        guard !state.isRunning else { return }
        state.items = savedRequests.map { RunnerState.Item(id: $0.id, name: $0.draft.name, method: $0.draft.method) }
        state.isRunning = true
        state.startedAt = Date()
        state.finishedAt = nil
        let requests = savedRequests
        state.task = Task {
            defer {
                state.isRunning = false
                state.finishedAt = Date()
            }
            for (index, request) in requests.enumerated() {
                if Task.isCancelled { break }
                state.items[index].status = .running
                do {
                    let outcome = try await perform(request.draft)
                    let results = AssertionEngine.evaluate(request.draft.assertions, result: outcome.result,
                                                           operation: operation(for: request.draft), spec: spec)
                    state.items[index].httpStatus = outcome.result.status
                    state.items[index].duration = outcome.result.duration
                    state.items[index].results = results
                    state.items[index].status = results.allSatisfy(\.passed) ? .passed : .failed
                    applyCaptures(AssertionEngine.captures(request.draft.captures, result: outcome.result))
                } catch {
                    if Task.isCancelled { break }
                    state.items[index].status = .error
                    state.items[index].error = error.localizedDescription
                }
                if state.stopOnFailure, state.items[index].status != .passed { break }
            }
        }
    }

    // MARK: Mock server

    func toggleMock() {
        if mockRunning {
            mock?.stop()
            mock = nil
            mockRunning = false
            if activeEnvironmentID == Self.mockEnvironmentID { activeEnvironmentID = environments.first?.id }
            return
        }
        UserDefaults.standard.set(Int(mockPort), forKey: "mockPort")
        let server = MockServer(spec: spec)
        server.onLog = { [weak self] entry in
            self?.mockLog.insert(entry, at: 0)
            if (self?.mockLog.count ?? 0) > 300 { self?.mockLog.removeLast() }
        }
        server.onStateChange = { [weak self] running, error in
            DispatchQueue.main.async {
                self?.mockRunning = running
                self?.mockError = error
                if running { self?.activeEnvironmentID = Self.mockEnvironmentID }
            }
        }
        do {
            try server.start(port: mockPort)
            mock = server
            mockError = nil
        } catch {
            mockError = error.localizedDescription
        }
    }

    func clearMockLog() {
        mockLog.removeAll()
    }

    // MARK: Docs

    func exportDocs() {
        let panel = NSSavePanel()
        panel.title = "Export API reference"
        panel.nameFieldStringValue = WorkspaceFiles.slug(spec.title) + "-reference.html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DocsExporter.html(for: spec).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            flash("The docs could not be written. \(error.localizedDescription)")
        }
    }

    // MARK: Notices

    func flash(_ message: String) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if notice == message { notice = nil }
        }
    }
}

private extension UInt16 {
    var nonZero: UInt16? { self == 0 ? nil : self }
}
