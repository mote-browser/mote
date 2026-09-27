import MoteCore
import Testing
import WebKit

@testable import Mote

extension MessageInbox {
    /// The first message the forms script posted of `kind`.
    fileprivate func first(_ kind: String) -> [String: Any]? {
        records.first { $0["kind"] as? String == kind }
    }
}

/// Passkeys offered or not for the duration of a test, as Settings › Passwords would.
@MainActor
private func withPasskeys<T>(_ offered: Bool, _ body: () async throws -> T) async rethrows -> T {
    let was = FormRelay.passkeysOffered
    FormRelay.passkeysOffered = offered
    defer { FormRelay.passkeysOffered = was }
    return try await body()
}

private let signIn = """
    <form action="/session">
      <input id="search" type="search">
      <input id="user" type="email">
      <input id="password" type="password">
      <button id="go">Sign in</button>
    </form>
    """

// Serialized: the passkey tests switch the shared Settings › Passwords value.
@Suite("Password and passkey scripts", .serialized)
@MainActor
struct PasswordScriptTests {
    /// A page with the scripts Tab.arm installs for sign-ins and passkeys, in the
    /// same worlds, frames and injection times, and their handlers in Mote's world.
    private func page(passkeys: Bool, forms inbox: MessageInbox = MessageInbox()) -> WebPage {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.add(inbox, contentWorld: Web.world, name: FormRelay.name)
        controller.addScriptMessageHandler(PasskeyRelay(), contentWorld: Web.world, name: PasskeyRelay.name)
        controller.addUserScript(
            WKUserScript(source: FormRelay.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Web.world))
        controller.addUserScript(
            WKUserScript(
                source: passkeys ? PasskeyRelay.page : FormRelay.withoutPasskeys, injectionTime: .atDocumentStart,
                forMainFrameOnly: false, in: .page))
        controller.addUserScript(
            WKUserScript(source: PasskeyRelay.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Web.world))
        return WebPage(configuration: configuration)
    }

