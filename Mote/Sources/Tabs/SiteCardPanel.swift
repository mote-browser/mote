import AppKit
import Combine
import SwiftUI

/// The site card's window: a panel hanging under the padlock that never
/// takes the keyboard, so focus stays where it was. It closes on a click
/// elsewhere, on leaving the app, or on going to another tab.
@MainActor
enum SiteCardPanel {
    private static var panel: Panel?
    private static var leaving: NSObjectProtocol?
    private static var clicks: Any?
    private static var tabWatch: AnyCancellable?

    /// The padlock the card hangs from (see SiteCardAnchor).
    fileprivate static weak var anchor: NSView?

    static var isShown: Bool { panel != nil }

    /// Opens the card, or closes it if it's open.
    static func toggle(for tab: Tab, in browser: Browser) {
        isShown ? hide() : open(for: tab, in: browser)
    }

    /// Opens the card for `tab` once the toolbar shows its padlock (a few
    /// frames after switching to it).
    static func open(for tab: Tab, in browser: Browser, security: Bool = false) {
        guard !tab.isBlank else { return }
        Task {
            for _ in 0..<16 {
                if let anchor, anchor.window != nil, browser.activeID == tab.id {
                    show(for: tab, in: browser, under: anchor, security: security)
                    tabWatch = browser.$activeID.dropFirst().sink { _ in MainActor.assumeIsolated { hide() } }
                    return
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private static func show(for tab: Tab, in browser: Browser, under padlock: NSView, security: Bool) {
        guard let window = padlock.window else { return }
        hide()
        let host = Host(rootView: AnyView(SiteCard(browser: browser, tab: tab, deeper: security) { hide() }.fixedSize()))
        let size = host.fittingSize
        let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        material.material = .menu
        material.state = .active
        // The blur behind is shaped by a mask image only: with the window
        // active it ignores the layer's rounded corners and fills them square.
        material.maskImage = Self.roundedMask(radius: MenuMetrics.corner)
        material.wantsLayer = true
        if let layer = material.layer {
            layer.cornerRadius = MenuMetrics.corner
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            layer.borderWidth = 0.5
            layer.borderColor = MenuMetrics.edge.cgColor
        }
        host.frame = material.bounds
        host.autoresizingMask = [.width, .height]
        material.addSubview(host)

        let panel = Panel(contentRect: material.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = material
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        // Under the padlock, the menu's text in line with the address.
        let spot = window.convertToScreen(padlock.convert(padlock.bounds, to: nil))
        var origin = NSPoint(x: spot.minX - 6, y: spot.minY - 8 - size.height)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = max(origin.y, screen.minY + 8)
        }
        panel.setFrameOrigin(origin)
        window.addChildWindow(panel, ordered: .above)
        // It grows downwards with its content: the security view is taller.
        host.resized = { [weak panel] fitted in
            guard let panel, fitted.height > 0 else { return }
            var frame = panel.frame
            frame.origin.y += frame.height - fitted.height
            frame.size = fitted
            panel.setFrame(frame, display: true)
            // Or the shadow keeps the card's old shape.
            panel.invalidateShadow()
        }
        self.panel = panel
        leaving = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) {
            _ in
            MainActor.assumeIsolated { hide() }
        }
        // A click anywhere but the card closes it; one on the padlock is the
        // padlock's, which toggles.
        clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            MainActor.assumeIsolated {
                let onPadlock =
                    anchor.map { $0.window === event.window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } ?? false
                if event.window !== panel, !onPadlock { hide() }
            }
            return event
        }
    }

    static func hide() {
        if let leaving { NotificationCenter.default.removeObserver(leaving) }
        if let clicks { NSEvent.removeMonitor(clicks) }
        leaving = nil
        clicks = nil
        tabWatch = nil
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
    }

    /// A rounded rectangle that stretches to any size, keeping its corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Takes the first click without the panel becoming key, and says when
    /// its content changes size.
    private final class Host: NSHostingView<AnyView> {
        var resized: ((NSSize) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func invalidateIntrinsicContentSize() {
            super.invalidateIntrinsicContentSize()
            let fitted = fittingSize
            Task { @MainActor [weak self] in self?.resized?(fitted) }
        }
    }
}

/// Marks the padlock the site card hangs from.
struct SiteCardAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let spot = Spot()
        SiteCardPanel.anchor = spot
        return spot
    }

    func updateNSView(_ view: NSView, context: Context) { SiteCardPanel.anchor = view }

    private final class Spot: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
