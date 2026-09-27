import AppKit
import SwiftUI
import Testing

@testable import Mote

@Suite("Menu panel placement")
@MainActor
struct MenuPanelPlacementTests {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = NSSize(width: 280, height: 140)
    private let gap = MenuPanel.gap
    private let margin = MenuPanel.margin

    @Test("Beside a sidebar button it opens to the right, rising from the button's bottom")
    func trailing() {
        let anchor = NSRect(x: 40, y: 300, width: 26, height: 26)
        let frame = MenuPanel.frame(size: size, anchor: anchor, edge: .trailing, within: screen)
        #expect(frame == NSRect(x: anchor.maxX + gap, y: anchor.minY, width: size.width, height: size.height))
    }

    @Test("A button at the bottom of the screen keeps the whole menu on screen")
    func trailingAtBottom() {
        let anchor = NSRect(x: 40, y: 2, width: 26, height: 26)
        let frame = MenuPanel.frame(size: size, anchor: anchor, edge: .trailing, within: screen)
        #expect(frame.minY == screen.minY + margin)
        #expect(frame.minX == anchor.maxX + gap)
    }

    @Test("A button near the top keeps the menu below the screen's top")
    func trailingNearTop() {
        let anchor = NSRect(x: 40, y: 850, width: 26, height: 26)
        let frame = MenuPanel.frame(size: size, anchor: anchor, edge: .trailing, within: screen)
        #expect(frame.maxY == screen.maxY - margin)
    }

    @Test("Without room on the right it opens on the left")
    func trailingFlips() {
        let anchor = NSRect(x: 1300, y: 300, width: 26, height: 26)
        let frame = MenuPanel.frame(size: size, anchor: anchor, edge: .trailing, within: screen)
        #expect(frame.maxX == anchor.minX - gap)
    }

    @Test("Below a tab bar button it opens under it, aligned to its left edge")
    func bottom() {
        let anchor = NSRect(x: 600, y: 850, width: 26, height: 26)
        let frame = MenuPanel.frame(size: size, anchor: anchor, edge: .bottom, within: screen)
        #expect(frame == NSRect(x: anchor.minX, y: anchor.minY - gap - size.height, width: size.width, height: size.height))
    }

    @Test("Without room below it opens above, and never past the screen's right edge")
    func bottomFlipsAndClamps() {
        let anchor = NSRect(x: 1400, y: 60, width: 26, height: 26)
        let frame = MenuPanel.frame(size: size, anchor: anchor, edge: .bottom, within: screen)
        #expect(frame.minY == anchor.maxY + gap)
        #expect(frame.maxX == screen.maxX - margin)
    }
}

/// Presents a small menu from a button-sized view, the way the sidebar does.
@MainActor
private final class MenuState: ObservableObject {
    @Published var open = false
}

private struct MenuHost: View {
    @ObservedObject var state: MenuState

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Rectangle().fill(Palette.wash).frame(width: 26, height: 26)
                    .menuPanel(isPresented: $state.open, edge: .trailing) {
                        Text("Menu").padding(20)
                    }
                Spacer()
            }
            .padding(10)
        }
        .frame(width: 400, height: 300)
    }
}

/// The tests that open real menu panels. They run one at a time: each looks up
/// the menu window it opened, and another test's menu would be mistaken for it.
@Suite("Menu panel on screen", .serialized)
@MainActor
struct MenuPanelOnScreenTests {}

extension MenuPanelOnScreenTests {
    @Suite("Behaviour")
    @MainActor
    struct Behaviour {
        /// A window with the menu's button at its bottom-left, the menu open.
        private func open() async throws -> (NSWindow, MenuState, NSWindow) {
            let state = MenuState()
            let window = NSWindow(
                contentRect: NSRect(x: 200, y: 200, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
                defer: false)
            window.contentView = NSHostingView(rootView: MenuHost(state: state))
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(150))
            state.open = true
            let menu = try await eventually { NSApp.windows.first { $0.isVisible && $0.className.contains("MenuPanel") } }
            return (window, state, menu)
        }

        private func click(at point: NSPoint, in window: NSWindow) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                NSApp.postEvent(event, atStart: false)
            }
        }

        @Test("Opens beside the button as a panel of its own, and closes when asked")
        func opensAndCloses() async throws {
            let (window, state, menu) = try await open()
            defer { window.close() }
            #expect(menu !== window)
            #expect(menu.frame.minX > window.frame.minX + 36)
            state.open = false
            _ = try await eventually { menu.isVisible ? nil : true }
        }

        @Test("Escape closes the menu and tells its owner")
        func escape() async throws {
            let (window, state, menu) = try await open()
            defer { window.close() }
            menu.cancelOperation(nil)
            _ = try await eventually { state.open ? nil : true }
            #expect(!menu.isVisible)
        }

        @Test("A click elsewhere in the window closes the menu")
        func clickElsewhere() async throws {
            let (window, state, menu) = try await open()
            defer { window.close() }
            click(at: NSPoint(x: 300, y: 250), in: window)
            _ = try await eventually { state.open ? nil : true }
            #expect(!menu.isVisible)
        }

        @Test("A click on the button that opened it is left to the button")
        func clickOnAnchor() async throws {
            let (window, state, menu) = try await open()
            defer {
                state.open = false
                window.close()
            }
            // The button sits 10 points in from the bottom-left corner.
            click(at: NSPoint(x: 23, y: 23), in: window)
            try await Task.sleep(for: .milliseconds(300))
            #expect(state.open)
            #expect(menu.isVisible)
        }

        @Test("Switching to another app closes the menu")
        func appSwitch() async throws {
            let (window, state, menu) = try await open()
            defer { window.close() }
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            _ = try await eventually { state.open ? nil : true }
            #expect(!menu.isVisible)
        }
    }
}
