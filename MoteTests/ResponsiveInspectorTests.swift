import SwiftUI
import Testing
import WebKit

@testable import Mote

@Suite("Responsive inspector", .serialized)
@MainActor
struct ResponsiveInspectorTests {
    @Test("Elements keeps native layout and responds to AppKit pointer events")
    func elements() async throws {
        let tab = Tab(shy: true)
        tab.setAddressOptimistically(URL(string: "https://elements.example/test")!)
        let web = tab.web
        let cards = (0..<80).map { "<article class='card' data-item='\($0)'><h2>Item \($0)</h2><p>Details</p></article>" }.joined()
        web.loadHTMLString("<style>#sample { color: rgb(10, 20, 30); display: flex } .card { padding: 12px; border: 1px solid gray }</style><main><button id='sample'>Inspect me</button>\(cards)</main>", baseURL: tab.address)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1500, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let stage = StageView()
        window.contentView = stage
        window.acceptsMouseMovedEvents = true
        let previousPolicy = NSApp.activationPolicy()
        let previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        stage.show(web)
        let inspector = try #require(web.unpublishedObject("_inspector"))
        let development = try #require(tab.development)
        defer {
            development.dispose()
            inspector.unpublished("close")
            tab.close()
            window.orderOut(nil)
            window.contentView = nil
            NSApp.setActivationPolicy(previousPolicy)
            previousApp?.activate()
        }
        development.prepareToOpen()
        inspector.unpublished("show")
        _ = try await eventually { development.tabIdentifier }
        let frontend = try #require(inspector.unpublishedObject("extensionHostWebView") as? WKWebView)
        _ = try await eventually { window.isKeyWindow ? true : nil }
        window.makeFirstResponder(frontend)
        func waitFor(_ expression: String) async throws {
            for _ in 0..<100 {
                if try await frontend.evaluateJavaScript(expression) as? Bool == true { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            print("Elements timeout: \(expression)")
            Issue.record("Inspector condition timed out: \(expression)")
        }
        func run(_ body: String) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                frontend.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { result in
                    continuation.resume(with: result.map { _ in () })
                }
            }
        }
        func snapshot(_ name: String) async throws {
            try await Task.sleep(for: .milliseconds(200))
            let image = try await frontend.takeSnapshot(configuration: nil)
            let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            try data.write(to: root.appendingPathComponent("build/elements-\(name).png"))
        }
        func pointer(_ selector: String, click: Bool = false, dragBy: NSPoint? = nil) async throws {
            let rect = try #require(try await frontend.evaluateJavaScript("""
                (() => { const element = [...document.querySelectorAll('\(selector)')].find(element => element.getClientRects().length);
                const r = element.getBoundingClientRect();
                return {x: r.left + Math.min(r.width / 2, 30), y: r.top + Math.min(r.height / 2, 8)}; })()
                """) as? [String: Double])
            let x = try #require(rect["x"]), y = try #require(rect["y"])
            let local = NSPoint(x: x, y: frontend.isFlipped ? y : frontend.bounds.height - y)
            let point = frontend.convert(local, to: nil)
            let target = try #require(frontend.hitTest(frontend.convert(local, to: frontend.superview)))
            let types: [NSEvent.EventType] = dragBy != nil ? [.leftMouseDown] + Array(repeating: .leftMouseDragged, count: 6) + [.leftMouseUp] : click ? [.mouseMoved, .leftMouseDown, .leftMouseUp] : [.mouseMoved]
            for (index, type) in types.enumerated() {
                let fraction = min(Double(index) / 6, 1)
                let location = dragBy.map { NSPoint(x: point.x + $0.x * fraction, y: point.y + $0.y * fraction) } ?? point
                let event = try #require(NSEvent.mouseEvent(
                    with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: click ? 1 : 0, pressure: 0))
                switch type {
                case .mouseMoved:
                    // WKWebView routes tracking through an internal owner, not NSResponder.mouseMoved.
                    let move = NSSelectorFromString("_simulateMouseMove:")
                    #expect(frontend.responds(to: move))
                    frontend.perform(move, with: event)
                case .leftMouseDown: target.mouseDown(with: event)
                case .leftMouseDragged: target.mouseDragged(with: event)
                case .leftMouseUp: target.mouseUp(with: event)
                default: break
                }
                if type == .leftMouseDragged { try await Task.sleep(for: .milliseconds(16)) }
            }
        }
        _ = try await frontend.evaluateJavaScript("WI.tabBrowser.showTabForContentView(WI.tabBar.tabBarItems.find(item => item.representedObject?.type === 'elements').representedObject)")
        try await waitFor("document.body.classList.contains('mote-elements') && !!WI.tabBrowser.selectedTabContentView.contentBrowser.currentContentView?.domTreeOutline")
        try await run("""
            const view = WI.tabBrowser.selectedTabContentView.contentBrowser.currentContentView;
            const id = await view.domTreeOutline.selectedDOMNode().ownerDocument.querySelector('#sample');
            view.selectAndRevealDOMNode(WI.domManager.nodeForId(id));
            """)
        _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowWidth(500)")
        try await waitFor("document.body.classList.contains('narrow')")
        #expect(try await frontend.evaluateJavaScript("document.getElementById('tab-browser').getBoundingClientRect().height > 100 && document.getElementById('details-sidebar').getBoundingClientRect().height > 100") as? Bool == true)
        #expect(try await frontend.evaluateJavaScript("document.getElementById('main').getBoundingClientRect().top <= 35 && !document.getElementById('mote-elements-bar')") as? Bool == true)
        let selected = try await frontend.evaluateJavaScript("WI.tabBrowser.selectedTabContentView.contentBrowser.currentContentView.domTreeOutline.selectedDOMNode().id") as? Int
        #expect(selected != nil)
        try await snapshot("compact")
        let rulers = try await frontend.evaluateJavaScript("WI.settings.showRulers.value") as? Bool
        let start = Date()
        try await pointer(".content-view.elements .item.show-rulers")
        try await waitFor("document.querySelector('.content-view.elements .item.show-rulers').matches(':hover')")
        print("Elements native hover observed after \(Date().timeIntervalSince(start) * 1000) ms")
        try await pointer(".content-view.elements .item.show-rulers", click: true)
        try await waitFor("WI.settings.showRulers.value !== \(rulers == true ? "true" : "false")")
        try await pointer(".content-view.elements .item.show-rulers", click: true)
        try await waitFor("WI.settings.showRulers.value === \(rulers == true ? "true" : "false")")
        try await pointer("#details-sidebar .item.style-computed", click: true)
        try await waitFor("WI.tabBrowser.detailsSidebar.selectedSidebarPanel.identifier === 'style-computed'")
        #expect(try await frontend.evaluateJavaScript("WI.tabBrowser.selectedTabContentView.contentBrowser.currentContentView.domTreeOutline.selectedDOMNode().id") as? Int == selected)
        try await snapshot("computed")
        try await pointer("#details-sidebar .item.style-rules", click: true)
        try await waitFor("WI.tabBrowser.detailsSidebar.selectedSidebarPanel.identifier === 'style-rules'")
        try await pointer(".tree-outline.dom li:not(.selected)")
        try await waitFor("!!document.querySelector('.tree-outline.dom li.hovered:not(.selected)')")
        #expect(try await frontend.evaluateJavaScript("getComputedStyle(document.querySelector('.tree-outline.dom li.hovered > .selection-area')).opacity === '1'") as? Bool == true)
        let oldHeight = try #require(try await frontend.evaluateJavaScript("document.getElementById('details-sidebar').getBoundingClientRect().height") as? Double)
        try await pointer("#details-sidebar > .resizer.horizontal-rule", dragBy: NSPoint(x: 0, y: 30))
        try await waitFor("Math.abs(document.getElementById('details-sidebar').getBoundingClientRect().height - \(oldHeight)) > 20")
        _ = try await frontend.evaluateJavaScript("WI.tabBrowser.detailsSidebar.height = 280")
        #expect(try await frontend.evaluateJavaScript("Math.abs(document.getElementById('details-sidebar').getBoundingClientRect().height - 280) < 2") as? Bool == true)
        frontend.appearance = NSAppearance(named: .aqua)
        try await waitFor("!matchMedia('(prefers-color-scheme: dark)').matches")
        try await snapshot("light")
        frontend.appearance = nil
        _ = try await frontend.evaluateJavaScript("InspectorFrontendHost.setAttachedWindowWidth(900)")
        try await waitFor("!document.body.classList.contains('narrow')")
        #expect(try await frontend.evaluateJavaScript("document.getElementById('tab-browser').getBoundingClientRect().width > 200 && document.getElementById('details-sidebar').getBoundingClientRect().width > 200") as? Bool == true)
        let oldWidth = try #require(try await frontend.evaluateJavaScript("document.getElementById('details-sidebar').getBoundingClientRect().width") as? Double)
        try await pointer(".resizer.vertical-rule", dragBy: NSPoint(x: -60, y: 0))
        try await waitFor("Math.abs(document.getElementById('details-sidebar').getBoundingClientRect().width - \(oldWidth)) > 40")
        #expect(try await frontend.evaluateJavaScript("WI.tabBrowser.selectedTabContentView.contentBrowser.currentContentView.domTreeOutline.selectedDOMNode().id") as? Int == selected)
        try await snapshot("wide")
        inspector.unpublished("showConsole")
        try await waitFor("!document.body.classList.contains('mote-elements')")
        #expect(try await web.evaluateJavaScript("typeof window.moteInspector") as? String == "undefined")
    }

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
