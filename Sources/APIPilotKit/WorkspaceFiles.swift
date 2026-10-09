import Foundation

public struct HistoryEntry: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var date: Date
    public var url: String
    public var status: Int?
    public var duration: TimeInterval?
    public var draft: RequestDraft

    public init(id: UUID = UUID(), date: Date, url: String, status: Int? = nil, duration: TimeInterval? = nil, draft: RequestDraft) {
        self.id = id
        self.date = date
        self.url = url
        self.status = status
        self.duration = duration
        self.draft = draft
    }
}

public struct WorkspaceConfig: Codable {
    public var source: String?

    public init(source: String? = nil) {
        self.source = source
    }
}

public struct WorkspaceFiles {
    public let specURL: URL

    public init(specURL: URL) {
        self.specURL = specURL
    }

    public var root: URL { specURL.deletingLastPathComponent() }
    public var dataFolder: URL { root.appendingPathComponent(".apipilot", isDirectory: true) }
    public var environmentsFolder: URL { dataFolder.appendingPathComponent("environments", isDirectory: true) }
    public var requestsFolder: URL { dataFolder.appendingPathComponent("requests", isDirectory: true) }
    public var configURL: URL { dataFolder.appendingPathComponent("workspace.json") }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static var supportFolder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("API Pilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public var config: WorkspaceConfig {
        get {
            (try? Data(contentsOf: configURL)).flatMap { try? Self.decoder.decode(WorkspaceConfig.self, from: $0) } ?? WorkspaceConfig()
        }
        nonmutating set {
            try? write(newValue, to: configURL)
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try Self.encoder.encode(value)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    private func files(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func secretAccount(environment: String, key: String) -> String {
        "\(specURL.path)|\(environment)|\(key)"
    }

    public func loadEnvironments() -> [APIEnvironment] {
        files(in: environmentsFolder).compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  var environment = try? Self.decoder.decode(APIEnvironment.self, from: data) else { return nil }
            environment.id = url.deletingPathExtension().lastPathComponent
            for index in environment.variables.indices where environment.variables[index].secret {
                let key = environment.variables[index].key
                environment.variables[index].value = Keychain.read(secretAccount(environment: environment.id, key: key)) ?? ""
            }
            return environment
        }
    }

    public func save(_ environment: APIEnvironment) throws {
        var stored = environment
        for index in stored.variables.indices where stored.variables[index].secret {
            let variable = stored.variables[index]
            Keychain.write(variable.value, account: secretAccount(environment: environment.id, key: variable.key))
            stored.variables[index].value = ""
        }
        try write(stored, to: environmentsFolder.appendingPathComponent(environment.id + ".json"))
    }

    public func delete(environment: APIEnvironment) {
        for variable in environment.variables where variable.secret {
            Keychain.delete(secretAccount(environment: environment.id, key: variable.key))
        }
        try? FileManager.default.removeItem(at: environmentsFolder.appendingPathComponent(environment.id + ".json"))
    }

    public func deleteSecret(environment: String, key: String) {
        Keychain.delete(secretAccount(environment: environment, key: key))
    }

    public func loadRequests() -> [SavedRequest] {
        files(in: requestsFolder).compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let draft = try? Self.decoder.decode(RequestDraft.self, from: data) else { return nil }
            return SavedRequest(id: url.deletingPathExtension().lastPathComponent, draft: draft)
        }
    }

    public func save(_ request: SavedRequest) throws {
        try write(request.draft.cleaned, to: requestsFolder.appendingPathComponent(request.id + ".json"))
    }

    public func delete(request: SavedRequest) {
        try? FileManager.default.removeItem(at: requestsFolder.appendingPathComponent(request.id + ".json"))
    }

    public func uniqueID(for name: String, existing: Set<String>) -> String {
        let base = Self.slug(name)
        var candidate = base
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }
        return candidate
    }

    public static func slug(_ name: String) -> String {
        let lowered = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        var result = ""
        for character in lowered {
            if character.isLetter || character.isNumber {
                result.append(character)
            } else if !result.isEmpty, result.last != "-" {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "request" : String(result.prefix(60))
    }

    private var historyURL: URL {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in specURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Self.supportFolder.appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent(String(hash, radix: 16) + ".json")
    }

    public func loadHistory() -> [HistoryEntry] {
        (try? Data(contentsOf: historyURL)).flatMap { try? Self.decoder.decode([HistoryEntry].self, from: $0) } ?? []
    }

    public func save(history: [HistoryEntry]) {
        try? write(history, to: historyURL)
    }
}
