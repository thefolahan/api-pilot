import SwiftUI
import APIPilotKit

struct OverviewView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        let spec = store.spec
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Chip(text: spec.version.isEmpty ? "No version" : "v" + spec.version)
                        Chip(text: spec.format)
                        if store.files.config.source != nil { Chip(text: "Remote") }
                    }
                    Text(spec.title)
                        .font(.system(size: 32, weight: .bold))
                        .textSelection(.enabled)
                    if let description = spec.description {
                        MarkdownText(text: description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 680, alignment: .leading)
                    }
                    Text(store.files.specURL.path(percentEncoded: false))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 12) {
                    Stat(value: spec.operations.count, label: "Endpoints", symbol: "arrow.left.arrow.right")
                    Stat(value: spec.schemaNames.count, label: "Models", symbol: "cube")
                    Stat(value: store.savedRequests.count, label: "Saved requests", symbol: "tray.full")
                    Stat(value: store.environments.count, label: "Environments", symbol: "globe")
                }

                if let error = store.specError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                HStack(alignment: .top, spacing: 24) {
                    if !spec.servers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Servers")
                            ForEach(spec.servers) { server in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(server.url).font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled)
                                    if let description = server.description {
                                        Text(description).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !spec.securitySchemes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Authentication")
                            ForEach(spec.securitySchemes) { scheme in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(scheme.name).font(.callout.weight(.medium))
                                    Text(scheme.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(spec.groupedOperations, id: \.tag) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.tag).font(.title3.weight(.semibold))
                            if let description = spec.tags.first(where: { $0.name == group.tag })?.description {
                                Text(description).font(.callout).foregroundStyle(.secondary)
                            }
                            VStack(spacing: 0) {
                                ForEach(group.operations) { operation in
                                    OverviewRow(operation: operation) {
                                        store.selection = .operation(operation.id)
                                    }
                                    if operation.id != group.operations.last?.id { Divider() }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    store.exportDocs()
                } label: {
                    Label("Export docs", systemImage: "square.and.arrow.up")
                }
                .help("Export a standalone HTML reference for this API")
            }
        }
    }
}

private struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

private struct Stat: View {
    let value: Int
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text("\(value)").font(.system(size: 24, weight: .semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}

private struct OverviewRow: View {
    let operation: APIOperation
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MethodBadge(method: operation.method)
                    .frame(width: 64, alignment: .leading)
                Text(operation.path)
                    .font(.system(size: 12.5, design: .monospaced))
                    .strikethrough(operation.deprecated)
                Text(operation.summary ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !operation.security.isEmpty {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(hovering ? Color.primary.opacity(0.04) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SchemaPage: View {
    @Environment(WorkspaceStore.self) private var store
    let name: String
    @State private var showsExample = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let raw = store.spec.schema(named: name) {
                    let schema = Schema(raw, document: store.spec.document)
                    HStack(spacing: 10) {
                        Image(systemName: "cube").foregroundStyle(.tint)
                        Text(name).font(.system(size: 26, weight: .bold, design: .monospaced))
                    }
                    if let description = schema.description {
                        MarkdownText(text: description).foregroundStyle(.secondary)
                    }
                    Picker("", selection: $showsExample) {
                        Text("Schema").tag(false)
                        Text("Example").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    if showsExample {
                        Text(ExampleGenerator.example(for: schema, purpose: .response).serialized(pretty: true))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                    } else {
                        SchemaTreeView(schema: schema, expandDepth: 2)
                    }
                    let users = store.spec.operations.filter { operationReferences($0, name: name) }
                    if !users.isEmpty {
                        SectionLabel("Used by").padding(.top, 10)
                        ForEach(users) { operation in
                            Button {
                                store.selection = .operation(operation.id)
                            } label: {
                                HStack {
                                    MethodBadge(method: operation.method)
                                    Text(operation.path).font(.system(size: 12.5, design: .monospaced))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    EmptyState(symbol: "cube", title: "\(name) is no longer in the spec")
                }
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func operationReferences(_ operation: APIOperation, name: String) -> Bool {
        let schemas = (operation.requestBody?.contents ?? []).compactMap(\.schema)
            + operation.responses.flatMap(\.contents).compactMap(\.schema)
        return schemas.contains { $0.serialized(pretty: false).contains("/\(name)\"") }
    }
}
