import SwiftUI

enum Palette {
    static func method(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return Color(red: 0.13, green: 0.62, blue: 0.36)
        case "POST": return Color(red: 0.86, green: 0.47, blue: 0.05)
        case "PUT": return Color(red: 0.15, green: 0.41, blue: 0.92)
        case "PATCH": return Color(red: 0.49, green: 0.29, blue: 0.91)
        case "DELETE": return Color(red: 0.86, green: 0.17, blue: 0.17)
        default: return .secondary
        }
    }

    static func status(_ status: Int) -> Color {
        switch status {
        case 200..<300: return Color(red: 0.13, green: 0.62, blue: 0.36)
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500...: return .red
        default: return .secondary
        }
    }

    static func status(_ code: String) -> Color {
        Int(code).map(status) ?? (code.hasPrefix("2") ? status(200) : code.hasPrefix("4") ? status(400) : code.hasPrefix("5") ? status(500) : .secondary)
    }
}

struct MethodBadge: View {
    let method: String
    var compact = false

    private var shortName: String {
        switch method.uppercased() {
        case "DELETE": return "DEL"
        case "OPTIONS": return "OPT"
        default: return method.uppercased()
        }
    }

    var body: some View {
        Text(compact ? shortName : method)
            .font(.system(size: compact ? 9 : 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(Palette.method(method))
            .frame(width: compact ? 38 : nil, alignment: .leading)
            .padding(.horizontal, compact ? 0 : 6)
            .padding(.vertical, compact ? 0 : 2)
            .background {
                if !compact {
                    RoundedRectangle(cornerRadius: 5).fill(Palette.method(method).opacity(0.14))
                }
            }
    }
}

struct StatusPill: View {
    let code: String
    var text: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Palette.status(code)).frame(width: 7, height: 7)
            Text(code).font(.system(.callout, design: .monospaced).weight(.semibold))
            if let text { Text(text).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(Palette.status(code).opacity(0.12)))
    }
}

struct TabStrip<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    var badge: (Tab) -> String? = { _ in nil }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 4) {
                        Text(title(tab))
                        if let badge = badge(tab) {
                            Text(badge)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout.weight(selection == tab ? .semibold : .regular))
                    .foregroundStyle(selection == tab ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline).foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct MarkdownText: View {
    let text: String

    var body: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        Text(attributed).textSelection(.enabled)
    }
}

extension Int {
    var byteText: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

extension TimeInterval {
    var millisecondText: String {
        self < 1 ? "\(Int(self * 1000)) ms" : String(format: "%.2f s", self)
    }
}
