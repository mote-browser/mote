import AppKit
import MoteCore
import SwiftUI

/// The address field itself. AppKit's, for inline completion: the rest of
/// an address shows after the caret, selected, so typing replaces it and
/// Return takes it; SwiftUI's field can't do that.
struct AddressField: NSViewRepresentable {
    @ObservedObject var browser: Browser
    var size: CGFloat = 15.5
    var placeholder = "Search or enter address"
    /// For a click outside the field and its suggestions (see KeepZone); nil
    /// leaves such clicks alone.
    var outside: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: size)
        field.textColor = Palette.NS.ink
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.placeholderAttributedString = prompt
        if let outside { context.coordinator.endOnClicks(outside: field, outside) }
        return field
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.stopWatching()
    }

    /// In ink, faintly: the system's placeholder all but disappears on a light ground.
    private var prompt: NSAttributedString {
        NSAttributedString(
            string: placeholder, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor(Palette.ink.opacity(0.35))])
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.browser = browser
        if field.placeholderAttributedString?.string != placeholder { field.placeholderAttributedString = prompt }
        // Only changes from outside (⌘L, walking the list, submitting). Checked
        // against the field's own text, the completion would come back after
        // every backspace and an address could never be shortened.
        let wanted = browser.field.completed
        if wanted != coordinator.shown {
            coordinator.shown = wanted
            field.stringValue = wanted
            Coordinator.selectCompletion(in: field, after: browser.field.typed)
        }
        if coordinator.focusAnswered != browser.field.focusRequest {
            coordinator.focusAnswered = browser.field.focusRequest
            Task { @MainActor in await Self.takeKeyboard(field) }
        }
    }

    /// Takes the keyboard with the text selected. A field SwiftUI just made
    /// may not be in its window yet, so it keeps trying for a moment.
    private static func takeKeyboard(_ field: NSTextField) async {
        for _ in 0..<10 where field.window == nil { try? await Task.sleep(for: .milliseconds(20)) }
        guard let window = field.window else { return }
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else { return }
        Coordinator.quietSelection(editor)
        editor.selectAll(nil)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var browser: Browser
        var focusAnswered = -1
        /// The text last put in from outside, to tell those changes from typing.
        var shown = ""
        /// A delete is under way: the next change mustn't complete again what
        /// was just deleted.
        private var deleting = false
        private var clicks: Any?

        init(browser: Browser) { self.browser = browser }

        /// A softer selection than the accent colour.
        static func quietSelection(_ editor: NSTextView) {
            editor.selectedTextAttributes = [.backgroundColor: NSColor(Palette.ink.opacity(0.12)), .foregroundColor: Palette.NS.ink]
        }

        /// Selects what follows `typed`, the completion. Counted in UTF-16,
        /// as NSRange is.
        static func selectCompletion(in field: NSTextField, after typed: String) {
            guard let editor = field.currentEditor() as? NSTextView else { return }
            quietSelection(editor)
            let whole = (field.stringValue as NSString).length
            let start = (typed as NSString).length
            if start <= whole { editor.selectedRange = NSRange(location: start, length: whole - start) }
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            let typed = field.stringValue
            browser.field.typed = typed
            defer { deleting = false }
            guard !deleting, let ending = browser.field.ending else {
                if deleting { browser.field.stopCompleting() }
                shown = browser.field.completed
                return
            }
            field.stringValue = typed + ending
            shown = field.stringValue
            Self.selectCompletion(in: field, after: typed)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)): browser.submit()
            case #selector(NSResponder.moveDown(_:)): browser.field.walk(1)
            case #selector(NSResponder.moveUp(_:)): browser.field.walk(-1)
            case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)):
                deleting = true
                return false
            default: return false
            }
            return true
        }

        /// Clicks on things that can't take the keyboard don't end editing by
        /// themselves, so clicks outside the field and its keep zones do. The
        /// clicks go on as usual.
        @MainActor func endOnClicks(outside field: NSTextField, _ outside: @escaping () -> Void) {
            guard clicks == nil else { return }
            clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak field] event in
                MainActor.assumeIsolated {
                    guard let field, event.window === field.window,
                        !field.bounds.contains(field.convert(event.locationInWindow, from: nil)),
                        !KeepZone.contains(event.locationInWindow, in: event.window)
                    else { return }
                    Task { @MainActor in outside() }
                }
                return event
            }
        }

        @MainActor func stopWatching() {
            if let clicks { NSEvent.removeMonitor(clicks) }
            clicks = nil
        }
    }
}
