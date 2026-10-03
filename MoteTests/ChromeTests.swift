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
        let kept = (prefs.sidebar, prefs.sideWidth, prefs.bookmarksBar, prefs.sidebarFolded, prefs.stripFolded, prefs.sideHides)
        defer {
            prefs.sidebar = kept.0
            prefs.sideWidth = kept.1
            prefs.bookmarksBar = kept.2
            prefs.sidebarFolded = kept.3
            prefs.stripFolded = kept.4
            prefs.sideHides = kept.5
            for tab in browser.tabs { tab.close() }
        }
        try await body(browser)
    }

    private func openPage(in browser: Browser) async throws -> Mote.Tab {
        let tab = browser.open(ChromeTests.page, foreground: true)
        _ = try await eventually { tab.address != nil ? true : nil }
        return tab
    }

    @Test("Manual fold is immediate and survives a new browser in either layout", arguments: [false, true])
    func foldPersists(sidebar: Bool) async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = sidebar
            browser.prefs.sideHides = false
            browser.folded = false
            browser.peeking = true
            browser.toggleFold()
            #expect(browser.folded)
            #expect(!browser.peeking)
            let restored = Browser()
            defer { for tab in restored.tabs { tab.close() } }
            #expect(restored.folded)
            #expect(!restored.peeking)
            // Peeking is temporary and never overwrites the saved fold.
            browser.peek(true)
            #expect(sidebar ? Preferences().sidebarFolded : Preferences().stripFolded)
            for _ in 0..<20 { browser.toggleFold() }
            #expect(browser.folded)
            browser.toggleFold()
            #expect(!browser.folded)
            #expect(!(sidebar ? Preferences().sidebarFolded : Preferences().stripFolded))
        }
    }

    @Test("Native sidebar animates its real frame, lands after rapid clicks and restores collapsed at launch")
    func nativeFold() async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = true
            browser.prefs.sideWidth = 260
            browser.folded = false
            let controller = NativeSidebar.Controller(browser: browser, prefs: browser.prefs)
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 1000, height: 640),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.contentViewController = controller
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            defer { window.orderOut(nil); window.contentViewController = nil }
            controller.view.layoutSubtreeIfNeeded()
            let side = controller.sidebarItem.viewController.view
            #expect(abs(side.frame.width - 260) < 1)
            #expect(TrafficLights.visible(in: window))
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
            let controls = try #require(buttons.first?.superview)
            #expect(controls.isDescendant(of: side))
            #expect(buttons.count == 3)
            for button in buttons {
                #expect(button.target as? NSWindow === window)
                #expect(button.action.map { window.responds(to: $0) } == true)
            }
            try await Task.sleep(for: .milliseconds(200))
            let bitmap = try #require(controls.bitmapImageRepForCachingDisplay(in: controls.bounds))
            controls.cacheDisplay(in: controls.bounds, to: bitmap)
            #expect(buttons.allSatisfy { !$0.isHiddenOrHasHiddenAncestor })
            let scale = CGFloat(bitmap.pixelsWide) / controls.bounds.width
            for button in buttons {
                let top = controls.isFlipped ? button.frame.midY : controls.bounds.height - button.frame.midY
                let drawn = try #require(bitmap.colorAt(x: Int(button.frame.midX * scale), y: Int(top * scale)))
                #expect(drawn.alphaComponent > 0.2, "The active window control must draw visible pixels")
            }

            browser.toggleFold()
            controller.update()
            try await Task.sleep(for: .milliseconds(100))
            let detail = controller.splitView.subviews.last!
            let during = detail.layer?.presentation()?.frame.minX ?? detail.frame.minX
            #expect(during > 0 && during < 260, "native animation must produce intermediate frames: \(during)")
            try await Task.sleep(for: .milliseconds(500))
            controller.view.layoutSubtreeIfNeeded()
            #expect(controller.sidebarItem.isCollapsed)
            #expect(!TrafficLights.visible(in: window))
            #expect(abs(controller.splitView.subviews.last!.frame.minX) < 1)

            for _ in 0..<5 {
                browser.toggleFold()
                controller.update()
                try await Task.sleep(for: .milliseconds(35))
            }
            try await Task.sleep(for: .milliseconds(500))
            controller.view.layoutSubtreeIfNeeded()
            #expect(!controller.sidebarItem.isCollapsed)
            #expect(abs(side.frame.width - 260) < 1)
            #expect(TrafficLights.visible(in: window))
            #expect(buttons.allSatisfy { !$0.isHiddenOrHasHiddenAncestor })

            browser.prefs.sideWidth = 290
            controller.update()
            controller.view.layoutSubtreeIfNeeded()
            #expect(abs(side.frame.width - 290) < 1)

            browser.toggleFold()
            controller.update()
            let restored = NativeSidebar.Controller(browser: browser, prefs: browser.prefs)
            #expect(restored.sidebarItem.isCollapsed)
            let restoredWindow = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 1000, height: 640),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            restoredWindow.contentViewController = restored
            #expect(!TrafficLights.visible(in: restoredWindow), "Controls must be absent before the first visible frame")
            restoredWindow.makeKeyAndOrderFront(nil)
            defer { restoredWindow.orderOut(nil); restoredWindow.contentViewController = nil }
            restored.view.layoutSubtreeIfNeeded()
            #expect(!TrafficLights.visible(in: restoredWindow))
            browser.toggleFold()
            restored.update()
            try await Task.sleep(for: .milliseconds(500))
            restored.view.layoutSubtreeIfNeeded()
            #expect(TrafficLights.visible(in: restoredWindow))
        }
    }

    // MARK: - Address

    @Test("Folded window controls are detached before display and stay absent through startup", arguments: [true, false])
    func foldedLightsNeverFlash(sidebar: Bool) async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = sidebar
            browser.folded = true
            let controller = NativeSidebar.Controller(browser: browser, prefs: browser.prefs)
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 1000, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.contentViewController = controller
            defer { window.orderOut(nil); window.contentViewController = nil }
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
            #expect(buttons.count == 3)
            #expect(buttons.allSatisfy { $0.window == nil }, "No native controls may reach the first displayed frame")
            window.makeKeyAndOrderFront(nil)
            // Exercise the deferred dressing and native layouts that used to
            // reveal the titlebar after startup, without touching the tabs.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            for tick in 0..<180 {
                if tick == 60 {
                    window.orderOut(nil)
                    window.makeKeyAndOrderFront(nil)
                }
                controller.view.layoutSubtreeIfNeeded()
                #expect(!browser.peeking)
                #expect(buttons.allSatisfy { $0.window == nil }, "Controls appeared during startup at tick \(tick)")
                try await Task.sleep(for: .milliseconds(16))
            }
            browser.toggleFold()
            controller.update()
            try await Task.sleep(for: .milliseconds(500))
            controller.view.layoutSubtreeIfNeeded()
            #expect(TrafficLights.visible(in: window))
            #expect(buttons.allSatisfy { $0.window === window && !$0.isHiddenOrHasHiddenAncestor })
        }
    }

    @Test("Chrome follows the rendered background, live header changes and the active tab")
    func pageColors() async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = false
            let html = """
                <style>html,body{margin:0;background:rgb(20,40,60)}
                header{position:fixed;top:0;width:100%;height:80px;background:rgb(30,60,90)}
                main{height:3000px}</style><header></header><main></main>
                """
            let url = try #require(URL(string: "data:text/html," + html.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!))
            let tab = browser.open(url, foreground: true)
            browser.closeOthers(but: tab)
            let body = NSColor(srgbRed: 20 / 255, green: 40 / 255, blue: 60 / 255, alpha: 1)
            let header = NSColor(srgbRed: 30 / 255, green: 60 / 255, blue: 90 / 255, alpha: 1)
            let host = NSHostingView(
                rootView: Chrome(browser: browser, prefs: browser.prefs).frame(width: 1000, height: 640)
                    .overlay(alignment: .bottomTrailing) { Color(nsColor: header).frame(width: 16, height: 16) })
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 1000, height: 640), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil }
            _ = try await eventually { tab.pageColor?.matches(body) == true || tab.pageColor?.matches(header) == true ? true : nil }
            #expect(browser.chromeScheme == .dark)
            if tab.web.responds(to: NSSelectorFromString("_sampledTopFixedPositionContentColor")) {
                _ = try await eventually { tab.pageColor?.matches(header) == true ? true : nil }
                try await Task.sleep(for: .milliseconds(200))
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
                let x = Int((Metrics.lights + (browser.prefs.usesSpaces ? SpaceDot.width + 4 : 0) + TabShape.foot + 40) * scale)
                let tabGround = try #require(bitmap.colorAt(x: x, y: Int((ChromeLayout.strip - 2) * scale)))
                let toolbarGround = try #require(bitmap.colorAt(x: x, y: Int((ChromeLayout.strip + 2) * scale)))
                // Compare in the same captured color space, including display conversion.
                let reference = try #require(bitmap.colorAt(x: bitmap.pixelsWide - Int(8 * scale), y: bitmap.pixelsHigh - Int(8 * scale)))
                #expect(tabGround.matches(reference), "Tab: \(tabGround), expected: \(reference)")
                #expect(toolbarGround.matches(reference), "Toolbar: \(toolbarGround), expected: \(reference)")
                _ = try await tab.web.evaluateJavaScript("document.querySelector('header').style.background = 'rgb(240,230,220)'")
                let changed = NSColor(srgbRed: 240 / 255, green: 230 / 255, blue: 220 / 255, alpha: 1)
                _ = try await eventually { tab.pageColor?.matches(changed) == true ? true : nil }
                #expect(browser.chromeScheme == .light)
                _ = try await tab.web.evaluateJavaScript(
                    """
                    document.querySelector('header').remove();
                    document.documentElement.style.background = 'rgb(20,40,60)';
                    document.body.style.background = 'rgb(20,40,60)'
                    """)
                _ = try await eventually { tab.pageColor?.matches(body) == true ? true : nil }
                _ = try await tab.web.evaluateJavaScript(
                    """
                    document.documentElement.style.background = 'rgb(240,230,220)';
                    document.body.style.background = 'rgb(240,230,220)'
                    """)
                _ = try await eventually { tab.pageColor?.matches(changed) == true ? true : nil }
                _ = try await tab.web.evaluateJavaScript(
                    """
                    document.body.innerHTML = '<div style="height:160px"></div><header style="position:sticky"></header><main></main>';
                    window.scrollTo(0, 250)
                    """)
                _ = try await eventually { tab.pageColor?.matches(header) == true ? true : nil }
                _ = try await tab.web.evaluateJavaScript("document.querySelector('header').style.background = 'rgb(240,230,220)'")
                _ = try await eventually { tab.pageColor?.matches(changed) == true ? true : nil }
            }
            browser.newTab()
            #expect(browser.chromeColor == nil)
            browser.select(tab)
            #expect(browser.chromeColor == tab.pageColor)
            tab.close()
            #expect(tab.built == nil)
        }
    }

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

    @Test("The tab's lower curves morph through intermediate geometry")
    func tabShapeMorphs() {
        let rect = CGRect(x: 0, y: 0, width: 214, height: 36)
        var shape = TabShape(attachment: 0)
        #expect(shape.path(in: rect).boundingRect.maxY == 34)
        shape.animatableData = 0.5
        #expect(shape.path(in: rect).boundingRect.maxY == 35)
        shape.animatableData = 1
        #expect(shape.path(in: rect).boundingRect.maxY == 36)
        #expect(shape.path(in: rect).boundingRect.minX == 0)
    }

    @Test("A dragged top tab stays visible and stops before the window controls", arguments: [-1000.0, -60.0, 500.0], [false, true])
    func draggedTabHasGround(distance: Double, selected: Bool) async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = false
            browser.folded = false
            browser.newTab()
            let first = try #require(browser.active)
            browser.closeOthers(but: first)
            browser.newTab()
            let dragged = try #require(browser.active)
            browser.select(selected ? dragged : first)
            let size = CGSize(width: 1000, height: 640)
            let host = NSHostingView(rootView: Chrome(browser: browser, prefs: browser.prefs).frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            ScriptedDrag.shared.play(dragged.id, by: CGSize(width: distance, height: 0), over: 0.4) {}
            try await Task.sleep(for: .milliseconds(200))
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            // Let the scripted gesture finish before any assertion can exit the test.
            try await Task.sleep(for: .milliseconds(400))
            let scale = CGFloat(bitmap.pixelsWide) / size.width
            let dot = browser.prefs.usesSpaces ? SpaceDot.width + 4 : 0
            let start = Metrics.lights + dot + TabShape.foot
            let travel = max(0, distance / 2)
            let heldX = distance < -Metrics.tabWidth ? start + 70 : start + Metrics.tabWidth + travel + 70
            let held = try #require(
                bitmap.colorAt(x: Int(heldX * scale), y: Int((ChromeLayout.strip - 6) * scale)))
            let ground = try #require(bitmap.colorAt(x: Int((start + 70) * scale), y: Int((ChromeLayout.strip + 2) * scale)))
            #expect(held.matches(ground), "The dragged tab must cover the frame and tabs behind it")
            #expect((distance < -Metrics.tabWidth / 2 ? browser.tabs.first : browser.tabs.last)?.id == dragged.id)
        }
    }

    @Test("The active top tab joins the card without a horizontal seam", arguments: [false, true])
    func topTabJoinsCard(page: Bool) async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = false
            browser.folded = false
            browser.newTab()
            if page { _ = try await openPage(in: browser) }
            browser.closeOthers(but: try #require(browser.active))
            let size = CGSize(width: 1000, height: 640)
            let host = NSHostingView(rootView: Chrome(browser: browser, prefs: browser.prefs).frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(400))
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / size.width
                // Inside the first tab, away from the icon, title and toolbar controls.
                let dot = browser.prefs.usesSpaces ? SpaceDot.width + 4 : 0
                let x = Int((Metrics.lights + dot + TabShape.foot + 40) * scale)
                let aboveTab = try #require(bitmap.colorAt(x: x, y: Int(2 * scale)))
                let frame = try #require(bitmap.colorAt(x: Int(800 * scale), y: Int(2 * scale)))
                #expect(aboveTab.matches(frame), "The tab must not paint a rectangle above its rounded outline")
                let ground = try #require(bitmap.colorAt(x: x, y: Int((ChromeLayout.strip - 2) * scale)))
                let header = try #require(bitmap.colorAt(x: x, y: Int((ChromeLayout.strip + 2) * scale)))
                #expect(header.matches(ground), "\(appearance): header \(header), tab \(ground)")
                for y in Int(ChromeLayout.strip * scale)..<Int((ChromeLayout.strip + 1) * scale) {
                    let seam = try #require(bitmap.colorAt(x: x, y: y))
                    #expect(seam.matches(ground), "\(appearance): seam \(seam), tab \(ground)")
                }
            }
        }
    }

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
        let host = NSHostingView(
            rootView: HStack(spacing: 0) {
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
