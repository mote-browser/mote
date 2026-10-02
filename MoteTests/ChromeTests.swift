import AppKit
import MoteCore
import SwiftUI
import Testing

@testable import Mote

/// The window's chrome: the page on an inset card beside the tabs, the toolbar
/// with the address, and the new tab page.
@Suite("Chrome", .serialized)
@MainActor
struct ChromeTests {
    private static let page = URL(string: "data:text/html,<title>Chrome test</title><p>Page</p>")!

    /// A browser on a page of its own, with the settings these tests change put
    /// back afterwards.
    private func withBrowser(_ body: (Browser) async throws -> Void) async throws {
        let browser = Browser()
        let prefs = browser.prefs
        let kept = (prefs.sidebar, prefs.sideWidth, prefs.bookmarksBar)
        defer {
            prefs.sidebar = kept.0
            prefs.sideWidth = kept.1
            prefs.bookmarksBar = kept.2
            for tab in browser.tabs { tab.close() }
        }
        try await body(browser)
    }

    private func openPage(in browser: Browser) async throws -> Mote.Tab {
        let tab = browser.open(ChromeTests.page, foreground: true)
        _ = try await eventually { tab.address != nil ? true : nil }
        return tab
    }

    // MARK: - Address

    @Test("The address and page-chat controls only appear on web pages")
    func pageToolsFollowTheActiveTab() async throws {
        try await withBrowser { browser in
            browser.newTab()
            #expect(!browser.pageToolsShown)
            let page = try await openPage(in: browser)
            #expect(browser.pageToolsShown)
            browser.newTab()
            #expect(!browser.pageToolsShown)
            browser.select(page)
            #expect(browser.pageToolsShown)
        }
    }

    @Test("⌘L on a page edits the address in the toolbar")
    func editsInToolbar() async throws {
        try await withBrowser { browser in
            _ = try await openPage(in: browser)
            #expect(!browser.editingInBar)
            browser.edit()
            #expect(browser.editingInBar)
            #expect(browser.field.typed == ChromeTests.page.absoluteString)
            browser.dismiss()
            #expect(!browser.editingInBar)
        }
    }

    @Test("⌘K opens the palette, not the toolbar's field")
    func summonIsNotTheBar() async throws {
        try await withBrowser { browser in
            _ = try await openPage(in: browser)
            browser.summon()
            #expect(browser.editing)
            #expect(!browser.editingInBar)
        }
    }

    @Test("A blank tab edits in its own composer, never in the toolbar")
    func blankTabComposes() async throws {
        try await withBrowser { browser in
            browser.newTab()
            #expect(browser.active?.isBlank == true)
            browser.edit()
            #expect(!browser.editingInBar)
            #expect(browser.fieldShowing)
        }
    }

    @Test("Choosing another tab ends the edit")
    func switchingEndsEdit() async throws {
        try await withBrowser { browser in
            let first = try await openPage(in: browser)
            _ = try await openPage(in: browser)
            browser.edit()
            browser.select(first)
            #expect(!browser.editingInBar)
        }
    }

    @Test(
        "With the whole address off, the toolbar shows the site for web pages and the whole address otherwise",
        arguments: [
            ("https://www.github.com/mote-browser/mote", "github.com"),
            ("http://example.com/page", "example.com"),
            ("file:///Users/someone/notes.html", "file:///Users/someone/notes.html"),
        ])
    func shownSite(address: String, shown: String) throws {
        let url = try #require(URL(string: address))
        #expect(AddressBar.display(url, whole: false) == shown)
    }

    @Test(
        "The toolbar shows the address untouched by default",
        arguments: [
            "https://www.github.com/mote-browser/mote?tab=readme#top",
            "http://example.com/page",
            "file:///Users/someone/notes.html",
        ])
    func shownWholeAddress(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(AddressBar.display(url, whole: true) == address)
    }

    // MARK: - Layout

    @Test("The layout follows the tabs' place and fold")
    func layoutFollowsPreferences() async throws {
        try await withBrowser { browser in
            let window = CGSize(width: 1200, height: 800)
            browser.prefs.sidebar = true
            browser.prefs.sideWidth = 260
            browser.folded = false
            #expect(browser.layout(in: window).sidebar?.width == 260)
            #expect(browser.layout(in: window).card.minX == 260)

            browser.folded = true
            #expect(browser.layout(in: window).sidebar == nil)
            #expect(browser.layout(in: window).card.minX == ChromeLayout.gap)

            browser.folded = false
            browser.prefs.sidebar = false
            #expect(browser.layout(in: window).strip != nil)
            #expect(browser.layout(in: window).card.minY == ChromeLayout.strip)
        }
    }

