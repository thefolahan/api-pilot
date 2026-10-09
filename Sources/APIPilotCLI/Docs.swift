import ArgumentParser
import Foundation
import APIPilotKit

struct Docs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export the spec as a single-file HTML API reference."
    )

    @OptionGroup var spec: SpecArgument

    @Option(name: .shortAndLong, help: "Where to write the HTML. Prints it when omitted.")
    var output: String?

    func run() async throws {
        let workspace = try Workspace.load(spec)
        let html = DocsExporter.html(for: workspace.spec)
        guard let output else {
            print(html)
            return
        }
        let url = URL(fileURLWithPath: output)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw Failure("\(output) could not be written. \(error.localizedDescription)")
        }
        printError("Wrote \(url.path)")
    }
}
