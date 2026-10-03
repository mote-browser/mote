import SwiftUI
import Testing
import WebKit

@testable import Mote

@Suite("Responsive inspector", .serialized)
@MainActor
struct ResponsiveInspectorTests {
    @Test("SwiftUI page keeps the responsive canvas inside the docked inspector's available area")
    func hostedPage() async throws {
        let tab = Tab(shy: true)
        tab.setAddressOptimistically(URL(string: "https://responsive.example/test")!)
        let web = tab.web
        web.loadHTMLString("<p>Hosted page</p>", baseURL: tab.address)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let browser = Browser()
        let previousSidebar = browser.prefs.sidebar
        browser.prefs.sidebar = true
        defer { browser.prefs.sidebar = previousSidebar }
        browser.show(tab, adopting: true)
        let host = NSHostingView(rootView: Chrome(browser: browser, prefs: browser.prefs))
        window.contentView = host
        window.orderFront(nil)
        defer { for page in browser.tabs { page.close() }; window.orderOut(nil); window.contentView = nil }
        let stage = try await eventually { web.superview as? StageView }
        let development = try #require(tab.development)
        development.showResponsive()
        _ = try await eventually { tab.responsive }
        let canvas = try #require(development.canvas)
        let inspector = try #require(web.unpublishedObject("_inspector"))
        let frontend = try #require(inspector.unpublishedObject("extensionHostWebView") as? WKWebView)
        #expect(try await frontend.evaluateJavaScript("!!document.getElementById('mote-inspector-rail')") as? Bool == true)
        #expect(try await frontend.evaluateJavaScript("Math.abs(document.getElementById('mote-inspector-rail').getBoundingClientRect().right - innerWidth) < 1 && document.getElementById('main').getBoundingClientRect().right <= document.getElementById('mote-inspector-rail').getBoundingClientRect().left + 1") as? Bool == true, "The rail stays on the right and the editor opens to its left")
        #expect(try await frontend.evaluateJavaScript("document.elementFromPoint(3, innerHeight / 2)?.id") as? String == "docked-resizer", "The left edge belongs to WebKit's resize handle, not the icon rail")
        _ = try await eventually { frontend.superview === stage ? true : nil }
        for width in [500, 550, 600] {
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowWidth(\(width))")
            _ = try await eventually {
                let expected = NSRect(
                    x: 0, y: 0, width: stage.bounds.width - frontend.frame.width,
                    height: stage.bounds.height)
                return abs(frontend.frame.width - CGFloat(width)) < 2 && canvas.frame == expected ? true : nil
            }
            #expect(canvas.bounds.size == canvas.frame.size)
            let divider = NSPoint(x: frontend.frame.minX + 1, y: frontend.frame.midY)
            let hit = stage.hitTest(stage.convert(divider, to: stage.superview))
            #expect(
                hit === frontend || hit?.isDescendant(of: frontend) == true,
                "The canvas must not intercept the inspector's resize handle")
            let previews = try #require(tab.responsive).panes
            _ = try await eventually {
                previews.allSatisfy { pane in
                    pane.web.convert(pane.web.bounds, to: canvas).height <= canvas.bounds.height - 70
                } ? true : nil
            }
        }
        for folded in [true, false, true] {
            let previousWidth = stage.bounds.width
            browser.toggleFold()
            _ = try await eventually { abs(stage.bounds.width - previousWidth) > 20 ? true : nil }
            try await Task.sleep(for: .milliseconds(500))
            #expect(browser.folded == folded)
            #expect(abs(frontend.frame.maxX - stage.bounds.maxX) < 2, "Resized DevTools stays at the right edge when folding the browser sidebar")
            #expect(abs(web.frame.maxX - frontend.frame.minX) < 2, "The page fills all space up to the inspector")
        }
        _ = try await frontend.evaluateJavaScript("document.querySelector('#mote-inspector-rail button').click()")
        _ = try await eventually { inspector.unpublishedFlag("isVisible") == false ? true : nil }
        #expect(abs(web.frame.width - (stage.bounds.width - 52)) < 2, "Folding resized DevTools leaves only the activity rail")
        development.prepareToOpen()
        _ = try await eventually { frontend.superview === stage ? true : nil }
        let other = Tab(shy: true)
        other.setAddressOptimistically(URL(string: "https://responsive.example/other")!)
        other.web.loadHTMLString("<p>Other tab</p>", baseURL: other.address)
        defer { other.close() }
        browser.show(other, adopting: true)
        _ = try await eventually { other.web.window === window ? true : nil }
        browser.select(tab)
        _ = try await eventually { web.window === window ? true : nil }
        #expect(frontend.superview === web.superview)
        #expect(frontend.window === window)
        #expect(tab.web === web)
        #expect(tab.responsive != nil)
        let keptProfiles = tab.responsive?.panes.map(\.profile)
        for side in ["right", "left", "bottom"] {
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.requestSetDockSide('\(side)')")
            _ = try await eventually {
                abs(frontend.frame.height - stage.bounds.height) < 2 && abs(frontend.frame.maxX - stage.bounds.maxX) < 2 ? true : nil
            }
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowWidth(550)")
            let returnedCanvas = try #require(development.canvas)
            _ = try await eventually {
                return returnedCanvas.frame
                    == NSRect(
                        x: 0, y: 0, width: stage.bounds.width - frontend.frame.width,
                        height: stage.bounds.height) ? true : nil
            }
            #expect(tab.responsive?.panes.map(\.profile) == keptProfiles)
        }
    }

    @Test("Context-menu inspection has its coordinator before any browser inspector command")
    func contextMenu() throws {
        let tab = Tab(shy: true)
        defer { tab.close() }
        let inspector = try #require(tab.web.unpublishedObject("_inspector"))
        let development = try #require(tab.development)
        #expect(inspector.unpublishedObject("delegate") === development)
    }

    @Test("The canvas shares the main stage and leaving restores the original page")
    func stage() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let stage = StageView()
        window.contentView = stage
        let page = NSView()
        let canvas = NSView()
        stage.show(page, overlay: canvas)
        #expect(page.superview === stage)
        #expect(canvas.superview === stage)
        #expect(canvas.frame == page.frame)
        stage.show(page)
        #expect(page.superview === stage)
        #expect(canvas.superview == nil)
        window.contentView = nil
    }

    @Test("A real inspector tab activates the main canvas and closes every preview on exit")
    func inspector() async throws {
        let tab = Tab(shy: true)
        tab.setAddressOptimistically(URL(string: "https://responsive.example/test")!)
        let web = tab.web
        web.loadHTMLString("<input id='original' value='kept'>", baseURL: tab.address)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let stage = StageView()
        window.contentView = stage
        window.orderFront(nil)
        stage.show(web)
        let inspector = try #require(web.unpublishedObject("_inspector"))
        let development = ResponsiveInspector(tab: tab, inspector: inspector)
        tab.development = development
        defer {
            development.dispose()
            inspector.unpublished("close")
            tab.close()
            window.orderOut(nil)
            window.contentView = nil
        }
        development.showResponsive()
        let session = try await eventually { tab.responsive }
        _ = try await eventually { development.panelReady ? true : nil }
        #expect(development.tabIdentifier != nil)
        #expect(development.failure == nil)
        #expect(session.panes.allSatisfy { $0.web.configuration.websiteDataStore === tab.store })
        let canvas = try #require(development.canvas)
        stage.show(web, overlay: canvas)
        let profilesBeforeDockResize = session.panes.map(\.profile)
        #expect(canvas.superview === stage)
        #expect(canvas.frame == web.frame)
        let frontend = try #require(inspector.unpublishedObject("extensionHostWebView") as? WKWebView)
        _ = try await eventually { frontend.superview === stage ? true : nil }
        stage.show(web, overlay: canvas)
        _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowWidth(500)")
        _ = try await eventually {
            let available = NSRect(
                x: 0, y: 0, width: stage.bounds.width - frontend.frame.width,
                height: stage.bounds.height)
            return abs(frontend.frame.width - 500) < 2 && canvas.frame == available ? true : nil
        }
        #expect(canvas.frame.width < stage.bounds.width)
        _ = try await frontend.evaluateJavaScript("document.querySelector('#mote-inspector-rail button').click()")
        for cycle in 0..<10 {
            _ = try await eventually { inspector.unpublishedFlag("isVisible") == false && frontend.superview == nil ? true : nil }
            let rail = try #require(stage.subviews.first { $0.accessibilityIdentifier() == "devtools-collapsed-rail" } as? NSScrollView)
            #expect(rail.frame.width == 52)
            #expect(canvas.frame == web.frame && canvas.frame.width == stage.bounds.width - 52)
            #expect(frontend.frame.width >= 500, "Folding never forces WebKit below its native minimum")
            #expect(tab.responsive === session)
            try await Task.sleep(for: .milliseconds(100))
            #expect(rail.superview === stage)
            let actions = try #require(rail.documentView)
            let expand = try #require(actions.subviews.first as? NSButton)
            #expect(expand.frame.minY == 10, "Collapsed tools start at the top without vertical centering")
            let nativeTools = actions.subviews.compactMap { $0 as? NSButton }.filter { $0.tag >= 0 }.compactMap(\.toolTip)
            let webTools = try await frontend.evaluateJavaScript("[...document.querySelectorAll('.mote-inspector-tabs button')].map(button=>button.title)") as? [String]
            #expect(nativeTools == webTools, "Both rails show the same tools in the same order")
            let hoverButton = try #require(actions.subviews.first as? InspectorRailButton)
            let restingColor = hoverButton.layer?.backgroundColor
            hoverButton.mouseEntered(with: NSEvent())
            #expect(hoverButton.layer?.backgroundColor != restingColor, "Native hover highlights the button")
            hoverButton.mouseExited(with: NSEvent())
            #expect(hoverButton.layer?.backgroundColor == restingColor, "Leaving restores its resting appearance")
            let webIconCount = try await frontend.evaluateJavaScript("document.querySelectorAll('.mote-inspector-tabs button img').length") as? Int
            let nativeIconCount = actions.subviews.compactMap { $0 as? NSButton }.filter { $0.tag >= 0 && $0.image != nil }.count
            #expect(webIconCount == nativeIconCount && nativeIconCount > 0, "Native buttons reuse the frontend icon images")
            let point = expand.convert(NSPoint(x: expand.bounds.midX, y: expand.bounds.midY), to: stage.superview)
            let hit = stage.hitTest(point)
            #expect(hit === expand || hit?.isDescendant(of: expand) == true, "The visible expand button must receive real pointer input")
            expand.performClick(nil)
            _ = try await eventually { frontend.superview === stage && inspector.unpublishedFlag("isVisible") == true ? true : nil }
            #expect(rail.superview == nil)
            #expect(abs(frontend.frame.width - 500) < 2)
            if cycle < 9 {
                _ = try await frontend.evaluateJavaScript("document.querySelector('#mote-inspector-rail button').click()")
            }
        }
        for side in ["right", "left", "bottom"] {
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.requestSetDockSide('\(side)')")
            _ = try await eventually {
                abs(frontend.frame.height - stage.bounds.height) < 2 && abs(frontend.frame.maxX - stage.bounds.maxX) < 2 ? true : nil
            }
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowWidth(550)")
            _ = try await eventually {
                let available = NSRect(x: 0, y: 0, width: stage.bounds.width - frontend.frame.width, height: stage.bounds.height)
                return abs(frontend.frame.width - 550) < 2 && canvas.frame == available ? true : nil
            }
        }
        #expect(session.panes.map(\.profile) == profilesBeforeDockResize)
        _ = try await frontend.evaluateJavaScript("document.querySelector('.mote-inspector-popout').click()")
        _ = try await eventually { frontend.superview !== stage ? true : nil }
        #expect(canvas.frame == stage.bounds)
        _ = try await frontend.evaluateJavaScript("document.querySelector('.mote-inspector-popout').click()")
        _ = try await eventually { frontend.superview === stage ? true : nil }
        try await panel(
            development,
            "document.getElementById('scale').value='0.25'; document.getElementById('scale').dispatchEvent(new Event('change'))")
        _ = try await eventually { session.scale == 0.25 ? true : nil }
        try await panel(development, "document.getElementById('sync').click()")
        _ = try await eventually { !session.syncing ? true : nil }
        let name = "Inspector test \(UUID())"
        try await panel(development, "document.getElementById('name').value='\(name)'; document.getElementById('save').click()")
        let saved = try await eventually { session.saved.first { $0.name == name } }
        try await panel(
            development,
            "document.getElementById('saved').value='\(saved.id)'; document.getElementById('saved').dispatchEvent(new Event('change')); document.getElementById('delete').click()"
        )
        _ = try await eventually { !session.saved.contains { $0.id == saved.id } ? true : nil }
        #expect(try await web.evaluateJavaScript("typeof window.webkit?.messageHandlers?.moteResponsivePanel") as? String == "undefined")
        #expect(try await web.evaluateJavaScript("typeof window.webkit?.messageHandlers?.moteInspector") as? String == "undefined")
        let panes = session.panes
        let retainedProfiles = panes.map(\.profile)
        inspector.unpublished("showConsole")
        _ = try await eventually { tab.responsive == nil ? true : nil }
        stage.show(web)
        #expect(tab.web === web)
        #expect(canvas.superview == nil)
        #expect(session.panes.isEmpty)
        #expect(panes.allSatisfy { $0.web.navigationDelegate == nil })
        #expect(try await web.evaluateJavaScript("document.querySelector('#original').value") as? String == "kept")
        development.showResponsive()
        let restored = try await eventually { tab.responsive }
        #expect(restored.scale == 0.25)
        #expect(restored.syncing == false)
        #expect(restored.panes.map(\.profile) == retainedProfiles)
        _ = try await eventually { development.panelReady ? true : nil }
        try await panel(development, "if (document.getElementById('scale').value !== '0.25' || document.getElementById('sync').checked) throw new Error('Responsive settings were reset')")
        inspector.unpublished("close")
        _ = try await eventually { tab.responsive == nil ? true : nil }
        // Reopen ordinary DevTools, without the Responsive shortcut that used
        // to reset the stale registration and conceal this regression.
        for _ in 0..<3 {
            development.prepareToOpen()
            #expect(development.tabIdentifier == nil)
            inspector.unpublished("show")
            _ = try await eventually { development.tabIdentifier }
            #expect(development.failure == nil)
            inspector.unpublished("close")
        }
        development.showResponsive()
        _ = try await eventually { tab.responsive }
        #expect(development.failure == nil)
        let reopened = try #require(tab.responsive)
        development.stop()
        #expect(reopened.panes.isEmpty)
        development.resumeIfSelected()
        #expect(tab.responsive != nil)
        #expect(tab.responsive !== reopened)
        tab.close()
        #expect(tab.responsive == nil)
        #expect(development.canvas == nil)
    }

    private func panel(_ development: ResponsiveInspector, _ script: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            development.evaluatePanel(script) { error, _ in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
