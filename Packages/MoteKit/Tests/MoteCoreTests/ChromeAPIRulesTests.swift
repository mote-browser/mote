import Foundation
import Testing

@testable import MoteCore

@Suite("ChromeBookmarks")
struct ChromeBookmarksTests {
    private let news = Bookmark.site("News", URL(string: "https://news.example/")!)
    private let docs = Bookmark.site("Swift docs", URL(string: "https://swift.org/docs")!)
    private let work: Bookmark
    private let roots: [Bookmark]

    init() {
        work = .folder("Work", [docs])
        roots = [news, work]
    }

    @Test("The tree is a root holding the bar holding everything")
    func tree() {
        let tree = ChromeBookmarks.tree(roots)
        let bar = (tree["children"] as? [[String: Any]])?.first
        #expect(tree["id"] as? String == "0")
        #expect(bar?["id"] as? String == "1" && bar?["folderType"] as? String == "bookmarks-bar")
        let top = bar?["children"] as? [[String: Any]]
        #expect(top?.map { $0["title"] as? String } == ["News", "Work"])
        #expect(top?[1]["dateGroupModified"] != nil && top?[0]["url"] as? String == "https://news.example/")
        let inside = top?[1]["children"] as? [[String: Any]]
        #expect(inside?.first?["parentId"] as? String == roots[1].id.uuidString)
        #expect(ChromeBookmarks.bar(roots, deep: false)["children"] == nil)
    }

    @Test("Finding, searching and the latest")
    func lookups() throws {
        let place = try #require(ChromeBookmarks.find(docs.id.uuidString, in: roots))
        #expect(place.parent == roots[1].id.uuidString && place.index == 0)
        #expect(ChromeBookmarks.search(roots, query: "swift DOCS").map(\.node.title) == ["Swift docs"])
        #expect(ChromeBookmarks.search(roots, query: "", url: "https://news.example/").map(\.node.title) == ["News"])
        #expect(ChromeBookmarks.search(roots, query: "", title: "Work").map(\.node.title) == ["Work"])
        #expect(ChromeBookmarks.recent(roots, count: 5).map(\.node.title) == ["Swift docs", "News"])
        #expect(ChromeBookmarks.recent(roots, count: 1).map(\.node.title) == ["Swift docs"])
    }
}

@Suite("ChromeAPIRules")
struct ChromeAPIRulesTests {
    @Test("Data APIs need their permission; settings need their family's")
    func gates() {
        #expect(ChromeAPIRules.gate(for: "history.search") == "history")
        #expect(ChromeAPIRules.gate(for: "tts.speak") == nil)
        #expect(ChromeAPIRules.settingFamily(of: "setting.get:privacy.services.passwordSavingEnabled") == "privacy")
        #expect(ChromeAPIRules.settingFamily(of: "setting.get:proxy.settings") == "proxy")
        #expect(ChromeAPIRules.settingFamily(of: "setting.get") == nil)
        #expect(ChromeAPIRules.settingFamily(of: "setting.get:") == nil)
    }

    @Test("Only permissions in the manifest may be requested; some come without asking")
    func requests() {
        let manifest: [String: Any] = ["permissions": ["tabs"], "optional_permissions": ["history", "idle"]]
        #expect(ChromeAPIRules.mayRequest(["history", "idle"], manifest: manifest))
        #expect(!ChromeAPIRules.mayRequest(["bookmarks"], manifest: manifest))
        #expect(ChromeAPIRules.request(["idle", "system.cpu"]) == (false, "idle, system cpu"))
        #expect(ChromeAPIRules.request(["idle", "history"]).ask)
    }

    @Test("setPopup for one tab keeps the rest; for all tabs, forgets each tab's own")
    func popups() {
        let one = ChromeAPIRules.settingPopup("a.html", tab: "t1", in: ["*": "all.html", "t2": "b.html"])
        #expect(one == ["*": "all.html", "t1": "a.html", "t2": "b.html"])
        #expect(ChromeAPIRules.settingPopup("z.html", tab: nil, in: one) == ["*": "z.html"])
    }

    @Test("Settings nobody set, data kinds, speech rates, context filters and globs")
    func odds() {
        #expect(ChromeAPIRules.defaultSetting("privacy.services.passwordSavingEnabled", savesPasswords: false) as? Bool == false)
        #expect(ChromeAPIRules.defaultSetting("privacy.websites.topicsEnabled", savesPasswords: true) as? Bool == false)
        #expect(ChromeAPIRules.defaultSetting("proxy.settings", savesPasswords: true) as? [String: String] == ["mode": "system"])
        #expect(ChromeAPIRules.defaultSetting("privacy.anything", savesPasswords: true) as? Bool == true)
        #expect(ChromeAPIRules.dataKind(of: "browsingData.removeLocalStorage") == "localStorage")
        #expect(ChromeAPIRules.dataKind(of: "browsingData.remove") == nil)
        #expect(ChromeAPIRules.speechRate(2, standard: 0.5, lowest: 0, highest: 0.8) == 0.8)
        #expect(ChromeAPIRules.speechRate(1, standard: 0.5, lowest: 0, highest: 1) == 0.5)
        #expect(ChromeAPIRules.keeps(type: "POPUP", address: "x", filter: [:]))
        #expect(!ChromeAPIRules.keeps(type: "POPUP", address: "x", filter: ["contextTypes": ["BACKGROUND"]]))
        #expect(!ChromeAPIRules.keeps(type: "POPUP", address: "x", filter: ["documentUrls": ["y"]]))
        #expect(ChromeAPIRules.globs(nil) == [] && ChromeAPIRules.globs(NSNull()) == [])
        #expect(ChromeAPIRules.globs(["*a*"]) == ["*a*"] && ChromeAPIRules.globs("*a*") == nil)
    }
}
