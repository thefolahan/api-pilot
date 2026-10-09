import SwiftUI
import APIPilotKit

struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @State private var address = ""
    @State private var targeted = false

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("API Pilot")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.top, 10)
                Text("Your OpenAPI spec as docs, a request client, tests and a mock server, in one native app.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380, alignment: .leading)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 10) {
                    WelcomeAction(symbol: "doc.badge.plus", title: "Open a spec", detail: "A YAML or JSON file, or a folder that has one") {
                        app.showOpenPanel()
                    }
                    WelcomeAction(symbol: "link", title: "Open from a URL", detail: "Download a published openapi.json") {
                        app.showsOpenURL = true
                    }
                    WelcomeAction(symbol: "sparkles", title: "Try the sample API", detail: "JSONPlaceholder, with live requests") {
                        app.openSample()
                    }
                }
                .padding(.top, 28)
                if let error = app.openError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: 400, alignment: .leading)
                        .padding(.top, 16)
                }
                Spacer()
            }
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Recent").padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 8)
                if app.recents.isEmpty {
                    Text("Specs you open appear here.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(app.recents, id: \.self) { url in
                            RecentRow(url: url) { app.open(url) }
                                .contextMenu {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    Button("Remove from list") { app.forget(url) }
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .frame(width: 300)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.primary.opacity(0.035))
        }
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(12)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            app.open(url)
            return true
        } isTargeted: { targeted = $0 }
        .sheet(isPresented: $app.showsOpenURL) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Open a spec from a URL").font(.headline)
                Text("API Pilot keeps a copy so you can work offline, and Reload (⌘R) downloads it again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("https://petstore3.swagger.io/api/v3/openapi.json", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .onSubmit { Task { await app.openRemote(address) } }
                HStack {
                    if app.isDownloading { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Cancel") { app.showsOpenURL = false }.keyboardShortcut(.cancelAction)
                    Button("Open") { Task { await app.openRemote(address) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(address.isEmpty || app.isDownloading)
                }
            }
            .padding(20)
            .frame(width: 460)
        }
    }
}

private struct WelcomeAction: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hovering ? 0.07 : 0.035)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentRow: View {
    let url: URL
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                Text(url.deletingLastPathComponent().path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var title: String {
        if url.path.contains("/API Pilot/Sample/") { return "JSONPlaceholder sample" }
        let folder = url.deletingLastPathComponent().lastPathComponent
        return url.deletingPathExtension().lastPathComponent.lowercased().hasPrefix("openapi") || url.deletingPathExtension().lastPathComponent.lowercased().hasPrefix("swagger")
            ? folder : url.lastPathComponent
    }
}
