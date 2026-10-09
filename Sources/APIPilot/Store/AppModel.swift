import AppKit
import UniformTypeIdentifiers
import Observation
import APIPilotKit

@Observable
@MainActor
final class AppModel {
    var workspace: WorkspaceStore?
    var openError: String?
    var isDownloading = false
    var showsOpenURL = false
    private(set) var recents: [URL] = []

    init() {
        recents = (UserDefaults.standard.stringArray(forKey: "recents") ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if let last = recents.first, UserDefaults.standard.bool(forKey: "reopenLast") {
            open(last)
        }
    }

    func open(_ url: URL) {
        var target = url
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
            guard let found = Self.findSpec(in: url) else {
                openError = "No OpenAPI file was found in \(url.lastPathComponent). Look for a file such as openapi.yaml or swagger.json."
                return
            }
            target = found
        }
        do {
            let data = try Data(contentsOf: target)
            let files = WorkspaceFiles(specURL: target)
            let spec = try SpecParser.parse(data: data, sourceURL: files.config.source.flatMap(URL.init(string:)))
            workspace?.close()
            workspace = WorkspaceStore(files: files, spec: spec)
            openError = nil
            remember(target)
            UserDefaults.standard.set(true, forKey: "reopenLast")
        } catch {
            openError = "\(target.lastPathComponent) could not be opened. \(error.localizedDescription)"
        }
    }

    func openRemote(_ address: String) async {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else {
            openError = "Enter a full address that starts with https://"
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            _ = try SpecParser.parse(data: data, sourceURL: url)
            let folder = WorkspaceFiles.supportFolder
                .appendingPathComponent("Remote", isDirectory: true)
                .appendingPathComponent(WorkspaceFiles.slug((url.host ?? "") + url.path), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = ["json", "yaml", "yml"].contains(url.pathExtension.lowercased()) ? url.lastPathComponent : "openapi.json"
            let file = folder.appendingPathComponent(name)
            try data.write(to: file, options: .atomic)
            WorkspaceFiles(specURL: file).config = WorkspaceConfig(source: url.absoluteString)
            showsOpenURL = false
            open(file)
        } catch {
            openError = "The spec at \(url.absoluteString) could not be loaded. \(error.localizedDescription)"
        }
    }

    func openSample() {
        let folder = WorkspaceFiles.supportFolder.appendingPathComponent("Sample", isDirectory: true)
        let file = folder.appendingPathComponent("openapi.yaml")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if (try? String(contentsOf: file, encoding: .utf8)) != SampleSpec.yaml {
            try? SampleSpec.yaml.write(to: file, atomically: true, encoding: .utf8)
        }
        open(file)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open an OpenAPI or Swagger file"
        panel.allowedContentTypes = [.json, .yaml, .folder]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func closeWorkspace() {
        workspace?.close()
        workspace = nil
        UserDefaults.standard.set(false, forKey: "reopenLast")
    }

    func forget(_ url: URL) {
        recents.removeAll { $0 == url }
        UserDefaults.standard.set(recents.map(\.path), forKey: "recents")
    }

    private func remember(_ url: URL) {
        recents.removeAll { $0 == url }
        recents.insert(url, at: 0)
        recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents.map(\.path), forKey: "recents")
    }

    static func findSpec(in folder: URL) -> URL? {
        let preferred = ["openapi.yaml", "openapi.yml", "openapi.json", "swagger.yaml", "swagger.yml", "swagger.json"]
        for name in preferred {
            let candidate = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var depthChecked = 0
        while let url = enumerator?.nextObject() as? URL, depthChecked < 2000 {
            depthChecked += 1
            if url.pathComponents.contains("node_modules") { enumerator?.skipDescendants(); continue }
            guard ["yaml", "yml", "json"].contains(url.pathExtension.lowercased()),
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let head = String(decoding: handle.readData(ofLength: 600), as: UTF8.self)
            try? handle.close()
            if head.contains("openapi") || head.contains("swagger") { return url }
        }
        return nil
    }
}
