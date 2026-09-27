import CoreGraphics
import Foundation

/// How a tab is named in the row.
public enum TabLabel {
    /// The name someone gave the tab; a pop-up's site (its opener controls its
    /// title); the page title; the address until a title arrives; or "New Tab".
    public static func text(name: String?, popup: Bool, address: URL?, title: String) -> String {
        if let name, !name.isEmpty { return name }
        if popup, let site = Address.siteHost(of: address), !site.isEmpty { return site }
        if !title.isEmpty { return title }
        if let address { return Address.displayString(for: address) }
        return "New Tab"
    }

    /// The site's first letter, for pinned tabs and pages without an icon.
    public static func monogram(for address: URL?) -> String {
        Address.siteHost(of: address)?.first.map { String($0).uppercased() } ?? "•"
    }
}

/// Page zoom: the page is laid out again at the new scale, so text stays sharp.
public enum PageZoom {
    public static let range: ClosedRange<CGFloat> = 0.4...3

    public static func clamped(_ value: CGFloat) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// Whether two zoom levels are far enough apart to be worth a relayout.
    public static func differs(_ one: CGFloat, _ other: CGFloat) -> Bool {
        abs(one - other) > 0.004
    }

    /// Close enough to 100% that nothing needs remembering.
    public static func isActualSize(_ value: CGFloat) -> Bool {
        abs(value - 1) < 0.01
    }
}

/// How far down a page is scrolled, from 0 to 1, in hundredths. Pages report
/// every frame while scrolling; rounding keeps the tab's reading bar from
/// redrawing on each one.
public func readingFraction(y: Double, of ceiling: Double) -> Double {
    guard ceiling > 0 else { return 0 }
    return (min(1, max(0, y / ceiling)) * 100).rounded() / 100
}

/// The "Version/… Safari/605.1.15" at the end of the user agent.
public enum SafariVersion {
    /// The Safari that ships with a macOS release, the oldest the system
    /// WebKit can be; for when Safari's own bundle can't be read.
    /// Under-reporting is safer than claiming features the engine lacks.
    /// Since macOS 26 Safari's major version matches the system's; before, it
    /// ran three ahead.
    public static func shipped(withMacOS major: Int) -> String {
        major >= 26 ? "\(major).0" : "\(major + 3).0"
    }

    public static func userAgentName(version: String) -> String {
        "Version/\(version) Safari/605.1.15"
    }
}

/// A sign-in the page just sent, held until it is known to have worked: a
/// page that settles without a password field took it, one that still shows
/// the field turned it down.
public struct SentSignIn: Equatable, Sendable {
    /// Taken from the sign-in page itself, before any redirect.
    public let host: String
    public let user: String
    public let password: String
    /// The page was plain HTTP.
    public let clear: Bool
    public let at: Date

    /// After this long the sign-in is no longer worth offering to save.
    public static let lifetime: TimeInterval = 45

    public init?(page: URL?, user: String, password: String, at: Date) {
        guard let host = Address.siteHost(of: page) else { return nil }
        self.host = host
        self.user = user
        self.password = password
        self.clear = page?.scheme?.lowercased() == "http"
        self.at = at
    }

    public func expired(at now: Date) -> Bool {
        now.timeIntervalSince(at) >= Self.lifetime
    }
}

/// Where the hovered link's address shows, along the page's bottom edge.
public enum LinkBubblePlace {
    /// It's never wider than this.
    public static func width(page: CGFloat) -> CGFloat { min(page * 0.6, 640) }

    /// Bottom left, unless the pointer is there: then bottom right, out of
    /// its way. `fromBottom` counts up from the page's bottom edge.
    public static func onRight(pointerX x: CGFloat, fromBottom: CGFloat, page: CGFloat) -> Bool {
        fromBottom < 50 && x < width(page: page) + 22
    }
}

/// Images the image menu may open, copy or download. Any page can post to
/// the menu's handler, so its address is checked here.
public enum ImageAddress {
    public static func usable(_ text: String) -> URL? {
        guard let url = URL(string: text), ["http", "https", "data", "blob"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}
