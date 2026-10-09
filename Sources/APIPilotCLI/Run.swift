import ArgumentParser
import Foundation
import APIPilotKit

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send the saved requests in .apipilot/requests in order and check their assertions.",
        discussion: """
        Values captured from a response are passed to the requests after it, but are not written \
        back to the environment files. Secret variables are read from the Keychain when available; \
        in CI, pass them with --var.
        """
    )

    @OptionGroup var spec: SpecArgument

    @Option(name: .customLong("env"), help: "The environment to use, by file name or display name. Defaults to the first one.")
    var environment: String?

    @Option(name: .customLong("var"), help: ArgumentHelp("Set or override a variable, such as --var token=abc.", valueName: "name=value"))
    var variables: [String] = []

    @Option(name: .customLong("only"), help: ArgumentHelp("Run only this request, by file name or name. Repeat to run several.", valueName: "request"))
    var only: [String] = []

    @Flag(help: "Stop at the first request that fails.")
    var stopOnFailure = false

    @Flag(help: "Print the results as JSON.")
    var json = false

    struct Report: Encodable {
        let environment: String?
        let passed: Int
        let failed: Int
        let durationMs: Int
        let requests: [RequestReport]
    }

    struct RequestReport: Encodable {
        let id: String
        let name: String
        let method: String
        var url: String?
        var status: Int?
        var durationMs: Int?
        var passed = false
        var error: String?
        var assertions: [AssertionReport] = []
    }

    struct AssertionReport: Encodable {
        let summary: String
        let passed: Bool
        let actual: String
        let issues: [String]
    }

    func validate() throws {
        for item in variables where !item.contains("=") {
            throw ValidationError("--var expects name=value, but got \"\(item)\".")
        }
    }

    func run() async throws {
        let workspace = try Workspace.load(spec)
        let api = workspace.spec

        var requests = workspace.files.loadRequests()
        if !only.isEmpty {
            requests = requests.filter { request in only.contains { $0 == request.id || $0 == request.draft.name } }
            let known = Set(requests.flatMap { [$0.id, $0.draft.name] })
            if let missing = only.first(where: { !known.contains($0) }) {
                throw Failure("There is no saved request called \"\(missing)\".")
            }
        }
        guard !requests.isEmpty else {
            throw Failure("There are no saved requests in \(workspace.files.requestsFolder.path). Save some in API Pilot first.")
        }

        let selected = try selectEnvironment(workspace.files.loadEnvironments())
        var values = selected?.values ?? [:]
        for item in variables {
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            values[String(parts[0])] = String(parts[1])
        }

        if !json {
            let target = selected.map { " against " + Style.bold($0.name) } ?? ""
            print("Running \(requests.count) request\(requests.count == 1 ? "" : "s")\(target)\n")
        }

        let nameWidth = requests.map { $0.draft.name.isEmpty ? $0.id.count : $0.draft.name.count }.max() ?? 0
        let client = HTTPClient()
        let start = Date()
        var reports: [RequestReport] = []
        for request in requests {
            let draft = request.draft
            var report = RequestReport(id: request.id, name: draft.name.isEmpty ? request.id : draft.name, method: draft.method.uppercased())
            do {
                var token: String?
                if draft.auth.mode == .oauth2 {
                    token = try await client.accessToken(for: draft.auth, variables: values)
                }
                let resolved = try RequestBuilder.build(draft, variables: values, accessToken: token)
                report.url = resolved.url.absoluteString
                let result = try await client.send(resolved)
                let operation = draft.operationID.flatMap(api.operation(id:))
                let results = AssertionEngine.evaluate(draft.assertions, result: result, operation: operation, spec: api)
                report.status = result.status
                report.durationMs = Int(result.duration * 1000)
                report.passed = results.allSatisfy(\.passed)
                report.assertions = results.map {
                    AssertionReport(summary: $0.assertion.summary, passed: $0.passed, actual: $0.actual,
                                    issues: $0.issues.map { "\($0.path) \($0.message)" })
                }
                values.merge(AssertionEngine.captures(draft.captures, result: result)) { _, new in new }
            } catch {
                report.error = error.localizedDescription
            }
            reports.append(report)
            if !json { printLine(report, nameWidth: nameWidth) }
            if stopOnFailure, !report.passed { break }
        }

        let passed = reports.filter(\.passed).count
        let failed = reports.count - passed
        let duration = Date().timeIntervalSince(start)
        if json {
            try printJSON(Report(environment: selected?.id, passed: passed, failed: failed,
                                 durationMs: Int(duration * 1000), requests: reports))
        } else {
            let skipped = requests.count - reports.count
            var summary = "\(passed) passed, \(failed) failed"
            if skipped > 0 { summary += ", \(skipped) skipped" }
            print("\n" + (failed == 0 ? Style.green(summary) : Style.red(summary)) + Style.dim(duration < 1 ? " in \(Int(duration * 1000)) ms" : String(format: " in %.1f s", duration)))
        }
        if failed > 0 { throw ExitCode.failure }
    }

    private func selectEnvironment(_ environments: [APIEnvironment]) throws -> APIEnvironment? {
        guard let environment else { return environments.first }
        if let match = environments.first(where: { $0.id == environment || $0.name.caseInsensitiveCompare(environment) == .orderedSame }) {
            return match
        }
        let names = environments.map(\.id).joined(separator: ", ")
        throw Failure("There is no environment called \"\(environment)\"." + (names.isEmpty ? "" : " Try one of: \(names)."))
    }

    private func printLine(_ report: RequestReport, nameWidth: Int) {
        let mark = report.error != nil ? Style.yellow("!") : report.passed ? Style.green("✔") : Style.red("✘")
        let method = report.method.padding(toLength: 7, withPad: " ", startingAt: 0)
        var line = "  \(mark) \(Style.bold(method)) " + report.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
        if let status = report.status { line += "  " + Style.status(status) }
        if let duration = report.durationMs { line += Style.dim("  \(duration) ms") }
        print(line)
        if let error = report.error {
            print("      " + Style.yellow(error))
        }
        for assertion in report.assertions where !assertion.passed {
            print("      " + Style.red("✘ \(assertion.summary)") + Style.dim("  got \(assertion.actual)"))
            for issue in assertion.issues.prefix(5) {
                print("        " + Style.dim(issue))
            }
            if assertion.issues.count > 5 {
                print("        " + Style.dim("and \(assertion.issues.count - 5) more"))
            }
        }
    }
}
