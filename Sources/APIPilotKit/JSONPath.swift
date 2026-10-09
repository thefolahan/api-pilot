import Foundation

public enum JSONPath {
    public enum Step: Equatable {
        case key(String)
        case index(Int)
        case all
    }

    public static func steps(_ path: String) -> [Step] {
        var text = path.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("$") { text.removeFirst() }
        var steps: [Step] = []
        var current = ""
        var index = text.startIndex

        func flush() {
            if !current.isEmpty { steps.append(.key(current)) }
            current = ""
        }

        while index < text.endIndex {
            let character = text[index]
            if character == "." {
                flush()
            } else if character == "[" {
                flush()
                guard let close = text[index...].firstIndex(of: "]") else { break }
                let inner = text[text.index(after: index)..<close].trimmingCharacters(in: .whitespaces)
                if inner == "*" {
                    steps.append(.all)
                } else if let number = Int(inner) {
                    steps.append(.index(number))
                } else {
                    steps.append(.key(inner.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))))
                }
                index = close
            } else {
                current.append(character)
            }
            index = text.index(after: index)
        }
        flush()
        return steps
    }

    public static func evaluate(_ path: String, in root: JSONValue) -> JSONValue? {
        var nodes: [JSONValue] = [root]
        var fannedOut = false
        for step in steps(path) {
            var next: [JSONValue] = []
            for node in nodes {
                switch step {
                case .key("length") where node.array != nil:
                    next.append(.number(String(node.array!.count)))
                case .key(let key):
                    if let value = node[key] { next.append(value) }
                case .index(let position):
                    if let items = node.array {
                        let resolved = position < 0 ? items.count + position : position
                        if items.indices.contains(resolved) { next.append(items[resolved]) }
                    }
                case .all:
                    fannedOut = true
                    if let items = node.array { next.append(contentsOf: items) }
                    if let members = node.members { next.append(contentsOf: members.map(\.value)) }
                }
            }
            nodes = next
            if nodes.isEmpty { return nil }
        }
        return fannedOut ? .array(nodes) : nodes.first
    }
}
