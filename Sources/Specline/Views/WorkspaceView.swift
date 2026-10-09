import SwiftUI

struct WorkspaceView: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store
    @AppStorage("showsDocs") private var showsDocs = true
    @State private var showsEnvironments = false
    @State private var showsMock = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 400)
        } detail: {
            detail
                .inspector(isPresented: inspectorBinding) {
                    if let session = store.currentSession, let operation = store.operation(for: session.draft) {
                        OperationDocsView(operation: operation, spec: store.spec)
                            .inspectorColumnWidth(min: 280, ideal: 340, max: 520)
                    } else {
                        EmptyState(symbol: "book", title: "No docs", message: "This request is not linked to an endpoint in the spec.")
                            .inspectorColumnWidth(min: 280, ideal: 340, max: 520)
                    }
                }
        }
        .navigationTitle(store.spec.title)
        .navigationSubtitle(store.activeEnvironment?.name ?? "No environment")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                environmentMenu
                Button {
                    showsMock.toggle()
                } label: {
                    Label("Mock server", systemImage: store.mockRunning ? "server.rack" : "server.rack")
                        .foregroundStyle(store.mockRunning ? Color.green : Color.primary)
                }
                .help(store.mockRunning ? "Mock server running on port \(store.mockPort)" : "Start a mock server from the spec")
                .popover(isPresented: $showsMock, arrowEdge: .bottom) {
                    MockPanel().environment(store)
                }
                Button {
                    store.startRunner()
                } label: {
                    Label("Run collection", systemImage: "play.rectangle")
                }
                .help("Run every saved request and its tests (⇧⌘R)")
                .disabled(store.savedRequests.isEmpty)
                if store.currentSession != nil {
                    Button {
                        showsDocs.toggle()
                    } label: {
                        Label("Docs", systemImage: "sidebar.right")
                    }
                    .help("Show the documentation for this endpoint")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = store.notice {
                Text(notice)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: store.notice)
        .sheet(isPresented: $showsEnvironments) {
            EnvironmentEditor().environment(store)
        }
        .sheet(isPresented: Binding(get: { store.runner != nil }, set: { if !$0 { store.runner = nil } })) {
            if let runner = store.runner {
                RunnerView(runner: runner).environment(store)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showEnvironments)) { _ in showsEnvironments = true }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            app.open(url)
            return true
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(get: { showsDocs && store.currentSession != nil }, set: { showsDocs = $0 })
    }

    @ViewBuilder private var detail: some View {
        switch store.selection {
        case .overview, .none:
            OverviewView()
        case .schema(let name):
            SchemaPage(name: name)
        default:
            if let session = store.currentSession {
                RequestView(session: session)
                    .id(session.id)
            } else {
                EmptyState(symbol: "questionmark.folder", title: "This item is no longer in the workspace")
            }
        }
    }

    private var environmentMenu: some View {
        Menu {
            Picker("Environment", selection: Binding(get: { store.activeEnvironmentID }, set: { store.activeEnvironmentID = $0 })) {
                ForEach(store.environments) { environment in
                    Text(environment.name).tag(Optional(environment.id))
                }
                if store.mockRunning {
                    Text("Mock server").tag(Optional(WorkspaceStore.mockEnvironmentID))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Manage environments…") { showsEnvironments = true }
        } label: {
            Label(store.activeEnvironment?.name ?? "Environment", systemImage: "globe")
                .labelStyle(.titleAndIcon)
        }
        .help("Choose the environment whose variables fill {{placeholders}} (⌘E to edit)")
    }
}

extension Notification.Name {
    static let showEnvironments = Notification.Name("SpeclineShowEnvironments")
}
