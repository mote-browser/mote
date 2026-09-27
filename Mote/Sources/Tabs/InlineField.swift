import AppKit
import SwiftUI

/// A text field that edits in place inside a tab: renaming it, or a pinned
/// tab's letter. It takes the keyboard with its text selected, so typing
/// replaces it, and ends on Return, Escape, or a click anywhere else.
/// AppKit's, for a selection colour SwiftUI's field can't set.
struct InlineField: NSViewRepresentable {
    let text: String
    var font = NSFont.systemFont(ofSize: 12.5)
    var centered = false
    /// Tab ends the edit as Return does.
    var tabEnds = false
    /// The text typed; returns what the field should show instead, if anything
    /// (a letter trimmed to one character).
    let changed: (String) -> String?
    /// Return (true) or Escape (false).
    let ended: (_ keep: Bool) -> Void
    /// Focus left some other way.
    let left: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.alignment = centered ? .center : .natural
        field.textColor = Palette.NS.ink
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.stringValue = text
        context.coordinator.watchClicks(outside: field)
        return field
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.stopWatching()
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.owner = self
        if !coordinator.typing, field.stringValue != text { field.stringValue = text }
        guard !coordinator.focused else { return }
        coordinator.focused = true
        Task { @MainActor in
            field.window?.makeFirstResponder(field)
            guard let editor = field.currentEditor() as? NSTextView else { return }
            editor.selectedTextAttributes = [.backgroundColor: NSColor(Palette.ink.opacity(0.11)), .foregroundColor: Palette.NS.ink]
            editor.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: InlineField?
        var focused = false
        var typing = false
        private var clicks: Any?

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            typing = true
            if let shown = owner?.changed(field.stringValue) { field.stringValue = shown }
            typing = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)):
                owner?.ended(true)
            case #selector(NSResponder.cancelOperation(_:)):
                owner?.ended(false)
            case #selector(NSResponder.insertTab(_:)) where owner?.tabEnds == true:
                owner?.ended(true)
            default:
                return false
            }
            return true
        }

        func controlTextDidEndEditing(_ note: Notification) {
            let left = owner?.left
            Task { @MainActor in left?() }
        }

        /// Clicks on things that can't take the keyboard don't end editing on
        /// their own, so a click anywhere outside the field does. The clicks
        /// themselves go on as usual.
        @MainActor func watchClicks(outside field: NSTextField) {
            guard clicks == nil else { return }
            clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
                [weak self, weak field] event in
                guard let field, event.window === field.window, !field.bounds.contains(field.convert(event.locationInWindow, from: nil))
                else { return event }
                let left = self?.owner?.left
                Task { @MainActor in left?() }
                return event
            }
        }

        @MainActor func stopWatching() {
            if let clicks { NSEvent.removeMonitor(clicks) }
            clicks = nil
        }
    }
}

extension InlineField {
    /// Renaming the tab being edited: an empty name brings back the page title.
    static func rename(_ browser: Browser) -> InlineField {
        InlineField(
            text: browser.tabDraft,
            changed: {
                browser.tabDraft = $0
                return nil
            }
        ) { keep in
            keep ? browser.commitTabEdit() : browser.cancelTabEdit()
        } left: {
            browser.finishTabEdit()
        }
    }

    /// A pinned tab's letter.
    static func letter(of tab: Tab, in browser: Browser) -> InlineField {
        InlineField(
            text: tab.pin ?? "", font: .systemFont(ofSize: 12, weight: .medium), centered: true, tabEnds: true,
            changed: {
                browser.letter($0, for: tab)
                return tab.pin ?? ""
            }, ended: { _ in browser.endPinEdit() }, left: { browser.endPinEdit() })
    }
}
