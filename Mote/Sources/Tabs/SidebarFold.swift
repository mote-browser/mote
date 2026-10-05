import MoteCore
import SwiftUI
import WebKit

/// Folded tabs (⌘S): they slide out over the page when the pointer reaches
/// the window's left edge (or top, for the strip) and go again soon after it
/// leaves, the traffic lights with them. The sidebar comes out as a panel of
/// its own floating over the card. When is EdgeReveal's decision.
struct SidebarFold: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @State private var timers = PeekTimers()
    @State private var pointer = PointerWatch()
    /// The pointer is over the peeking tabs.
    @State private var inside = false

    private static let corner: CGFloat = 12

    /// Folded, with the page not full screen.
    private var folding: Bool { browser.folded && browser.active?.immersed != true }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // With the sidebar the page reaches the window's top, so a thin band
            // there drags the window and double-click zooms it.
            if prefs.sidebar, browser.active?.immersed != true {
                DragStrip().frame(height: ChromeLayout.gap).frame(maxWidth: .infinity)
            }
            if folding, !prefs.sidebar, browser.peeking {
                // The strip has no ground of its own: give it the frame's, so the page
                // doesn't show through and its shadow falls from the strip's edge.
                TabBar(browser: browser)
                    .background { Palette.frame.shadow(color: .black.opacity(0.16), radius: 20, y: 6) }
                    .transition(.move(edge: .top))
            }
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: 0)
                if folding, prefs.sidebar, browser.peeking {
                    floatingSidebar.padding(ChromeLayout.gap).transition(.move(edge: .leading))
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .onAppear {
            watch()
        }
        .onDisappear {
            pointer.stop()
            timers.cancelShow()
            timers.cancelHide()
        }
        .background(
            WindowSetup { window in
                pointer.window = window
                watch()
            }
        )
        .onChange(of: folding) {
            timers.cancelShow()
            timers.cancelHide()
            inside = false
            watch()
        }
        // Each layout owns its persisted fold; a temporary peek never carries over.
        .onChange(of: prefs.sidebar) {
            browser.peeking = false
        }
        .onChange(of: prefs.sideHides) {
            guard prefs.sidebar else { return }
            browser.peeking = false
        }
        // Hiding waits while a tab is being renamed; once that ends, hide if the pointer left.
        .onChange(of: browser.editingTab) { _, editing in
            if editing == nil, !inside, browser.peeking { hide() }
        }
    }

    /// The sidebar as a floating panel: the frame's colour, rounded, outlined,
    /// and lifted off the card by a deep, soft shadow.
    private var floatingSidebar: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        return Sidebar(browser: browser, prefs: prefs)
            .frame(maxHeight: .infinity)
            .background(Palette.frame)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.ink.opacity(0.12)))
            // Straddling the edge; the width it sets is the docked sidebar's too.
            .overlay(alignment: .trailing) {
                ResizeGrip(prefs: prefs) {}
                    .frame(width: ResizeGrip.width)
                    .offset(x: ResizeGrip.width / 2)
            }
            .background {
                shape.fill(Palette.frame)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    .shadow(color: .black.opacity(0.18), radius: 28, x: 6, y: 10)
            }
    }

    /// The pointer is watched only while folded.
    private func watch() {
        folding ? pointer.start { follow() } : pointer.stop()
    }

    /// Works out peeking from where the pointer is, on every move. Hover
    /// tracking can't be trusted here: a view appearing under a still pointer
    /// never hears it enter, so never hears it leave.
    private func follow() {
        guard folding, let window = pointer.window, window.isVisible else { return timers.cancelShow() }
        // A drag begun on the peeking tabs, such as resizing them, keeps them out.
        if browser.peeking, NSEvent.pressedMouseButtons & 1 != 0 {
            timers.cancelShow()
            return show()
        }
        let screen = NSEvent.mouseLocation
        let point = window.convertPoint(fromScreen: screen)
        let size = window.frame.size
        let inWindow = point.x >= 0 && point.x < size.width && point.y >= 0 && point.y < size.height
        // From the left edge for the sidebar, from the top for the strip.
        let distance = prefs.sidebar ? point.x : size.height - point.y
        // Other apps' windows on top don't count; Mote's own (a menu from the
        // sidebar) do. The hit test is costly, so it runs only while out or at the edge.
        let near = browser.peeking || (inWindow && distance < EdgeReveal.edge)
        let top = near ? NSWindow.windowNumber(at: screen, belowWindowWithWindowNumber: 0) : 0
        let onWindow = top == window.windowNumber
        let pointer = EdgeReveal.Pointer(
            inWindow: inWindow, onWindow: onWindow, onOwnPanel: near && !onWindow && NSApp.windows.contains { $0.windowNumber == top },
            distance: distance)
        // The floating sidebar sits in by the card's gap, its resize grip just
        // past its edge; the strip has neither.
        let reach = prefs.sidebar ? prefs.sideWidth + ChromeLayout.gap + ResizeGrip.width : ChromeLayout.strip
        // The strip always waits, as its edge is crossed on the way to the menu
        // bar; so does a sidebar that hides by itself.
        let waits = !prefs.sidebar || prefs.sideHides
        switch EdgeReveal.step(pointer, peeking: browser.peeking, reach: reach, waits: waits) {
        case .show:
            timers.cancelShow()
            if browser.peeking { inside = true }
            show()
        case .showSoon:
            timers.showAfter(EdgeReveal.dwell) { show() }
        case .hideSoon:
            timers.cancelShow()
            inside = false
            hide()
        case .pass:
            timers.cancelShow()
        }
    }

    private func show() {
        timers.cancelHide()
        if folding, !browser.peeking { browser.peek(true) }
    }

    /// After a grace period counted from when the pointer left, not from its
    /// latest move; not while a tab is being renamed.
    private func hide() {
        timers.hideAfter(EdgeReveal.grace) {
            if folding, browser.editingTab == nil { browser.peek(false) }
        }
    }
}

