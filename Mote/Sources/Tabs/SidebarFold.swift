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
    private var lightsOff: Bool { browser.folded && !browser.peeking }

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
                    floatingSidebar.padding(ChromeLayout.gap).transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .onAppear {
            slideLights()
            watch()
        }
        .onDisappear { pointer.stop() }
        // The sidebar can start folded before the window exists; hide the lights once it does.
        .background(
            WindowSetup { window in
                Self.window = window
                Self.lightsWanted = lightsOff
                window.standardWindowButton(.closeButton)?.superview?.isHidden = lightsOff
                Self.holdLights()
                pointer.window = window
                watch()
            }
        )
        .onChange(of: lightsOff) { slideLights() }
        .onChange(of: folding) { watch() }
        // Changing layout puts the fold back to what the settings say.
        .onChange(of: prefs.sidebar) {
            browser.folded = prefs.sidebar && prefs.sideHides
            browser.peeking = false
        }
        .onChange(of: prefs.sideHides) { _, hides in
            guard prefs.sidebar else { return }
            browser.peeking = false
            withAnimation(Motion.fold) { browser.folded = hides }
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
            .overlay(shape.strokeBorder(Palette.edge))
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
        // The floating sidebar sits in by the card's gap; the strip doesn't.
        let reach = prefs.sidebar ? prefs.sideWidth + ChromeLayout.gap : ChromeLayout.strip
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
        if !browser.peeking { browser.peek(true) }
    }

    /// After a grace period counted from when the pointer left, not from its
    /// latest move; not while a tab is being renamed.
    private func hide() {
        timers.hideAfter(EdgeReveal.grace) {
            if browser.editingTab == nil { browser.peek(false) }
        }
    }

    /// The title bar view holds the traffic lights and their stand-ins for
    /// when the app is in the background (see RestingLights); moving it moves both.
    private func slideLights() {
        // Without a title bar yet, kept for when it turns up (see `holdLights`).
        guard let bar = Self.titlebar else { return Self.lightsWanted = lightsOff }
        if prefs.sidebar {
            Self.slide(bar, off: lightsOff, by: prefs.sideWidth + ChromeLayout.gap)
        } else {
            Self.slide(bar, off: lightsOff, by: ChromeLayout.band(for: .strip), up: true)
        }
    }

    /// The window the fold is in, once it exists.
    private static weak var window: NSWindow?

    static var titlebar: NSView? { (window ?? AppDelegate.window)?.standardWindowButton(.closeButton)?.superview }

    /// Counts slides, so an interrupted one's end doesn't hide the lights.
    private static var slides = 0
    /// Whether the lights should be away, once no slide is under way.
    private static var lightsWanted: Bool?

    /// The title bar whose `hidden` is watched, and the watch.
    private static weak var watchedBar: NSView?
    private static var hiddenWatch: NSKeyValueObservation?

    /// Puts the lights back where the fold wants them when something else
    /// (AppKit laying the title bar out again, or showing it, say) moved them
    /// in between.
    static func holdLights() {
        guard let bar = titlebar else { return }
        watchHidden(bar)
        guard let wanted = lightsWanted, bar.layer?.animation(forKey: "fold") == nil, bar.isHidden != wanted else { return }
        bar.isHidden = wanted
    }

    /// AppKit can show the title bar again while the tabs are folded, without
    /// laying anything out that TrafficLights would hear; it's hidden again.
    private static func watchHidden(_ bar: NSView) {
        guard bar !== watchedBar else { return }
        watchedBar = bar
        hiddenWatch = bar.observe(\.isHidden) { _, _ in
            // Once AppKit's own change has finished.
            DispatchQueue.main.async { MainActor.assumeIsolated { holdLights() } }
        }
    }

    /// The end of a slide: the lights where they were going, the animation gone.
    private static func land(_ bar: NSView, off: Bool, turn: Int) {
        guard turn == slides else { return }
        bar.layer?.removeAnimation(forKey: "fold")
        bar.isHidden = off
    }

    /// Slides the traffic lights off (left, or `up`) or back, on the tabs'
    /// own spring, picking up from where they are if a slide is under way.
    static func slide(_ bar: NSView, off: Bool, by distance: CGFloat, up: Bool = false) {
        slides += 1
        let turn = slides
        lightsWanted = off
        guard let layer = bar.layer else { return bar.isHidden = off }
        // Up is +y in a superview that isn't flipped, -y in one that is.
        let path = up ? "transform.translation.y" : "transform.translation.x"
        let away = up && bar.superview?.isFlipped != true ? distance : -distance
        // A slide on the other axis (the layout changed midway) is dropped.
        if (layer.animation(forKey: "fold") as? CABasicAnimation)?.keyPath != path { layer.removeAnimation(forKey: "fold") }
        let from =
            layer.animation(forKey: "fold") != nil
            ? layer.presentation()?.value(forKeyPath: path) as? CGFloat ?? 0 : bar.isHidden ? away : 0
        let to: CGFloat = off ? away : 0
        guard from != to else {
            layer.removeAnimation(forKey: "fold")
            return bar.isHidden = off
        }
        let curve = SpringCurve(response: Motion.foldResponse, dampingFraction: 1)
        let spring = CASpringAnimation(keyPath: path)
        spring.mass = curve.mass
        spring.stiffness = curve.stiffness
        spring.damping = curve.damping
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        spring.fillMode = .forwards
        spring.isRemovedOnCompletion = false
        bar.isHidden = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { land(bar, off: off, turn: turn) } }
        layer.add(spring, forKey: "fold")
        CATransaction.commit()
        // Core Animation can drop the completion (the layer rebuilt midway):
        // the slide lands anyway once it should have ended.
        DispatchQueue.main.asyncAfter(deadline: .now() + spring.duration + 0.1) { land(bar, off: off, turn: turn) }
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
