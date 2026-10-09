import SwiftUI
import APIPilotKit

struct RunnerView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var runner: RunnerState
    @State private var expanded: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Collection run").font(.title3.weight(.semibold))
                    Text("\(runner.items.count) requests against \(store.activeEnvironment?.name ?? "no environment")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if runner.completed > 0 {
                    HStack(spacing: 10) {
                        Label("\(runner.passed)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Label("\(runner.failed)", systemImage: "xmark.circle.fill").foregroundStyle(runner.failed > 0 ? .red : .secondary)
                        if let start = runner.startedAt {
                            Text((runner.finishedAt ?? Date()).timeIntervalSince(start).millisecondText)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .font(.callout.weight(.medium))
                }
            }
            .padding(18)
            ProgressView(value: Double(runner.completed), total: Double(max(runner.items.count, 1)))
                .tint(runner.failed > 0 ? .red : .green)
                .padding(.horizontal, 18)
            List {
                ForEach(runner.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: item.status.symbol)
                                .foregroundStyle(color(item.status))
                                .symbolEffect(.pulse, isActive: item.status == .running)
                            MethodBadge(method: item.method, compact: true)
                            Text(item.name)
                            Spacer()
                            if let status = item.httpStatus {
                                Text("\(status)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Palette.status(status))
                            }
                            if let duration = item.duration {
                                Text(duration.millisecondText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            if !item.results.isEmpty {
                                Text("\(item.results.filter(\.passed).count)/\(item.results.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { expanded = expanded == item.id ? nil : item.id }
                        if let error = item.error {
                            Text(error).font(.caption).foregroundStyle(.red).padding(.leading, 30)
                        }
                        if expanded == item.id || item.status == .failed {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(item.results) { result in
                                    AssertionResultRow(result: result)
                                }
                            }
                            .padding(.leading, 30)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Toggle("Stop on first failure", isOn: $runner.stopOnFailure)
                    .toggleStyle(.checkbox)
                    .disabled(runner.isRunning)
                Text("Values saved by a request are available to the ones after it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if runner.isRunning {
                    Button("Stop") { runner.task?.cancel() }
                } else {
                    Button("Run again") { store.startRunner() }
                }
                Button("Done") {
                    runner.task?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 720, height: 520)
    }

    private func color(_ status: RunnerState.Status) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return .blue
        case .passed: return .green
        case .failed: return .red
        case .error: return .orange
        }
    }
}
