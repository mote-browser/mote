import MoteCore
import Testing
import WebKit

@testable import Mote

@Suite("Responsive session", .serialized)
@MainActor
struct ResponsiveSessionTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "mote.responsive.tests.\(UUID())")!
    }

    @Test("Saving and reopening restores the view settings without persisting a URL")
    func saves() throws {
        let settings = defaults()
        let session = ResponsiveSession(store: .nonPersistent(), defaults: settings)
        let phone = try ResponsiveViewport(name: "Custom", width: 412, height: 915, userAgent: "Mote test")
        session.apply([phone])
        try session.save(name: "My views")
        let reopened = ResponsiveSession(store: .nonPersistent(), defaults: settings)
        #expect(reopened.saved.map(\.name) == ["My views"])
        #expect(reopened.saved.first?.viewports == [phone])
        #expect(reopened.panes.map(\.profile) == [phone])
        #expect(reopened.address.isEmpty)
        session.close()
        reopened.close()
    }

    @Test("Changing dimensions retains the page; changing its agent requires a fresh page")
    func edits() throws {
        let session = ResponsiveSession(store: .nonPersistent(), defaults: defaults())
        let pane = try #require(session.panes.first)
        let web = pane.web
        let resized = try ResponsiveViewport(id: pane.id, name: "Resized", width: 412, height: 915)
        session.replace(resized)
        #expect(session.panes.first?.web === web)
        let agent = try ResponsiveViewport(id: pane.id, name: "Agent", width: 412, height: 915, userAgent: "Test agent")
        session.replace(agent)
        #expect(session.panes.first?.web !== web)
        #expect(session.panes.first?.web.customUserAgent == "Test agent")
        session.close()
    }

    @Test("Only web URLs can be opened and each pane shares the supplied privacy store")
    func navigation() throws {
        let store = WKWebsiteDataStore.nonPersistent()
        let session = ResponsiveSession(store: store, defaults: defaults())
        #expect(session.panes.allSatisfy { $0.web.configuration.websiteDataStore === store })
        #expect(throws: (any Error).self) { try session.navigate("javascript:alert(1)") }
        #expect(throws: (any Error).self) { try session.navigate("file:///etc/passwd") }
        #expect(session.panes.allSatisfy { $0.web.url == nil })
        session.close()
        #expect(session.panes.isEmpty)
    }

    @Test("Corrupt saved settings are preserved separately before defaults are used")
    func corrupt() {
        let settings = defaults()
        let invalid = Data("invalid".utf8)
        settings.set(invalid, forKey: ResponsiveSession.savedKey)
        let session = ResponsiveSession(store: .nonPersistent(), defaults: settings)
        #expect(session.saved.isEmpty)
        #expect(session.notice != nil)
        #expect(settings.data(forKey: ResponsiveSession.savedKey + ".unreadable") == invalid)
        session.close()
    }

    @Test("Removing one view releases its handler and leaves the others intact")
    func remove() throws {
        let session = ResponsiveSession(store: .nonPersistent(), defaults: defaults())
        let first = try #require(session.panes.first)
        let other = try #require(session.panes.last)
        session.remove(first.id)
        #expect(!session.panes.contains { $0.id == first.id })
        #expect(session.panes.last === other)
        session.close()
    }

    @Test("A scaled canvas retains exact CSS dimensions and media queries")
    func scale() async throws {
        let profile = try ResponsiveViewport(name: "Phone", width: 390, height: 844)
        let page = WebPage()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 195, height: 422), styleMask: [.borderless], backing: .buffered, defer: false)
        let stage = ResponsiveStageView(frame: NSRect(x: 0, y: 0, width: 195, height: 422))
        window.contentView = stage
        stage.show(page.webView, size: NSSize(width: profile.width, height: profile.height))
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        stage.layoutSubtreeIfNeeded()
        try await page.load(
            html: "<!doctype html><meta name='viewport' content='width=device-width, initial-scale=1'><body>Responsive</body>")
        #expect(try await page.string("String(innerWidth)") == "390")
        #expect(try await page.string("String(innerHeight)") == "844")
        #expect(try await page.string("String(matchMedia('(max-width: 400px)').matches)") == "true")
        stage.frame.size = NSSize(width: 390, height: 844)
        stage.layoutSubtreeIfNeeded()
        #expect(try await page.string("String(innerWidth)") == "390")
    }

    @Test("The bundled bridge replays field values without exposing itself to the page")
    func bridge() async throws {
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: ResponsiveSession.script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: ResponsiveSession.world))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        let page = WebPage(configuration: config)
        try await page.load(html: "<input id='name'><input id='secret' type='password'>")
        #expect(try await page.string("typeof moteResponsiveSync") == "undefined")
        let event: [String: Any] = ["kind": "input", "selector": "#name", "value": "WebKit", "start": 2, "end": 4]
        let result = try await page.webView.callAsyncJavaScript(
            "return moteResponsiveSync.receive(event)", arguments: ["event": event], contentWorld: ResponsiveSession.world)
        #expect(result as? Bool == true)
        #expect(try await page.string("document.querySelector('#name').value") == "WebKit")
        #expect(try await page.string("String(document.querySelector('#name').selectionStart)") == "2")
    }

    @Test("Trusted focus crosses the native bridge, and disabling sync keeps the views independent")
    func focusSync() async throws {
        let session = ResponsiveSession(store: .nonPersistent(), defaults: defaults())
        defer { session.close() }
        let source = try #require(session.panes.first)
        let target = try #require(session.panes.last)
        let url = URL(string: "https://responsive.example/test")!
        for pane in session.panes {
            pane.web.loadHTMLString("<input id='first'><input id='second'><p id='loaded'>Ready</p>", baseURL: url)
        }
        for pane in session.panes { try await wait(pane.web, "String(!!document.querySelector('#loaded'))", equals: "true") }
        _ = try await source.web.evaluateJavaScript("document.querySelector('#first').focus()")
        try await wait(target.web, "document.activeElement.id", equals: "first")
        session.syncing = false
        _ = try await source.web.evaluateJavaScript("document.querySelector('#second').focus()")
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await target.web.evaluateJavaScript("document.activeElement.id") as? String == "first")
    }

    @Test("Scroll progress crosses different heights without echoing back to the source")
    func scrollSync() async throws {
        let session = ResponsiveSession(store: .nonPersistent(), defaults: defaults())
        defer { session.close() }
        let source = try #require(session.panes.first)
        let target = try #require(session.panes.last)
        // Animation frames are suspended for detached web views. Host both panes as the workspace does.
        let windows = [source, target].enumerated().map { index, pane in
            let size = NSSize(width: Double(pane.profile.width) * 0.25, height: Double(pane.profile.height) * 0.25)
            let window = NSWindow(
                contentRect: NSRect(origin: NSPoint(x: 80 + index * 420, y: 80), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            let stage = ResponsiveStageView(frame: NSRect(origin: .zero, size: size))
            window.contentView = stage
            stage.show(pane.web, size: NSSize(width: pane.profile.width, height: pane.profile.height))
            // Keep rendering active even when another test or browser window is in front.
            window.level = .floating
            window.orderFront(nil)
            stage.layoutSubtreeIfNeeded()
            return window
        }
        defer {
            windows.forEach {
                $0.orderOut(nil); $0.contentView = nil
            }
        }
        for pane in session.panes {
            pane.web.loadHTMLString(
                "<!doctype html><body style='margin:0'><div id='loaded' style='height:3000px'>Scroll</div></body>",
                baseURL: URL(string: "https://responsive.example/scroll")!)
            try await wait(pane.web, "String(!!document.querySelector('#loaded'))", equals: "true")
        }
        _ = try await source.web.evaluateJavaScript("window.scrollTo({top:500, behavior:'instant'})")
        try await wait(target.web, "String(scrollY > 0)", equals: "true")
        let sourceProgress = try #require(
            try await source.web.evaluateJavaScript("scrollY/(document.documentElement.scrollHeight-innerHeight)") as? Double)
        let targetProgress = try #require(
            try await target.web.evaluateJavaScript("scrollY/(document.documentElement.scrollHeight-innerHeight)") as? Double)
        #expect(abs(sourceProgress - targetProgress) < 0.002)
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await source.web.evaluateJavaScript("Math.round(scrollY)") as? Int == 500)
    }

    private func wait(_ web: WKWebView, _ expression: String, equals expected: String) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if (try? await web.evaluateJavaScript(expression)) as? String == expected { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw TimedOut()
    }
}
