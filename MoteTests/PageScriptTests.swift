import Foundation
import Testing
import WebKit

@testable import Mote

/// A page with `source` injected into Mote's isolated world as the app injects it,
/// and `inbox` listening there as `handler`, if given.
@MainActor
private func page(
    injecting source: String, at time: WKUserScriptInjectionTime, mainFrameOnly: Bool,
    handler: String? = nil, inbox: MessageInbox? = nil
) -> WebPage {
    let configuration = WKWebViewConfiguration()
    let controller = configuration.userContentController
    if let handler, let inbox { controller.add(inbox, contentWorld: Web.world, name: handler) }
    controller.addUserScript(
        WKUserScript(source: source, injectionTime: time, forMainFrameOnly: mainFrameOnly, in: Web.world))
    return WebPage(configuration: configuration)
}

/// Runs a called script's function body in `world` and returns its result.
@MainActor
private func call(
    _ page: WebPage, _ body: String, _ arguments: [String: Any] = [:], in world: WKContentWorld = .page
) async throws -> Any? {
    try await page.webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: world)
}

@Suite("Page scripts")
@MainActor
struct PageScriptTests {
    @Test("Every page script is in the app bundle")
    func bundled() {
        for name in [
            "middle-click", "selected-text", "smart-zoom", "scroll-report", "bench-locate", "bench-act",
            "popup-size", "image-menu", "swipe-watch", "favicon-probe",
        ] {
            #expect(!InjectedScript.source(name).isEmpty)
        }
    }