    @Test("Bookmarks show on a new tab always, and on pages only when asked for")
    func bookmarksOnNewTab() async throws {
        try await withBrowser { browser in
            let url = try #require(URL(string: "https://mote-chrome-test.example/"))
            let added = !browser.bookmarks.contains(url)
            if added { browser.bookmarks.add(url, title: "Chrome test") }
            defer {
                if added, let mark = browser.bookmarks.roots.first(where: { $0.url == url.absoluteString }) {
                    browser.bookmarks.remove(mark.id)
                }
            }
            browser.prefs.bookmarksBar = false
            browser.newTab()
            #expect(browser.bookmarksShown)

            _ = try await openPage(in: browser)
            #expect(!browser.bookmarksShown)
            browser.prefs.bookmarksBar = true
            #expect(browser.bookmarksShown)
        }
    }

    // MARK: - Renaming

    @Test("Renaming a tab keeps the name; an empty name gives the title back")
    func renames() async throws {
        try await withBrowser { browser in
            let tab = try await openPage(in: browser)
            browser.beginTabRename(tab)
            #expect(browser.editingTab == tab.id)
            #expect(browser.tabDraft == tab.label)
            browser.tabDraft = "Mine"
            browser.commitTabEdit()
            #expect(tab.name == "Mine")
            #expect(browser.editingTab == nil)

            browser.beginTabRename(tab)
            browser.tabDraft = "   "
            browser.finishTabEdit()
            #expect(tab.name == nil)
        }
    }

    // MARK: - Rendering

    @Test("Empty header and new-tab areas drag the window; controls keep their clicks")
    func emptyAreasDrag() async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = true
            browser.newTab()
            let host = NSHostingView(rootView: Chrome(browser: browser, prefs: browser.prefs).frame(width: 1000, height: 640))
            host.frame = CGRect(x: 0, y: 0, width: 1000, height: 640)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            let layout = browser.layout(in: host.bounds.size)
            func hit(_ x: CGFloat, _ y: CGFloat) -> NSView? {
                host.hitTest(CGPoint(x: x, y: host.bounds.height - y))
            }
            let middle = layout.card.midX
            let headerY = layout.card.minY + layout.toolbar / 2
            #expect(hit(middle, headerY) is DragStrip.Strip)
            #expect(!(hit(layout.card.minX + 22, headerY) is DragStrip.Strip))
            #expect(hit(layout.card.maxX - 30, layout.page.maxY - 30) is DragStrip.Strip)
            // The composer sits below the logo in the group centred at 42%.
            let composerY = layout.page.minY + layout.page.height * 0.42 + (57 + 26) / 2
            #expect(!(hit(middle, composerY) is DragStrip.Strip))
            _ = try await openPage(in: browser)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            #expect(!(hit(middle, headerY) is DragStrip.Strip))
            #expect(hit(layout.card.maxX - 3, headerY) is DragStrip.Strip)
        }
    }

    @Test("New-tab marks render the Mote pebble in the muted gray")
    func rendersNewTabMark() async throws {
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            Mark(icon: nil, letter: "", mote: true)
            Palette.muted.frame(width: 16, height: 16)
        })
        host.frame = CGRect(x: 0, y: 0, width: 32, height: 16)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 4, y: bitmap.pixelsHigh / 2))
        let muted = try #require(bitmap.colorAt(x: bitmap.pixelsWide * 3 / 4, y: bitmap.pixelsHigh / 2))
        #expect(center.matches(muted))
    }

    @Test("The sidebar sits on the frame with no line beside it, and the card is inset in its own colour")
    func rendersInsetCard() async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = true
            browser.prefs.sideWidth = Metrics.side
            browser.folded = false
            browser.newTab()
            let size = CGSize(width: 1000, height: 640)
            let host = NSHostingView(rootView: Chrome(browser: browser, prefs: browser.prefs).frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(400))

            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / size.width
            func colour(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
                try #require(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale)))
            }
            let low = size.height - 40
            // The native material depends on what's behind the window; compare
            // the frame's regions with one another instead of a fixed colour.
            let frame = try colour(20, low)
            func materials(in view: NSView) -> [NSVisualEffectView] {
                if let material = view as? NSVisualEffectView { return [material] }
                return view.subviews.flatMap { materials(in: $0) }
            }
            let effects = materials(in: host)
            #expect(effects.count == 1)
            let effect = try #require(effects.first)
            #expect(effect.material == .sidebar)
            #expect(effect.blendingMode == .behindWindow)
            #expect(effect.state == .followsWindowActiveState)

            // Low in the sidebar, below any tab: the frame, right up to the card.
            for (x, y) in [(20, low), (Metrics.side - 2, low)] {
                let seen = try colour(x, y)
                #expect(seen.matches(frame), "at \(x), \(y): \(seen), frame \(frame)")
            }
            // The gap on the far side of the card, and below it.
            for (x, y) in [(size.width - ChromeLayout.gap / 2, size.height / 2), (size.width / 2, size.height - ChromeLayout.gap / 2)] {
                let seen = try colour(x, y)
                #expect(seen.matches(frame), "at \(x), \(y): \(seen), frame \(frame)")
            }
            // Inside the card: the card's own colour, not the frame's.
            #expect(try !colour(Metrics.side + 40, low).matches(frame))
        }
    }
}

extension NSColor {
    /// Whether two colours match to within a couple of 8-bit rounding steps.
    fileprivate func matches(_ other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02 && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}
