import Foundation

final class SpecDocument {
    let root: JSONValue

    init(root: JSONValue) {
        self.root = root
    }

    func pointer(_ reference: String) -> JSONValue? {
        guard reference.hasPrefix("#") else { return nil }
        var current = root
        for raw in reference.dropFirst().split(separator: "/") {
            let token = (String(raw).removingPercentEncoding ?? String(raw))
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            if let next = current[token] {
                current = next
            } else if let position = Int(token), let next = current[position] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    func resolve(_ value: JSONValue) -> JSONValue {
        var current = value
        var hops = 0
        while let reference = current["$ref"]?.string, hops < 32 {
            guard let target = pointer(reference) else { break }
            current = target
            hops += 1
        }
        return current
    }

    static func referenceName(_ value: JSONValue) -> String? {
        guard let reference = value["$ref"]?.string else { return nil }
        return reference.split(separator: "/").last.map(String.init)
    }
}
