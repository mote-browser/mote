import Foundation

/// A suggestion under the address field.
public struct Suggestion: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable {
        /// An open tab.
        case open
        /// A history entry.
        case visited
        /// A built-in popular site.
        case known
        /// A search query.
        case search
    }

    /// Normalized address without scheme or "www.".
    public let key: String
    public let title: String
    public let url: URL
    public let kind: Kind
    /// The tab already showing this page, if any.
    public var tab: UUID?

    public var id: String { key }

    public init(key: String, title: String, url: URL, kind: Kind, tab: UUID? = nil) {
        self.key = key
        self.title = title
        self.url = url
        self.kind = kind
        self.tab = tab
    }
}

/// Where someone has been, ranked for the address field.
///
/// A value type with no I/O: persistence belongs to the caller, which stores
/// `visits` and restores them with `init(visits:)`.
public struct HistoryIndex: Sendable {
    public struct Visit: Codable, Equatable, Sendable {
        public var url: String
        public var key: String
        public var title: String
        public var count: Int
        public var last: Date

        public init(url: String, key: String, title: String, count: Int, last: Date) {
            self.url = url
            self.key = key
            self.title = title
            self.count = count
            self.last = last
        }
    }

    /// A history entry as the History panel shows it.
    public struct Entry: Identifiable, Equatable, Sendable {
        public let key: String
        public let title: String
        public let url: URL
        public let last: Date
        public let count: Int

        public var id: String { key }
    }

    public private(set) var visitsByKey: [String: Visit] = [:]

    /// Entries kept when saving, by frecency.
    public static let capacity = 2_000

    public init() {}

    /// Restores saved visits. Keys are recomputed, and entries whose keys now
    /// collide are merged.
    public init(visits: [Visit]) {
        visitsByKey = Dictionary(
            visits.map { saved in
                var visit = saved
                if let url = URL(string: visit.url) { visit.key = HistoryIndex.key(for: url) }
                return (visit.key, visit)
            },
            uniquingKeysWith: { first, second in
                var kept = first.last >= second.last ? first : second
                kept.count = first.count + second.count
                return kept
            })
    }

    public var isEmpty: Bool { visitsByKey.isEmpty }

    /// The address as history stores it: the display address, lowercased,
    /// plus the query, which can identify distinct pages and stays
    /// case-sensitive.
    public static func key(for url: URL) -> String {
        let address = Address.displayString(for: url).lowercased()
        guard let query = url.query(percentEncoded: true) else { return address }
        return address + "?" + query
    }

    // MARK: - Writing

    public mutating func record(_ url: URL, title: String, at date: Date = Date()) {
        guard isRecordable(url) else { return }
        let key = HistoryIndex.key(for: url)
        guard !key.isEmpty else { return }

        // A visit to a deep page also counts as a visit to the site root, so
        // typing a domain prefix suggests the front page rather than a subpage.
        if let host = url.host(), key.contains("/") {
            let root = (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host).lowercased()
            var home =
                visitsByKey[root]
                ?? Visit(url: "https://" + root + "/", key: root, title: "", count: 0, last: date)
            home.count += 1
            home.last = date
            visitsByKey[root] = home
        }

        if var seen = visitsByKey[key] {
            seen.count += 1
            seen.last = date
            seen.url = url.absoluteString
            if !title.isEmpty { seen.title = title }
            visitsByKey[key] = seen
        } else {
            visitsByKey[key] = Visit(url: url.absoluteString, key: key, title: title, count: 1, last: date)
        }
    }

    /// Merges an entry imported from another browser, keeping its visit count.
    public mutating func merge(_ url: URL, title: String, count: Int, last: Date) {
        guard isRecordable(url) else { return }
        let key = HistoryIndex.key(for: url)
        guard !key.isEmpty else { return }
        if var seen = visitsByKey[key] {
            seen.count += count
            if last > seen.last { seen.last = last }
            if seen.title.isEmpty { seen.title = title }
            visitsByKey[key] = seen
        } else {
            visitsByKey[key] = Visit(url: url.absoluteString, key: key, title: title, count: count, last: last)
        }
    }

