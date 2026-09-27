import AppKit
import MoteCore

/// The window's traffic lights, placed where a window with a toolbar has
/// them, without one: on macOS 26 a toolbar also rounds the window's corners
/// much more (31.5 pt rather than 17.5). AppKit puts them back whenever it
/// lays out the title bar, so they are placed again each time.
@MainActor
final class TrafficLights: NSObject {
    /// Where the tabs are, which decides where the lights sit (see
    /// `ChromeLayout.lights`). Changing it moves every window's.
    static var tabs = ChromeLayout.Tabs.sidebar {
        didSet { if tabs != oldValue { managed.values.forEach { $0.place() } } }
    }

    /// The close button's centre, from the window's top-left corner.
    static var centre: CGPoint { ChromeLayout.lights(for: tabs) }

    private static var managed: [ObjectIdentifier: TrafficLights] = [:]

    /// Takes over a window's lights; `moved` hears each time they are placed.
    static func keep(_ window: NSWindow, moved: @escaping () -> Void) {
        let key = ObjectIdentifier(window)
        if managed[key] == nil { managed[key] = TrafficLights(window, moved: moved) }
    }

    private weak var window: NSWindow?
    private let moved: () -> Void
    private var placing = false
    /// AppKit's gap between buttons, read once: read on every pass, it can
    /// catch AppKit halfway through a layout after a resize and come out wrong.
    private let spacing: CGFloat

    private var buttons: [NSButton] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window?.standardWindowButton($0) }
    }

    private init(_ window: NSWindow, moved: @escaping () -> Void) {
        self.window = window
        self.moved = moved
        let pair = [NSWindow.ButtonType.closeButton, .miniaturizeButton].compactMap(window.standardWindowButton)
        let gap = pair.count == 2 ? pair[1].frame.minX - pair[0].frame.minX : 0
        spacing = (16...32).contains(gap) ? gap : 20
        super.init()
        let center = NotificationCenter.default
        let windowChanges: [Notification.Name] = [
            NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification, NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification,
        ]
        for name in windowChanges { center.addObserver(self, selector: #selector(place), name: name, object: window) }
        // The title bar's views changing frame means AppKit laid them out again.
        if let bar = buttons.first?.superview, let container = bar.superview {
            for view in [container, bar] + buttons {
                view.postsFrameChangedNotifications = true
                center.addObserver(self, selector: #selector(place), name: NSView.frameDidChangeNotification, object: view)
            }
        }
        place()
    }

    @objc private func place() {
        // In full screen the title bar is a window of macOS's own.
        guard !placing, let window, !window.styleMask.contains(.fullScreen) else { return }
        let buttons = buttons
        guard buttons.count == 3, let bar = buttons[0].superview, let container = bar.superview else { return }
        placing = true
        defer { placing = false }
        // The title bar as tall as the band the lights sit in, so they can sit lower.
        let height = ChromeLayout.band(for: Self.tabs)
        if container.frame.height != height || container.frame.maxY != window.frame.height {
            container.frame = NSRect(x: container.frame.minX, y: window.frame.height - height, width: container.frame.width, height: height)
        }
        for (index, button) in buttons.enumerated() {
            let size = button.frame.size
            let origin = NSPoint(
                x: Self.centre.x - size.width / 2 + CGFloat(index) * spacing, y: bar.bounds.height - Self.centre.y - size.height / 2)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
        // AppKit laying the title bar out again can show it while the tabs
        // are folded away.
        SidebarFold.holdLights()
        moved()
    }
}
