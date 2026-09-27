import AppKit
import MoteCore
import WebKit

// The person's bookmarks, history, downloads and closed tabs, for extensions
// allowed them.

@available(macOS 15.4, *)
extension ChromeAPI {
    // MARK: - bookmarks

    static func bookmarks(_ call: ChromeCall) async throws -> Any? {
        let store = call.browser.bookmarks
        let roots = store.roots
        let place = { (id: String) in ChromeBookmarks.find(id, in: roots) }
        func existing() throws -> UUID {
            guard let id = (call.first as? String).flatMap(UUID.init(uuidString:)) else { throw Refusal("No such bookmark") }
            return id
        }
        // After a change, as the tree now has it.
        func now(_ id: UUID) -> Any? { ChromeBookmarks.find(id.uuidString, in: store.roots).map { ChromeBookmarks.node($0, deep: false) } }

        switch call.method {
        case "getTree":
            return [ChromeBookmarks.tree(roots)]
        case "getSubTree":
            switch call.first as? String {
            case nil: return []
            case ChromeBookmarks.root: return [ChromeBookmarks.tree(roots)]
            case ChromeBookmarks.bar: return [ChromeBookmarks.bar(roots)]
            case let id?: return place(id).map { [ChromeBookmarks.node($0, deep: true)] } ?? []
            }
        case "getChildren":
            let id = call.first as? String ?? ChromeBookmarks.bar
            if id == ChromeBookmarks.root { return [ChromeBookmarks.bar(roots, deep: false)] }
            let children = id == ChromeBookmarks.bar ? roots : place(id)?.node.children ?? []
            return children.enumerated().map { ChromeBookmarks.node(ChromeBookmarks.Place(node: $1, parent: id, index: $0), deep: false) }
        case "get":
            let ids = call.first as? [String] ?? (call.first as? String).map { [$0] } ?? []
            return ids.compactMap(place).map { ChromeBookmarks.node($0, deep: false) }
        case "getRecent":
            return ChromeBookmarks.recent(roots, count: call.first as? Int ?? 10).map { ChromeBookmarks.node($0, deep: false) }
        case "search":
            let query = call.first as? String ?? call.option("query") ?? ""
            return ChromeBookmarks.search(roots, query: query, url: call.option("url"), title: call.option("title"))
                .map { ChromeBookmarks.node($0, deep: false) }
        case "create":
            let title: String = call.option("title") ?? ""
            let parent = (call.option("parentId") as String?).flatMap(UUID.init(uuidString:))
            let made = (call.option("url") as String?).flatMap(URL.init(string:)).map { Bookmark.site(title, $0) } ?? .folder(title, [])
            let kept = store.insert(made, into: parent)
            return ChromeBookmarks.node(
                ChromeBookmarks.Place(node: kept, parent: parent?.uuidString ?? ChromeBookmarks.bar, index: 0), deep: false)
        case "update":
            let id = try existing()
            let changes = call.arg(1) as? [String: Any] ?? [:]
            store.update(id, title: changes["title"] as? String, url: changes["url"] as? String)
            return now(id)
        case "move":
            let id = try existing()
            store.move(id, into: ((call.arg(1) as? [String: Any])?["parentId"] as? String).flatMap(UUID.init(uuidString:)))
            return now(id)
        case "remove", "removeTree":
            store.remove(try existing())
            return nil
        default:
            throw unavailable(call)
        }
    }

    // MARK: - history

    private static func chromeTime(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }
    private static func date(_ chrome: Double) -> Date { Date(timeIntervalSince1970: chrome / 1000) }

    static func history(_ call: ChromeCall) async throws -> Any? {
        let history = call.browser.history
        let address: String = call.option("url") ?? ""
        switch call.method {
        case "search":
            let start = (call.option("startTime") as Double?).map(date) ?? Date().addingTimeInterval(-24 * 3600)
            let end = (call.option("endTime") as Double?).map(date) ?? .distantFuture
            return history.entries(matching: call.option("text") ?? "")
                .filter { $0.last >= start && $0.last <= end }
                .sorted { $0.last > $1.last }
                .prefix(call.option("maxResults") ?? 100)
                .map { visit in
                    [
                        "id": visit.key, "url": visit.url.absoluteString, "title": visit.title, "lastVisitTime": chromeTime(visit.last),
                        "visitCount": visit.count, "typedCount": 0,
                    ] as [String: Any]
                }
        case "getVisits":
            return history.entries().filter { $0.url.absoluteString == address }.map {
                ["id": $0.key, "visitId": "1", "visitTime": chromeTime($0.last), "referringVisitId": "0", "transition": "link"]
                    as [String: Any]
            }
        case "addUrl":
            if let url = URL(string: address) { history.record(url, title: "") }
        case "deleteUrl":
            history.entries().filter { $0.url.absoluteString == address }.forEach { history.remove($0.key) }
        case "deleteRange":
            let start = date(call.option("startTime") ?? 0), end = date(call.option("endTime") ?? 0)
            history.entries().filter { $0.last >= start && $0.last <= end }.forEach { history.remove($0.key) }
        case "deleteAll":
            history.clear()
        default:
            throw unavailable(call)
        }
        return nil
    }

    static func topSites(_ call: ChromeCall) async throws -> Any? {
        var visits: [String: (url: URL, title: String, count: Int)] = [:]
        for visit in call.browser.history.entries() {
            guard let host = visit.url.host() else { continue }
            visits[host, default: (visit.url, visit.title, 0)].count += 1
        }
        return visits.values.sorted { $0.count > $1.count }.prefix(10).map { ["url": $0.url.absoluteString, "title": $0.title] }
    }

    // MARK: - downloads

