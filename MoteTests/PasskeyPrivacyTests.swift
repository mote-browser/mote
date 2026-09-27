import Testing
import WebKit

@testable import Mote

/// A page with the passkey scripts Tab.arm installs when passkeys are offered:
/// the relay in the page world (twice for `copies: 2`, as when an extension
/// carries its own copy) and the bridge and its handler in Mote's world.
@MainActor
private func passkeyPage(copies: Int = 1) -> WebPage {
    let configuration = WKWebViewConfiguration()
    let controller = configuration.userContentController
    controller.addScriptMessageHandler(PasskeyRelay(), contentWorld: Web.world, name: PasskeyRelay.name)
    for _ in 0..<copies {
        controller.addUserScript(
            WKUserScript(source: PasskeyRelay.page, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    }
    controller.addUserScript(
        WKUserScript(source: PasskeyRelay.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Web.world))
    return WebPage(configuration: configuration)
}

/// Runs `body` as an async function in the page world, with `arguments` as its parameters.
@MainActor
private func inPage(_ page: WebPage, _ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
    try await page.webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page)
}

/// The event names a page would need to talk to the bridge, which only the test knows.
private let names: [String: String] = ["asked": PasskeyRelay.asked, "answered": PasskeyRelay.answered]

/// Starts a sign-in the page doesn't wait for: its outcome lands in `window.outcomes[label]`,
/// and the token the relay gave it in `window.tokens[label]`.
private let startSignIn = """
    window.outcomes = window.outcomes || {};
    window.tokens = window.tokens || {};
    const capture = (event) => {
      const message = JSON.parse(event.detail);
      if (message.kind !== 'cancel') window.tokens[label] = message.token;
    };
    addEventListener(asked, capture, { once: true });
    const signal = window.controllers && window.controllers[label] ? window.controllers[label].signal : undefined;
    navigator.credentials.get({ publicKey: { challenge: new Uint8Array([1, 2, 3]) }, signal }).then(
      (credential) => { window.outcomes[label] = credential instanceof PublicKeyCredential ? 'credential' : 'other'; },
      (error) => { window.outcomes[label] = error.name + ': ' + error.message; });
    return window.tokens[label] || null;
    """

/// Passkeys offered, with rehearsals held until the test lets them go.
@MainActor
private func withHeldRehearsals<T>(_ body: () async throws -> T) async rethrows -> T {
    let offered = FormRelay.passkeysOffered
    FormRelay.passkeysOffered = true
    Passkeys.rehearsalWaits = true
    defer {
        Passkeys.rehearsalWaits = false
        Passkeys.shared.releaseRehearsal()
        FormRelay.passkeysOffered = offered
    }
    return try await body()
}

@MainActor
private func outcome(_ page: WebPage, _ label: String) async throws -> String? {
    try await inPage(page, "return (window.outcomes || {})[label] || null", ["label": label]) as? String
}

/// Waits for the outcome of `label`'s sign-in.
@MainActor
private func settled(_ page: WebPage, _ label: String) async throws -> String {
    for _ in 0..<100 {
        if let found = try await outcome(page, label) { return found }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw TimedOut()
}

private let generic = "NotAllowedError: The operation either timed out or was not allowed."

// Passkeys give Mote away to no site. In PasswordScriptTests' suite, which is
// serialized: these tests too switch the shared Settings › Passwords value, and
// hold the one ceremony Passkeys runs at a time, which would refuse the other
// suite's requests.
extension PasswordScriptTests {
    // MARK: - Detection

    @Test("The relay's event names are random for each launch, not Mote's own words")
    func eventNamesUnguessable() {
        let all = [PasskeyRelay.asked, PasskeyRelay.answered]
        for name in all {
            #expect(name.count >= 32, "\(name)")
            #expect(name.allSatisfy { $0.isHexDigit }, "\(name)")
        }
        #expect(Set(all).count == all.count)
        #expect(!PasskeyRelay.page.contains("mote-passkeys"))
        #expect(!PasskeyRelay.bridge.contains("mote-passkeys"))
    }

    @Test("Nothing marks the credentials prototype, not even in the global symbol registry")
    func noMark() async throws {
        let page = passkeyPage()
        try await page.load(html: "<p>Page</p>")
        let bare = WebPage()
        try await bare.load(html: "<p>Page</p>")
        let marks = """
            JSON.stringify([
              Object.getOwnPropertySymbols(CredentialsContainer.prototype).map(String),
              Symbol.for('search.passkeys') in CredentialsContainer.prototype,
            ])
            """
        let native = try #require(try await bare.string(marks))
        #expect(native.hasSuffix(",false]"))
        #expect(try await page.string(marks) == native)
    }

    @Test("Two copies of the relay in one page install once, and a request is asked once")
    func installsOnce() async throws {
        try await offeringPasskeys {
            let page = passkeyPage(copies: 2)
            try await page.load(html: "<p>Page</p>")
            let before = Passkeys.asked
            let asked = try await inPage(
                page,
                """
                let seen = 0;
                addEventListener(asked, () => { seen += 1; });
                const credential = await navigator.credentials.get({ publicKey: { challenge: new Uint8Array([1]) } });
                return [credential instanceof PublicKeyCredential, seen].join(' ');
                """, names)
            #expect(asked as? String == "true 1")
            #expect(Passkeys.asked == before + 1)
        }
    }

    @Test("The replaced functions present as WebKit's own")
    func looksNative() async throws {
        let bare = WebPage()
        try await bare.load(html: "<iframe srcdoc='<p>Frame</p>'></iframe>")
        let page = passkeyPage()
        try await page.load(html: "<iframe srcdoc='<p>Frame</p>'></iframe>")
        let describe = """
            await new Promise((resolve) => {
              const frame = document.querySelector('iframe');
              if (frame.contentDocument && frame.contentDocument.readyState === 'complete') resolve();
              else frame.addEventListener('load', resolve);
            });
            const P = PublicKeyCredential;
            const functions = {
              get: CredentialsContainer.prototype.get,
              create: CredentialsContainer.prototype.create,
              uvpaa: P.isUserVerifyingPlatformAuthenticatorAvailable,
              conditional: P.isConditionalMediationAvailable,
              capabilities: P.getClientCapabilities,
              toString: Function.prototype.toString,
            };
            const other = document.querySelector('iframe').contentWindow.Function.prototype.toString;
            const out = {};
            for (const [key, f] of Object.entries(functions)) {
              if (typeof f !== 'function') { out[key] = typeof f; continue; }
              let constructs;
              try { new f(); constructs = 'constructs'; } catch (error) { constructs = error.constructor.name; }
              out[key] = [
                Function.prototype.toString.call(f), other.call(f), f.name, f.length, 'prototype' in f, constructs,
                JSON.stringify(Object.getOwnPropertyNames(f).sort()),
              ];
            }
            out.descriptor = JSON.stringify(Object.getOwnPropertyDescriptor(CredentialsContainer.prototype, 'get'), (k, v) => typeof v === 'function' ? 'function' : v);
            return JSON.stringify(out);
            """
        let native = try #require(try await bare.webView.callAsyncJavaScript(describe, contentWorld: .page) as? String)
        let ours = try #require(try await inPage(page, describe) as? String)
        #expect(native.contains("[native code]"))
        #expect(ours == native)
    }

    // MARK: - Errors

    @Test("Refusals carry the one message each error name has, whatever the reason")
    func genericRefusals() async throws {
        try await offeringPasskeys {
            // An insecure page, which WebKit gives no navigator.credentials: only a
            // forged event could ask from it.
            let insecure = passkeyPage()
            try await insecure.load(html: "<p>Page</p>", baseURL: URL(string: "http://insecure.example/")!)
            let refused = try await forgeRequest(["kind": "get", "token": "a", "challenge": "AQID"], on: insecure)
            #expect(refused["error"] as? String == "NotAllowedError")
            #expect(refused["message"] as? String == "The operation either timed out or was not allowed.")

            let page = passkeyPage()
            try await page.load(html: "<p>Page</p>")
            let elsewhere = try await forgeRequest(["kind": "get", "token": "b", "challenge": "AQID", "rpId": "evil.example"], on: page)
            #expect(elsewhere["error"] as? String == "SecurityError")
            #expect(elsewhere["message"] as? String == "The operation is insecure.")

            // What the page hears for arguments of the wrong kind.
            let malformed = try await inPage(
                page,
                """
                const outcomes = [];
                for (const call of [
                  () => navigator.credentials.get({ publicKey: { challenge: 'text' } }),
                  () => navigator.credentials.create({ publicKey: { challenge: new Uint8Array([1]) } }),
                ]) {
                  try { await call(); outcomes.push('ok'); } catch (error) { outcomes.push(error.name + ': ' + error.message); }
                }
                return JSON.stringify(outcomes);
                """)
            #expect(malformed as? String == #"["TypeError: Type error","TypeError: Type error"]"#)
        }
    }

    @Test("A reply the relay can't read rejects the request instead of leaving it pending")
    func malformedReply() async throws {
        try await offeringPasskeys {
            let page = passkeyPage()
            try await page.load(html: "<p>Page</p>")
            let outcome = try await inPage(
                page,
                """
                // Answer first, with a reply that is no credential, before Swift does.
                addEventListener(asked, (event) => {
                  const { token } = JSON.parse(event.detail);
                  const reply = { kind: 'get', id: '%%%', clientDataJSON: '%%%', authenticatorData: '%%%', signature: '%%%' };
                  dispatchEvent(new CustomEvent(answered, { detail: JSON.stringify({ token, reply }) }));
                }, { once: true });
                const request = navigator.credentials.get({ publicKey: { challenge: new Uint8Array([1]) } });
                const timeout = new Promise((resolve) => setTimeout(() => resolve('pending'), 2000));
                return await Promise.race([request.then(() => 'credential', (error) => error.name), timeout]);
                """, names)
            #expect(outcome as? String == "NotAllowedError")
        }
    }

    // MARK: - One ceremony, owned by the document that asked

    @Test("Tokens come from a cryptographic source")
    func randomTokens() async throws {
        try await withHeldRehearsals {
            let page = passkeyPage()
            try await page.load(html: "<p>Page</p>")
            let token = try await inPage(page, startSignIn, names.merging(["label": "first"]) { $1 }) as? String
            #expect(token?.count == 32, "\(token ?? "none")")
            #expect(token?.allSatisfy { $0.isHexDigit } == true)
        }
    }

    @Test("Another tab can't cancel a request")
    func cancelFromAnotherTab() async throws {
        try await withHeldRehearsals {
            let asking = passkeyPage()
            try await asking.load(html: "<p>Asking</p>")
            let other = passkeyPage()
            try await other.load(html: "<p>Other</p>")

            let token = try #require(
                try await inPage(asking, startSignIn, names.merging(["label": "first"]) { $1 }) as? String)
            _ = try await eventually { Passkeys.shared.isWaiting ? true : nil }
            _ = try await inPage(
                other, "dispatchEvent(new CustomEvent(asked, { detail: JSON.stringify({ kind: 'cancel', token }) }))",
                names.merging(["token": token]) { $1 })
            try await Task.sleep(for: .milliseconds(300))

            #expect(Passkeys.shared.isWaiting)
            #expect(try await outcome(asking, "first") == nil)
            Passkeys.shared.releaseRehearsal()
            #expect(try await settled(asking, "first") == "credential")
        }
    }

    @Test("A request from another tab is refused while one is pending, and doesn't take its place")
    func otherTabRefused() async throws {
        try await withHeldRehearsals {
            let asking = passkeyPage()
            try await asking.load(html: "<p>Asking</p>")
            let other = passkeyPage()
            try await other.load(html: "<p>Other</p>")

            _ = try await inPage(asking, startSignIn, names.merging(["label": "first"]) { $1 })
            _ = try await eventually { Passkeys.shared.isWaiting ? true : nil }
            _ = try await inPage(other, startSignIn, names.merging(["label": "second"]) { $1 })

            #expect(try await settled(other, "second") == generic)
            #expect(try await outcome(asking, "first") == nil)
            Passkeys.shared.releaseRehearsal()
            #expect(try await settled(asking, "first") == "credential")
        }
    }

    @Test("A new request from the same page takes the place of its own pending one, as in Safari")
    func sameDocumentReplaces() async throws {
        try await withHeldRehearsals {
            let page = passkeyPage()
            try await page.load(html: "<p>Page</p>")

            _ = try await inPage(page, startSignIn, names.merging(["label": "first"]) { $1 })
            _ = try await eventually { Passkeys.shared.isWaiting ? true : nil }
            _ = try await inPage(page, startSignIn, names.merging(["label": "second"]) { $1 })

            #expect(try await settled(page, "first") == generic)
            Passkeys.shared.releaseRehearsal()
            #expect(try await settled(page, "second") == "credential")
        }
    }

    @Test("The page that asked can let its request go")
    func cancelOwn() async throws {
        try await withHeldRehearsals {
            let page = passkeyPage()
            try await page.load(html: "<p>Page</p>")

            _ = try await inPage(
                page, "window.controllers = { first: new AbortController() }; " + startSignIn,
                names.merging(["label": "first"]) { $1 })
            _ = try await eventually { Passkeys.shared.isWaiting ? true : nil }
            _ = try await inPage(page, "window.controllers.first.abort(); return null")

            #expect(try await settled(page, "first").hasPrefix("AbortError"))
            _ = try await eventually { Passkeys.shared.isWaiting ? nil : true }
        }
    }

    // MARK: - Helpers

    private func offeringPasskeys<T>(_ body: () async throws -> T) async rethrows -> T {
        let was = FormRelay.passkeysOffered
        FormRelay.passkeysOffered = true
        defer { FormRelay.passkeysOffered = was }
        return try await body()
    }

    /// Dispatches a request as the page's own window event and returns Swift's reply.
    private func forgeRequest(_ request: [String: Any], on page: WebPage) async throws -> [String: Any] {
        let reply = try await inPage(
            page,
            """
            return await new Promise((resolve) => {
              addEventListener(answered, (event) => {
                const answer = JSON.parse(event.detail);
                if (answer.token === request.token) resolve(JSON.stringify(answer.reply));
              });
              dispatchEvent(new CustomEvent(asked, { detail: JSON.stringify(request) }));
            });
            """, ["asked": PasskeyRelay.asked, "answered": PasskeyRelay.answered, "request": request])
        let text = try #require(reply as? String)
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