    /// Runs `body` as an async function in Mote's isolated world.
    private func inMote(_ page: WebPage, _ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await page.webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: Web.world)
    }

    /// Dispatches a passkey request as the page world's own window event, the
    /// way `passkey-relay` does (or a page could without it), and returns the reply.
    private func forge(_ request: [String: Any], on page: WebPage) async throws -> [String: Any] {
        let reply = try await page.webView.callAsyncJavaScript(
            """
            return await new Promise((resolve) => {
              addEventListener(answered, (event) => {
                const answer = JSON.parse(event.detail);
                if (answer.token === request.token) resolve(JSON.stringify(answer.reply));
              });
              dispatchEvent(new CustomEvent(asked, { detail: JSON.stringify(request) }));
            });
            """,
            arguments: ["request": request, "asked": PasskeyRelay.asked, "answered": PasskeyRelay.answered],
            contentWorld: .page)
        let text = try #require(reply as? String)
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// Names the page world can see on `window` and on the credentials prototype.
    private func pageNames(_ page: WebPage) async throws -> String? {
        try await page.string(
            """
            JSON.stringify({
              window: Object.getOwnPropertyNames(window).sort(),
              symbols: Object.getOwnPropertySymbols(window).map(String),
              credentials: Object.getOwnPropertyNames(CredentialsContainer.prototype).sort(),
              webkit: typeof window.webkit
            })
            """)
    }

    // MARK: - Sign-in forms

    @Test("A sign-in form is found, and what it sends is reported")
    func signInReported() async throws {
        let inbox = MessageInbox()
        let page = page(passkeys: false, forms: inbox)
        try await page.load(html: signIn)

        _ = try await eventually { inbox.first("form") }
        _ = try await page.string(
            """
            document.getElementById('user').value = 'ada@example.com';
            document.getElementById('password').value = 'correct horse';
            document.querySelector('form').addEventListener('submit', (e) => e.preventDefault());
            document.querySelector('form').requestSubmit();
            'sent'
            """)
        let sent = try await eventually { inbox.first("submit") }

        #expect(sent["user"] as? String == "ada@example.com")
        #expect(sent["password"] as? String == "correct horse")
    }

    @Test("Sign-in fields going away without a new page count as a sign-in that took")
    func signInSettled() async throws {
        let inbox = MessageInbox()
        let page = page(passkeys: false, forms: inbox)
        try await page.load(html: signIn)
        _ = try await eventually { inbox.first("form") }

        _ = try await page.string("document.querySelector('form').remove(); 'removed'")

        _ = try await eventually { inbox.first("settled") }
        #expect(try await inMote(page, "return window.__moteForms.hasPassword()") as? Bool == false)
    }

    @Test("A page without a password field is no sign-in")
    func noSignIn() async throws {
        let inbox = MessageInbox()
        let page = page(passkeys: false, forms: inbox)
        try await page.load(html: #"<form><input type="text"><input type="password" style="display: none"></form>"#)

        _ = try await eventually { inbox.first("focus") }
        #expect(inbox.first("form") == nil)
        #expect(try await inMote(page, "return window.__moteForms.hasPassword()") as? Bool == false)
    }

    @Test("Nothing is filled until Swift fills the account the user picked")
    func fillOnlyWhenAsked() async throws {
        let inbox = MessageInbox()
        let page = page(passkeys: false, forms: inbox)
        try await page.load(html: signIn)
        _ = try await eventually { inbox.first("form") }

        let values = "JSON.stringify(['search', 'user', 'password'].map((id) => document.getElementById(id).value))"
        #expect(try await page.string(values) == #"["","",""]"#)

        let filled = try await inMote(
            page, "return window.__moteForms.fill(user, password)",
            arguments: ["user": "ada@example.com", "password": "p`${a}\\'\""])
        #expect(filled as? Bool == true)
        #expect(try await page.string(values) == #"["","ada@example.com","p`${a}\\'\""]"#)
    }

    @Test("Text a script puts in a field doesn't keep the page awake")
    func unsavedInput() async throws {
        let page = page(passkeys: false)
        try await page.load(html: #"<textarea id="note"></textarea>"#)
        let unsaved = "return window.__moteForms.unsaved()"
        #expect(try await inMote(page, unsaved) as? Bool == false)

        // Only input the user makes counts; a script's doesn't.
        _ = try await page.string(
            """
            const note = document.getElementById('note');
            note.value = 'Draft';
            note.dispatchEvent(new Event('input', { bubbles: true }));
            'typed'
            """)
        #expect(try await inMote(page, unsaved) as? Bool == false)
    }

    // MARK: - Nothing of Mote's in the page world

    @Test("The page world sees no names, handlers or window.webkit of Mote's", arguments: [false, true])
    func pageWorldUntouched(passkeys: Bool) async throws {
        try await withPasskeys(passkeys) {
            let bare = WebPage()
            try await bare.load(html: signIn)
            let scripted = page(passkeys: passkeys)
            try await scripted.load(html: signIn)

            let names = try #require(try await pageNames(scripted))
            #expect(names == (try await pageNames(bare)))
            #expect(names.contains(#""webkit":"undefined""#))
            // Mote's own world has them.
            #expect(try await inMote(scripted, "return typeof window.__moteForms") as? String == "object")
            #expect(try await inMote(scripted, "return typeof window.__motePasskeyBridge") as? String == "boolean")
        }
    }

    // MARK: - Passkeys

    @Test("Passkeys off: the API is hidden and public-key requests are refused as NotAllowedError")
    func passkeysHidden() async throws {
        let page = page(passkeys: false)
        try await page.load(html: "<p>Page</p>")

        #expect(try await page.string("typeof window.PublicKeyCredential") == "undefined")
        let refused = try await page.call(
            """
            try {
              await navigator.credentials.create({ publicKey: { challenge: new Uint8Array([1]) } });
              return 'made';
            } catch (error) {
              return error.name + ': ' + error.message;
            }
            """)
        #expect(refused == "NotAllowedError: The operation either timed out or was not allowed.")
    }

    @Test("A passkey request is answered for the origin WebKit reports")
    func passkeyOrigin() async throws {
        try await withPasskeys(true) {
            let page = page(passkeys: true)
            try await page.load(html: "<p>Page</p>")

            let client = try await page.call(
                """
                const credential = await navigator.credentials.get({ publicKey: { challenge: new Uint8Array([1, 2, 3]) } });
                const client = JSON.parse(new TextDecoder().decode(credential.response.clientDataJSON));
                return [credential instanceof PublicKeyCredential, client.type, client.origin].join(' ');
                """)
            #expect(client == "true webauthn.get https://example.com")
        }
    }

    @Test("A page that forges the relay's events can't choose the origin or the relying party")
    func forgedOrigin() async throws {
        try await withPasskeys(true) {
            let page = page(passkeys: true)
            try await page.load(html: "<p>Page</p>")

            // Straight to the bridge, as a page could, naming another origin.
            let forged = try await forge(
                ["kind": "get", "token": "forged", "challenge": "AQID", "origin": "https://evil.example"], on: page)
            let client = try #require(WebAuthn.decode(forged["clientDataJSON"]))
            let origin = (try JSONSerialization.jsonObject(with: client) as? [String: Any])?["origin"] as? String
            #expect(origin == "https://example.com")

            let elsewhere = try await forge(
                ["kind": "get", "token": "elsewhere", "challenge": "AQID", "rpId": "evil.example"], on: page)
            #expect(elsewhere["error"] as? String == "SecurityError", "\(elsewhere)")
        }
    }

    @Test("A refused passkey request reaches the page as NotAllowedError, whatever the reason")
    func passkeyRefused() async throws {
        // Passkeys turned off after the page loaded with the relay in it.
        let page = page(passkeys: true)
        try await page.load(html: "<p>Page</p>")
        let refused = try await withPasskeys(false) {
            try await page.call(
                """
                try {
                  await navigator.credentials.get({ publicKey: { challenge: new Uint8Array([1]) } });
                  return 'signed in';
                } catch (error) {
                  return error.name + ': ' + error.message;
                }
                """)
        }
        #expect(refused == "NotAllowedError: The operation either timed out or was not allowed.")
    }
}
