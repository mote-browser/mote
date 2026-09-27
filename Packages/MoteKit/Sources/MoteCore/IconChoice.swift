import Foundation

/// Choosing a site's icon from those its page declares.
public enum IconChoice {
    /// An icon a page declares with `<link rel="icon">` and the like.
    public struct Declared: Equatable, Sendable {
        public var href: String
        public var rel: String
        public var sizes: String
        public var type: String
        public var media: String

        public init(href: String, rel: String = "", sizes: String = "", type: String = "", media: String = "") {
            self.href = href
            self.rel = rel
            self.sizes = sizes
            self.type = type
            self.media = media
        }

        /// From the page script's answer: lowercased strings by name.
        public init?(_ fields: [String: String]) {
            guard let href = fields["href"] else { return nil }
            self.init(
                href: href, rel: fields["rel"] ?? "", sizes: fields["sizes"] ?? "", type: fields["type"] ?? "", media: fields["media"] ?? ""
            )
        }
    }

    /// The appearance an icon is meant for.
    public enum Scheme: Sendable { case any, light, dark }

    /// What a `media` attribute asks for.
    public static func scheme(_ media: String) -> Scheme {
        let media = media.lowercased()
        guard media.contains("prefers-color-scheme") else { return .any }
        return media.contains("dark") ? .dark : media.contains("light") ? .light : .any
    }

    /// Whether the page has an icon for dark mode.
    public static func offersDark(_ icons: [Declared]) -> Bool {
        icons.contains { scheme($0.media) == .dark }
    }

    /// Where to try downloading from, best first: icons for this appearance,
    /// then 32–64 px ones, scalable ones, touch icons, the rest, and last the
    /// site's /favicon.ico. Icons for the other appearance are left out.
    public static func candidates(_ icons: [Declared], page: URL, dark: Bool) -> [URL] {
        let ranked = icons.compactMap { icon -> (URL, Int)? in
            guard let url = URL(string: icon.href), url.scheme?.hasPrefix("http") == true else { return nil }
            let fit = scheme(icon.media)
            if fit == (dark ? .light : .dark) { return nil }
            return (url, score(icon, url: url) + (fit == .any ? 0 : 40))
        }
        var urls = ranked.sorted { $0.1 > $1.1 }.map(\.0)
        if let host = page.host(), let fallback = URL(string: "\(page.scheme ?? "https")://\(host)/favicon.ico") { urls.append(fallback) }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func score(_ icon: Declared, url: URL) -> Int {
        if icon.sizes == "any" || icon.type.contains("svg") || url.pathExtension.lowercased() == "svg" { return 35 }
        let largest = icon.sizes.split(separator: " ").compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }.max()
        switch largest {
        case nil: return icon.rel.contains("apple-touch") ? 40 : 25
        case let px? where px < 24: return 10
        case let px? where px < 48: return 45
        case let px? where px < 128: return 50
        case let px? where px < 260: return 42
        default: return 20
        }
    }
}
