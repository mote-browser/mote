import AppKit
import MoteCore
import SwiftUI

/// The window's content: the chrome and page, with the folded tabs, the
/// notices at the bottom, the ⌘K switcher and the panels over them.
struct ContentView: View {
    @ObservedObject var browser: Browser

    @State private var window: NSWindow?
    @State private var keys = KeyRouter()
    @State private var lights = LightStandIns()

    /// Runs a key through the window's shortcuts, for the bench.
    static var keyHook: ((NSEvent) -> NSEvent?)?

    /// The switcher over a page; a blank tab switches in its own composer.
    private var switching: Bool { browser.field.switching && browser.active?.isStart == false }

    var body: some View {
        Chrome(browser: browser, prefs: browser.prefs)
            .overlay(alignment: .leading) { SidebarFold(browser: browser, prefs: browser.prefs) }
            .overlay(alignment: .bottom) { Notices(browser: browser) }
            .overlay {
                if switching { Omnibox(browser: browser) }
            }
            .overlay { panels }
            // In on a spring, out quickly.
            .animation(switching ? Motion.settle : Motion.quick, value: switching)
            .background(
                WindowSetup {
                    window = $0
                    WindowDressing.dress($0) { lights.place(in: $0) }
                    arrive()
                }
            )
            .onChange(of: browser.welcoming) { _, on in if on { arrive() } }
            .onChange(of: browser.prefs.sidebar) { _, sidebar in
                TrafficLights.tabs = sidebar ? .sidebar : .strip
                if let window { Task { @MainActor in lights.place(in: window) } }
            }
            // macOS draws background traffic lights almost white on a light
            // window, so Mote draws its own while the app is in the background.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                if let window { lights.place(in: window) }
                lights.show(true)
                // This window's browser only, so other windows' videos stay put.
                browser.appLeft()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                lights.show(false)
                browser.appBack()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                if let window, note.object as? NSWindow === window { Browser.front = browser }
            }
            .onChange(of: browser.fieldShowing) { _, showing in
                if showing { Task { @MainActor in browser.field.askFocus() } } else { keyboardToPage() }
            }
            .onChange(of: browser.activeID) { keyboardToPage() }
            .animation(Motion.settle, value: browser.recalling)
            .animation(Motion.settle, value: browser.showingDownloads)
            .animation(Motion.settle, value: browser.welcoming)
            .animation(Motion.settle, value: browser.bookmarking)
            .animation(Motion.settle, value: browser.logins.managing)
            .onAppear {
                TrafficLights.tabs = browser.prefs.sidebar ? .sidebar : .strip
                keys.start(for: browser)
                Self.keyHook = { [keys] in keys.route($0) }
                browser.field.askFocus()
                AppDelegate.hand(to: browser)
                SettingsWindow.watch(browser)
                BookmarkMenu.shared.start(for: browser)
            }
    }

    @ViewBuilder
    private var panels: some View {
        if browser.recalling {
            Sheet(close: { browser.recalling = false }) { HistoryPanel(browser: browser) }
        }
        if browser.showingDownloads {
            Sheet(close: { browser.showingDownloads = false }) { DownloadsPanel(browser: browser, downloads: browser.downloads) }
        }
        if browser.bookmarking {
            Sheet(close: { browser.bookmarking = false }) { BookmarksPanel(browser: browser, bookmarks: browser.bookmarks) }
        }
        if browser.welcoming, !browser.arriving {
            WelcomePanel(browser: browser, prefs: browser.prefs).ignoresSafeArea()
        }
        if browser.logins.managing {
            Sheet(close: { browser.logins.managing = false }) { PasswordsPanel(logins: browser.logins) }
        }
    }

    /// Gives the keyboard back to the page when the address field goes: keys
    /// would otherwise go nowhere, and passkeys and pages' own key handling
    /// need a focused document.
    private func keyboardToPage() {
        guard !browser.fieldShowing, browser.editingTab == nil else { return }
        Task { @MainActor in
            if let page = browser.active?.web, let window = page.window { window.makeFirstResponder(page) }
        }
    }

    /// The arrival, when the welcome starts (see Arrival.swift).
    private func arrive() {
        guard browser.welcoming, !browser.arriving, let window, #available(macOS 15, *) else { return }
        browser.arriving = Arrival.play(over: window) { browser.arriving = false }
    }
}

/// A panel over a dimmed window; a click on the dimming closes it.
private struct Sheet<Panel: View>: View {
    let close: () -> Void
    @ViewBuilder let panel: () -> Panel

    var body: some View {
        ZStack {
            ArrowCursor().frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
            Color.black.opacity(0.10).ignoresSafeArea().onTapGesture(perform: close)
            panel().transition(.scale(scale: 0.97).combined(with: .opacity))
        }
        .transition(.opacity)
    }
}

/// An arrow pointer over panels. WebKit does `cursor: none` with an AppKit
/// cursor rect over the whole page, and SwiftUI overlays add none of their
/// own, so without this the pointer stays hidden over a panel.
private struct ArrowCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Area() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Area: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

        // Asked again as it moves or resizes, so it applies before the pointer moves.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }
    }
}
