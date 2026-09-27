import Foundation

/// Turns what someone typed into the address field into a URL, or nothing.
///
/// Text that doesn't look like a place is never guessed into one; the caller
/// decides whether it becomes a search instead.
public enum Address {
    /// Schemes a tab can show. Anything else typed with a scheme (`mailto:`,
    /// an app link) belongs to another app and is refused here.
    private static let supportedSchemes: Set<String> = ["http", "https", "file", "about", "data"]

    public static func url(from typed: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        if let separator = text.range(of: "://") {
            let scheme = text[..<separator.lowerBound].lowercased()
            guard supportedSchemes.contains(scheme) else { return nil }
            return URL(string: text)
        }
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("about:") || lowercased.hasPrefix("data:") {
            return URL(string: text)
        }

        let authority = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !authority.contains("@") else { return nil }
        let host = authority.split(separator: ":").first.map(String.init) ?? String(authority)
        guard isPlausibleHost(host) else { return nil }

        // Local servers rarely have a certificate, so https would just fail.
        return URL(string: (isLocal(host) ? "http://" : "https://") + text)
    }

    /// The address as a tab shows it before the page has a title: no scheme,
    /// no `www.`, no trailing slash.
    /// The host a site's settings are kept under: lowercased, without "www.".
    public static func siteHost(of url: URL?) -> String? {
        guard let host = url?.host()?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func displayString(for url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path()
        return path.isEmpty || path == "/" ? bareHost : bareHost + path
    }

    static func isLocal(_ host: String) -> Bool {
        host == "localhost"
            || host.hasSuffix(".localhost")
            || host == "127.0.0.1"
            || host == "0.0.0.0"
            || host.hasPrefix("192.168.")
            || host.hasPrefix("10.")
    }

    static func isPlausibleHost(_ host: String) -> Bool {
        if host == "localhost" { return true }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count == 4, labels.allSatisfy({ UInt8($0) != nil }) { return true }

        guard labels.count >= 2 else { return false }
        let validLabels = labels.allSatisfy { label in
            !label.isEmpty
                && !label.hasPrefix("-")
                && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
        guard validLabels else { return false }

        // A dotted name ending in letters is a domain; ending in digits it's a
        // version number ("1.2.3").
        let topLevel = labels[labels.count - 1]
        return topLevel.count >= 2 && topLevel.allSatisfy(\.isLetter)
    }
}
