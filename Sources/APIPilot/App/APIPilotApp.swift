import AppKit
import SwiftUI

@main
struct APIPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()

    var body: some Scene {
        Window("API Pilot", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1360, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Spec…") { app.showOpenPanel() }
                    .keyboardShortcut("o")
                Button("Open from URL…") {
                    app.closeWorkspace()
                    app.showsOpenURL = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Open Sample API") { app.openSample() }
                Divider()
                Button("Close Workspace") { app.closeWorkspace() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(app.workspace == nil)
            }
            CommandGroup(after: .importExport) {
                Button("Export HTML Docs…") { app.workspace?.exportDocs() }
                    .disabled(app.workspace == nil)
                Button("Show Workspace in Finder") {
                    if let workspace = app.workspace { NSWorkspace.shared.activateFileViewerSelecting([workspace.files.specURL]) }
                }
                .disabled(app.workspace == nil)
            }
            CommandMenu("API") {
                Button("Reload Spec") { app.workspace?.reloadSpec() }
                    .keyboardShortcut("r")
                    .disabled(app.workspace == nil)
                Button("Environments…") { NotificationCenter.default.post(name: .showEnvironments, object: nil) }
                    .keyboardShortcut("e")
                    .disabled(app.workspace == nil)
                Divider()
                Button("Run Collection") { app.workspace?.startRunner() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(app.workspace?.savedRequests.isEmpty ?? true)
                Button(app.workspace?.mockRunning == true ? "Stop Mock Server" : "Start Mock Server") { app.workspace?.toggleMock() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(app.workspace == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        AppDelegate.pendingURLs = urls
        NotificationCenter.default.post(name: .openFiles, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let workspace = app.workspace {
                WorkspaceView()
                    .environment(workspace)
                    .id(ObjectIdentifier(workspace))
            } else {
                WelcomeView()
                    .navigationTitle("API Pilot")
            }
        }
        .onAppear {
            openPending()
            applyLaunchArguments()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFiles)) { _ in openPending() }
    }

    private func openPending() {
        guard let url = AppDelegate.pendingURLs.first else { return }
        AppDelegate.pendingURLs.removeAll()
        app.open(url)
    }

    private func applyLaunchArguments() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "APIPilotSample") { app.openSample() }
        if let path = defaults.string(forKey: "APIPilotOpen") { app.open(URL(fileURLWithPath: path)) }
        guard let workspace = app.workspace, let id = defaults.string(forKey: "APIPilotSelect") else { return }
        workspace.selection = id == "overview" ? .overview : .operation(id)
        if defaults.bool(forKey: "APIPilotSend"), let session = workspace.currentSession {
            workspace.send(session)
        }
    }
}

extension Notification.Name {
    static let openFiles = Notification.Name("APIPilotOpenFiles")
}
