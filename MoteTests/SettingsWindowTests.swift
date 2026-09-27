import AppKit
import Combine
import SwiftUI
import Testing

@testable import Mote

@Suite("Settings window")
@MainActor
struct SettingsWindowTests {
    /// Stands in for `browser.tuning`.
    final class Tuning: ObservableObject {
        @Published var on = false
    }

    /// A settings window following `tuning`, counting the panels it builds.
    private func make(_ tuning: Tuning, built: @escaping () -> Void = {}) -> SettingsWindow {
        SettingsWindow(
            showing: tuning.$on,
            panel: {
                built()
                return NSView()
            },
            dismissed: { tuning.on = false }
        )
    }

    private func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    @Test("Opens in a window of its own when settings are asked for")
    func opens() async throws {
        let tuning = Tuning()
        let settings = make(tuning)
        defer { settings.window.close() }
        #expect(!settings.window.isVisible)

        tuning.on = true
        _ = try await eventually { settings.window.isVisible ? true : nil }
        #expect(settings.window !== AppDelegate.window)
        #expect(settings.window.styleMask.contains(.titled))
        #expect(settings.window.styleMask.contains(.closable))
    }

    @Test("Closes when settings are dismissed from elsewhere")
    func closesWhenDismissed() async throws {
        let tuning = Tuning()
        let settings = make(tuning)
        defer { settings.window.close() }
        tuning.on = true
        _ = try await eventually { settings.window.isVisible ? true : nil }

        tuning.on = false
        _ = try await eventually { settings.window.isVisible ? nil : true }
    }

    @Test("Closing the window dismisses settings")
    func closingDismisses() async throws {
        let tuning = Tuning()
        let settings = make(tuning)
        tuning.on = true
        _ = try await eventually { settings.window.isVisible ? true : nil }

        settings.window.performClose(nil)
        _ = try await eventually { tuning.on ? nil : true }
        #expect(!settings.window.isVisible)
    }

    @Test("Asking again while open keeps the same panel; reopening builds a fresh one")
    func freshPanelOnReopen() async throws {
        let tuning = Tuning()
        var panels = 0
        let settings = make(tuning) { panels += 1 }
        defer { settings.window.close() }

        tuning.on = true
        _ = try await eventually { settings.window.isVisible ? true : nil }
        tuning.on = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(panels == 1)

        tuning.on = false
        _ = try await eventually { settings.window.isVisible ? nil : true }
        tuning.on = true
        _ = try await eventually { settings.window.isVisible ? true : nil }
        #expect(panels == 2)
    }

    @Test("Escape and ⌘W close the window; other keys are left alone")
    func keys() async throws {
        let tuning = Tuning()
        let settings = make(tuning)
        defer { settings.window.close() }
        let window = settings.window

        tuning.on = true
        _ = try await eventually { window.isVisible ? true : nil }
        #expect(!settings.take(key("t", code: 17, flags: .command, in: window)))
        #expect(!settings.take(key("a", code: 0, in: window)))
        #expect(window.isVisible)

        #expect(settings.take(key("\u{1b}", code: 53, in: window)))
        _ = try await eventually { tuning.on ? nil : true }
        #expect(!window.isVisible)

        tuning.on = true
        _ = try await eventually { window.isVisible ? true : nil }
        #expect(settings.take(key("w", code: 13, flags: .command, in: window)))
        _ = try await eventually { tuning.on ? nil : true }
        #expect(!window.isVisible)
    }

    @Test("Opens centred over the browser window")
    func centred() {
        let origin = SettingsWindow.origin(
            for: NSSize(width: 660, height: 500),
            over: NSRect(x: 100, y: 100, width: 1180, height: 780),
            within: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(origin == NSPoint(x: 360, y: 240))
    }

    @Test("Stays on screen when the browser window hangs off it")
    func keptOnScreen() {
        let size = NSSize(width: 660, height: 500)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let left = SettingsWindow.origin(
            for: size, over: NSRect(x: -900, y: -600, width: 1000, height: 700), within: screen)
        #expect(left == NSPoint(x: 0, y: 0))
        let right = SettingsWindow.origin(
            for: size, over: NSRect(x: 1300, y: 700, width: 1000, height: 700), within: screen)
        #expect(right == NSPoint(x: 780, y: 400))
    }

    /// The window's content drawn to a bitmap, as it appears on screen.
    private func snapshot(_ window: NSWindow) throws -> NSBitmapImageRep {
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    @Test("The page runs all the way to the bottom of the window")
    func pageReachesBottom() async throws {
        let browser = Browser()
        let tuning = Tuning()
        let settings = SettingsWindow(
            showing: tuning.$on,
            panel: { NSHostingView(rootView: SettingsPanel(browser: browser, prefs: browser.prefs)) },
            dismissed: { tuning.on = false }
        )
        defer { settings.window.close() }
        tuning.on = true
        _ = try await eventually { settings.window.isVisible ? true : nil }
        try await Task.sleep(for: .milliseconds(300))

        let window = settings.window
        let content = try #require(window.contentView)
        // The panel fills the window's content, title bar area included.
        #expect(content.frame.size == window.frame.size)
        let bitmap = try snapshot(window)
        #expect(bitmap.size == content.bounds.size)

        // Sampled in the margin beside the sections: the same color halfway
        // down and in the last row of the window.
        let x = 8 * bitmap.pixelsWide / Int(bitmap.size.width)
        let middle = try #require(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2))
        let bottom = try #require(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1))
        #expect(bottom.isApproximately(middle), "page \(middle), bottom edge \(bottom)")
    }
}

extension NSColor {
    /// Whether two colors match to within a rounding step of 8-bit channels.
    fileprivate func isApproximately(_ other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02 && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}
