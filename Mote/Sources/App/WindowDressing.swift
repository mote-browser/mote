import AppKit

/// Setting up the browser window once it exists.
@MainActor
enum WindowDressing {
    /// `lights` places the traffic lights' stand-ins (see LightStandIns)
    /// whenever the real ones move.
    static func dress(_ window: NSWindow, lights: @escaping (NSWindow) -> Void) {
        AppDelegate.window = window
        // The appearance is set for the whole app (see Look.apply).
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        // DragStrip moves the window, so selecting text can't.
        window.isMovableByWindowBackground = false
        // Or AppKit would move the window when a tab is dragged along the strip.
        window.isMovable = false
        // The frame is kept in the standard defaults, which test runs share with
        // the real app, so test runs keep theirs under another name.
        window.setFrameAutosaveName(Storage.world.map { "mote (\($0))" } ?? "mote")

        TrafficLights.keep(window) { lights(window) }
        Task { @MainActor in
            lights(window)
            raiseTitleBar(in: window)
        }
    }

    /// The full-size content view's layer draws over the title bar and hides
    /// the traffic lights, whatever AppKit's view order says; the title bar's
    /// container is raised explicitly.
    private static func raiseTitleBar(in window: NSWindow) {
        guard let container = window.standardWindowButton(.closeButton)?.superview?.superview, let content = window.contentView,
            let frame = content.superview
        else { return }
        frame.addSubview(container, positioned: .above, relativeTo: content)
        container.wantsLayer = true
        container.layer?.zPosition = 10
    }
}

/// Mote's own traffic lights for while the app is in the background, laid
/// over the real ones.
@MainActor
final class LightStandIns {
    private var view: RestingLights?

    func place(in window: NSWindow) {
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        let lights = view ?? RestingLights()
        if lights.superview !== titlebar {
            lights.frame = titlebar.bounds
            lights.autoresizingMask = [.width, .height]
            titlebar.addSubview(lights, positioned: .above, relativeTo: nil)
            view = lights
        }
        lights.spots = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap(window.standardWindowButton)
            .map { $0.convert($0.bounds, to: titlebar) }
        lights.isHidden = NSApp.isActive
    }

    func show(_ shown: Bool) { view?.isHidden = !shown }
}
