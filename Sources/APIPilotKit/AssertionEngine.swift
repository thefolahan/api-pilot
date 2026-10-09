import Foundation

public struct AssertionResult: Identifiable {
    public let id = UUID()
    public let assertion: Assertion
    public let passed: Bool
    public let actual: String
    public let issues: [ValidationIssue]
}

public enum AssertionEngine {
    public static func evaluate(_ assertions: [Assertion], result: HTTPResult, operation: APIOperation?, spec: APISpec?) -> [AssertionResult] {
        let json = result.json
        return assertions.filter(\.enabled).map { assertion in
            switch assertion.source {
            case .schema:
                return schemaCheck(assertion, result: result, json: json, operation: operation, spec: spec)
            case .status:
                return compare(assertion, actual: String(result.status))
            case .responseTime:
                return compare(assertion, actual: String(Int(result.duration * 1000)))
            case .body:
                return compare(assertion, actual: result.text)
            case .header:
                return compare(assertion, actual: result.header(assertion.target))
            case .jsonPath:
                return compare(assertion, actual: json.flatMap { JSONPath.evaluate(assertion.target, in: $0) }?.plainText)
            }
        }
    }

    public static func schemaIssues(result: HTTPResult, operation: APIOperation?, spec: APISpec?) -> (checked: Bool, issues: [ValidationIssue], note: String) {
        guard let operation, let spec else { return (false, [], "This request is not linked to an operation in the spec.") }
        guard let response = operation.response(for: result.status) else {
            return (true, [ValidationIssue(path: "status", message: "\(result.status) is not a documented response")], "")
        }
        guard let schemaValue = response.preferred?.schema else {
            return (false, [], "The spec documents \(response.status) without a body schema.")
        }
        guard let json = result.json else {
            if result.body.isEmpty { return (true, [ValidationIssue(path: "$", message: "the body is empty")], "") }
            return (false, [], "The body is not JSON, so it was not checked.")
        }
        return (true, SchemaValidator.validate(json, against: Schema(schemaValue, document: spec.document)), "")
    }

    private static func schemaCheck(_ assertion: Assertion, result: HTTPResult, json: JSONValue?, operation: APIOperation?, spec: APISpec?) -> AssertionResult {
        let check = schemaIssues(result: result, operation: operation, spec: spec)
        if !check.checked {
            return AssertionResult(assertion: assertion, passed: true, actual: check.note, issues: [])
        }
        let actual = check.issues.isEmpty ? "Valid" : "\(check.issues.count) problem\(check.issues.count == 1 ? "" : "s")"
        return AssertionResult(assertion: assertion, passed: check.issues.isEmpty, actual: actual, issues: check.issues)
    }

    private static func compare(_ assertion: Assertion, actual: String?) -> AssertionResult {
        let expected = assertion.expected
        let passed: Bool
        switch assertion.comparison {
        case .exists:
            passed = actual != nil
        case .equals:
            passed = actual == expected || (Double(actual ?? "x").map { $0 == Double(expected) } ?? false)
        case .notEquals:
            passed = actual != expected
        case .contains:
            passed = actual?.contains(expected) ?? false
        case .lessThan:
            passed = (Double(actual ?? "") ?? .infinity) < (Double(expected) ?? -.infinity)
        case .greaterThan:
            passed = (Double(actual ?? "") ?? -.infinity) > (Double(expected) ?? .infinity)
        case .matches:
            passed = actual.map { $0.range(of: expected, options: .regularExpression) != nil } ?? false
        }
        let shown = actual.map { $0.count > 120 ? String($0.prefix(120)) + "…" : $0 } ?? "missing"
        return AssertionResult(assertion: assertion, passed: passed, actual: shown, issues: [])
    }

    public static func captures(_ captures: [Capture], result: HTTPResult) -> [String: String] {
        let json = result.json
        var values: [String: String] = [:]
        for capture in captures where capture.enabled && !capture.variable.isEmpty {
            switch capture.source {
            case .header:
                if let value = result.header(capture.path) { values[capture.variable] = value }
            case .jsonPath:
                if let json, let value = JSONPath.evaluate(capture.path, in: json) { values[capture.variable] = value.plainText }
            }
        }
        return values
    }
}
