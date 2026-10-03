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
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let browser = Browser()
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
        _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.requestSetDockSide('bottom')")
        _ = try await eventually { frontend.superview === stage ? true : nil }
        for height in [350, 250, 450] {
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowHeight(\(height))")
            _ = try await eventually {
                let expected = NSRect(
                    x: 0, y: frontend.frame.maxY, width: stage.bounds.width,
                    height: stage.bounds.maxY - frontend.frame.maxY)
                return abs(frontend.frame.height - CGFloat(height)) < 2 && canvas.frame == expected ? true : nil
            }
            #expect(canvas.bounds.size == canvas.frame.size)
            let divider = NSPoint(x: frontend.frame.midX, y: frontend.frame.maxY - 1)
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
        for side in ["right", "left"] {
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.requestSetDockSide('\(side)')")
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowWidth(550)")
            let returnedCanvas = try #require(development.canvas)
            _ = try await eventually {
                let x: CGFloat = side == "left" ? frontend.frame.maxX : 0
                return returnedCanvas.frame
                    == NSRect(
                        x: x, y: 0, width: stage.bounds.width - frontend.frame.width,
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
        _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.requestSetDockSide('bottom')")
        _ = try await eventually { frontend.superview === stage ? true : nil }
        stage.show(web, overlay: canvas)
        _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowHeight(350)")
        _ = try await eventually {
            let available = NSRect(
                x: 0, y: frontend.frame.maxY, width: stage.bounds.width,
                height: stage.bounds.maxY - frontend.frame.maxY)
            return abs(frontend.frame.height - 350) < 2 && canvas.frame == available ? true : nil
        }
        #expect(canvas.frame.height < stage.bounds.height)
        _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowHeight(250)")
        _ = try await eventually {
            canvas.frame.height == stage.bounds.height - frontend.frame.height && abs(frontend.frame.height - 250) < 2 ? true : nil
        }
        for side in ["right", "left"] {
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.requestSetDockSide('\(side)')")
            _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowWidth(550)")
            _ = try await eventually {
                let x: CGFloat = side == "left" ? frontend.frame.maxX : 0
                let available = NSRect(x: x, y: 0, width: stage.bounds.width - frontend.frame.width, height: stage.bounds.height)
                return abs(frontend.frame.width - 550) < 2 && canvas.frame == available ? true : nil
            }
        }
        #expect(session.panes.map(\.profile) == profilesBeforeDockResize)
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
        let panes = session.panes
        inspector.unpublished("showConsole")
        _ = try await eventually { tab.responsive == nil ? true : nil }
        stage.show(web)
        #expect(tab.web === web)
        #expect(canvas.superview == nil)
        #expect(session.panes.isEmpty)
        #expect(panes.allSatisfy { $0.web.navigationDelegate == nil })
        #expect(try await web.evaluateJavaScript("document.querySelector('#original').value") as? String == "kept")
        development.showResponsive()
        _ = try await eventually { tab.responsive }
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
