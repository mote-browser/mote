import AppKit

@MainActor
enum WindowDressing {
    static func dress(_ window: NSWindow) {
        AppDelegate.window = window
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        // DragStrip owns window dragging; text selection and tab drags cannot move it.
        window.isMovableByWindowBackground = false
        window.isMovable = false
        window.setFrameAutosaveName(Storage.world.map { "mote (\($0))" } ?? "mote")
        TrafficLights.refresh(in: window)
    }

}
