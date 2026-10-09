import AppKit
import SwiftUI
import APIPilotKit

enum SyntaxHighlighter {
    static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    private static func color(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let keyColor = color(light: NSColor(red: 0.55, green: 0.18, blue: 0.70, alpha: 1), dark: NSColor(red: 0.85, green: 0.62, blue: 1, alpha: 1))
    static let stringColor = color(light: NSColor(red: 0.10, green: 0.50, blue: 0.25, alpha: 1), dark: NSColor(red: 0.55, green: 0.86, blue: 0.55, alpha: 1))
    static let numberColor = color(light: NSColor(red: 0.12, green: 0.36, blue: 0.85, alpha: 1), dark: NSColor(red: 0.50, green: 0.75, blue: 1, alpha: 1))
    static let literalColor = color(light: NSColor(red: 0.80, green: 0.25, blue: 0.10, alpha: 1), dark: NSColor(red: 1, green: 0.58, blue: 0.40, alpha: 1))
    static let variableColor = color(light: NSColor(red: 0, green: 0.50, blue: 0.60, alpha: 1), dark: NSColor(red: 0.35, green: 0.85, blue: 0.90, alpha: 1))

    static func highlight(_ storage: NSTextStorage) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: full)
        guard text.length < 1_500_000 else {
            storage.endEditing()
            return
        }
        var index = 0
        let length = text.length
        while index < length {
            let character = text.character(at: index)
            switch character {
            case 0x22:
                var end = index + 1
                while end < length {
                    let current = text.character(at: end)
                    if current == 0x5C { end += 2; continue }
                    if current == 0x22 || current == 0x0A { break }
                    end += 1
                }
                end = min(end + 1, length)
                var look = end
                while look < length, [0x20, 0x09].contains(text.character(at: look)) { look += 1 }
                let isKey = look < length && text.character(at: look) == 0x3A
                storage.addAttribute(.foregroundColor, value: isKey ? keyColor : stringColor, range: NSRange(location: index, length: end - index))
                index = end
            case 0x2D, 0x30...0x39:
                let previous = index > 0 ? text.character(at: index - 1) : 0x20
                let startsToken = !(isWordCharacter(previous))
                var end = index + 1
                while end < length, isNumberCharacter(text.character(at: end)) { end += 1 }
                if startsToken && (end >= length || !isWordCharacter(text.character(at: end))) {
                    storage.addAttribute(.foregroundColor, value: numberColor, range: NSRange(location: index, length: end - index))
                }
                index = end
            case 0x74, 0x66, 0x6E:
                var matched = false
                for word in ["true", "false", "null"] where index + word.count <= length {
                    let range = NSRange(location: index, length: word.count)
                    let before = index > 0 ? text.character(at: index - 1) : 0x20
                    let after = index + word.count < length ? text.character(at: index + word.count) : 0x20
                    if text.substring(with: range) == word, !isWordCharacter(before), !isWordCharacter(after) {
                        storage.addAttribute(.foregroundColor, value: literalColor, range: range)
                        index += word.count
                        matched = true
                        break
                    }
                }
                if !matched { index += 1 }
            default:
                index += 1
            }
        }
        let pattern = try! NSRegularExpression(pattern: #"\{\{[^{}]+\}\}"#)
        for match in pattern.matches(in: storage.string, range: full) {
            storage.addAttributes([
                .foregroundColor: variableColor,
                .backgroundColor: variableColor.withAlphaComponent(0.12)
            ], range: match.range)
        }
        storage.endEditing()
    }

    private static func isWordCharacter(_ character: unichar) -> Bool {
        (0x30...0x39).contains(character) || (0x41...0x5A).contains(character) || (0x61...0x7A).contains(character) || character == 0x5F
    }

    private static func isNumberCharacter(_ character: unichar) -> Bool {
        (0x30...0x39).contains(character) || [0x2E, 0x65, 0x45, 0x2B, 0x2D].contains(character)
    }
}

struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var highlights = true
    var wraps = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = SyntaxHighlighter.font
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.typingAttributes = [.font: SyntaxHighlighter.font, .foregroundColor: NSColor.labelColor]
        if !wraps {
            textView.isHorizontallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
        }
        textView.string = text
        context.coordinator.rehighlight(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            if isEditable, let first = selection.first as? NSRange, first.location <= (text as NSString).length {
                textView.selectedRanges = selection
            }
            context.coordinator.rehighlight(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        private var pending: DispatchWorkItem?

        init(_ parent: CodeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            pending?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                if let textView { self?.rehighlight(textView) }
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        func rehighlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            if parent.highlights {
                SyntaxHighlighter.highlight(storage)
            } else {
                storage.setAttributes([.font: SyntaxHighlighter.font, .foregroundColor: NSColor.labelColor],
                                      range: NSRange(location: 0, length: storage.length))
            }
        }
    }
}
