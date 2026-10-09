import SwiftUI

struct OperationDocsView: View {
    let operation: APIOperation
    let spec: APISpec

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !operation.security.isEmpty { security }
                if !operation.parameters.isEmpty { parameters }
                if let body = operation.requestBody { requestBody(body) }
                if !operation.responses.isEmpty { responses }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MethodBadge(method: operation.method)
                Text(operation.path)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .textSelection(.enabled)
            }
            Text(operation.title).font(.title3.weight(.semibold))
            if operation.deprecated {
                Label("Deprecated", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let description = operation.description {
                MarkdownText(text: description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let operationID = operation.operationID {
                Text(operationID)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    private var security: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Authentication")
            ForEach(operation.security, id: \.self) { name in
                let scheme = spec.securitySchemes.first { $0.name == name }
                Label {
                    Text(name).font(.callout.weight(.medium)) + Text("  " + (scheme?.summary ?? "")).font(.callout).foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Parameters")
            ForEach(operation.parameters) { parameter in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(parameter.name).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        if let schema = parameter.schema {
                            Text(Schema(schema, document: spec.document).typeLabel)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.tint)
                        }
                        Text(parameter.location.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                        if parameter.required {
                            Text("required").font(.caption2.weight(.semibold)).foregroundStyle(.red)
                        }
                    }
                    if let description = parameter.description {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func requestBody(_ body: APIRequestBody) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Request body")
                if body.required { Text("required").font(.caption2.weight(.semibold)).foregroundStyle(.red) }
                Spacer()
                if let type = body.preferred?.contentType {
                    Text(type).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            if let description = body.description {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            if let schema = body.preferred?.schema {
                SchemaTreeView(schema: Schema(schema, document: spec.document))
            }
        }
    }

    private var responses: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Responses")
            ForEach(operation.responses) { response in
                ResponseDocRow(response: response, spec: spec)
            }
        }
    }
}

private struct ResponseDocRow: View {
    let response: APIResponse
    let spec: APISpec
    @State private var expanded = false
    @State private var showsExample = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text(response.status)
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.status(response.status))
                    Text(response.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 1)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let media = response.preferred {
                        Text(media.contentType).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                        Picker("", selection: $showsExample) {
                            Text("Schema").tag(false)
                            Text("Example").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)
                        if showsExample {
                            let example = ExampleGenerator.example(for: media, document: spec.document, purpose: .response)
                            Text(example?.serialized(pretty: true) ?? "No example")
                                .font(.system(size: 11.5, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                        } else if let schema = media.schema {
                            SchemaTreeView(schema: Schema(schema, document: spec.document))
                        }
                    } else {
                        Text("No body").font(.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(response.headers, id: \.name) { header in
                        Text("Header \(header.name)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .onAppear { expanded = response.isSuccess }
    }
}
