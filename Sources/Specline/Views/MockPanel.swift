import SwiftUI

struct MockPanel: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var portText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mock server").font(.headline)
                    Text(store.mockRunning ? "Serving examples from the spec" : "Answers every endpoint with its documented examples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { store.mockRunning }, set: { _ in store.toggleMock() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            HStack(spacing: 6) {
                Text("http://127.0.0.1:").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                TextField("4010", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 64)
                    .disabled(store.mockRunning)
                    .onSubmit(applyPort)
                    .onChange(of: portText) { applyPort() }
                if store.mockRunning {
                    Button("Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("http://127.0.0.1:\(store.mockPort)", forType: .string)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            if let error = store.mockError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            Text("Send a Prefer: code=404 header to get another documented response. JSON bodies are checked against the request schema and get a 422 when they do not match.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                SectionLabel("Log")
                Spacer()
                if !store.mockLog.isEmpty {
                    Button("Clear") { store.clearMockLog() }.buttonStyle(.borderless).font(.caption)
                }
            }
            if store.mockLog.isEmpty {
                Text("No requests yet").font(.callout).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.mockLog) { entry in
                            HStack(spacing: 8) {
                                Text("\(entry.status)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Palette.status(entry.status))
                                MethodBadge(method: entry.method, compact: true)
                                Text(entry.path).font(.system(size: 11.5, design: .monospaced)).lineLimit(1)
                                Spacer()
                                Text(entry.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .help(entry.note ?? entry.operation ?? "")
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear { portText = String(store.mockPort) }
    }

    private func applyPort() {
        if let port = UInt16(portText), port > 1023 { store.mockPort = port }
    }
}