    /// A download's id is its place in the list, from 1.
    static func downloads(_ call: ChromeCall) async throws -> Any? {
        let browser = call.browser
        let kept = browser.downloads.kept
        switch call.method {
        case "download":
            guard let url = (call.option("url") as String?).flatMap(URL.init(string:)) else { throw Refusal("No url to download") }
            guard let page = browser.active?.built ?? browser.tabs.lazy.compactMap(\.built).first else {
                throw Refusal("No page to download through")
            }
            // Only the name, never a path.
            if let name: String = call.option("filename"), !name.isEmpty {
                browser.namedDownloads[url] = (name as NSString).lastPathComponent
            }
            browser.keep(await page.startDownload(using: URLRequest(url: url)))
            return browser.downloads.kept.count + 1
        case "search":
            return kept.enumerated().map { index, download in
                [
                    "id": index + 1, "url": download.url.absoluteString, "finalUrl": download.url.absoluteString, "filename": download.path,
                    "state": "complete", "exists": download.stillThere, "startTime": ISO8601DateFormatter().string(from: download.date),
                    "mime": "",
                ] as [String: Any]
            }
        case "open", "show":
            guard let number = call.first as? Int, kept.indices.contains(number - 1) else { return nil }
            let download = kept[number - 1]
            if call.method == "open" { browser.downloads.open(download) } else { browser.downloads.reveal(download) }
            return nil
        case "showDefaultFolder":
            NSWorkspace.shared.open(browser.prefs.downloads)
            return nil
        case "erase":
            return []
        case "pause", "resume", "cancel", "removeFile", "getFileIcon":
            throw Refusal("\(call.api) isn't available in Mote yet")
        default:
            throw unavailable(call)
        }
    }

    // MARK: - sessions

    static func sessions(_ call: ChromeCall) async throws -> Any? {
        let browser = call.browser
        let now = Int(Date().timeIntervalSince1970)
        switch call.method {
        case "getRecentlyClosed":
            return browser.ghosts.reversed().prefix(call.option("maxResults") ?? 25).map { closed in
                [
                    "lastModified": now,
                    "tab": [
                        "sessionId": closed.id.uuidString, "url": closed.url.absoluteString, "title": closed.title, "index": closed.index,
                        "windowId": 1, "active": false, "pinned": false, "highlighted": false, "incognito": false, "selected": false,
                        "discarded": false, "autoDiscardable": true, "groupId": -1,
                    ],
                ] as [String: Any]
            }
        case "getDevices":
            return []
        case "restore":
            let chosen = (call.first as? String).flatMap { id in browser.ghosts.first { $0.id.uuidString == id } } ?? browser.ghosts.last
            guard let closed = chosen else { throw Refusal("Nothing to restore") }
            browser.reopen(closed)
            return [
                "lastModified": now,
                "tab": ["url": closed.url.absoluteString, "title": closed.title, "index": closed.index, "windowId": 1],
            ]
        default:
            throw unavailable(call)
        }
    }

    /// Mote has no reading list.
    static func readingList(_ call: ChromeCall) async throws -> Any? {
        guard call.method == "query" else { throw Refusal("Mote has no reading list") }
        return []
    }

    // MARK: - browsingData

    private static let websiteData: [String: [String]] = [
        "cache": [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache],
        "cacheStorage": [WKWebsiteDataTypeFetchCache], "appcache": [WKWebsiteDataTypeOfflineWebApplicationCache],
        "cookies": [WKWebsiteDataTypeCookies], "localStorage": [WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage],
        "indexedDB": [WKWebsiteDataTypeIndexedDBDatabases], "serviceWorkers": [WKWebsiteDataTypeServiceWorkerRegistrations],
        "webSQL": [WKWebsiteDataTypeWebSQLDatabases], "fileSystems": [WKWebsiteDataTypeFileSystem],
    ]

    static func browsingData(_ call: ChromeCall) async throws -> Any? {
        if call.method == "settings" {
            let permitted = [
                "cache", "cookies", "history", "downloads", "localStorage", "indexedDB", "serviceWorkers", "cacheStorage", "fileSystems",
                "webSQL",
            ]
            return [
                "options": ["since": 0], "dataToRemove": [:],
                "dataRemovalPermitted": Dictionary(uniqueKeysWithValues: permitted.map { ($0, true) }),
            ]
        }
        let what: [String: Bool]
        if call.method == "remove" {
            what = (call.arg(1) as? [String: Any] ?? [:]).compactMapValues { $0 as? Bool }
        } else if let kind = ChromeAPIRules.dataKind(of: call.api) {
            what = [kind: true]
        } else {
            throw unavailable(call)
        }
        try await clear(what, options: call.options, browser: call.browser)
        return nil
    }

    /// WebKit's website data, and history when asked and no origins are named.
    private static func clear(_ what: [String: Bool], options: [String: Any], browser: Browser) async throws {
        let since = date(options["since"] as? Double ?? 0)
        let origins = (options["origins"] as? [String])?.compactMap { URL(string: $0)?.host() }
        let types = Set(what.filter(\.value).flatMap { websiteData[$0.key] ?? [] })
        let store = Storage.websites
        if !types.isEmpty {
            if let origins {
                let records = await store.dataRecords(ofTypes: types).filter { record in
                    origins.contains { $0 == record.displayName || $0.hasSuffix("." + record.displayName) }
                }
                await store.removeData(ofTypes: types, for: records)
            } else {
                await store.removeData(ofTypes: types, modifiedSince: since)
            }
        }
        if what["history"] == true, origins == nil {
            browser.history.entries().filter { $0.last >= since }.forEach { browser.history.remove($0.key) }
        }
    }
}
