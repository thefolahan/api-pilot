import ArgumentParser
import Foundation
import APIPilotKit

struct Validate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check that a spec loads and that its references, operation IDs and path parameters are sound."
    )

    @OptionGroup var spec: SpecArgument

    @Flag(help: "Print the result as JSON.")
    var json = false

    @Flag(help: "Fail on warnings as well as errors.")
    var strict = false

    struct Report: Encodable {
        var title: String?
        var version: String?
        var format: String?
        var operations: Int?
        let valid: Bool
        let problems: [Problem]
    }

    struct Problem: Encodable {
        let severity: String
        let location: String
        let message: String
    }

    func run() async throws {
        let workspace: Workspace
        do {
            workspace = try Workspace.load(spec)
        } catch let failure as Failure where json {
            try printJSON(Report(valid: false, problems: [Problem(severity: "error", location: spec.spec, message: failure.description)]))
            throw ExitCode.failure
        }
        let api = workspace.spec
        let problems = SpecLinter.problems(in: api)
        let errors = problems.filter { $0.severity == .error }.count
        let warnings = problems.count - errors
        let valid = errors == 0 && (!strict || warnings == 0)

        if json {
            try printJSON(Report(
                title: api.title, version: api.version, format: api.format, operations: api.operations.count, valid: valid,
                problems: problems.map { Problem(severity: $0.severity.rawValue, location: $0.location, message: $0.message) }
            ))
        } else {
            print(Style.bold(api.title) + " " + api.version + Style.dim("  \(api.format)"))
            let counts = [(api.operations.count, "operation"), (api.schemaNames.count, "schema"), (api.servers.count, "server")]
            print(Style.dim(counts.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }.joined(separator: ", ")))
            if !problems.isEmpty { print() }
            for problem in problems {
                let label = problem.severity == .error ? Style.red("error") : Style.yellow("warning")
                print("\(label)  \(problem.location)  \(problem.message)")
            }
            print()
            if problems.isEmpty {
                print(Style.green("✔ No problems found"))
            } else {
                let summary = "\(errors) error\(errors == 1 ? "" : "s"), \(warnings) warning\(warnings == 1 ? "" : "s")"
                print(valid ? Style.yellow("✔ " + summary) : Style.red("✘ " + summary))
            }
        }
        if !valid { throw ExitCode.failure }
    }
}
