import Foundation

public struct SpecProblem: Equatable {
    public enum Severity: String {
        case error, warning
    }

    public let severity: Severity
    public let location: String
    public let message: String

    public init(severity: Severity, location: String, message: String) {
        self.severity = severity
        self.location = location
        self.message = message
    }
}

public enum SpecLinter {
    public static func problems(in spec: APISpec) -> [SpecProblem] {
        var problems: [SpecProblem] = []
        checkReferences(spec.document.root, path: "#", document: spec.document, problems: &problems)

        var seen: [String: String] = [:]
        for operation in spec.operations {
            if let operationID = operation.operationID {
                if let first = seen[operationID] {
                    problems.append(SpecProblem(severity: .error, location: operation.id,
                                                message: "operationId \"\(operationID)\" is also used by \(first)"))
                } else {
                    seen[operationID] = operation.id
                }
            }

            let declared = Set(operation.parameters.filter { $0.location == .path }.map(\.name))
            for name in templateNames(in: operation.path) where !declared.contains(name) {
                problems.append(SpecProblem(severity: .error, location: operation.id,
                                            message: "path parameter \"\(name)\" is not declared"))
            }
            if operation.responses.isEmpty {
                problems.append(SpecProblem(severity: .warning, location: operation.id, message: "no responses are documented"))
            }
        }
        return problems
    }

    private static func checkReferences(_ value: JSONValue, path: String, document: SpecDocument, problems: inout [SpecProblem]) {
        switch value {
        case .object(let members):
            if let reference = value["$ref"]?.string {
                if !reference.hasPrefix("#") {
                    problems.append(SpecProblem(severity: .warning, location: path,
                                                message: "external reference \(reference) is not followed"))
                } else if document.pointer(reference) == nil {
                    problems.append(SpecProblem(severity: .error, location: path,
                                                message: "\(reference) does not point to anything"))
                }
            }
            for member in members {
                let token = member.key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                checkReferences(member.value, path: path + "/" + token, document: document, problems: &problems)
            }
        case .array(let items):
            for (offset, item) in items.enumerated() {
                checkReferences(item, path: path + "/\(offset)", document: document, problems: &problems)
            }
        default:
            break
        }
    }

    private static func templateNames(in path: String) -> [String] {
        var names: [String] = []
        var remainder = path[...]
        while let open = remainder.firstIndex(of: "{"), let close = remainder[open...].firstIndex(of: "}") {
            names.append(String(remainder[remainder.index(after: open)..<close]))
            remainder = remainder[remainder.index(after: close)...]
        }
        return names
    }
}