    @Test("The scroll report tells Swift the page's position on load")
    func scrollReport() async throws {
        let inbox = MessageInbox()
        let page = page(
            injecting: ScrollRelay.script, at: .atDocumentEnd, mainFrameOnly: true, handler: ScrollRelay.name, inbox: inbox)
        try await page.load(html: #"<body style="margin: 0"><div style="height: 3000px"></div></body>"#)

        let report = try await eventually { inbox.messages.first as? [String: Double] }
        #expect(report["y"] == 0)
        #expect(report["max"].map { Int($0.rounded()) } == 3000 - 768)
    }

    @Test("A horizontal swipe over a scrolling strip is taken, and elsewhere is free")
    func swipeWatch() async throws {
        let inbox = MessageInbox()
        let page = page(
            injecting: Swipe.watch, at: .atDocumentStart, mainFrameOnly: false, handler: ScrollRelay.name, inbox: inbox)
        try await page.load(
            html: """
                <div id="strip" style="width: 200px; overflow-x: auto"><div style="width: 2000px; height: 50px"></div></div>
                <p id="text">Text</p>
                """)

        _ = try await page.string(
            """
            const swipe = (id) => document.getElementById(id).dispatchEvent(new WheelEvent('wheel', { deltaX: 30, bubbles: true }));
            swipe('strip'); swipe('text');
            'done'
            """)
        let messages = try await eventually { inbox.messages.count >= 2 ? inbox.messages : nil }

        #expect(messages.compactMap { ($0 as? [String: String])?["side"] } == ["taken", "free"])
    }

    @Test("A right-click on an image asks for Mote's menu instead of WebKit's")
    func imageMenu() async throws {
        let inbox = MessageInbox()
        let page = page(
            injecting: ImageRelay.watch, at: .atDocumentStart, mainFrameOnly: false, handler: ImageRelay.name, inbox: inbox)
        let image = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='20' height='20'/%3E"
        try await page.load(html: #"<img id="image" src="\#(image)">"#)

        let allowed = try await page.string(
            """
            String(document.getElementById('image').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })))
            """)
        let messages = try await eventually { inbox.messages.isEmpty ? nil : inbox.messages }

        #expect(allowed == "false")
        #expect((messages.first as? [String: String])?["src"] == image)
    }

    @Test("Without Mote's menu to ask for, WebKit's stays")
    func imageMenuWithoutHandler() async throws {
        let page = page(injecting: ImageRelay.watch, at: .atDocumentStart, mainFrameOnly: false)
        let image = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='20' height='20'/%3E"
        try await page.load(html: #"<img id="image" src="\#(image)">"#)

        let allowed = try await page.string(
            """
            String(document.getElementById('image').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })))
            """)
        #expect(allowed == "true")
    }

    @Test("The selected text is read from a focused field")
    func selectedText() async throws {
        let page = WebPage()
        try await page.load(html: #"<p>Other text</p><input id="field" value="hello world">"#)
        _ = try await page.string(
            "const field = document.getElementById('field'); field.focus(); field.setSelectionRange(6, 11); 'done'")

        #expect(try await call(page, PageView.selected, in: .defaultClient) as? String == "world")
    }

    @Test("Smart zoom fits the column under the pointer to the view")
    func smartZoom() async throws {
        let page = WebPage()
        try await page.load(
            html: #"<body style="margin: 0"><p style="width: 400px; height: 100px; margin: 0 0 0 100px">Text</p></body>"#)

        let arguments: [String: Any] = ["x": 150.0, "y": 50.0, "scale": 1.0, "width": 1024.0]
        let json = try #require(try await call(page, PageView.smart, arguments) as? String)
        let zoom = try JSONDecoder().decode([String: Double].self, from: Data(json.utf8))

        #expect(abs((zoom["scale"] ?? 0) - 1024.0 / 424) < 0.001)
        #expect(zoom["x"] == 88)
    }

    @Test("The favicon probe lists declared icons with absolute addresses")
    func faviconProbe() async throws {
        let page = WebPage()
        try await page.load(html: #"<link rel="stylesheet" href="data:text/css,"><link rel="icon" href="/a.png" sizes="32x32">"#)

        let probe = InjectedScript.call("favicon-probe")
        let icons = try #require(try await call(page, probe) as? [[String: String]])

        #expect(icons.count == 1)
        #expect(icons.first?["href"] == "https://example.com/a.png")
        #expect(icons.first?["sizes"] == "32x32")
    }

    @Test("A popup fits the width its page sets, and its inline style is restored")
    @available(macOS 15.4, *)
    func popupSize() async throws {
        let page = WebPage()
        try await page.load(
            html: #"<!doctype html><html style="width: 300px"><body style="margin: 0"><div style="height: 120px"></div></body></html>"#)

        let fit = try await call(page, ExtensionPopup.size, ["stage": "fit"]) as? [Double]
        #expect(fit == [300, 120])
        #expect(try await page.string("document.documentElement.getAttribute('style')") == "width: 300px")
    }

    @Test("A growing popup is told how tall its page overflows")
    @available(macOS 15.4, *)
    func popupGrows() async throws {
        let page = WebPage()
        try await page.load(html: #"<!doctype html><body style="margin: 0"><div style="height: 2000px"></div></body>"#)

        let grow = try #require(try await call(page, ExtensionPopup.size, ["stage": "grow"]) as? [Double])
        #expect(grow.last == 2000)
    }

    @Test("The bench finds a button by its text and types into a field")
    func bench() async throws {
        let page = WebPage()
        try await page.load(
            html: """
                <body style="margin: 0">
                <button style="position: absolute; left: 100px; top: 50px; width: 40px; height: 20px">Go</button>
                <input id="field" style="position: absolute; top: 200px">
                </body>
                """)

        let locate = InjectedScript.call("bench-locate", arguments: ["selector"])
        #expect(try await call(page, locate, ["selector": "text=go"]) as? [Double] == [120, 60])

        let act = InjectedScript.call("bench-act", arguments: ["verb", "selector", "text"])
        let said = try await call(page, act, ["verb": "type", "selector": "#field", "text": "hello"]) as? String
        #expect(said == "ok")
        #expect(try await page.string("document.getElementById('field').value") == "hello")
    }
}
