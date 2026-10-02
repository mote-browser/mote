import AppKit
import MoteCore
import SwiftUI

/// Hands over the window once the view is in one, for what has to be set
/// up in AppKit.
struct WindowSetup: NSViewRepresentable {
    let ready: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Probe(ready: ready) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Probe: NSView {
        let ready: (NSWindow) -> Void

        init(ready: @escaping (NSWindow) -> Void) {
            self.ready = ready
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        /// Never hit: it can lie over views spanning the window (SidebarFold's)
        /// and would take their clicks.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // The window is still being set up; anything set now would be overwritten.
            Task { @MainActor in self.ready(window) }
        }
    }
}

/// The title bar's behaviour — drag to move, double-click to zoom — in a
/// window whose title bar is under SwiftUI content.
struct DragStrip: NSViewRepresentable {
    /// From the leading edge, left to the tabs: the strip is under them but
    /// would be hit first, so it lets clicks there through.
    var reserved: CGFloat = 0
    /// From the top edge, left to other content (the sidebar's tabs).
    var below: CGFloat = 0
    /// From the trailing edge, left to a button.
    var trailing: CGFloat = 0
    /// A single click on the empty new-tab background focuses its composer.
    var click: () -> Void = {}

    func makeNSView(context: Context) -> NSView { Strip() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let strip = view as? Strip else { return }
        strip.reserved = reserved
        strip.below = below
        strip.trailing = trailing
        strip.click = click
    }

    final class Strip: NSView {
        var reserved: CGFloat = 0
        var below: CGFloat = 0
        var trailing: CGFloat = 0
        var click: () -> Void = {}
        private var pressed: NSEvent?
        private var dragged = false

        /// The strip drags and double-clicks by itself; left to AppKit too, a
        /// double click would happen twice (down and up) and undo itself.
        override var mouseDownCanMoveWindow: Bool { false }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            // AppKit counts up from the bottom; `below` is from the top.
            guard local.x >= reserved, local.x <= bounds.width - trailing, bounds.height - local.y >= below else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            pressed = event
            dragged = false
        }

        /// The window doesn't move by itself (so dragging a tab doesn't move it);
        /// for this one drag it may, handed to the system's drag with its snapping and tiling.
        override func mouseDragged(with event: NSEvent) {
            guard let window, let pressed, !dragged,
                max(abs(event.locationInWindow.x - pressed.locationInWindow.x), abs(event.locationInWindow.y - pressed.locationInWindow.y))
                    >= 3
            else { return }
            dragged = true
            window.isMovable = true
            window.performDrag(with: pressed)
            window.isMovable = false
        }

        /// A double click, on the way up, does what System Settings says.
        override func mouseUp(with event: NSEvent) {
            guard !dragged else { return }
            if event.clickCount == 1 { click() }
            guard let window, event.clickCount == 2 else { return }
            switch TitleBarClick(setting: UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")) {
            case .zoom: window.zoom(nil)
            case .minimize: window.miniaturize(nil)
            case .nothing: break
            }
        }
    }
}

/// Traffic lights drawn by Mote while the app is in the background: the
/// system's are almost invisible on a light window then. Drawn where the
/// real buttons are, in the title bar, above the window's content.
final class RestingLights: NSView {
    /// The buttons' frames; a redraw only when they change.
    var spots: [CGRect] = [] {
        didSet { if spots != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirty: NSRect) {
        Palette.NS.resting.setFill()
        spots.forEach { NSBezierPath(ovalIn: $0).fill() }
    }

    /// Never hit: the real buttons under it take over once the app is active.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
