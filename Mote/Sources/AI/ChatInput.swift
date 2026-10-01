import AppKit
import SwiftUI

/// Where the next message is written: AppKit's text view, so Return sends
/// while Shift- or Option-Return starts a new line, and it grows with the
/// text up to a few lines before scrolling.
struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    /// The height the text needs, for the frame around it.
    @Binding var height: CGFloat
    var placeholder: String
    /// Incremented to ask for the keyboard.
    var focus: Int
    let submit: () -> Void
    /// Move a highlight while a picker is open. False leaves normal navigation alone.
    let moveSelection: (Int) -> Bool
    /// Confirm the highlighted picker item. False leaves normal Tab handling alone.
    let choose: () -> Bool
    /// Escape; true when it was used.
    let escape: () -> Bool

    static let font = NSFont.systemFont(ofSize: 14)
    static var line: CGFloat { ceil(font.ascender - font.descender + font.leading) + 2 }
    static let most: CGFloat = line * 8

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let view = scroll.documentView as! NSTextView
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = Self.font
        view.textColor = Palette.NS.ink
        view.insertionPointColor = Palette.NS.ink
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.selectedTextAttributes = [.backgroundColor: NSColor(Palette.ink.opacity(0.12)), .foregroundColor: Palette.NS.ink]
        view.setAccessibilityLabel(placeholder)
        view.string = text
        view.postsFrameChangedNotifications = true
        context.coordinator.view = view
        // A new width can take the text over more or fewer lines.
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.resized), name: NSView.frameDidChangeNotification, object: view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let view = coordinator.view else { return }
        if view.string != text {
            view.string = text
            // A draft seeded from outside (a selection asked about) leaves the
            // caret at its end, ready to edit; typing itself never lands here.
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            coordinator.measure()
        }
        if coordinator.focused != focus {
            coordinator.focused = focus
            Task { @MainActor in
                for _ in 0..<10 where view.window == nil { try? await Task.sleep(for: .milliseconds(20)) }
                view.window?.makeFirstResponder(view)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput
        weak var view: NSTextView?
        var focused = -1

        init(_ parent: ChatInput) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            parent.text = view.string
            measure()
        }

        @objc func resized() { measure() }

        /// Reports the height the text needs, after the current view update.
        func measure() {
            guard let view, let manager = view.layoutManager, let container = view.textContainer else { return }
            manager.ensureLayout(for: container)
            let used = max(manager.usedRect(for: container).height, ChatInput.line)
            let wanted = min(ceil(used), ChatInput.most)
            guard abs(wanted - parent.height) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in self?.parent.height = wanted }
        }

        func textView(_ textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                // Shift or Option makes a new line, as in every chat.
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.submit()
                }
                return true
            case #selector(NSResponder.insertTab(_:)):
                return parent.choose()
            case #selector(NSResponder.moveDown(_:)):
                return parent.moveSelection(1)
            case #selector(NSResponder.moveUp(_:)):
                return parent.moveSelection(-1)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.escape()
            default:
                return false
            }
        }
    }
}
