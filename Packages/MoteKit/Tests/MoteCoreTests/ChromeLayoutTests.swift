import CoreGraphics
import Testing

@testable import MoteCore

@Suite("ChromeLayout")
struct ChromeLayoutTests {
    private let window = CGSize(width: 1200, height: 800)
    private let gap = ChromeLayout.gap

    private func layout(
        _ tabs: ChromeLayout.Tabs, folded: Bool = false, immersed: Bool = false, bookmarked: Bool = false, side: CGFloat = 240,
        chatting: Bool = false, panel: CGFloat = ChromeLayout.panel
    ) -> ChromeLayout {
        ChromeLayout(
            window: window, tabs: tabs, sideWidth: side, folded: folded, immersed: immersed, bookmarked: bookmarked, chatting: chatting,
            panelWidth: panel)
    }

    @Test("Beside a sidebar the card starts where the sidebar ends and keeps a gap on the other sides")
    func sidebarCard() {
        let chrome = layout(.sidebar)
        #expect(chrome.sidebar == CGRect(x: 0, y: 0, width: 240, height: 800))
        #expect(chrome.card == CGRect(x: 240, y: gap, width: 1200 - 240 - gap, height: 800 - 2 * gap))
        #expect(chrome.strip == nil)
        #expect(chrome.corner == ChromeLayout.corner)
    }

    @Test("A folded sidebar leaves the card inset evenly on every side")
    func foldedSidebar() {
        let chrome = layout(.sidebar, folded: true)
        #expect(chrome.sidebar == nil)
        #expect(chrome.card == CGRect(x: gap, y: gap, width: 1200 - 2 * gap, height: 800 - 2 * gap))
    }

    @Test("Under a strip the card meets the strip with no gap, so the active tab runs into it")
    func stripCard() {
        let chrome = layout(.strip)
        #expect(chrome.strip == CGRect(x: 0, y: 0, width: 1200, height: ChromeLayout.strip))
        #expect(chrome.card.minY == ChromeLayout.strip)
        #expect(chrome.card.minX == gap)
        #expect(chrome.card.maxX == 1200 - gap)
        #expect(chrome.card.maxY == 800 - gap)
    }

    @Test("The page sits under the toolbar, and under the bookmarks bar when it shows")
    func pageUnderBars() {
        let plain = layout(.sidebar)
        #expect(plain.page.minY == plain.card.minY + ChromeLayout.toolbar)
        #expect(plain.page.maxY == plain.card.maxY)
        #expect(plain.page.width == plain.card.width)

        let marked = layout(.sidebar, bookmarked: true)
        #expect(marked.bookmarks == ChromeLayout.bookmarks)
        #expect(marked.page.minY == marked.card.minY + ChromeLayout.toolbar + ChromeLayout.bookmarks)
    }

    @Test("A chat panel docks full height on the window's trailing edge, the mirror of the sidebar, and takes its width off the card")
    func chatPanel() throws {
        let chrome = layout(.sidebar, chatting: true)
        let panel = try #require(chrome.chatPanel)
        #expect(panel.width == ChromeLayout.panel)
        #expect(panel.minX == chrome.card.maxX)
        #expect(panel.maxX == window.width)
        #expect(panel.minY == 0)
        #expect(panel.maxY == window.height)
        // The card gives the panel its width; the page keeps the whole card.
        #expect(chrome.card.width == 1200 - 240 - ChromeLayout.panel)
        #expect(chrome.page.width == chrome.card.width)
        #expect(chrome.page.maxX == panel.minX)
    }

    @Test("The chat panel runs the window's full height even when the card carries the bars")
    func chatPanelBars() throws {
        let chrome = layout(.sidebar, bookmarked: true, chatting: true)
        let panel = try #require(chrome.chatPanel)
        #expect(panel.minY == 0)
        #expect(panel.maxY == window.height)
        #expect(chrome.page.minY == chrome.card.minY + ChromeLayout.toolbar + ChromeLayout.bookmarks)
        #expect(chrome.page.maxY == chrome.card.maxY)
    }

    @Test("The chat panel's width comes from the caller, not a fixed size")
    func chatPanelWidth() throws {
        let width: CGFloat = 300
        let chrome = layout(.sidebar, chatting: true, panel: width)
        let panel = try #require(chrome.chatPanel)
        #expect(panel.width == width)
        #expect(chrome.card.width == 1200 - 240 - width)
    }

    @Test("No chat panel leaves the page across the whole card")
    func noChatPanel() {
        let chrome = layout(.sidebar)
        #expect(chrome.chatPanel == nil)
        #expect(chrome.page.width == chrome.card.width)
    }

    @Test("Full-screen video leaves no room for a chat panel, however it was asked for", arguments: [true, false])
    func chatPanelImmersed(chatting: Bool) {
        let chrome = layout(.sidebar, immersed: true, chatting: chatting)
        #expect(chrome.chatPanel == nil)
        #expect(chrome.page == chrome.card)
    }

    @Test("A window too small for the panel keeps a non-negative page")
    func chatPanelTiny() {
        let chrome = ChromeLayout(
            window: CGSize(width: 100, height: 20), tabs: .sidebar, sideWidth: 240, folded: false, immersed: false, bookmarked: true,
            chatting: true)
        #expect(chrome.page.width >= 0)
        #expect((chrome.chatPanel?.width ?? 0) >= 0)
    }

    @Test("Full-screen video fills the window with a bare page", arguments: [ChromeLayout.Tabs.sidebar, .strip])
    func immersed(tabs: ChromeLayout.Tabs) {
        let chrome = layout(tabs, immersed: true, bookmarked: true)
        #expect(chrome.card == CGRect(origin: .zero, size: window))
        #expect(chrome.page == chrome.card)
        #expect(chrome.corner == 0)
        #expect(chrome.toolbar == 0)
        #expect(chrome.bookmarks == 0)
        #expect(chrome.sidebar == nil)
        #expect(chrome.strip == nil)
    }

    @Test("A window too small for the chrome never gets a negative card")
    func tinyWindow() {
        let chrome = ChromeLayout(
            window: CGSize(width: 100, height: 20), tabs: .sidebar, sideWidth: 240, folded: false, immersed: false, bookmarked: true)
        #expect(chrome.card.width == 0)
        #expect(chrome.page.height >= 0)
    }

    @Test("The traffic lights line up with the toolbar beside a sidebar and sit in the strip above tabs")
    func lights() {
        let side = ChromeLayout.lights(for: .sidebar)
        #expect(side.y == ChromeLayout.gap + ChromeLayout.toolbar / 2)
        #expect(ChromeLayout.band(for: .sidebar) == 2 * side.y)

        let strip = ChromeLayout.lights(for: .strip)
        #expect(strip.y == ChromeLayout.strip / 2)
        #expect(ChromeLayout.band(for: .strip) == ChromeLayout.strip)
    }

    @Test("A peeking sidebar floats inset like the card")
    func floating() {
        let frame = ChromeLayout.floatingSidebar(window: window, sideWidth: 240)
        #expect(frame == CGRect(x: gap, y: gap, width: 240, height: 800 - 2 * gap))
    }
}
