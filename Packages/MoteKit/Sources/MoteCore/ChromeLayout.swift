import CoreGraphics

/// Where the window's parts go: the page sits on a rounded card inset from the
/// window's edges, with the tabs (a sidebar or a strip) on the window's own
/// ground around it, as in Arc and Dia. The card carries the toolbar and the
/// bookmarks bar above the page.
///
/// Every frame is in window points measured from the top-left corner.
public struct ChromeLayout: Equatable, Sendable {
    public enum Tabs: Sendable {
        case sidebar, strip
    }

    /// Space between the card and the window's edges.
    public static let gap: CGFloat = 8
    /// Corner radius of the card.
    public static let corner: CGFloat = 10
    /// Height of the toolbar at the top of the card. With the card `gap` below
    /// the window's top, its middle lines up with the traffic lights (see
    /// `lights`).
    public static let toolbar: CGFloat = 36
    /// Height of the tab strip above the card.
    public static let strip: CGFloat = 40
    /// Height of the bookmarks bar under the toolbar.
    public static let bookmarks: CGFloat = 30

    /// The card: toolbar, bookmarks bar and page.
    public let card: CGRect
    /// The page, inside the card, under the toolbar and bookmarks bar.
    public let page: CGRect
    public let corner: CGFloat
    /// Heights of the bars at the top of the card; zero when hidden.
    public let toolbar: CGFloat
    public let bookmarks: CGFloat
    /// The docked sidebar, or nil when there is none on screen.
    public let sidebar: CGRect?
    /// The tab strip, or nil when there is none on screen.
    public let strip: CGRect?

    /// - Parameters:
    ///   - folded: the sidebar or strip is put away (it may still peek out over the card).
    ///   - immersed: a page is in full-screen video; the card fills the window bare.
    ///   - bookmarked: the bookmarks bar is shown.
    public init(
        window: CGSize, tabs: Tabs, sideWidth: CGFloat, folded: Bool, immersed: Bool, bookmarked: Bool
    ) {
        let whole = CGRect(origin: .zero, size: window)
        guard !immersed else {
            self.init(card: whole, corner: 0, toolbar: 0, bookmarks: 0, sidebar: nil, strip: nil)
            return
        }
        let gap = ChromeLayout.gap
        // Edges rather than a CGRect while working: a CGRect with a negative width
        // reports it as positive, which would hide a window too small for the chrome.
        var (left, top, right, bottom) = (gap, gap, window.width - gap, window.height - gap)
        var sidebar: CGRect?
        var strip: CGRect?
        switch (tabs, folded) {
        case (.sidebar, false):
            // The sidebar keeps its own margin on the side of the card, so the card
            // starts right where the sidebar ends.
            let side = CGRect(x: 0, y: 0, width: sideWidth, height: window.height)
            sidebar = side
            left = side.maxX
        case (.strip, false):
            // The active tab runs into the card, so there is no gap between the two.
            let band = CGRect(x: 0, y: 0, width: window.width, height: ChromeLayout.strip)
            strip = band
            top = band.maxY
        case (_, true):
            break
        }
        right = max(left, right)
        bottom = max(top, bottom)
        let card = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        self.init(
            card: card, corner: ChromeLayout.corner, toolbar: ChromeLayout.toolbar,
            bookmarks: bookmarked ? ChromeLayout.bookmarks : 0, sidebar: sidebar, strip: strip)
    }

    private init(card: CGRect, corner: CGFloat, toolbar: CGFloat, bookmarks: CGFloat, sidebar: CGRect?, strip: CGRect?) {
        self.card = card
        self.corner = corner
        self.toolbar = toolbar
        self.bookmarks = bookmarks
        self.sidebar = sidebar
        self.strip = strip
        let top = min(card.height, toolbar + bookmarks)
        page = CGRect(x: card.minX, y: card.minY + top, width: card.width, height: card.height - top)
    }

    /// Centre of the close button for the traffic lights, from the window's
    /// top-left corner: level with the toolbar beside a sidebar, and in the
    /// middle of the strip above the tabs.
    public static func lights(for tabs: Tabs) -> CGPoint {
        switch tabs {
        case .sidebar: CGPoint(x: 26, y: gap + toolbar / 2)
        case .strip: CGPoint(x: 21, y: strip / 2)
        }
    }

    /// Height of the band the title bar (and so the traffic lights) sits in.
    public static func band(for tabs: Tabs) -> CGFloat {
        switch tabs {
        case .sidebar: 2 * lights(for: .sidebar).y
        case .strip: strip
        }
    }

    /// Frame of the sidebar floating over the card while it peeks out from a
    /// folded state: inset like the card, so it reads as a panel of its own.
    public static func floatingSidebar(window: CGSize, sideWidth: CGFloat) -> CGRect {
        CGRect(x: gap, y: gap, width: sideWidth, height: max(0, window.height - 2 * gap))
    }
}
