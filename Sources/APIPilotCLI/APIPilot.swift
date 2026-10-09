import ArgumentParser
import Foundation
import APIPilotKit

@main
struct APIPilot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apipilot",
        abstract: "Check, test, mock and document an API from its OpenAPI spec.",
        version: "1.1.0",
        subcommands: [Validate.self, Run.self, Mock.self, Docs.self]
    )
}

struct SpecArgument: ParsableArguments {
    @Argument(help: "The spec file, or a folder that contains openapi.yaml, openapi.json, swagger.yaml or swagger.json.")
    var spec: String = "."
}

struct Workspace {
    let files: WorkspaceFiles
    let spec: APISpec

    private static let candidates = ["openapi.yaml", "openapi.yml", "openapi.json", "swagger.yaml", "swagger.yml", "swagger.json"]

    static func load(_ argument: SpecArgument) throws -> Workspace {
        var url = URL(fileURLWithPath: argument.spec).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw Failure("There is no file at \(argument.spec).")
        }
        if isDirectory.boolValue {
            let folder = url
            guard let found = candidates.lazy.map({ folder.appendingPathComponent($0) })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                throw Failure("\(argument.spec) has no \(candidates.joined(separator: ", ")). Pass the spec file instead.")
            }
            url = found
        }
        let files = WorkspaceFiles(specURL: url)
        do {
            let data = try Data(contentsOf: url)
            let spec = try SpecParser.parse(data: data, sourceURL: files.config.source.flatMap(URL.init(string:)))
            return Workspace(files: files, spec: spec)
        } catch {
            throw Failure("\(url.lastPathComponent) could not be read. \(error.localizedDescription)")
        }
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

enum Style {
    static let enabled = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func green(_ text: String) -> String { paint(text, "32") }
    static func red(_ text: String) -> String { paint(text, "31") }
    static func yellow(_ text: String) -> String { paint(text, "33") }
    static func dim(_ text: String) -> String { paint(text, "2") }
    static func bold(_ text: String) -> String { paint(text, "1") }

    private static func paint(_ text: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    static func status(_ code: Int) -> String {
        let text = "\(code) \(HTTPStatus.reason(code))"
        switch code {
        case 200..<300: return green(text)
        case 300..<400: return text
        case 400..<500: return yellow(text)
        default: return red(text)
        }
    }
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}
