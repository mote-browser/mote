import Foundation
import Testing

@testable import MoteCore

@Suite("ExtensionRules")
struct ExtensionRulesTests {
    @Test("Records read and write the same JSON as before, old files included")
    func record() throws {
        let old = #"[{"id":"abc","name":"A","version":"1.0","enabled":true,"fromStore":true,"permissions":["tabs"]}]"#
        let read = try JSONDecoder().decode([InstalledExtension].self, from: Data(old.utf8))
        #expect(read == [InstalledExtension(id: "abc", name: "A", version: "1.0", fromStore: true, permissions: ["tabs"])])
        let keys =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(
                    InstalledExtension(id: "x", name: "X", version: "2", fromStore: false, permissions: [], pinned: true, source: "/a"))
            ) as? [String: Any]
        #expect(keys?.keys.sorted() == ["enabled", "fromStore", "id", "name", "permissions", "pinned", "source", "version"])
        let local = InstalledExtension.localID(from: UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!)
        #expect(local == "local-abcdef12")
    }

    @Test("Old extension addresses move to chrome-extension://")
    func addresses() {
        #expect(
            ExtensionRules.current(URL(string: "webkit-extension://id/page.html?a=1")!).absoluteString
                == "chrome-extension://id/page.html?a=1")
        #expect(ExtensionRules.current(URL(string: "https://a.b/")!).absoluteString == "https://a.b/")
    }

    @Test("Popups: the copy's name, the manifest's popup, and setPopup overrides")
    func popups() {
        #expect(ExtensionRules.popupCopyName(of: "popup.html") == "popup.mote-popup.html")
        #expect(ExtensionRules.popupCopyName(of: "popup") == "popup.mote-popup")
        #expect(ExtensionRules.manifestPopup(["action": ["default_popup": "p.html"]]) == "p.html")
        #expect(ExtensionRules.manifestPopup(["browser_action": ["default_popup": "b.html"]]) == "b.html")
        #expect(ExtensionRules.manifestPopup(["action": ["default_popup": ""]]) == nil)
        #expect(ExtensionRules.popup(overrides: [:], tab: "t") == .manifest)
        #expect(ExtensionRules.popup(overrides: ["*": "all.html", "t": "one.html"], tab: "t") == .page("one.html"))
        #expect(ExtensionRules.popup(overrides: ["*": "all.html"], tab: "t") == .page("all.html"))
        #expect(ExtensionRules.popup(overrides: ["t": ""], tab: "t") == .none)
    }

    @Test("Grants leave out what the shim added and name sites and native APIs")
    func grants() {
        let grants = ExtensionRules.grants(
            requested: ["tabs", "storage", "unlimitedStorage"], patterns: ["*://a.com/*"], declared: ["history", "tabs", "downloads"],
            added: ["unlimitedStorage", "downloads"])
        #expect(grants == ["search:history", "site:*://a.com/*", "storage", "tabs"])
        #expect(!ExtensionRules.wantsMore(["tabs"], than: ["tabs", "storage"]))
        #expect(ExtensionRules.wantsMore(["tabs", "site:<all_urls>"], than: ["tabs"]))
    }

    @Test("What an extension asks for, said plainly")
    func describe() {
        typealias Site = ExtensionRules.Site
        let everywhere = ExtensionRules.describe(
            requested: ["tabs", "scripting", "storage"], sites: [Site(host: nil, everywhere: true)], declared: ["bookmarks"],
            added: ["scripting"])
        #expect(
            everywhere == [
                "Read and change everything on every website", "See your open tabs and their addresses", "Read and change your bookmarks",
            ])
        let hosts = (1...6).map { Site(host: "h\($0).com", everywhere: false) }
        let some = ExtensionRules.describe(requested: [], sites: hosts, declared: [], added: [])
        #expect(some == ["Read and change what's on h1.com, h2.com, h3.com, h4.com and 2 more"])
        #expect(ExtensionRules.installDetail([]) == "It doesn't ask for anything special.")
        #expect(ExtensionRules.installDetail(["A", "B"]) == "It will be able to:\n• A\n• B")
    }

    @Test("The store's answer: only <updatecheck> counts, and only a new version")
    func updates() {
        let answer =
            #"<?xml version="1.0"?><gupdate><app appid="x" status="ok"><updatecheck codebase="c" version="2.1" status="ok"/></app></gupdate>"#
        #expect(ExtensionRules.offeredVersion(in: answer, current: "2.0") == "2.1")
        #expect(ExtensionRules.offeredVersion(in: answer, current: "2.1") == nil)
        let none = #"<?xml version="1.0"?><gupdate><app appid="x" status="ok"><updatecheck status="noupdate"/></app></gupdate>"#
        #expect(ExtensionRules.offeredVersion(in: none, current: "1") == nil)
        let url = ExtensionRules.updateCheckURL(id: "abc", version: "1.2")?.absoluteString ?? ""
        #expect(url.contains("x=id%3Dabc%26v%3D1.2%26uc"))
    }

    @Test("The newest enabled extension with a new tab page wins")
    func newTab() {
        let a = InstalledExtension(id: "a", name: "A", version: "1", fromStore: true, permissions: [])
        var b = InstalledExtension(id: "b", name: "B", version: "1", fromStore: true, permissions: [])
        let page = URL(string: "chrome-extension://a/new.html")!
        let pageB = URL(string: "chrome-extension://b/new.html")!
        #expect(ExtensionRules.newTabOwner([a, b], pages: ["a": page, "b": pageB])?.id == "b")
        b.enabled = false
        #expect(ExtensionRules.newTabOwner([a, b], pages: ["a": page, "b": pageB])?.id == "a")
        #expect(ExtensionRules.newTabOwner([a], pages: [:]) == nil)
    }

    @Test("Tab changes: closed, opened, and moved among those that stayed")
    func tabs() {
        let changes = ExtensionRules.tabChanges(from: [1, 2, 3, 4], to: [3, 5, 1, 2])
        #expect(changes.closed == [4])
        #expect(changes.opened == [5])
        #expect(changes.moved.map(\.id) == [1, 2, 3])
        #expect(changes.moved.map(\.from) == [0, 1, 2])
        let same = ExtensionRules.tabChanges(from: [1, 2], to: [1, 2, 3])
        #expect(same.moved.isEmpty && same.opened == [3] && same.closed.isEmpty)
    }

    @Test("Errors keep the latest forty")
    func errors() {
        let many = (1...45).reduce([String]()) { ExtensionRules.noting("e\($1)", in: $0) }
        #expect(many.count == 40)
        #expect(many.first == "e6" && many.last == "e45")
    }

    @Test("Failures past the limit in a second wait; restarts once a minute")
    func throttles() {
        var throttle = FailureThrottle()
        let start = Date(timeIntervalSince1970: 0)
        let waits = (0..<13).map { throttle.failed("x", at: start.addingTimeInterval(Double($0) * 0.01)) }
        #expect(waits.filter { $0 }.count == 1 && waits.last == true)
        let later = throttle.failed("x", at: start.addingTimeInterval(5))
        #expect(!later)
        var cooldown = Cooldown(60)
        let first = cooldown.take("a", at: start)
        let soon = cooldown.take("a", at: start.addingTimeInterval(30))
        let other = cooldown.take("b", at: start.addingTimeInterval(30))
        let after = cooldown.take("a", at: start.addingTimeInterval(61))
        #expect(first && !soon && other && after)
    }

    @Test("Store pages, old and new")
    func store() {
        #expect(ExtensionRules.isStorePage(URL(string: "https://chromewebstore.google.com/detail/x/abc")!))
        #expect(ExtensionRules.isStorePage(URL(string: "https://chrome.google.com/webstore/detail/abc")!))
        #expect(!ExtensionRules.isStorePage(URL(string: "https://chrome.google.com/other")!))
    }

    @Test("The line under an extension's name")
    func detail() {
        var item = InstalledExtension(id: "a", name: "A", version: "2.0", fromStore: true, permissions: [])
        #expect(ExtensionRules.detail(item, running: true, showsInNewTabs: false, warnings: 0) == "Version 2.0 · Chrome Web Store")
        #expect(
            ExtensionRules.detail(item, running: false, showsInNewTabs: true, warnings: 1)
                == "Version 2.0 · Chrome Web Store · couldn't start · shows in new tabs · 1 warning")
        item = InstalledExtension(id: "b", name: "B", version: "1", fromStore: false, permissions: [], source: "/Users/me/dev/My Ext")
        item.enabled = false
        #expect(ExtensionRules.detail(item, running: false, showsInNewTabs: false, warnings: 3) == "Version 1 · From “My Ext” · 3 warnings")
    }
}
