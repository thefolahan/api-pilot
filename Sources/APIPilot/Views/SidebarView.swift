import SwiftUI
import APIPilotKit

enum SidebarMode: String, CaseIterable, Identifiable {
    case endpoints, saved, history
    var id: String { rawValue }
}

struct SidebarView: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage("sidebarMode") private var mode: SidebarMode = .endpoints
    @State private var search = ""
    @State private var renaming: SavedRequest?

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Image(systemName: "list.bullet.rectangle").help("Endpoints").tag(SidebarMode.endpoints)
                Image(systemName: "tray.full").help("Saved requests").tag(SidebarMode.saved)
                Image(systemName: "clock.arrow.circlepath").help("History").tag(SidebarMode.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            List(selection: $store.selection) {
                switch mode {
                case .endpoints: endpoints
                case .saved: saved
                case .history: history
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "Filter")
        }
        .sheet(item: $renaming) { request in
            NameSheet(title: "Rename request", name: request.draft.name, action: "Rename") { name in
                store.rename(request, to: name)
            }
        }
    }

    private func matches(_ values: String?...) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return values.contains { $0?.localizedCaseInsensitiveContains(query) ?? false }
    }

    @ViewBuilder private var endpoints: some View {
        let spec = store.spec
        Label(spec.title, systemImage: "book.closed")
            .tag(SidebarSelection.overview)
        ForEach(spec.groupedOperations, id: \.tag) { group in
            let operations = group.operations.filter {
                matches($0.path, $0.summary, $0.operationID, $0.method, group.tag)
            }
            if !operations.isEmpty {
                Section(group.tag) {
                    ForEach(operations) { operation in
                        EndpointRow(operation: operation)
                            .tag(SidebarSelection.operation(operation.id))
                    }
                }
            }
        }
        let models = spec.schemaNames.filter { matches($0) }
        if !models.isEmpty {
            Section("Models") {
                ForEach(models, id: \.self) { name in
                    Label(name, systemImage: "cube")
                        .font(.system(size: 12, design: .monospaced))
                        .tag(SidebarSelection.schema(name))
                }
            }
        }
    }

    @ViewBuilder private var saved: some View {
        let requests = store.savedRequests.filter { matches($0.draft.name, $0.draft.url, $0.draft.method) }
        if requests.isEmpty {
            Text(store.savedRequests.isEmpty ? "Press ⌘S on any request to save it here. Saved requests are files you can commit." : "No matches")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        ForEach(requests) { request in
            HStack(spacing: 8) {
                MethodBadge(method: request.draft.method, compact: true)
                Text(request.draft.name).lineLimit(1)
                Spacer()
                if store.sessions[.saved(request.id)]?.isDirty == true {
                    Circle().fill(Color.secondary).frame(width: 6, height: 6)
                }
            }
            .tag(SidebarSelection.saved(request.id))
            .contextMenu {
                Button("Rename…") { renaming = request }
                Button("Duplicate") { store.duplicate(request) }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.files.requestsFolder.appendingPathComponent(request.id + ".json")])
                }
                Divider()
                Button("Delete", role: .destructive) { store.delete(request) }
            }
        }
    }

    @ViewBuilder private var history: some View {
        let entries = store.history.filter { matches($0.url, $0.draft.name, $0.draft.method) }
        if entries.isEmpty {
            Text("Requests you send appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        MethodBadge(method: entry.draft.method, compact: true)
                        Text(entry.draft.name.isEmpty ? entry.url : entry.draft.name).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if let status = entry.status {
                            Text("\(status)")
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Palette.status(status))
                        } else {
                            Text("failed").font(.caption2).foregroundStyle(.red)
                        }
                        Text(entry.date, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 40)
                }
                .tag(SidebarSelection.history(entry.id))
            }
            Button("Clear history", role: .destructive) { store.clearHistory() }
                .buttonStyle(.borderless)
                .font(.caption)
                .padding(.top, 6)
        }
    }
}

private struct EndpointRow: View {
    let operation: APIOperation

    var body: some View {
        HStack(spacing: 8) {
            MethodBadge(method: operation.method, compact: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(operation.summary ?? operation.path)
                    .lineLimit(1)
                    .strikethrough(operation.deprecated)
                if operation.summary != nil {
                    Text(operation.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 1)
        .help(operation.method + " " + operation.path)
    }
}
