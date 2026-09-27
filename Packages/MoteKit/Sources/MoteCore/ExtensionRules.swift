import Foundation

/// One installed extension, as kept in Extensions/installed.json.
public struct InstalledExtension: Codable, Identifiable, Equatable, Sendable {
    /// Its Chrome Web Store id, or "local-…" for one loaded from a folder.
    public let id: String
    public var name: String
    public var version: String
    public var enabled: Bool
    public var fromStore: Bool
    /// What it was allowed at install (see `ExtensionRules.grants`); an
    /// update wanting more asks again.
    public var permissions: [String]
    /// Its button shows in the toolbar. Missing in older files.
    public var pinned: Bool?
    /// The folder an unpacked extension came from, copied again on reload.
    public var source: String?

    public init(
        id: String, name: String, version: String, enabled: Bool = true, fromStore: Bool, permissions: [String], pinned: Bool? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.enabled = enabled
        self.fromStore = fromStore
        self.permissions = permissions
        self.pinned = pinned
        self.source = source
    }

    /// A folder extension's id: "local-" and eight lowercase hex digits.
    public static func localID(from uuid: UUID = UUID()) -> String {
        "local-" + uuid.uuidString.prefix(8).lowercased()
    }
}

public enum ExtensionRules {
    // MARK: - Addresses

    /// Extension pages live at chrome-extension://<id>/, as in Chrome: some
    /// sites and servers look for that origin.
    public static let scheme = "chrome-extension"
    /// What they were served from before; saved addresses are moved over.
    public static let formerScheme = "webkit-extension"

    public static func current(_ url: URL) -> URL {
        guard url.scheme == formerScheme, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.scheme = scheme
        return parts.url ?? url
    }

    /// Popups load from a copy of their page with this in its name: WebKit
    /// takes any page at the popup's own path for its popup, and a popup it
    /// doesn't show itself never hears events such as storage.onChanged.
    public static let popupCopy = ".mote-popup"

    /// "popup.html" → "popup.mote-popup.html".
    public static func popupCopyName(of file: String) -> String {
        let name = file as NSString
        let ext = name.pathExtension
        return name.deletingPathExtension + popupCopy + (ext.isEmpty ? "" : "." + ext)
    }

    /// The manifest's own popup, relative to the extension.
    public static func manifestPopup(_ manifest: [String: Any]) -> String? {
        let action = (manifest["action"] ?? manifest["browser_action"]) as? [String: Any]
        guard let path = action?["default_popup"] as? String, !path.isEmpty else { return nil }
        return path
    }

    public enum Popup: Equatable, Sendable {
        case manifest
        case none
        case page(String)
    }

    /// What action.setPopup chose: for this tab, else for every tab ("*"),
    /// else the manifest's. An empty page means no popup.
    public static func popup(overrides: [String: String], tab: String?) -> Popup {
        guard let path = tab.flatMap({ overrides[$0] }) ?? overrides["*"] else { return .manifest }
        return path.isEmpty ? .none : .page(path)
    }

    // MARK: - Permissions

    /// Chrome APIs Mote answers itself, and how to say what each allows.
    public static let nativeAPIs: [(name: String, sentence: String)] = [
        ("userScripts", "Run scripts you add to it on websites"), ("history", "Read and change your history"),
        ("bookmarks", "Read and change your bookmarks"), ("downloads", "Manage your downloads"),
        ("privacy", "Change your privacy settings"), ("browsingData", "Clear your browsing data"),
        ("management", "See your other extensions"), ("notifications", "Show notifications"),
        ("sessions", "See your recently closed tabs"), ("topSites", "See your most visited sites"),
        ("readingList", "Read and change your reading list"),
    ]

    /// WebKit permissions worth a sentence when asking.
    public static let permissionSentences: [(name: String, sentence: String)] = [
        ("tabs", "See your open tabs and their addresses"), ("cookies", "Read and change cookies"),
        ("webNavigation", "See where you go"), ("webRequest", "See the requests pages make"),
        ("declarativeNetRequest", "Block or change requests pages make"), ("clipboardWrite", "Write to the clipboard"),
        ("nativeMessaging", "Talk to apps on this Mac"), ("scripting", "Run scripts in pages"),
    ]

    /// What an extension is allowed, compared at every update: WebKit's
    /// permissions, sites as "site:<pattern>", and APIs Mote answers as
    /// "search:<name>". What Mote's shim added to the manifest doesn't count.
    public static func grants(requested: [String], patterns: [String], declared: [String], added: Set<String>) -> [String] {
        let native = Set(nativeAPIs.map(\.name))
        var out = Set(requested.filter { !added.contains($0) })
        out.formUnion(patterns.map { "site:" + $0 })
        out.formUnion(declared.filter { native.contains($0) && !added.contains($0) }.map { "search:" + $0 })
        return out.sorted()
    }

    /// Whether an update or reload wants more than was allowed.
    public static func wantsMore(_ grants: [String], than allowed: [String]) -> Bool {
        !Set(grants).isSubset(of: Set(allowed))
    }

    /// A site pattern as the install question needs it.
    public struct Site: Sendable {
        public var host: String?
        /// `<all_urls>`, or every host.
        public var everywhere: Bool

        public init(host: String?, everywhere: Bool) {
            self.host = host
            self.everywhere = everywhere
        }
    }

