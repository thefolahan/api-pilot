import SwiftUI
import APIPilotKit

struct SchemaTreeView: View {
    let schema: Schema
    var expandDepth = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let target = container(of: schema)
            if target.properties.isEmpty {
                HStack(spacing: 6) {
                    Text(schema.typeLabel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tint)
                    if let description = schema.description {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                if schema.primaryType == "array" {
                    Text(schema.typeLabel)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                ForEach(target.properties, id: \.name) { property in
                    SchemaPropertyRow(
                        name: property.name,
                        schema: property.schema,
                        required: target.required.contains(property.name),
                        depth: 0,
                        expandDepth: expandDepth
                    )
                }
            }
        }
    }
}

private func container(of schema: Schema) -> Schema {
    if schema.primaryType == "array", let items = schema.items { return items }
    if schema.properties.isEmpty, let first = schema.oneOf.first, !first.properties.isEmpty { return first }
    return schema
}

private struct SchemaPropertyRow: View {
    let name: String
    let schema: Schema
    let required: Bool
    let depth: Int
    let expandDepth: Int
    @State private var expanded: Bool?

    private var children: Schema? {
        let target = container(of: schema)
        return target.properties.isEmpty || depth > 14 ? nil : target
    }

    var body: some View {
        let isExpanded = expanded ?? (depth < expandDepth - 1)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .opacity(children == nil ? 0 : 1)
                    .frame(width: 10)
                Text(name)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .strikethrough(schema.deprecated)
                Text(schema.typeLabel)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.tint)
                if required {
                    Text("required").font(.caption2.weight(.semibold)).foregroundStyle(.red)
                }
                if schema.readOnly {
                    Text("read only").font(.caption2).foregroundStyle(.secondary)
                }
                if schema.writeOnly {
                    Text("write only").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if children != nil {
                    withAnimation(.easeOut(duration: 0.15)) { expanded = !isExpanded }
                }
            }
            if let description = schema.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let notes = schema.constraints + (schema.enumValues.isEmpty ? [] : ["one of " + schema.enumValues.map(\.plainText).joined(separator: ", ")])
            if !notes.isEmpty {
                Text(notes.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isExpanded, let children {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(children.properties, id: \.name) { property in
                        SchemaPropertyRow(
                            name: property.name,
                            schema: property.schema,
                            required: children.required.contains(property.name),
                            depth: depth + 1,
                            expandDepth: expandDepth
                        )
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).padding(.leading, 4)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
