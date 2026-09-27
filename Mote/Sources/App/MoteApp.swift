import AppKit
import MoteCore
import SwiftUI

@main
struct MoteApp: App {
    @StateObject private var browser = Browser()
    /// Links from other apps and reopening from the Dock.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var links

    var body: some Scene {
        Window("Mote", id: "browser") {
            ContentView(browser: browser).frame(minWidth: 640, minHeight: 420)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands { MenuBar(browser: browser) }
    }
}

/// The menu bar. One window, so "New" makes tabs.
private struct MenuBar: Commands {
    @ObservedObject var browser: Browser

    private var blank: Bool { browser.active?.isBlank ?? true }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab", action: browser.newTab).keyboardShortcut("t")
            Button("New Private Tab", action: browser.newShyTab).keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Reopen Closed Tab") { browser.reopen() }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(
                browser.ghosts.isEmpty)
            Divider()
            Button("Open Address…", action: browser.edit).keyboardShortcut("l")
            Divider()
            Button("Close Tab") { if let tab = browser.active { browser.close(tab) } }.keyboardShortcut("w")
        }
        CommandGroup(replacing: .printItem) {
            Button("Share…", action: browser.share).disabled(blank)
            Button("Print…", action: browser.printPage).keyboardShortcut("p").disabled(blank)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find on Page…", action: browser.openFind).keyboardShortcut("f").disabled(blank)
            Button("Find Next") { browser.finder.look(forward: true) }.keyboardShortcut("g").disabled(!browser.finder.showing)
            Button("Find Previous") { browser.finder.look(forward: false) }.keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!browser.finder.showing)
        }
        CommandGroup(replacing: .toolbar) { view }
        CommandMenu("Tabs") { tabs }
        CommandMenu("Bookmarks") {
            Button("Add This Page", action: browser.bookmarkCurrent).keyboardShortcut("b", modifiers: [.command, .shift]).disabled(blank)
            Button("Show Bookmarks…") { browser.bookmarking = true }
            Toggle(
                "Show Bookmarks Bar",
                isOn: Binding(
                    get: { browser.prefs.bookmarksBar }, set: { on in withAnimation(Motion.glide) { browser.prefs.bookmarksBar = on } }))
            // The bookmarks themselves are added by AppKit (see BookmarkMenu).
        }
        CommandMenu("History") { history }
        CommandGroup(after: .appSettings) {
            Button("Settings…") { browser.tuning = true }.keyboardShortcut(",")
            Button("Welcome…") { browser.welcoming = true }
            Button("Passwords…") { browser.logins.managing = true }.keyboardShortcut("l", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .help) {
            Button("Send Feedback…") { AppDelegate.writeFeedback() }
        }
    }

    @ViewBuilder
    private var view: some View {
        Toggle("Show Tabs in Sidebar", isOn: Binding(get: { browser.prefs.sidebar }, set: { _ in browser.toggleSidebar() }))
            .keyboardShortcut("s", modifiers: [.command, .shift])
        // Folds the sidebar or strip away (see SidebarFold).
        Button("\(browser.folded ? "Show" : "Hide") \(browser.prefs.sidebar ? "Sidebar" : "Tab Bar")", action: browser.toggleFold)
            .keyboardShortcut("s")
        Picker("Tabs Wear", selection: Binding(get: { browser.prefs.glyph }, set: { browser.prefs.glyph = $0 })) {
            ForEach(Glyph.allCases) { Text($0.title).tag($0) }
        }
        Divider()
        Button("Reload Page", action: browser.reload).keyboardShortcut("r")
        Button("Reading Mode", action: browser.toggleReader).keyboardShortcut("r", modifiers: [.command, .shift])
        Button("Float Video", action: browser.toggleFloat).keyboardShortcut("p", modifiers: [.command, .shift])
        Divider()
        Button("Hide Elements…", action: browser.toggleHiding).keyboardShortcut("h", modifiers: [.command, .shift])
        Button("Hidden on This Site…") { browser.reviewing.toggle() }.keyboardShortcut("u", modifiers: [.command, .shift])
        Divider()
        Button("Zoom In") { browser.zoom(by: 1.1) }.keyboardShortcut("+")
        Button("Zoom Out") { browser.zoom(by: 1 / 1.1) }.keyboardShortcut("-")
        Button("Actual Size", action: browser.resetZoom).keyboardShortcut("0")
        Divider()
        // Chrome's shortcuts (see Inspector.swift).
        Button("Web Inspector", action: browser.toggleInspector).keyboardShortcut("i", modifiers: [.command, .option])
        Button("JavaScript Console", action: browser.showConsole).keyboardShortcut("j", modifiers: [.command, .option])
        Button("Inspect Element", action: browser.inspectElement).keyboardShortcut("c", modifiers: [.command, .option])
    }

    @ViewBuilder
    private var tabs: some View {
        Button("Back", action: browser.back).keyboardShortcut("[").disabled(browser.active?.canGoBack != true)
        Button("Forward", action: browser.forward).keyboardShortcut("]").disabled(browser.active?.canGoForward != true)
        Divider()
        Button("Next Tab") { browser.step(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
        Button("Previous Tab") { browser.step(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
        Button("Search Tabs…", action: browser.summon).keyboardShortcut("k")
        Divider()
        if let tab = browser.active {
            if tab.pin == nil {
                Button("Pin Tab") { browser.pin(tab) }.disabled(tab.isBlank)
            } else {
                Button("Change Letter") { browser.editLetter(tab) }
                Button("Unpin Tab") { browser.unpin(tab) }
            }
        }
        Button("Rename Tab") { if let tab = browser.active { browser.beginTabRename(tab) } }.disabled(browser.active == nil)
        Button("Duplicate Tab", action: browser.duplicate).keyboardShortcut("d").disabled(blank)
        Button("Copy Address", action: browser.copyAddress).keyboardShortcut("c", modifiers: [.command, .shift]).disabled(blank)
        Button("Copy as Markdown Link", action: browser.copyMarkdownLink).disabled(blank)
        Button("Paste and Go", action: browser.pasteAndGo).keyboardShortcut("v", modifiers: [.command, .shift])
        Divider()
        Button("Close Other Tabs") { if let tab = browser.active { browser.closeOthers(but: tab) } }.disabled(browser.tabs.count < 2)
        Button("Stop Sound in Tab", action: browser.pauseMedia).keyboardShortcut("m", modifiers: [.command, .shift])
    }

    @ViewBuilder
    private var history: some View {
        Section("Recently Visited") {
            ForEach(browser.recentlyVisited) { place in
                Button {
                    browser.open(place.url, foreground: true)
                } label: {
                    PageMenuItem(title: place.title.isEmpty ? place.key : place.title, url: place.url)
                }
            }
        }
        if !browser.ghosts.isEmpty {
            Section("Recently Closed") {
                ForEach(browser.ghosts.reversed().prefix(10)) { ghost in
                    Button {
                        browser.reopen(ghost)
                    } label: {
                        PageMenuItem(title: ghost.label, url: ghost.url)
                    }
                }
            }
        }
        Divider()
        Button("Show History…") { browser.recalling = true }.keyboardShortcut("y")
        Button("Downloads…") { browser.showingDownloads = true }.keyboardShortcut("j", modifiers: [.command, .shift])
        Divider()
        Button("Clear History", action: browser.clearHistory)
    }
}

/// A page in a menu: its cached icon, if there is one, and its title.
private struct PageMenuItem: View {
    let title: String
    let url: URL

    var body: some View {
        if let icon {
            Label {
                Text(title)
            } icon: {
                Image(nsImage: icon)
            }
        } else {
            Text(title)
        }
    }

    /// The site's icon at menu size: they're kept at 64 pt, so a copy is resized.
    private var icon: NSImage? {
        guard let host = url.host()?.lowercased(), let cached = Favicons.shared.cached(host), let small = cached.copy() as? NSImage else {
            return nil
        }
        small.size = NSSize(width: 16, height: 16)
        return small
    }
}