    /// Sets a page's title, which usually arrives after the visit is recorded.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func retitle(_ url: URL, _ title: String) -> Bool {
        let key = HistoryIndex.key(for: url)
        guard !title.isEmpty, var seen = visitsByKey[key], seen.title != title else { return false }
        seen.title = title
        visitsByKey[key] = seen
        return true
    }

    public mutating func remove(_ key: String) {
        visitsByKey[key] = nil
    }

    public mutating func removeAll() {
        visitsByKey = [:]
    }

    private func isRecordable(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }

    // MARK: - Reading

    /// Entries whose address or title contains `text`, newest first.
    public func entries(matching text: String = "") -> [Entry] {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        return visitsByKey.values
            // Untitled site roots added by `record` would duplicate every row.
            .filter { !($0.title.isEmpty && !$0.key.contains("/")) }
            .filter { needle.isEmpty || $0.key.contains(needle) || $0.title.lowercased().contains(needle) }
            .sorted { $0.last > $1.last }
            .compactMap { visit in
                URL(string: visit.url).map {
                    Entry(key: visit.key, title: visit.title, url: $0, last: visit.last, count: visit.count)
                }
            }
    }

    /// The visits worth keeping on disk: the `capacity` with the highest frecency.
    public func visitsToSave(now: Date = Date()) -> [Visit] {
        Array(visitsByKey.values.sorted { frecency($0, now: now) > frecency($1, now: now) }.prefix(Self.capacity))
    }

    // MARK: - Suggestions

    /// Ranked suggestions for what was typed. Visited entries always outrank
    /// built-in sites and are ordered by match position and frecency.
    public func suggestions(for typed: String, limit: Int = 5, now: Date = Date()) -> [Suggestion] {
        let needle = HistoryIndex.normalized(typed)
        guard !needle.isEmpty else { return [] }

        var scored: [(suggestion: Suggestion, score: Double)] = []
        for visit in visitsByKey.values {
            guard let rank = HistoryIndex.rank(visit.key, against: needle), let url = URL(string: visit.url) else {
                continue
            }
            // Bare domains are preferred over deeper pages.
            let score = rank + 4 + frecency(visit, now: now) + (visit.key.contains("/") ? 0 : 1.5)
            scored.append((Suggestion(key: visit.key, title: visit.title, url: url, kind: .visited), score))
        }

        for site in HistoryIndex.knownSites where visitsByKey[site.address] == nil {
            guard let rank = HistoryIndex.rank(site.address, against: needle),
                let url = URL(string: "https://" + site.address)
            else { continue }
            scored.append((Suggestion(key: site.address, title: site.title, url: url, kind: .known), rank))
        }

        return
            scored
            .sorted { $0.score == $1.score ? $0.suggestion.key.count < $1.suggestion.key.count : $0.score > $1.score }
            .prefix(limit)
            .map(\.suggestion)
    }

    /// The text that would complete `typed` inline, from the first option whose
    /// key extends it.
    public static func completion(for typed: String, among options: [Suggestion]) -> String? {
        let lower = typed.lowercased()
        guard lower.count >= 2, let hit = options.first(where: { $0.key.hasPrefix(lower) }) else { return nil }
        let rest = String(hit.key.dropFirst(lower.count))
        return rest.isEmpty ? nil : rest
    }

    /// Match score by position: key prefix, then the label after the first
    /// dot, then anywhere in the host. Paths are not matched.
    static func rank(_ key: String, against needle: String) -> Double? {
        if key.hasPrefix(needle) { return 6 }
        let host = key[..<(key.firstIndex(of: "/") ?? key.endIndex)]
        if let dot = host.firstIndex(of: "."), host[host.index(after: dot)...].hasPrefix(needle) { return 3 }
        // Substring matches need two characters to avoid noise.
        if needle.count >= 2, host.contains(needle) { return 2 }
        return nil
    }

    /// Visit count with exponential decay, time constant 30 days.
    func frecency(_ visit: Visit, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(visit.last) / 86_400)
        return Double(visit.count) * exp(-days / 30)
    }

    static func normalized(_ typed: String) -> String {
        var text = typed.trimmingCharacters(in: .whitespaces).lowercased()
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text = String(text.dropFirst(scheme.count))
        }
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        return text
    }

    /// Popular sites suggested before they appear in history.
    static let knownSites: [(address: String, title: String)] = [
        ("google.com", "Google"), ("mail.google.com", "Gmail"),
        ("drive.google.com", "Google Drive"), ("calendar.google.com", "Google Calendar"),
        ("maps.google.com", "Google Maps"), ("youtube.com", "YouTube"),
        ("github.com", "GitHub"), ("figma.com", "Figma"), ("vercel.com", "Vercel"),
        ("notion.so", "Notion"), ("linear.app", "Linear"), ("slack.com", "Slack"),
        ("discord.com", "Discord"), ("x.com", "X"), ("linkedin.com", "LinkedIn"),
        ("instagram.com", "Instagram"), ("reddit.com", "Reddit"),
        ("news.ycombinator.com", "Hacker News"), ("stackoverflow.com", "Stack Overflow"),
        ("claude.ai", "Claude"), ("chatgpt.com", "ChatGPT"),
        ("dribbble.com", "Dribbble"), ("behance.net", "Behance"),
        ("awwwards.com", "Awwwards"), ("mobbin.com", "Mobbin"),
        ("siteinspire.com", "SiteInspire"), ("are.na", "Are.na"),
        ("pinterest.com", "Pinterest"), ("framer.com", "Framer"),
        ("webflow.com", "Webflow"), ("developer.apple.com", "Apple Developer"),
        ("swift.org", "Swift"), ("npmjs.com", "npm"), ("supabase.com", "Supabase"),
        ("stripe.com", "Stripe"), ("shopify.com", "Shopify"),
        ("cloudflare.com", "Cloudflare"), ("netlify.com", "Netlify"),
        ("apple.com", "Apple"), ("spotify.com", "Spotify"), ("netflix.com", "Netflix"),
        ("wikipedia.org", "Wikipedia"), ("deepl.com", "DeepL"), ("loom.com", "Loom"),
        ("amazon.com", "Amazon"),
    ]
}