/// The pending show and hide of the folded tabs.
@MainActor
private final class PeekTimers {
    private var showing: Task<Void, Never>?
    private var hiding: Task<Void, Never>?

    /// Unless one is already waiting.
    func showAfter(_ delay: TimeInterval, _ show: @escaping @MainActor () -> Void) {
        guard showing == nil else { return }
        showing = later(delay) { [weak self] in
            self?.showing = nil
            show()
        }
    }

    /// Unless one is already waiting: the grace runs from when the pointer left.
    func hideAfter(_ delay: TimeInterval, _ hide: @escaping @MainActor () -> Void) {
        guard hiding == nil else { return }
        hiding = later(delay) { [weak self] in
            self?.hiding = nil
            hide()
        }
    }

    func cancelShow() {
        showing?.cancel()
        showing = nil
    }

    func cancelHide() {
        hiding?.cancel()
        hiding = nil
    }

    private func later(_ delay: TimeInterval, _ act: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if !Task.isCancelled { act() }
        }
    }
}

/// Pointer moves while folded, from other apps too, so the edge works when
/// another app is in front.
@MainActor
private final class PointerWatch {
    weak var window: NSWindow?
    private var monitors: [Any] = []
    /// The window's own `acceptsMouseMovedEvents`, put back on stop.
    private var accepted = false

    func start(_ moved: @escaping @MainActor () -> Void) {
        guard monitors.isEmpty, let window else { return }
        // Moves over the whole window, while watching.
        accepted = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching: kinds) { event in
                MainActor.assumeIsolated { moved() }
                return event
            } as Any,
            NSEvent.addGlobalMonitorForEvents(matching: kinds) { _ in MainActor.assumeIsolated { moved() } } as Any,
        ]
    }

    func stop() {
        guard !monitors.isEmpty else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        window?.acceptsMouseMovedEvents = accepted
    }
}
