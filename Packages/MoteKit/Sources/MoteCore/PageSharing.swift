import Foundation

/// Whether a tab's page can be shared with its chat, and when sharing ends.
///
/// A chat about a page is not about a tab: the address picks the page, and the
/// chat outlives it. These are the rules, kept apart from the web view so they
/// can be read and tested without one.
public enum PageSharing {
    /// A page worth sharing: one that leads somewhere on the web or on disk.
    /// A blank tab, `about:blank` and the browser's own `data:`, `blob:` and
    /// extension pages are not pages the model can be told about.
    public static func canShare(_ address: URL?) -> Bool {
        switch address?.scheme?.lowercased() {
        case "http", "https", "file": true
        default: false
        }
    }

    /// Whether two addresses name the same page. The part after `#` is a place
    /// within the page, so moving to another `#fragment` is not another page.
    public static func isSamePage(_ one: URL?, _ other: URL?) -> Bool {
        guard let one, let other else { return false }
        return withoutFragment(one) == withoutFragment(other)
    }

    /// Whether a chat sharing `shared` must stop sharing when its tab moves to
    /// `url`: it must for another page, and must not for a move within the page
    /// it already shares. Nothing shared, nothing to let go.
    public static func detaches(from shared: URL?, movingTo url: URL?) -> Bool {
        guard shared != nil else { return false }
        return !isSamePage(shared, url)
    }

    /// Whether a chat on screen takes up the page at `address` without being
    /// asked: it does when the page can be read and it is not already holding
    /// that same page. A page held but let go (detached) still counts as held,
    /// so merely looking away to another tab and back does not share it again.
    public static func takesUp(_ address: URL?, chatting: Bool, holding: URL?) -> Bool {
        guard chatting, canShare(address) else { return false }
        return !isSamePage(holding, address)
    }

    /// Whether a fresh read of the page at `address` may replace the page a
    /// chat already holds. It may for that held page, unless the page was
    /// taken up with a selection: the person's own ask, which a later,
    /// automatic read must not drop. A page not held at all is never replaced
    /// by a read — only the page on screen is read.
    public static func replaces(_ address: URL?, holding: URL?, selection: Bool) -> Bool {
        guard canShare(address), isSamePage(holding, address) else { return false }
        return !selection
    }

    /// The address without its fragment, so two moves within one page compare equal.
    private static func withoutFragment(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.fragment = nil
        return parts?.string ?? url.absoluteString
    }
}
