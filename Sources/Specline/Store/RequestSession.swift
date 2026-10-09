import Foundation
import Observation

enum SidebarSelection: Hashable {
    case overview
    case operation(String)
    case schema(String)
    case saved(String)
    case history(UUID)
}

@Observable
@MainActor
final class RequestSession: Identifiable {
    let id = UUID()
    var draft: RequestDraft
    var baseline: RequestDraft
    var savedID: String?
    var result: HTTPResult?
    var resolved: ResolvedRequest?
    var error: String?
    var isSending = false
    var assertionResults: [AssertionResult] = []
    var schemaIssues: [ValidationIssue] = []
    var schemaNote: String?
    var schemaChecked = false
    var task: Task<Void, Never>?

    init(draft: RequestDraft, savedID: String? = nil) {
        self.draft = draft
        self.baseline = draft
        self.savedID = savedID
    }

    var isDirty: Bool { savedID != nil && draft.cleaned != baseline.cleaned }

    var passedCount: Int { assertionResults.filter(\.passed).count }
}
