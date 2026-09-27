import Foundation

/// The search engines the address field can send words to.
public enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case google, duckduckgo, bing, ecosia, startpage, kagi, brave, qwant, custom

    public static let standard = SearchEngine.google

    /// Where the search words go in a URL template.
    static let placeholder = "%s"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .google: "Google"
        case .duckduckgo: "DuckDuckGo"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        case .kagi: "Kagi"
        case .brave: "Brave Search"
        case .qwant: "Qwant"
        case .custom: "Custom"
        }
    }

    /// The URL template, with `%s` where the words go. A custom template that
    /// isn't usable falls back to the standard engine.
    public func template(custom: String) -> String {
        switch self {
        case .google: "https://www.google.com/search?q=%s"
        case .duckduckgo: "https://duckduckgo.com/?q=%s"
        case .bing: "https://www.bing.com/search?q=%s"
        case .ecosia: "https://www.ecosia.org/search?q=%s"
        case .startpage: "https://www.startpage.com/sp/search?query=%s"
        case .kagi: "https://kagi.com/search?q=%s"
        case .brave: "https://search.brave.com/search?q=%s"
        case .qwant: "https://www.qwant.com/?q=%s"
        case .custom:
            SearchEngine.accepts(custom.trimmed) ? custom.trimmed : SearchEngine.standard.template(custom: "")
        }
    }

    /// The name shown in the field: the engine's title, or a custom
    /// template's host without `www.`.
    public func name(custom: String) -> String {
        guard self == .custom else { return title }
        guard let host = SearchEngine.host(of: custom) else { return SearchEngine.standard.title }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Whether `template` is an http(s) URL with `%s` outside its host.
    public static func accepts(_ template: String) -> Bool {
        host(of: template) != nil
    }

    public static func url(for text: String, template: String) -> URL? {
        let words = text.trimmed
        let marker = "MOTESEARCHWORDS"
        guard !words.isEmpty,
            let escaped = words.addingPercentEncoding(withAllowedCharacters: unreserved),
            let base = URL(string: template.replacingOccurrences(of: placeholder, with: marker))?.absoluteString
        else { return nil }
        return URL(string: base.replacingOccurrences(of: marker, with: escaped), encodingInvalidCharacters: false)
    }

    /// RFC 3986 unreserved characters: everything else in the words is escaped.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// The template's host, if it has one that doesn't depend on the words.
    private static func host(of template: String) -> String? {
        let trimmed = template.trimmed
        guard trimmed.contains(placeholder),
            let first = URLComponents(string: trimmed.replacingOccurrences(of: placeholder, with: "a")),
            let second = URLComponents(string: trimmed.replacingOccurrences(of: placeholder, with: "b")),
            let scheme = first.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = first.host, !host.isEmpty, host == second.host
        else { return nil }
        return host.lowercased()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
