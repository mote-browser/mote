import Foundation

/// A web page a reply drew on: one the provider searched up or read, or one
/// the reply links to.
public struct Source: Identifiable, Hashable, Codable, Sendable {
    public var url: URL
    public var title: String
    /// A few words from the page, when the provider gave them.
    public var snippet: String?

    public init(url: URL, title: String, snippet: String? = nil) {
        self.url = url
        self.title = title
        self.snippet = snippet
    }

    /// The same for every spelling of the page's address (see `key(for:)`).
    public var id: String { Source.key(for: url) }

    /// The host, without www.
    public var site: String {
        let host = url.host()?.lowercased() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The site's own name, for a citation chip: "wikipedia" for
    /// en.wikipedia.org, "bbc" for news.bbc.co.uk.
    public var brand: String {
        var labels = site.split(separator: ".").map(String.init)
        guard labels.count > 1 else { return site }
        labels.removeLast()
        // Second-level endings such as co.uk, com.au.
        if labels.count > 1, ["co", "com", "org", "net", "gov", "ac", "edu"].contains(labels.last!) { labels.removeLast() }
        return labels.last ?? site
    }

    /// The title; without one, the page's own name from its address
    /// ("Swift (programming language)"), or else the site.
    public var name: String {
        let title = title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { return title }
        let last = url.lastPathComponent.replacingOccurrences(of: #"\.[a-z0-9]{2,5}$"#, with: "", options: .regularExpression)
        let words = last.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return last.isEmpty || last == "/" || words.count < 3 ? site : words
    }

    /// The page's address reduced to what tells pages apart: no scheme, no
    /// www, no fragment, no tracking parameters, no trailing slash.
    public static func key(for url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = parts.host?.lowercased() else {
            return url.absoluteString
        }
        let items = (parts.queryItems ?? []).filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !["fbclid", "gclid", "ref", "ref_src"].contains(name)
        }
        parts.queryItems = items.isEmpty ? nil : items
        let query = parts.percentEncodedQuery.map { "?" + $0 } ?? ""
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) + path + query
    }
}

/// Finding a reply's citations: the links it makes to web pages, which the
/// chat shows as numbered chips.
public enum Citations {
    /// A source as the chat lists it: with its number when the reply cites it.
    public struct Entry: Equatable, Sendable {
        public var source: Source
        public var number: Int?
    }

    /// The pages the text links to, by `Source.key`, in the order first cited.
    /// Links in code and images don't count.
    public static func order(in text: String) -> [String] {
        links(in: text).map { Source.key(for: $0.url) }.reduce(into: [String]()) { seen, key in
            if !seen.contains(key) { seen.append(key) }
        }
    }

    /// Every source to list for a reply: those cited, numbered in citation
    /// order (pages cited but never reported included), then the rest.
    public static func arrange(_ sources: [Source], for text: String) -> [Entry] {
        var known = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for link in links(in: text) where known[Source.key(for: link.url)] == nil {
            known[Source.key(for: link.url)] = Source(url: link.url, title: link.label)
        }
        let cited = order(in: text)
        let numbered = cited.enumerated().compactMap { index, key in known[key].map { Entry(source: $0, number: index + 1) } }
        let rest = sources.filter { !cited.contains($0.id) }.map { Entry(source: $0, number: nil) }
        return numbered + rest
    }

    /// The reply as the chat shows it: without a closing list of the pages
    /// it cites, which models add though asked not to, and which the list of
    /// sources above the reply already shows.
    public static func shown(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let header = lines.lastIndex(where: { heading(in: $0) != nil }) else { return text }
        let rest = [heading(in: lines[header]) ?? ""] + lines[(header + 1)...]
        let listed = rest.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !listed.isEmpty, listed.allSatisfy(onlyLinks) else { return text }
        return lines[..<header].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let sourcesHeading = try! NSRegularExpression(
        pattern: #"^\s*(?:#{1,6}\s*)?(?:\*\*)?(?:sources?|fuentes?|references?|referencias?)(?:\*\*)?\s*:?\s*(?:\*\*)?\s*:?(.*)$"#,
        options: [.caseInsensitive])

    /// What follows a "Sources:" heading on its line, or nil when the line isn't one.
    private static func heading(in line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = sourcesHeading.firstMatch(in: line, range: range), let rest = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[rest])
    }

    /// A line that starts with a link and says little else: an item of a
    /// list of sources.
    private static func onlyLinks(_ line: String) -> Bool {
        let item = line.replacingOccurrences(of: #"^(?:[-*+]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        guard item.hasPrefix("["), !links(inLine: item).isEmpty else { return false }
        let range = NSRange(item.startIndex..., in: item)
        let words = link.stringByReplacingMatches(in: item, range: range, withTemplate: "")
        return words.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).count <= 40
    }

    /// Markdown links to http(s) pages outside code, images left out.
    static func links(in text: String) -> [(label: String, url: URL)] {
        var found: [(String, URL)] = []
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            found += links(inLine: line)
        }
        return found
    }

    /// An address may hold balanced parentheses, as Wikipedia's do.
    private static let link = try! NSRegularExpression(pattern: #"(!?)\[([^\]]*)\]\((https?://(?:[^\s()]|\([^\s()]*\))+)\)"#)

    private static func links(inLine line: String) -> [(String, URL)] {
        // Code spans are blanked out first, keeping the offsets.
        let plain = line.replacingOccurrences(of: #"`[^`]*`"#, with: "", options: .regularExpression)
        let range = NSRange(plain.startIndex..., in: plain)
        return link.matches(in: plain, range: range).compactMap { match in
            guard let bang = Range(match.range(at: 1), in: plain), plain[bang].isEmpty,
                let label = Range(match.range(at: 2), in: plain), let address = Range(match.range(at: 3), in: plain),
                let url = URL(string: String(plain[address]))
            else { return nil }
            return (String(plain[label]), url)
        }
    }
}
