import Foundation
import Observation
import APIPilotKit

@Observable
@MainActor
final class RunnerState {
    enum Status {
        case pending, running, passed, failed, error

        var symbol: String {
            switch self {
            case .pending: return "circle.dotted"
            case .running: return "arrow.triangle.2.circlepath"
            case .passed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }
    }

    struct Item: Identifiable {
        let id: String
        let name: String
        let method: String
        var status: Status = .pending
        var httpStatus: Int?
        var duration: TimeInterval?
        var results: [AssertionResult] = []
        var error: String?
    }

    var items: [Item]
    var isRunning = false
    var startedAt: Date?
    var finishedAt: Date?
    var stopOnFailure = false
    var task: Task<Void, Never>?

    init(requests: [SavedRequest]) {
        items = requests.map { Item(id: $0.id, name: $0.draft.name.isEmpty ? $0.id : $0.draft.name, method: $0.draft.method) }
    }

    var passed: Int { items.filter { $0.status == .passed }.count }
    var failed: Int { items.filter { $0.status == .failed || $0.status == .error }.count }
    var completed: Int { passed + failed }
}
