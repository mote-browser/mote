import Testing
import WebKit

@testable import Mote

/// A page with the picker installed as Tab installs it, and its inbox.
@MainActor
private func pickerPage() -> (WebPage, MessageInbox) {
    let inbox = MessageInbox()
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(inbox, contentWorld: Web.world, name: ElementHiderRelay.name)
    configuration.userContentController.addUserScript(
        WKUserScript(source: ElementPicker.picker, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Web.world)
    )
    return (WebPage(configuration: configuration), inbox)
}

/// Runs `body` in Mote's isolated world, as Tab does.
@MainActor
private func inAppWorld(_ page: WebPage, _ body: String) async throws {
    _ = try await page.webView.callAsyncJavaScript(body, contentWorld: Web.world)
}

/// Presses the pointer over the middle of the element marked `data-target`, as a
/// click would: on the element under that point.
@MainActor
private func pressTarget(_ page: WebPage) async throws {
    _ = try await page.string(
        """
        (() => {
          const box = document.querySelector('[data-target]').getBoundingClientRect();
          const at = { clientX: box.left + box.width / 2, clientY: box.top + box.height / 2, bubbles: true, cancelable: true, composed: true };
          document.elementFromPoint(at.clientX, at.clientY).dispatchEvent(new PointerEvent('pointerdown', at));
          return '';
        })()
        """)
}

/// `text` as a JavaScript string literal.
private func literal(_ text: String) -> String {
    String(decoding: (try? JSONEncoder().encode(text)) ?? Data(#""""#.utf8), as: UTF8.self)
}

@Suite("Element picker script")
@MainActor
struct ElementPickerScriptTests {
    @Test("The script is in the app bundle")
    func bundled() {
        #expect(!InjectedScript.source("element-picker").isEmpty)
    }

    @Test(
        "Picks the pressed element with a selector that selects it alone, escaped where needed",
        arguments: [
            (#"<div id="1:weird.id [x]" data-target>Weird id</div>"#, #"#\31 \:weird\.id\ \[x\]"#),
            (
                #"<button aria-label='Close "cookie" banner' data-target>×</button>"#,
                #"button[aria-label="Close\ \"cookie\"\ banner"]"#
            ),
            (#"<p data-testid="a\b" data-target>Text</p><p data-testid="a">Other</p>"#, #"p[data-testid="a\\b"]"#),
            (
                #"<p class="promo-box sc-a1b2 box12345 news_box" data-target>Promo</p><p class="promo-box">Other</p>"#,
                "p.promo-box.news_box"
            ),
            (#"<div id="dup">A</div><div id="dup" data-target>B</div>"#, "body > div:nth-of-type(2)"),
        ])
    func picks(html: String, expected: String) async throws {
        let (page, inbox) = pickerPage()
        try await page.load(html: html)

        try await inAppWorld(page, "window.__moteVeil.on()")
        try await pressTarget(page)
        let message = try await eventually { inbox.records.first }

        let selector = try #require(message["selector"] as? String)
        #expect(selector == expected)
        let alone = try await page.string(
            """
            (() => {
              const all = document.querySelectorAll(\(literal(selector)));
              return String(all.length === 1 && all[0] === document.querySelector('[data-target]'));
            })()
            """)
        #expect(alone == "true")
    }

    @Test("Swallows the press, labels what it picked, and reports being switched off")
    func swallowsAndSwitchesOff() async throws {
        let (page, inbox) = pickerPage()
        try await page.load(
            html: #"""
                <nav id="menu" style="height: 50px" onpointerdown="window.pagePressed = 'yes'" data-target>Menu</nav>
                """#)

        try await inAppWorld(page, "window.__moteVeil.on()")
        #expect(try await page.string("document.documentElement.style.cursor") == "crosshair")
        try await pressTarget(page)
        let picked = try await eventually { inbox.records.first }
        #expect(picked["selector"] as? String == "#menu")
        #expect(picked["label"] as? String == "Navigation")
        #expect((picked["note"] as? String)?.contains("×50 · top") == true)
        #expect(try await page.string("String(window.pagePressed)") == "undefined")

        try await inAppWorld(page, "window.__moteVeil.off()")
        let off = try await eventually { inbox.records.count >= 2 ? inbox.records[1] : nil }
        #expect(off["off"] as? Bool == true)
        #expect(try await page.string("document.documentElement.style.cursor") == "")
        try await pressTarget(page)
        #expect(try await page.string("String(window.pagePressed)") == "yes")
    }

    @Test(
        "Names an element called like a member of Object.prototype by its tag",
        arguments: ["constructor", "toString", "__proto__"])
    func picksPrototypeNames(name: String) async throws {
        let (page, inbox) = pickerPage()
        try await page.load(html: #"<p id="text">Text</p>"#)
        // Made with the DOM, which keeps the case the HTML parser would lower
        // and allows names it would not read as a tag at all.
        _ = try await page.string(
            """
            (() => {
              const element = document.createElementNS('http://www.w3.org/1999/xhtml', \(literal(name)));
              element.setAttribute('data-target', '');
              element.style.cssText = 'display: block; height: 50px';
              document.body.append(element);
              return '';
            })()
            """)

        try await inAppWorld(page, "window.__moteVeil.on()")
        try await pressTarget(page)
        let message = try await eventually { inbox.records.first }

        #expect(message["trouble"] == nil)
        #expect(message["label"] as? String == name)
    }

    @Test("Peeking shows one hidden element outlined, and unpeeking hides it again")
    func peeks() async throws {
        let (page, _) = pickerPage()
        try await page.load(html: #"<div id="banner">Cookies?</div><div id="other">Other</div>"#)

        try await inAppWorld(page, "window.__moteVeil.peek(['#other'], '#banner')")
        #expect(try await page.string("getComputedStyle(document.getElementById('banner')).outlineStyle") == "solid")
        #expect(try await page.string("getComputedStyle(document.getElementById('banner')).display") == "block")
        #expect(try await page.string("getComputedStyle(document.getElementById('other')).display") == "none")

        try await inAppWorld(page, "window.__moteVeil.unpeek(['#banner', '#other'])")
        #expect(try await page.string("getComputedStyle(document.getElementById('banner')).display") == "none")
        #expect(try await page.string("getComputedStyle(document.getElementById('other')).display") == "none")
        #expect(try await page.string("String(document.getElementById('mote-peek').sheet.cssRules.length)") == "0")
    }

    @Test("A selector can't add rules of its own to the page while peeking")
    func peekKeepsSelectorsToOneRule() async throws {
        let (page, _) = pickerPage()
        try await page.load(html: #"<div id="banner">Cookies?</div><p id="text">Text</p>"#)
        let breakout = "#none {} #text { display: none !important; } #x"

        try await inAppWorld(page, "window.__moteVeil.peek([\(literal(breakout)), '#banner'], \(literal(breakout)))")
        #expect(try await page.string("getComputedStyle(document.getElementById('text')).display") == "block")
        #expect(try await page.string("getComputedStyle(document.getElementById('banner')).display") == "none")

        try await inAppWorld(page, "window.__moteVeil.unpeek([\(literal(breakout))])")
        #expect(try await page.string("getComputedStyle(document.getElementById('text')).display") == "block")
        #expect(try await page.string("getComputedStyle(document.getElementById('banner')).display") == "block")
    }
}