    /// What an extension asks for, in sentences.
    public static func describe(requested: Set<String>, sites: [Site], declared: Set<String>, added: Set<String>) -> [String] {
        var out: [String] = []
        if sites.contains(where: \.everywhere) {
            out.append("Read and change everything on every website")
        } else if !sites.isEmpty {
            let hosts = sites.compactMap(\.host).filter { !$0.isEmpty }
            let more = hosts.count > 4 ? " and \(hosts.count - 4) more" : ""
            out.append("Read and change what's on " + hosts.prefix(4).joined(separator: ", ") + more)
        }
        out += permissionSentences.filter { requested.contains($0.name) && !added.contains($0.name) }.map(\.sentence)
        out += nativeAPIs.filter { declared.contains($0.name) }.map(\.sentence)
        return out
    }

    /// The install question's detail.
    public static func installDetail(_ wants: [String]) -> String {
        wants.isEmpty ? "It doesn't ask for anything special." : "It will be able to:\n• " + wants.joined(separator: "\n• ")
    }

    // MARK: - Updates

    /// Checked at most this often.
    public static let updateInterval: TimeInterval = 20 * 60 * 60

    public static func updateCheckURL(id: String, version: String) -> URL? {
        var parts = URLComponents(string: "https://clients2.google.com/service/update2/crx")
        parts?.queryItems = [
            URLQueryItem(name: "response", value: "updatecheck"), URLQueryItem(name: "prodversion", value: CRX.chromeVersion),
            URLQueryItem(name: "acceptformat", value: "crx3"), URLQueryItem(name: "x", value: "id=\(id)&v=\(version)&uc"),
        ]
        return parts?.url
    }

    /// The version the store offers, when it isn't `current`. Only the
    /// <updatecheck> element counts: the XML declaration has a version too,
    /// and <app> always says status="ok".
    public static func offeredVersion(in response: String, current: String) -> String? {
        guard let range = response.range(of: #"<updatecheck\b[^>]*>"#, options: .regularExpression) else { return nil }
        let check = String(response[range])
        guard check.contains(#"status="ok""#),
            let found = check.range(of: #"\bversion="([^"]+)""#, options: .regularExpression)
        else { return nil }
        let version = String(check[found].dropFirst(#"version=""#.count).dropLast())
        return version == current ? nil : version
    }

    // MARK: - New tab pages

    /// Whose new tab page shows: the latest installed of the enabled ones
    /// that has one.
    public static func newTabOwner(_ installed: [InstalledExtension], pages: [String: URL]) -> (id: String, page: URL)? {
        for item in installed.reversed() where item.enabled {
            if let page = pages[item.id] { return (item.id, page) }
        }
        return nil
    }

    // MARK: - The store and Settings

    /// A Chrome Web Store page, new or old.
    public static func isStorePage(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host == "chromewebstore.google.com" || (host == "chrome.google.com" && url.path.hasPrefix("/webstore"))
    }

    /// The line under an extension's name in Settings.
    public static func detail(_ item: InstalledExtension, running: Bool, showsInNewTabs: Bool, warnings: Int) -> String {
        let folder = item.source.map { "From “\(URL(fileURLWithPath: $0).lastPathComponent)”" } ?? "From a folder"
        var parts = ["Version \(item.version)", item.fromStore ? "Chrome Web Store" : folder]
        if item.enabled, !running { parts.append("couldn't start") }
        if showsInNewTabs { parts.append("shows in new tabs") }
        if warnings > 0 { parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Tabs

    public struct TabChanges<ID: Hashable>: Equatable {
        public var closed: [ID]
        public var opened: [ID]
        /// Tabs that stayed but moved, with where they were among those that stayed.
        public var moved: [(id: ID, from: Int)]

        public static func == (a: Self, b: Self) -> Bool {
            a.closed == b.closed && a.opened == b.opened && a.moved.map(\.id) == b.moved.map(\.id)
                && a.moved.map(\.from) == b.moved.map(\.from)
        }
    }

    /// What to tell WebKit when the tabs go from `old` to `new`.
    public static func tabChanges<ID: Hashable>(from old: [ID], to new: [ID]) -> TabChanges<ID> {
        let now = Set(new), before = Set(old)
        let stayed = old.filter(now.contains)
        let stayedNow = new.filter(before.contains)
        let moved = stayed.enumerated().filter { stayedNow[$0.offset] != $0.element }.map { (id: $0.element, from: $0.offset) }
        return TabChanges(closed: old.filter { !now.contains($0) }, opened: new.filter { !before.contains($0) }, moved: moved)
    }

    // MARK: - Keeping count

    /// The last errors kept for an extension.
    public static let errorsKept = 40

    public static func noting(_ error: String, in errors: [String]) -> [String] {
        Array((errors + [error]).suffix(errorsKept))
    }
}

/// Failures of one kind: past `limit` within `window`, the next failure
/// should wait, so a retry loop can't spin.
public struct FailureThrottle: Sendable {
    public var limit = 12
    public var window: TimeInterval = 1
    private var seen: [String: [Date]] = [:]

    public init() {}

    /// Notes a failure; true when it should wait.
    public mutating func failed(_ key: String, at now: Date = Date()) -> Bool {
        let recent = (seen[key] ?? []).filter { now.timeIntervalSince($0) < window } + [now]
        seen[key] = recent
        return recent.count > limit
    }
}

/// Once per `interval` per key: restarting an extension, say.
public struct Cooldown: Sendable {
    public var interval: TimeInterval
    private var last: [String: Date] = [:]

    public init(_ interval: TimeInterval) { self.interval = interval }

    /// True, and starts the wait, when `key` may go again.
    public mutating func take(_ key: String, at now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(last[key] ?? .distantPast) > interval else { return false }
        last[key] = now
        return true
    }
}
