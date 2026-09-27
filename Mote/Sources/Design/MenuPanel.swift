import AppKit
import SwiftUI

extension View {
    /// Shows `content` as a menu beside this view while `isPresented` is true:
    /// a rounded card in a panel of its own, on the given `edge` of the view.
    ///
    /// Used instead of a popover because a popover's arrow can't be removed,
    /// and when the button sits at the bottom of the screen the arrow is pushed
    /// into the popover's rounded corner, which then loses its shape.
    func menuPanel<Content: View>(
        isPresented: Binding<Bool>, edge: Edge, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(MenuPanelAnchor(isPresented: isPresented, edge: edge, content: content))
    }
}

/// Marks where the menu opens from and presents it.
private struct MenuPanelAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let edge: Edge
    let content: () -> Content

    func makeCoordinator() -> MenuPanel { MenuPanel() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ anchor: NSView, context: Context) {
        let menu = context.coordinator
        menu.dismissed = { isPresented = false }
        if isPresented {
            menu.show(AnyView(content()), from: anchor, edge: edge)
        } else {
            menu.close()
        }
    }

    static func dismantleNSView(_ anchor: NSView, coordinator: MenuPanel) {
        coordinator.close()
    }
}

/// A menu in a borderless panel beside the control that opened it. It closes
/// on a click anywhere else, on Escape, when Mote stops being the active app,
/// and when the window it belongs to closes.
@MainActor
final class MenuPanel {
    /// Space between the control and the menu, in points.
    static let gap: CGFloat = 6
    /// Closest the menu comes to the screen's edges, in points.
    static let margin: CGFloat = 8
    static let cornerRadius: CGFloat = 14

    /// Called when the menu closes by itself, so the caller can clear its state.
    var dismissed: () -> Void = {}

    private var panel: Panel?
    private var host: NSHostingView<AnyView>?
    private weak var anchor: NSView?
    private var monitors: [Any] = []
    /// Set while the menu closes. Closing the panel makes SwiftUI update the
    /// view that owns it, which may still ask for the menu; it isn't reopened.
    private var closing = false
    private var observers: [NSObjectProtocol] = []

    var isShown: Bool { panel?.isVisible == true }

    /// Where a menu of `size` opens on `edge` of `anchor` (both in screen
    /// coordinates), kept within `screen` and flipped to the other side when
    /// there is no room.
    static func frame(size: NSSize, anchor: NSRect, edge: Edge, within screen: NSRect) -> NSRect {
        let bounds = screen.insetBy(dx: margin, dy: margin)
        var origin: NSPoint
        switch edge {
        case .trailing, .leading:
            let right = anchor.maxX + gap
            let left = anchor.minX - gap - size.width
            let fitsRight = right + size.width <= bounds.maxX
            let fitsLeft = left >= bounds.minX
            let x = edge == .trailing ? (fitsRight || !fitsLeft ? right : left) : (fitsLeft || !fitsRight ? left : right)
            // Rises from the control's bottom, as a menu from a footer button would.
            origin = NSPoint(x: x, y: anchor.minY)
        case .bottom, .top:
            let below = anchor.minY - gap - size.height
            let above = anchor.maxY + gap
            let fitsBelow = below >= bounds.minY
            let fitsAbove = above + size.height <= bounds.maxY
            let y = edge == .bottom ? (fitsBelow || !fitsAbove ? below : above) : (fitsAbove || !fitsBelow ? above : below)
            origin = NSPoint(x: anchor.minX, y: y)
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }

    func show(_ content: AnyView, from anchor: NSView, edge: Edge) {
        let card = AnyView(
            content
                .background(Palette.ground)
                .clipShape(RoundedRectangle(cornerRadius: MenuPanel.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MenuPanel.cornerRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
        guard !closing else { return }
        if let host, isShown {
            host.rootView = card
            return
        }
        // A panel that is no longer on screen is replaced, never left behind.
        close()
        guard let window = anchor.window, let screen = window.screen ?? NSScreen.main else { return }
        self.anchor = anchor

        let host = NSHostingView(rootView: card)
        let size = host.fittingSize
        let panel = Panel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        // Hidden by AppKit as soon as Mote stops being the active app.
        panel.hidesOnDeactivate = true
        panel.appearance = window.effectiveAppearance
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.dismiss() }

        let anchorOnScreen = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        panel.setFrame(MenuPanel.frame(size: size, anchor: anchorOnScreen, edge: edge, within: screen.visibleFrame), display: true)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.host = host
        watch(window)
    }

    /// Closes the menu without telling the caller, which already knows.
    func close() {
        guard !closing else { return }
        closing = true
        defer { closing = false }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        // Let go of the panel before ordering it out: ordering out updates
        // SwiftUI, and whatever that does must not find this panel still here.
        let closed = panel
        panel = nil
        host = nil
        closed?.orderOut(nil)
    }

    /// Closes the menu because of something the user did outside it.
    private func dismiss() {
        guard isShown else { return }
        // The owner learns first, so any update that closing causes already
        // sees the menu as closed.
        dismissed()
        close()
    }

    private func watch(_ window: NSWindow) {
        let mouseDowns: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: mouseDowns,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.clicked(event) }
                return event
            })
        {
            monitors.append(local)
        }
        // Clicks in other apps. While Mote isn't the active app, clicks on its
        // own windows are reported here too; the local monitor handles those.
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: mouseDowns,
            handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    let point = NSEvent.mouseLocation
                    guard !NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(point) }) else { return }
                    self?.dismiss()
                }
            })
        {
            monitors.append(global)
        }
        let center = NotificationCenter.default
        for (name, object) in [
            (NSApplication.didResignActiveNotification, nil as AnyObject?),
            (NSWindow.willCloseNotification, window),
            (NSWindow.didMoveNotification, window),
        ] {
            observers.append(
                center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss() }
                })
        }
    }

    /// A click outside the menu closes it, except on the control that opened
    /// it: that control toggles the menu itself.
    private func clicked(_ event: NSEvent) {
        guard let panel, event.window !== panel else { return }
        if let anchor, let window = anchor.window, event.window === window {
            let point = anchor.convert(event.locationInWindow, from: nil)
            if anchor.bounds.contains(point) { return }
        }
        dismiss()
    }

    /// A borderless panel that can take key status, so the menu's own controls
    /// and Escape work.
    private final class Panel: NSPanel {
        var onEscape: () -> Void = {}

        override var canBecomeKey: Bool { true }

        override func cancelOperation(_ sender: Any?) { onEscape() }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onEscape() } else { super.keyDown(with: event) }
        }
    }
}
