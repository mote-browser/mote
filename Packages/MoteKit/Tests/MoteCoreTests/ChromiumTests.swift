import Foundation
import Testing

@testable import MoteCore

@Suite("Chromium")
struct ChromiumTests {
    private let key = Chromium.key(passphrase: "peanuts")

    private func sealed(_ text: String, prefix: Data = Data()) -> Data {
        Data("v10".utf8) + Chromium.aes(encrypting: Array(prefix + Data(text.utf8)), key: key)!
    }

    @Test("The key is 16 bytes and depends on the passphrase")
    func keys() {
        #expect(key.count == 16)
        #expect(key != Chromium.key(passphrase: "almonds"))
        #expect(key == Chromium.key(passphrase: "peanuts"))
    }

    @Test("v10 passwords decrypt, with or without the site hash in front")
    func decrypting() {
        #expect(Chromium.decrypt(sealed("hunter2"), key: key) == "hunter2")
        #expect(Chromium.decrypt(sealed("hunter2", prefix: Data(repeating: 0xFF, count: 32)), key: key) == "hunter2")
        #expect(Chromium.decrypt(sealed("hunter2"), key: Chromium.key(passphrase: "wrong")) == nil)
    }

    @Test("Very old plain passwords read as they are")
    func plain() {
        #expect(Chromium.decrypt(Data("old".utf8), key: key) == "old")
    }

    @Test("Rows become logins once per site and account, with the never list apart")
    func rows() {
        let rows = [
            Chromium.LoginRow(origin: "https://www.github.com/login", user: "me", blob: sealed("a"), never: false, used: nil),
            Chromium.LoginRow(origin: "https://github.com/", user: "me", blob: sealed("b"), never: false, used: nil),
            Chromium.LoginRow(origin: "http://shop.test/", user: "you", blob: sealed("c"), never: false, used: nil),
            Chromium.LoginRow(origin: "https://spam.test/", user: "", blob: Data(), never: true, used: nil),
            Chromium.LoginRow(origin: "https://broken.test/", user: "x", blob: sealed("d"), never: false, used: nil),
            Chromium.LoginRow(origin: "", user: "x", blob: sealed("e"), never: false, used: nil),
        ]
        var broken = rows
        broken[4].blob = Data("v10".utf8) + Data(repeating: 1, count: 16)
        let found = Chromium.passwords(in: broken, key: key)
        #expect(found.logins.map(\.password) == ["a", "c"])
        #expect(found.logins[1].clear)
        #expect(found.never == ["spam.test"])
    }

    @Test("Times count microseconds from 1601")
    func times() {
        #expect(Chromium.date(0) == nil)
        #expect(Chromium.date(11_644_473_600_000_000) == Date(timeIntervalSince1970: 0))
    }

    @Test("Bookmarks: the bar at the top, Other and Mobile as folders, web addresses only")
    func bookmarks() {
        let json = """
            {"roots": {
              "bookmark_bar": {"children": [
                {"type": "url", "name": "A", "url": "https://a.com/"},
                {"type": "url", "name": "Local", "url": "file:///x"},
                {"type": "folder", "name": "F", "children": [{"type": "url", "name": "B", "url": "http://b.com/"}]}
              ]},
              "other": {"children": [{"type": "url", "name": "C", "url": "https://c.com/"}]},
              "synced": {"children": []}
            }}
            """
        let found = Chromium.bookmarks(json: Data(json.utf8))
        #expect(found.map(\.title) == ["A", "F", "Other"])
        #expect(found[1].children?.map(\.title) == ["B"])
        #expect(Chromium.bookmarks(json: Data("nope".utf8)).isEmpty)
    }

    @Test("Icons: one page per site, the page then the site's root")
    func icons() {
        let urls = ["https://a.com/1", "https://A.com/2", "https://b.com/"].compactMap(URL.init(string:))
        #expect(Chromium.iconSites(urls, limit: 5).map(\.host) == ["a.com", "b.com"])
        #expect(Chromium.iconSites(urls, limit: 1).count == 1)
        #expect(Chromium.iconPages(for: urls[0]) == ["https://a.com/1", "https://a.com/"])
    }
}
