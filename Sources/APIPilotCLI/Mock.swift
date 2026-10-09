import ArgumentParser
import Foundation
import APIPilotKit

struct Mock: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Serve the spec on localhost with its documented examples.",
        discussion: "Request bodies are validated against the spec. Send a Prefer: code=404 header to get another documented response."
    )

    @OptionGroup var spec: SpecArgument

    @Option(name: .shortAndLong, help: "The port to listen on.")
    var port: UInt16 = 4010

    func validate() throws {
        guard port > 0 else { throw ValidationError("Choose a port between 1 and 65535.") }
    }

    func run() async throws {
        let workspace = try Workspace.load(spec)
        let server = MockServer(spec: workspace.spec)
        let operations = workspace.spec.operations.count

        server.onStateChange = { [port] running, error in
            if running {
                print("Serving \(Style.bold(workspace.spec.title)) on " + Style.bold("http://127.0.0.1:\(port)")
                      + Style.dim("  \(operations) operations. Press Ctrl-C to stop.") + "\n")
            } else if let error {
                printError("The mock server could not start on port \(port). \(error)")
                Foundation.exit(1)
            }
        }
        server.onLog = { entry in
            var line = Style.dim(entry.date.formatted(date: .omitted, time: .standard)) + "  " + Style.status(entry.status)
            line += "  \(entry.method) \(entry.path)"
            if let note = entry.note { line += Style.dim("  \(note)") }
            print(line)
        }

        try server.start(port: port)

        var sources: [DispatchSourceSignal] = []
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                server.stop()
                Foundation.exit(0)
            }
            source.resume()
            sources.append(source)
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(3600))
        }
        withExtendedLifetime(sources) {}
    }
}
