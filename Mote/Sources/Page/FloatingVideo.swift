import AppKit
import MoteCore
import WebKit

/// A tab's video playing in a window of its own above every app and Space.
///
/// macOS picture-in-picture needs a user gesture Mote can't make. Instead
/// the page hides all but its video (see Isolate) and the whole web view
/// moves into a floating panel, so it never stops playing.
@MainActor
final class FloatingVideo {
    /// Asks for the window to close. The owner tidies up and calls `drop`, so
    /// there is one way out.
    var onClose: (() -> Void)?
    /// Back to the video's tab.
    var onReturn: (() -> Void)?
    /// Plays or pauses; hears whether it's playing now.
    var onPlayPause: ((@escaping (Bool) -> Void) -> Void)?
    /// Jumps by some seconds.
    var onSkip: ((Double) -> Void)?
    /// Asked twice a second for how far the video is and whether it plays.
    var onProgress: ((@escaping (Double, Bool) -> Void) -> Void)?

    /// A two-finger swipe throws the window to a corner rather than pushing
    /// it along (Settings › General).
    static var flicks = false

    private var panel: NSPanel?
    private var controls: FloatControls?
    private weak var page: NSView?
    private var ticker: Timer?
    private var framesKept: [NSObjectProtocol] = []

    var showing: Bool { panel != nil }

    private static let startSize = NSSize(width: 440, height: 247)

    func lift(_ page: NSView) {
        guard panel == nil else { return }
        self.page = page
        let screen = NSScreen.main?.visibleFrame ?? .zero
        // Where it last was, if that's still on screen; the bottom-right corner otherwise.
        let frame =
            Self.remembered
            ?? NSRect(
                x: screen.maxX - Self.startSize.width - 24, y: screen.minY + 24, width: Self.startSize.width, height: Self.startSize.height)

        let panel = FloatPanel(
            contentRect: frame, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // A shadow makes WindowServer composite every frame of the video: about
        // 28% of its GPU time instead of 16–20%.
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.aspectRatio = Self.startSize
        panel.minSize = NSSize(width: 260, height: 146)
        // The frame is kept after a resize, on closing and on quitting, not at every step.
        framesKept = [(NSWindow.didEndLiveResizeNotification, panel), (NSApplication.willTerminateNotification, NSApp)].map {
            name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak panel] _ in
                MainActor.assumeIsolated { if let panel { Self.remembered = panel.frame } }
            }
        }

        let ground = NSView(frame: NSRect(origin: .zero, size: frame.size))
        ground.wantsLayer = true
        ground.layer?.backgroundColor = NSColor.black.cgColor
        ground.layer?.cornerRadius = 14
        ground.layer?.masksToBounds = true
        // WebKit's pinch handling runs before the responder chain and would take
        // pinches meant for resizing the window; given back in `drop`.
        (page as? WKWebView)?.allowsMagnification = false
        page.removeFromSuperview()
        page.frame = ground.bounds
        page.autoresizingMask = [.width, .height]
        ground.addSubview(page)

        let controls = FloatControls(frame: ground.bounds)
        controls.autoresizingMask = [.width, .height]
        controls.onClose = { [weak self] in self?.onClose?() }
        controls.onReturn = { [weak self] in self?.onReturn?() }
        controls.onPlayPause = { [weak self] in self?.onPlayPause? { self?.controls?.playing = $0 } }
        controls.onSkip = { [weak self] in self?.onSkip?($0) }
        ground.addSubview(controls)
        self.controls = controls

        panel.contentView = ground
        panel.orderFrontRegardless()
        self.panel = panel
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(ground) }
        }
    }

    private func tick(_ ground: NSView) {
        // Another owner took the page back: close, so an empty window never
        // lingers longer than a tick.
        guard page?.superview === ground else { return onClose?() ?? () }
        onProgress? { [weak self] through, playing in
            self?.controls?.progress = through
            self?.controls?.playing = playing
        }
    }

    /// Lets the page go and closes the window. The page's owner takes it back
    /// on its next layout.
    func drop() {
        guard let panel else { return }
        Self.remembered = panel.frame
        framesKept.forEach(NotificationCenter.default.removeObserver)
        framesKept = []
        ticker?.invalidate()
        ticker = nil
        (page as? WKWebView)?.allowsMagnification = true
        page?.removeFromSuperview()
        page = nil
        controls = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }

    /// Where the window last was, if it's still mostly on a screen.
    private static var remembered: NSRect? {
        get {
            Storage.settings.string(forKey: "float.frame").flatMap {
                FloatGeometry.remembered(NSRectFromString($0), on: NSScreen.screens.map(\.visibleFrame))
            }
        }
        set { Storage.settings.set(newValue.map(NSStringFromRect), forKey: "float.frame") }
    }
}

/// A panel that doesn't bring Mote forward but can take the keyboard:
/// borderless windows can't by default, and windows that can't stop getting
/// trackpad gestures.
private final class FloatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
