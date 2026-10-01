import Foundation

/// How safely a page arrived.
public enum Connection: Equatable, Sendable {
    /// Encrypted, and everything on the page came that way too.
    case secure
    /// Encrypted, but some of the page came over plain http.
    case mixed
    /// Encrypted with a certificate this Mac doesn't trust (let through by
    /// the user).
    case untrusted
    /// Plain http.
    case plain

    /// For a page's scheme, whether its certificate checked out (nil while
    /// unknown) and whether all it loaded was secure. nil for pages that
    /// aren't from the web: files, about:blank.
    public static func of(scheme: String?, certified: Bool?, onlySecureContent: Bool?) -> Connection? {
        switch scheme?.lowercased() {
        case "https":
            if certified == false { return .untrusted }
            return onlySecureContent == false ? .mixed : .secure
        case "http":
            return .plain
        default:
            return nil
        }
    }

    public var isSecure: Bool { self == .secure }
}

extension Address {
    /// A page's site for headings: its host without "www.", "File" for files,
    /// or its scheme for pages without a host.
    public static func siteName(for url: URL) -> String {
        if let host = url.host(), !host.isEmpty { return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
        return url.isFileURL ? "File" : url.scheme ?? url.absoluteString
    }
}

extension Address {
    /// What the toolbar shows for a page's address: all of it, or with `whole`
    /// off the site of a web page (its port too, which tells local servers
    /// apart), and for anything else the address without its scheme and `www.`.
    public static func shown(_ url: URL, whole: Bool) -> String {
        guard !whole else { return url.absoluteString }
        return switch url.scheme?.lowercased() {
        case "http", "https": siteWithPort(of: url)
        default: displayString(for: url)
        }
    }

    private static func siteWithPort(of url: URL) -> String {
        let site = siteName(for: url)
        guard let port = url.port else { return site }
        return (site.contains(":") ? "[\(site)]" : site) + ":\(port)"
    }
}
