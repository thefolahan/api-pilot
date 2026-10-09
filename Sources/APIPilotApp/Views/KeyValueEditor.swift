import SwiftUI
import APIPilotKit

struct KeyValueEditor: View {
    @Binding var rows: [KeyValue]
    var keyPlaceholder = "Key"
    var valuePlaceholder = "Value"
    var lockedKeys = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach($rows) { $row in
                KeyValueRow(
                    row: $row,
                    keyPlaceholder: keyPlaceholder,
                    valuePlaceholder: valuePlaceholder,
                    lockedKey: lockedKeys,
                    onDelete: lockedKeys ? nil : { rows.removeAll { $0.id == row.id } }
                )
                Divider().opacity(0.5)
            }
        }
        .onAppear(perform: ensureBlankRow)
        .onChange(of: rows) { ensureBlankRow() }
    }

    private func ensureBlankRow() {
        guard !lockedKeys else { return }
        if rows.last.map({ !$0.isBlank }) ?? true {
            rows.append(KeyValue())
        }
    }
}

private struct KeyValueRow: View {
    @Binding var row: KeyValue
    let keyPlaceholder: String
    let valuePlaceholder: String
    let lockedKey: Bool
    let onDelete: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $row.enabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .opacity(row.isBlank ? 0.3 : 1)
                .disabled(row.isBlank)
            Group {
                if lockedKey {
                    Text(row.key)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(keyPlaceholder, text: $row.key)
                }
            }
            .frame(width: 190, alignment: .leading)
            .help(row.note ?? "")
            TextField(row.note.map { String($0.prefix(60)) } ?? valuePlaceholder, text: $row.value)
            if let onDelete, !row.isBlank {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help("Remove")
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12.5, design: .monospaced))
        .foregroundStyle(row.enabled || row.isBlank ? .primary : .secondary)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
    }
}
