import SwiftUI

struct EnvironmentEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var working: APIEnvironment?
    @State private var addingName: String?
    @State private var revealed: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(store.environments) { environment in
                        HStack {
                            Text(environment.name)
                            Spacer()
                            if environment.id == store.activeEnvironmentID {
                                Image(systemName: "checkmark").font(.caption).foregroundStyle(.tint)
                            }
                        }
                        .tag(Optional(environment.id))
                        .contextMenu {
                            Button("Use this environment") { store.activeEnvironmentID = environment.id }
                            Button("Delete", role: .destructive) { store.delete(environment: environment) }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button {
                            addingName = "Staging"
                        } label: {
                            Image(systemName: "plus")
                        }
                        Button {
                            if let environment = store.environments.first(where: { $0.id == selectedID }) {
                                store.delete(environment: environment)
                                selectedID = store.environments.first?.id
                            }
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(selectedID == nil)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                }
                .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)

                editor.frame(minWidth: 480)
            }
            Divider()
            HStack {
                Text("Values live in .specline/environments. Secret values are kept in your Keychain and never written to the repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    commit()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 760, height: 460)
        .onAppear {
            selectedID = store.activeEnvironmentID.flatMap { id in store.environments.contains { $0.id == id } ? id : nil } ?? store.environments.first?.id
        }
        .onChange(of: selectedID, initial: true) { old, new in
            if old != new { commit() }
            working = store.environments.first { $0.id == new }
        }
        .sheet(isPresented: Binding(get: { addingName != nil }, set: { if !$0 { addingName = nil } })) {
            NameSheet(title: "New environment", prompt: "It starts with the same variable names as your first environment.",
                      name: addingName ?? "", action: "Create") { name in
                commit()
                selectedID = store.addEnvironment(named: name).id
            }
        }
    }

    @ViewBuilder private var editor: some View {
        if let binding = Binding($working) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Name", text: binding.name)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .padding(14)
                Divider()
                HStack(spacing: 8) {
                    Text("Variable").frame(width: 170, alignment: .leading)
                    Text("Value")
                    Spacer()
                    Text("Secret")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(binding.variables) { $variable in
                            HStack(spacing: 8) {
                                Toggle("", isOn: $variable.enabled).labelsHidden().toggleStyle(.checkbox)
                                TextField("name", text: $variable.key).frame(width: 150)
                                Group {
                                    if variable.secret && !revealed.contains(variable.id) {
                                        SecureField("value", text: $variable.value)
                                    } else {
                                        TextField("value", text: $variable.value)
                                    }
                                }
                                if variable.secret {
                                    Button {
                                        if revealed.contains(variable.id) { revealed.remove(variable.id) } else { revealed.insert(variable.id) }
                                    } label: {
                                        Image(systemName: revealed.contains(variable.id) ? "eye.slash" : "eye")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Toggle("", isOn: $variable.secret).labelsHidden().help("Keep the value in the Keychain")
                                Button {
                                    working?.variables.removeAll { $0.id == variable.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            Divider().opacity(0.5)
                        }
                        Button {
                            working?.variables.append(EnvironmentVariable())
                        } label: {
                            Label("Add variable", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else {
            EmptyState(symbol: "globe", title: "No environment selected")
        }
    }

    private func commit() {
        guard let working, let original = store.environments.first(where: { $0.id == working.id }), original != working else { return }
        for variable in original.variables where variable.secret {
            if !working.variables.contains(where: { $0.secret && $0.key == variable.key }) {
                Keychain.delete(store.files.secretAccount(environment: original.id, key: variable.key))
            }
        }
        var cleaned = working
        cleaned.variables.removeAll { $0.key.isEmpty && $0.value.isEmpty }
        store.save(environment: cleaned)
    }
}
