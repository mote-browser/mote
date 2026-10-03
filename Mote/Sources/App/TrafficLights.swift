import AppKit
import MoteCore
import SwiftUI

/// The original AppKit group is hosted inside the moving pane.
struct TrafficLights: NSViewRepresentable {
    var showing: Bool
    var strip = false
    var inset: CGFloat = 0
    func makeNSView(context: Context) -> Host { Host() }
    func updateNSView(_ host: Host, context: Context) {
        host.showing = showing
        host.strip = strip
        host.inset = inset
        host.mount()
    }

    @MainActor final class Host: NSView {
        static let groups = NSMapTable<NSWindow, NSView>.weakToStrongObjects()
        static let titlebars = NSMapTable<NSWindow, NSView>.weakToWeakObjects()
        static let hosts = NSHashTable<Host>.weakObjects()
        var showing = false
        var strip = false
        var inset: CGFloat = 0
        override var isFlipped: Bool { true }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            Self.hosts.add(self)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            mount()
        }
        func mount() {
            guard showing, let window, !window.styleMask.contains(.fullScreen) else { return }
            let group: NSView
            if let saved = Self.groups.object(forKey: window) {
                group = saved
            } else {
                guard let original = window.standardWindowButton(.closeButton)?.superview else { return }
                // The empty system titlebar must not cover the controls now
                // hosted in full-size content, or intercept their hover.
                original.superview?.isHidden = true
                if let titlebar = original.superview { Self.titlebars.setObject(titlebar, forKey: window) }
                group = original
                group.autoresizesSubviews = false
                group.autoresizingMask = []
                Self.groups.setObject(group, forKey: window)
            }
            if group.superview !== self { addSubview(group) }
            layoutControls()
        }
        override func layout() {
            super.layout()
            layoutControls()
        }
        private func layoutControls() {
            guard let window, let group = Self.groups.object(forKey: window), group.superview === self else { return }
            Self.titlebars.object(forKey: window)?.isHidden = true
            group.frame = bounds
            let center = ChromeLayout.lights(for: strip ? .strip : .sidebar)
            for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                button.autoresizingMask = []
                let y =
                    group.isFlipped
                    ? center.y - inset - button.frame.height / 2 : bounds.height - center.y + inset - button.frame.height / 2
                button.setFrameOrigin(NSPoint(x: center.x - inset + CGFloat(index) * 20 - button.frame.width / 2, y: y))
                button.isHidden = false
                button.updateTrackingAreas()
            }
            group.updateTrackingAreas()
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            let hit = super.hitTest(point)
            return hit === self ? nil : hit
        }
    }
    @MainActor static func refresh(in window: NSWindow) {
        for host in Host.hosts.allObjects where host.window === window && host.showing { host.mount() }
    }
    @MainActor static func visible(in window: NSWindow) -> Bool {
        window.standardWindowButton(.closeButton).map { !$0.isHiddenOrHasHiddenAncestor } ?? false
    }
}
