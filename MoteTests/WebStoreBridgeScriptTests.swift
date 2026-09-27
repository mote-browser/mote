import Testing
import WebKit

@testable import Mote

private let extensionID = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
private let otherID = "nngceckbapebfimnlniiiahkandclblb"

/// A store detail page, much reduced: the "Switch to Chrome" banner, the disabled
/// install button, and a link to another extension the page could try to pass off.
private let detailPage = """
    <div id="banner"><span>Switch to Chrome?</span><button aria-label="Switch to Chrome">Switch</button></div>
    <main>
      <h1>uBlock Origin</h1>
      <button disabled jsaction="click:install" class="install" data-extension="\(otherID)"><i></i><span>Add to Chrome</span></button>
      <a href="/detail/other/\(otherID)">Other</a>
    </main>
    <script>
      document.addEventListener('click', () => { window.storeSawClick = 'yes'; });
    </script>
    """

/// A page with the bridge installed as Tab installs it, and its inbox.
@MainActor
private func storePage() -> (WebPage, MessageInbox) {
    let inbox = MessageInbox()
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(inbox, contentWorld: Web.world, name: WebStoreBridge.name)
    configuration.userContentController.addUserScript(
        WKUserScript(source: WebStoreBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Web.world)
    )
    return (WebPage(configuration: configuration), inbox)
}

@Suite("Web Store bridge script")
@MainActor
struct WebStoreBridgeScriptTests {
    private let storeURL = URL(string: "https://chromewebstore.google.com/detail/ublock-origin/\(extensionID)")!

    @Test("The script is in the app bundle")
    func bundled() {
        #expect(!InjectedScript.source("web-store-bridge").isEmpty)
    }

    @Test("Replaces the install button, hides the banner, and reports the id from the address")
    func replacesButton() async throws {
        let (page, inbox) = storePage()
        try await page.load(html: detailPage, baseURL: storeURL)

        let placed = try await eventually { inbox.records.first { $0["placed"] != nil } }
        // From the page's address, never from anything the page says.
        #expect(placed["placed"] as? String == extensionID)
        #expect(try await page.string("document.querySelector('button[data-mote=\"add\"]').textContent") == "Add to Mote")
        #expect(try await page.string("String(document.querySelector('button[data-mote=\"add\"]').disabled)") == "false")
        #expect(try await page.string("document.querySelector('button[data-mote=\"theirs\"]').style.display") == "none")
        #expect(try await page.string("document.getElementById('banner').style.display") == "none")
    }

    @Test("A click on Add to Mote goes to Swift, not to the store")
    func click() async throws {
        let (page, inbox) = storePage()
        try await page.load(html: detailPage, baseURL: storeURL)
        _ = try await eventually { inbox.records.first { $0["placed"] != nil } }

        _ = try await page.string("document.querySelector('button[data-mote=\"add\"] span').click(); ''")

        let add = try await eventually { inbox.records.first { $0["add"] != nil } }
        #expect(add["add"] as? Bool == true)
        #expect(try await page.string("String(window.storeSawClick)") == "undefined")
    }

    @Test("Shows what Swift says: installing, then installed")
    func state() async throws {
        let (page, inbox) = storePage()
        try await page.load(html: detailPage, baseURL: storeURL)
        _ = try await eventually { inbox.records.first { $0["placed"] != nil } }
        let button = "document.querySelector('button[data-mote=\"add\"]')"

        _ = try await page.webView.callAsyncJavaScript(
            "window.__moteStore.state({ installed: [], busy: id })", arguments: ["id": extensionID], contentWorld: Web.world)
        #expect(try await page.string("\(button).textContent + ' ' + \(button).disabled") == "Adding… true")

        _ = try await page.webView.callAsyncJavaScript(
            "window.__moteStore.state({ installed: [id], busy: null })", arguments: ["id": extensionID],
            contentWorld: Web.world)
        #expect(try await page.string("\(button).textContent + ' ' + \(button).disabled") == "Added to Mote true")
    }

    @Test("Leaves every other site alone")
    func otherSites() async throws {
        let (page, inbox) = storePage()
        try await page.load(html: detailPage, baseURL: URL(string: "https://example.com/detail/ublock-origin/\(extensionID)")!)

        try await Task.sleep(for: .milliseconds(200))
        #expect(inbox.records.isEmpty)
        #expect(try await page.string("String(document.querySelector('[data-mote]'))") == "null")
        #expect(try await page.string("document.getElementById('banner').style.display") == "")
    }
}
