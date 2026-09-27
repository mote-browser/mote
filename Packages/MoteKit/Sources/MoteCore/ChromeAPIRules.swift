import Foundation

/// Mote's bookmarks as chrome.bookmarks sees them: a root "0" holding one
/// bar, "1", holding everything.
public enum ChromeBookmarks {
    public static let root = "0"
    public static let bar = "1"

    /// A bookmark where it sits: its parent's id and its place there.
    public struct Place: Sendable {
        public var node: Bookmark
        public var parent: String
        public var index: Int

        public init(node: Bookmark, parent: String, index: Int) {
            self.node = node
            self.parent = parent
            self.index = index
        }
    }

    /// Every bookmark and folder, depth first.
    public static func all(_ nodes: [Bookmark], in parent: String = bar) -> [Place] {
        nodes.enumerated().flatMap { index, node in
            [Place(node: node, parent: parent, index: index)] + all(node.children ?? [], in: node.id.uuidString)
        }
    }

    public static func find(_ id: String, in roots: [Bookmark]) -> Place? {
        all(roots).first { $0.node.id.uuidString == id }
    }

    /// A BookmarkTreeNode; `deep` includes a folder's children.
    public static func node(_ place: Place, deep: Bool) -> [String: Any] {
        node(place.node, parent: place.parent, index: place.index, deep: deep)
    }

    static func node(_ node: Bookmark, parent: String, index: Int, deep: Bool) -> [String: Any] {
        var out: [String: Any] = [
            "id": node.id.uuidString, "parentId": parent, "index": index, "title": node.title, "dateAdded": 0, "syncing": false,
        ]
        if let url = node.url { out["url"] = url }
        if node.isFolder {
            out["dateGroupModified"] = 0
            if deep { out["children"] = children(node.children ?? [], of: node.id.uuidString) }
        }
        return out
    }

    private static func children(_ nodes: [Bookmark], of parent: String) -> [[String: Any]] {
        nodes.enumerated().map { node($1, parent: parent, index: $0, deep: true) }
    }

    public static func bar(_ roots: [Bookmark], deep: Bool = true) -> [String: Any] {
        var out: [String: Any] = [
            "id": bar, "parentId": root, "index": 0, "title": "Bookmarks", "dateAdded": 0, "folderType": "bookmarks-bar", "syncing": false,
        ]
        if deep { out["children"] = children(roots, of: bar) }
        return out
    }

    public static func tree(_ roots: [Bookmark]) -> [String: Any] {
        ["id": root, "title": "", "dateAdded": 0, "syncing": false, "children": [bar(roots)]]
    }

    /// bookmarks.search: every word of `query` in the title or address, and
    /// the exact `url` and `title` when given.
    public static func search(_ roots: [Bookmark], query: String, url: String? = nil, title: String? = nil) -> [Place] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return all(roots).filter { place in
            let node = place.node
            if let url, node.url != url { return false }
            if let title, node.title != title { return false }
            let text = (node.title + " " + (node.url ?? "")).lowercased()
            return words.allSatisfy(text.contains)
        }
    }

    /// bookmarks.getRecent: the last `count` bookmarks added, newest first.
    public static func recent(_ roots: [Bookmark], count: Int) -> [Place] {
        all(roots).filter { !$0.node.isFolder }.suffix(count).reversed()
    }
}

/// What extensions may do through Mote's own answers.
public enum ChromeAPIRules {
    /// API families with the person's data, and the manifest permission each
    /// needs. WebKit has no permission for these, so the manifest decides.
    public static let gates: [String: String] = [
        "bookmarks": "bookmarks", "history": "history", "downloads": "downloads", "sessions": "sessions", "topSites": "topSites",
        "browsingData": "browsingData", "readingList": "readingList", "userScripts": "userScripts", "identity": "identity",
    ]

    /// The permission an API call needs, if any.
    public static func gate(for api: String) -> String? {
        gates[String(api.prefix { $0 != "." })]
    }

    /// A setting call ("setting.get:privacy.services.x") needs the
    /// permission its first name part names ("privacy"), as in Chrome.
    public static func settingFamily(of api: String) -> String? {
        guard let name = api.split(separator: ":", maxSplits: 1).dropFirst().first else { return nil }
        let family = String(name.prefix { $0 != "." })
        return family.isEmpty ? nil : family
    }

    /// Permissions Chrome gives without asking.
    public static let silent: Set<String> = [
        "tabGroups", "sidePanel", "offscreen", "idle", "power", "fontSettings", "search", "system.cpu", "system.memory", "system.display",
        "favicon",
    ]

    /// permissions.request: only what the manifest names may be asked for.
    public static func mayRequest(_ wanted: [String], manifest: [String: Any]) -> Bool {
        let named = ((manifest["permissions"] as? [Any] ?? []) + (manifest["optional_permissions"] as? [Any] ?? [])).compactMap {
            $0 as? String
        }
        return Set(wanted).isSubset(of: Set(named))
    }

    /// Whether to ask the person, and how to name what's asked for.
    public static func request(_ wanted: [String]) -> (ask: Bool, names: String) {
        (!wanted.allSatisfy(silent.contains), wanted.map { $0.replacingOccurrences(of: ".", with: " ") }.joined(separator: ", "))
    }

    /// action.setPopup: for one tab, or for all of them, which forgets each
    /// tab's own.
    public static func settingPopup(_ path: String, tab: String?, in popups: [String: String]) -> [String: String] {
        guard let tab else { return ["*": path] }
        var popups = popups
        popups[tab] = path
        return popups
    }

    /// A chrome.privacy or chrome.proxy value nobody set.
    public static func defaultSetting(_ name: String, savesPasswords: Bool) -> Any {
        switch name {
        case "privacy.services.passwordSavingEnabled": return savesPasswords
        case "privacy.network.webRTCIPHandlingPolicy": return "default"
        case "privacy.websites.doNotTrackEnabled", "privacy.websites.adMeasurementEnabled", "privacy.websites.fledgeEnabled",
            "privacy.websites.topicsEnabled", "privacy.services.safeBrowsingExtendedReportingEnabled":
            return false
        case "proxy.settings": return ["mode": "system"]
        default: return true
        }
    }

    /// browsingData.removeCookies → "cookies".
    public static func dataKind(of api: String) -> String? {
        let prefix = "browsingData.remove"
        guard api.hasPrefix(prefix), api.count > prefix.count else { return nil }
        let kind = api.dropFirst(prefix.count)
        return kind.prefix(1).lowercased() + kind.dropFirst()
    }

    /// Chrome's speech rate is a multiplier around 1; AVFoundation's sits
    /// between a minimum and maximum around its own default.
    public static func speechRate(_ chrome: Double, standard: Float, lowest: Float, highest: Float) -> Float {
        min(max(Float(chrome) * standard, lowest), highest)
    }

    /// runtime.getContexts: which of the extension's pages a filter keeps.
    public static func keeps(type: String, address: String, filter: [String: Any]) -> Bool {
        let types = filter["contextTypes"] as? [String]
        let addresses = filter["documentUrls"] as? [String]
        return (types?.contains(type) ?? true) && (addresses?.contains(address) ?? true)
    }

    /// A user script's includeGlobs or excludeGlobs: none when missing, nil
    /// (refused, as Chrome does) when not a list of strings.
    public static func globs(_ value: Any?) -> [String]? {
        switch value {
        case nil, is NSNull: return []
        case let strings as [String]: return strings
        default: return nil
        }
    }
}
