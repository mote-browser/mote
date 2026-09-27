import Foundation
import MoteCore
import Testing
import WebKit

@testable import Mote

/// Serves an empty page for any address of the extension scheme, so a page can
/// have an extension's origin without an extension.
private final class ExtensionScheme: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let data = Data("<!doctype html><title>Extension page</title>".utf8)
        task.didReceive(
            URLResponse(url: task.request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// A page with a stand-in for WebKit's extension APIs, where the shim can run
/// without a real extension. Like WebKit's, the stand-in's methods live on its
/// objects' prototypes; `sendNativeMessage` is recorded in `__natives` and
/// answered from `__answers`, or with `{ value: null }`.
@available(macOS 15.4, *)
@MainActor
private struct ShimPage {
    let page: WebPage

    /// A WebKit-like `chrome`, as an extension's page (or, on a website, a content script) sees it.
    static let fakeChrome = #"""
        (() => {
          const eventProto = {
            addListener(f) { this._l.add(f); }, removeListener(f) { this._l.delete(f); },
            hasListener(f) { return this._l.has(f); }, hasListeners() { return this._l.size > 0; },
          };
          const event = () => Object.assign(Object.create(eventProto), { _l: new Set() });
          const namespace = (methods, events = [], extra = {}) => {
            const ns = Object.create(Object.assign({}, methods));
            for (const e of events) ns[e] = event();
            return Object.assign(ns, extra);
          };
          window.__natives = [];
          window.__answers = {};
          window.__sent = [];
          const portProto = { postMessage() {}, disconnect() {} };
          const port = (name) => Object.assign(Object.create(portProto), { name, sender: undefined, onMessage: event(), onDisconnect: event() });
          const tabs = [{ id: 7, index: 0, windowId: 1, active: true }];
          const chrome = {
            runtime: namespace({
              getManifest: () => ({ manifest_version: 3, version: "1.0", permissions: ["tabs", "storage"], background: { service_worker: "worker.js" } }),
              getURL: (path) => location.origin + "/" + String(path).replace(/^\//, ""),
              sendNativeMessage: (application, message) => {
                window.__natives.push({ application, message });
                return Promise.resolve(window.__answers[message.api] ?? { value: null });
              },
              sendMessage: (...args) => { window.__sent.push(args); return Promise.resolve("reply"); },
              connect: (info) => port((info && info.name) || ""),
              connectNative: (name) => port(name),
            }, ["onMessage", "onMessageExternal", "onConnect", "onInstalled"], { id: "fakeextension" }),
            tabs: namespace({
              query: () => Promise.resolve(tabs.map((t) => ({ ...t }))),
              get: (id) => Promise.resolve({ ...tabs.find((t) => t.id === id) }),
              getCurrent: () => Promise.resolve({ ...tabs[0] }),
              sendMessage: () => Promise.resolve(undefined),
            }, ["onCreated", "onUpdated"]),
            storage: namespace({}, ["onChanged"], {
              local: namespace({ get: () => Promise.resolve({}), set: (items) => { window.__stored = items; return Promise.resolve(); } }),
            }),
            permissions: namespace({
              contains: () => Promise.resolve(true), request: () => Promise.resolve(true),
              getAll: () => Promise.resolve({ permissions: ["tabs"], origins: [] }), remove: () => Promise.resolve(true),
            }),
            declarativeNetRequest: namespace({ updateDynamicRules: (o) => { window.__rules = o; return Promise.resolve(); } }),
            windows: namespace({
              getAll: () => Promise.resolve([{ id: 1, focused: true, state: "normal", tabs: tabs.map((t) => ({ ...t })) }]),
            }),
            contextMenus: namespace({ create: (p) => { window.__menu = p; return 1; }, update: () => {} }, ["onClicked"]),
            extension: namespace({ getViews: () => [], getBackgroundPage: () => null }),
          };
          for (const key of ["chrome", "browser"]) {
            Object.defineProperty(window, key, { value: chrome, configurable: true, writable: true, enumerable: true });
          }
        })();
        """#

    /// Loads a page at `origin`, with the stand-in `chrome` unless `bare`, then runs `scripts` in it.
    static func load(
        _ scripts: [String], origin: String = "chrome-extension://fakeextension/", bare: Bool = false
    ) async throws
        -> ShimPage
    {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(ExtensionScheme(), forURLScheme: "chrome-extension")
        if !bare {
            configuration.userContentController.addUserScript(
                WKUserScript(source: fakeChrome, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let page = WebPage(configuration: configuration)
        try await page.load(html: "<!doctype html><title>Page</title>", baseURL: URL(string: origin)!)
        for script in scripts { _ = try await page.webView.evaluateJavaScript(script + "\n;0") }
        return ShimPage(page: page)
    }

    /// The built shim with an extension's values, as `ExtensionShims.shim(for:)` makes it.
    static let shim = InjectedScript.source(
        "extension-shims",
        config: ExtensionShims.ShimConfig(events: [], scripts: [], chromeVersion: "140.0.7339.0", verbose: false))

    /// Runs `body` as an async function; its result comes back as JSON.
    func json(_ body: String) async throws -> String {
        try await page.call("return JSON.stringify(await (async () => { \(body) })());") ?? "null"
    }
}

@Suite("Extension shims")
@MainActor
struct ExtensionShimTests {
    @Test("An extension's page gets the namespaces WebKit lacks, and Chrome's user agent")
    @available(macOS 15.4, *)
    func namespaces() async throws {
        let page = try await ShimPage.load([ShimPage.shim])
        let surfaces = try await page.json(
            """
            return [
              typeof chrome.bookmarks.getTree, typeof chrome.bookmarks.onCreated.addListener, typeof chrome.history.search,
              typeof chrome.downloads.download, typeof chrome.tts.speak, typeof chrome.sidePanel.open,
              typeof chrome.offscreen.createDocument, chrome.offscreen.Reason.DOM_PARSER, typeof chrome.identity.getRedirectURL,
              typeof chrome.privacy.services.passwordSavingEnabled.get, typeof chrome.userScripts, typeof chrome.system.cpu.getInfo,
              chrome.tabs.TAB_ID_NONE ?? chrome.tabs.TAB_INDEX_NONE, chrome.runtime.OnInstalledReason.INSTALL,
              chrome.declarativeNetRequest.ResourceType === chrome.webRequest?.ResourceType, typeof requestFileSystem,
              window.__moteShim, navigator.userAgent.includes(" Chrome/140.0.7339.0 "), browser.bookmarks === chrome.bookmarks,
            ];
            """)
        #expect(
            surfaces
                == #"["function","function","function","function","function","function","function","DOM_PARSER","function","function","undefined","function",-1,"install",false,"function",true,true,true]"#
        )
    }

    @Test("Calls go to the browser as native messages, and a refusal reaches the callback as lastError")
    @available(macOS 15.4, *)
    func nativeMessages() async throws {
        let page = try await ShimPage.load([ShimPage.shim])
        let result = try await page.json(
            """
            __answers["bookmarks.getTree"] = { value: [{ id: "0" }] };
            __answers["history.deleteAll"] = { error: "The extension never asked for history" };
            const tree = await chrome.bookmarks.getTree();
            await chrome.history.search({ text: "a", skipped: undefined });
            await chrome.privacy.services.passwordSavingEnabled.get({});
            const refused = await new Promise((r) => chrome.history.deleteAll(() => r(chrome.runtime.lastError.message)));
            const rejected = await chrome.history.deleteAll().catch((e) => e.message);
            return { tree, refused, rejected, after: chrome.runtime.lastError ?? null, natives: __natives };
            """)
        #expect(
            result
                == #"{"tree":[{"id":"0"}],"refused":"The extension never asked for history","rejected":"The extension never asked for history","after":null,"natives":[{"application":"mote","message":{"api":"bookmarks.getTree","args":[]}},{"application":"mote","message":{"api":"history.search","args":[{"text":"a"}]}},{"application":"mote","message":{"api":"setting.get:privacy.services.passwordSavingEnabled","args":[{}]}},{"application":"mote","message":{"api":"history.deleteAll","args":[]}},{"application":"mote","message":{"api":"history.deleteAll","args":[]}}]}"#
        )
    }

    @Test("WebKit's namespaces get Chrome's behaviour: rules, menus, storage, tabs and permissions")
    @available(macOS 15.4, *)
    func mends() async throws {
        let page = try await ShimPage.load([ShimPage.shim])
        let result = try await page.json(
            """
            await chrome.declarativeNetRequest.updateDynamicRules({ addRules: [
              { id: 1, action: { type: "redirect", redirect: { url: location.origin + "/blocked.html" } }, condition: { resourceTypes: ["main_frame", "object"] } },
              { id: 2, action: { type: "block" }, condition: { resourceTypes: ["webbundle"] } } ] });
            chrome.contextMenus.create({ id: "m", contexts: ["browser_action", "launcher"] });
            await chrome.storage.local.set(Object.assign(Object.create(null), { a: 1 }));
            const tab = await chrome.tabs.get(7);
            const unknown = await chrome.permissions.contains({ permissions: ["bogus"] });
            return { rules: __rules, menu: __menu, plain: Object.getPrototypeOf(__stored) === Object.prototype, group: tab.groupId, unknown };
            """)
        #expect(
            result
                == #"{"rules":{"addRules":[{"id":1,"action":{"type":"redirect","redirect":{"extensionPath":"/blocked.html"}},"condition":{"resourceTypes":["main_frame"]}}]},"menu":{"id":"m","contexts":["action"]},"plain":true,"group":-1,"unknown":false}"#
        )
    }

    @Test("A window is not taken for a tab, and the tabs inside it are mended")
    @available(macOS 15.4, *)
    func windows() async throws {
        let page = try await ShimPage.load([ShimPage.shim])
        let result = try await page.json(
            """
            const [window] = await chrome.windows.getAll({ populate: true });
            return { window: "groupId" in window, tab: window.tabs[0].groupId };
            """)
        #expect(result == #"{"window":false,"tab":-1}"#)
    }

    @Test("Without WebKit's contextMenus.update, only that mend is skipped")
    @available(macOS 15.4, *)
    func menusWithoutUpdate() async throws {
        let page = try await ShimPage.load(["delete Object.getPrototypeOf(chrome.contextMenus).update;", ShimPage.shim])
        let result = try await page.json(
            """
            chrome.contextMenus.create({ id: "m", contexts: ["launcher"] });
            const tab = await chrome.tabs.get(7);
            return { menu: __menu, update: typeof chrome.contextMenus.update, group: tab.groupId, userScripts: typeof chrome.runtime.onUserScriptMessage };
            """)
        #expect(result == #"{"menu":{"id":"m","contexts":["page"]},"update":"undefined","group":-1,"userScripts":"object"}"#)
    }

    @Test("A content script gets Chrome's behaviour, and no API Chrome keeps from it")
    @available(macOS 15.4, *)
    func contentScript() async throws {
        let page = try await ShimPage.load([ShimPage.shim], origin: "https://example.com/")
        let result = try await page.json(
            """
            const { sendMessage } = chrome.runtime;
            return [typeof chrome.bookmarks, window.__moteShim, await sendMessage({ hi: 1 }), navigator.userAgent.includes("Chrome/")];
            """)
        #expect(result == #"["undefined",true,"reply",false]"#)
    }

    @Test("A page's own world, without extension APIs, is left untouched")
    @available(macOS 15.4, *)
    func pageWorld() async throws {
        let page = try await ShimPage.load([ShimPage.shim], origin: "https://example.com/", bare: true)
        let result = try await page.json("return [typeof __moteShim, typeof __moteKept, typeof requestFileSystem];")
        #expect(result == #"["undefined","undefined","undefined"]"#)
    }

    @Test("Loaded twice, the shim mends once")
    @available(macOS 15.4, *)
    func once() async throws {
        let page = try await ShimPage.load([ShimPage.shim])
        let first = try await page.json("window.__first = chrome.bookmarks; return 0;")
        _ = try await page.page.webView.evaluateJavaScript(ShimPage.shim + "\n;0")
        let same = try await page.json("return chrome.bookmarks === window.__first;")
        #expect(first == "0")
        #expect(same == "true")
    }

    @Test("A user script runs where its globs allow, and its USER_SCRIPT world's messages are tagged")
    @available(macOS 15.4, *)
    func userScript() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        func file(_ script: [String: Any]) throws -> String {
            try String(contentsOf: folder.appendingPathComponent(ExtensionShims.userScriptFile(script, in: folder)), encoding: .utf8)
        }
        let code = [["code": "window.__ran = (window.__ran || 0) + 1; chrome.runtime.sendMessage({ hi: 1 });"]]
        let included = try file(["id": "a", "js": code, "includeGlobs": ["https://example.com/*"]])
        let excluded = try file(["id": "b", "js": code, "excludeGlobs": ["*example.com*"]])
        let main = try file(["id": "c", "js": [["code": "window.__main = typeof chrome.runtime.sendMessage;"]], "world": "MAIN"])

        let page = try await ShimPage.load([included, excluded, main], origin: "https://example.com/")
        let result = try await page.json("return [window.__ran, __sent, window.__main];")
        #expect(result == #"[1,[[{"__moteUserScript":true,"message":{"hi":1}}]],"function"]"#)
    }

    @Test("A user script whose globs aren't arrays of strings is refused with an error, as Chrome refuses it")
    @available(macOS 15.4, *)
    func userScriptInvalidGlobs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let code = [["code": "window.__ran = 1;"]]
        let invalid: [[String: Any]] = [
            ["id": "a", "js": code, "includeGlobs": "https://example.com/*"],
            ["id": "b", "js": code, "excludeGlobs": "*example.com*"],
            ["id": "c", "js": code, "includeGlobs": ["https://example.com/*", 3]],
            ["id": "d", "js": code, "excludeGlobs": ["glob": "*"]],
        ]
        for script in invalid {
            let error = #expect(throws: ExtensionShims.InvalidUserScript.self) {
                try ExtensionShims.userScriptFile(script, in: folder)
            }
            #expect(error?.localizedDescription.contains("Globs") == true)
        }
        // Absent or null globs are none, as before.
        let valid = try ExtensionShims.userScriptFile(["id": "e", "js": code, "includeGlobs": NSNull()], in: folder)
        let text = try String(contentsOf: folder.appendingPathComponent(valid), encoding: .utf8)
        #expect(text.contains("})([], [], true);"))
    }

    @Test("An extension's scripts are listed alike in every preparation")
    @available(macOS 15.4, *)
    func preparedScripts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = #"{"manifest_version": 3, "name": "Test", "version": "1", "background": {"service_worker": "worker.js"}}"#
        try manifest.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "importScripts('lib.js');\n".write(to: folder.appendingPathComponent("worker.js"), atomically: true, encoding: .utf8)
        try "self.lib = 1;\n".write(to: folder.appendingPathComponent("lib.js"), atomically: true, encoding: .utf8)
        func scripts() throws -> [String] {
            let shim = try String(contentsOf: folder.appendingPathComponent(ExtensionShims.file), encoding: .utf8)
            let prefix = "const moteConfig = "
            let line = try #require(shim.split(separator: "\n").first { $0.hasPrefix(prefix) })
            let config = try JSONSerialization.jsonObject(with: Data(line.dropFirst(prefix.count).dropLast().utf8))
            return try #require((config as? [String: Any])?["scripts"] as? [String])
        }

        try ExtensionShims.prepare(folder)
        let first = try scripts()
        try "0123abcd".write(to: folder.appendingPathComponent(ExtensionShims.stamp), atomically: true, encoding: .utf8)
        try ExtensionShims.prepare(folder)
        #expect(try scripts() == first)
        #expect(first == ["/lib.js", "/\(ExtensionShims.passkeys)", "/\(ExtensionShims.file)", "/worker.js"])
    }

    @Test("An extension is prepared with the shim and its values, and prepared again for a new shim")
    @available(macOS 15.4, *)
    func prepare() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = #"{"manifest_version": 3, "name": "Test", "version": "1", "background": {"service_worker": "worker.js"}}"#
        try manifest.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let worker = "chrome.tabs.onUpdated.addListener(() => {});\n"
        try worker.write(to: folder.appendingPathComponent("worker.js"), atomically: true, encoding: .utf8)

        try ExtensionShims.prepare(folder)
        let stamp = folder.appendingPathComponent(ExtensionShims.stamp)
        #expect(try String(contentsOf: stamp, encoding: .utf8) == ExtensionShims.version)
        let prepared = try String(contentsOf: folder.appendingPathComponent("worker.js"), encoding: .utf8)
        #expect(prepared.hasPrefix(ExtensionShims.marker + "\n"))
        #expect(prepared.hasSuffix(ExtensionShims.ender + "\n" + worker))
        #expect(prepared.contains(#""events":["tabs.onUpdated"]"#))
        let shim = try String(contentsOf: folder.appendingPathComponent(ExtensionShims.file), encoding: .utf8)
        #expect(shim.contains("const moteConfig = {"))

        // Prepared by an older build: the shim is replaced, not added again.
        try "0123abcd".write(to: stamp, atomically: true, encoding: .utf8)
        try ExtensionShims.prepare(folder)
        let again = try String(contentsOf: folder.appendingPathComponent("worker.js"), encoding: .utf8)
        #expect(again.components(separatedBy: ExtensionShims.marker).count == 2)
        #expect(again.hasSuffix(ExtensionShims.ender + "\n" + worker))
        #expect(again.contains(#""events":["tabs.onUpdated"]"#))
        #expect(try String(contentsOf: stamp, encoding: .utf8) == ExtensionShims.version)
    }

    @Test("A new launch refreshes only the passkey relay, not the whole extension")
    @available(macOS 15.4, *)
    func newLaunchRefreshesOnlyTheRelay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = #"{"manifest_version": 3, "name": "Test", "version": "1", "background": {"service_worker": "worker.js"}}"#
        try manifest.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "self.ready = true;\n".write(to: folder.appendingPathComponent("worker.js"), atomically: true, encoding: .utf8)
        try ExtensionShims.prepare(folder)

        // What the previous launch left: its relay carried other event names.
        let relay = folder.appendingPathComponent(ExtensionShims.passkeys)
        try "/* the previous launch's relay */".write(to: relay, atomically: true, encoding: .utf8)
        let worker = folder.appendingPathComponent("worker.js")
        let written = try worker.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        try ExtensionShims.prepare(folder)

        #expect(try String(contentsOf: relay, encoding: .utf8) == PasskeyRelay.page)
        #expect(try worker.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == written)
    }

    @Test("The shim's version is the hash of what is written, so a new build prepares extensions again")
    @available(macOS 15.4, *)
    func version() {
        #expect(
            ExtensionShims.version
                == ExtensionShims.version(of: InjectedScript.source("extension-shims") + InjectedScript.source("passkey-relay")))
        #expect(ExtensionShims.version(of: ExtensionShims.script + "\n") != ExtensionShims.version)
    }
}
