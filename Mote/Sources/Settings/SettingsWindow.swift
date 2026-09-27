import Combine
import SwiftUI

// Settings in a window of its own, beside the browser rather than over it.
// Follows `browser.tuning`: setting it opens the window (or brings it to the
// front), clearing it closes the window, and closing the window clears it.

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    /// The browser's settings window, once the browser window has appeared.
    private static var shared: SettingsWindow?

    let window: NSWindow
    /// Builds the window's content each time it opens.
    private let panel: () -> NSView
    /// Called when the window closes while settings are still asked for.
    private let dismissed: () -> Void
    private var watching: AnyCancellable?

    /// Starts following the browser's settings state. Called once the browser
    /// window exists.
    static func watch(_ browser: Browser) {
        guard shared == nil else { return }
        shared = SettingsWindow(
            showing: browser.$tuning,
            panel: { [weak browser] in
                guard let browser else { return NSView() }
                return NSHostingView(rootView: SettingsPanel(browser: browser, prefs: browser.prefs))
            },
            dismissed: { [weak browser] in
                if browser?.tuning == true { browser?.tuning = false }
            }
        )
    }

    /// The settings window that owns a given window, if any.
    static func owning(_ window: NSWindow?) -> SettingsWindow? {
        guard let window, let shared, shared.window === window else { return nil }
        return shared
    }

    init(showing: some Publisher<Bool, Never>, panel: @escaping () -> NSView, dismissed: @escaping () -> Void) {
        self.panel = panel
        self.dismissed = dismissed
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsPanel.width, height: SettingsPanel.height),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        super.init()
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.NS.ground
        window.delegate = self
        // Receives the current value too, so settings asked for before the
        // browser window appeared still open. On the next turn, since
        // @Published sends before the value is stored.
        watching =
            showing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in on ? self?.show() : self?.hide() }
    }

    /// Handles the window's key shortcuts before the browser: Escape and ⌘W
    /// close it. Other keys go to the settings controls and the menus.
    func take(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard event.keyCode == 53 && flags.isEmpty || key == "w" && flags == .command else { return false }
        window.performClose(nil)
        return true
    }

    private func show() {
        if !window.isVisible {
            // A fresh panel each time, so it opens on the page last chosen
            // (Manage Extensions… picks one before opening settings).
            window.contentView = panel()
            place()
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// Centres the window over the browser window, or on screen without one.
    private func place() {
        guard let main = AppDelegate.window, main.isVisible,
            let screen = (main.screen ?? NSScreen.main)?.visibleFrame
        else {
            window.center()
            return
        }
        window.setFrameOrigin(SettingsWindow.origin(for: window.frame.size, over: main.frame, within: screen))
    }

    /// Where a window of `size` sits centred over `main`, moved as little as
    /// needed to stay within `screen`.
    static func origin(for size: NSSize, over main: NSRect, within screen: NSRect) -> NSPoint {
        let x = main.midX - size.width / 2
        let y = main.midY - size.height / 2
        return NSPoint(
            x: min(max(x, screen.minX), screen.maxX - size.width),
            y: min(max(y, screen.minY), screen.maxY - size.height)
        )
    }

    /// Closes the window when settings are dismissed from elsewhere (a button
    /// that leads to the browser, the bench), returning focus to the browser.
    private func hide() {
        guard window.isVisible else { return }
        let wasKey = window.isKeyWindow
        window.close()
        if wasKey { AppDelegate.window?.makeKeyAndOrderFront(nil) }
    }

    func windowWillClose(_ notification: Notification) {
        dismissed()
        // Drops the panel so it stops observing while hidden.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.window.isVisible else { return }
            self.window.contentView = nil
        }
    }
}
