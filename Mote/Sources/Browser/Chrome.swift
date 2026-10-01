import MoteCore
import SwiftUI

// The window's layout (see ChromeLayout): the tabs sit on the window's frame,
// in a sidebar or a strip, and the page on a rounded card inset from the
// window's edges, with the toolbar across its top.

extension Browser {
    /// Whether the bookmarks bar is on the card: on every page when asked for in
    /// Settings, and always on a new tab, which has no page to cover.
    var bookmarksShown: Bool {
        guard !bookmarks.isEmpty, active?.immersed != true else { return false }
        return prefs.bookmarksBar || active?.isStart != false
    }

    /// Whether the address field is being edited in the toolbar, over a page. A
    /// blank tab edits in its own composer, and ⌘K opens the palette instead.
    var editingInBar: Bool {
        editing && !field.switching && active?.isStart == false
    }

    func layout(in window: CGSize) -> ChromeLayout {
        ChromeLayout(
            window: window, tabs: prefs.sidebar ? .sidebar : .strip, sideWidth: prefs.sideWidth, folded: folded,
            immersed: active?.immersed == true, bookmarked: bookmarksShown, chatting: chatting, panelWidth: prefs.chatWidth)
    }
}

struct Chrome: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    var body: some View {
        GeometryReader { geo in
            let layout = browser.layout(in: geo.size)
            ZStack(alignment: .topLeading) {
                // Black in full-screen video, so no band shows during the transition.
                (layout.corner == 0 ? Color.black : Palette.frame)
                    .opacity(browser.foldNudge ? 0.999 : 1)

                // Kept in the tree while folded, just slid off the window: building the
                // whole list again as it comes back would cost the first frames of the
                // slide. It slides as one solid panel, beside the card.
                if prefs.sidebar, browser.active?.immersed != true {
                    let docked = layout.sidebar != nil
                    Sidebar(browser: browser, prefs: prefs, showing: docked)
                        .frame(width: prefs.sideWidth, height: geo.size.height)
                        .offset(x: docked ? 0 : -prefs.sideWidth - ChromeLayout.gap)
                        .allowsHitTesting(docked)
                        .accessibilityHidden(!docked)
                        .transition(.move(edge: .leading))
                }

                // The chat about the page, the mirror of the sidebar: full window
                // height on the trailing edge, outside the card, so the card gives
                // up the width it takes and keeps its rounded corners. Like the
                // sidebar it stays in the tree while a page shows, just slid off
                // the window, so the slide back costs no first frames; it moves on
                // the sidebar's own fold spring.
                if browser.active?.immersed != true, let tab = browser.active, !tab.isBlank || tab.chatOpen {
                    let docked = layout.chatPanel != nil
                    PageChatPanel(browser: browser, tab: tab)
                        .frame(width: prefs.chatWidth, height: geo.size.height)
                        .offset(x: docked ? geo.size.width - prefs.chatWidth : geo.size.width + ChromeLayout.gap)
                        .allowsHitTesting(docked)
                        .accessibilityHidden(!docked)
                        .transition(.move(edge: .trailing))
                }

                PageCard(browser: browser, prefs: prefs, layout: layout)
                    .frame(width: layout.card.width, height: layout.card.height)
                    .offset(x: layout.card.minX, y: layout.card.minY)

                // Over the card, so the active tab covers the card's top edge and the
                // two read as one surface.
                if layout.strip != nil {
                    TabBar(browser: browser)
                        .frame(width: geo.size.width, height: ChromeLayout.strip)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Over the card's edge, so the gap beside the page is what resizes the
                // sidebar; no line is drawn for it.
                if let side = layout.sidebar {
                    ResizeGrip(prefs: prefs, edge: .leading) { browser.toggleFold() }
                        .frame(width: ResizeGrip.width, height: side.height)
                        .offset(x: side.maxX - ResizeGrip.width + ResizeGrip.over)
                }

                // The same handle mirrored on the panel's edge: dragging the gap
                // between card and panel is what resizes the panel.
                if let panel = layout.chatPanel {
                    ResizeGrip(prefs: prefs, edge: .trailing) { browser.togglePageChat() }
                        .frame(width: ResizeGrip.width, height: panel.height)
                        .offset(x: panel.minX - ResizeGrip.over)
                }
            }
        }
        .ignoresSafeArea()
        .animation(Motion.glide, value: prefs.sidebar)
        .animation(Motion.fold, value: browser.chatting)
        .animation(.easeOut(duration: 0.12), value: browser.active?.immersed)
    }
}

// MARK: - Card

/// The rounded card: the toolbar, the bookmarks bar, and the page.
private struct PageCard: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    let layout: ChromeLayout

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: layout.corner, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            if layout.toolbar > 0 {
                Toolbar(browser: browser, prefs: prefs)
                    .frame(height: layout.toolbar)
                    .zIndex(1)
            }
            if layout.bookmarks > 0 {
                BookmarksBar(browser: browser, bookmarks: browser.bookmarks, ruled: browser.active?.isStart == false)
                    .frame(height: layout.bookmarks)
                    .transition(.opacity)
            }
            // The page takes its new size at once, without animating, and keeps to the
            // card's far corner while the card's near edge slides over it or away; a
            // picture of how it was dissolves on top (see `Browser.dissolvingPage`).
            stage
                .frame(width: layout.page.width, height: layout.page.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transaction { $0.animation = nil }
                .overlay(alignment: .bottomTrailing) {
                    if let veil = browser.pageVeil {
                        Image(nsImage: veil)
                            .frame(width: veil.size.width, height: veil.size.height)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .clipped()
        }
        .background {
            if layout.corner > 0 {
                shape
                    .fill(Palette.ground)
                    .shadow(color: .black.opacity(0.06), radius: 1.5, y: 0.5)
                    .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
            } else {
                Palette.ground
            }
        }
        .clipShape(shape)
        .overlay {
            if layout.corner > 0 {
                shape.strokeBorder(Palette.edge, lineWidth: 1).allowsHitTesting(false)
            }
        }
        // Over the page, under the address field; outside the clip so a long list isn't cut.
        .overlayPreferenceValue(AddressBar.Bounds.self) { anchor in
            GeometryReader { proxy in
                if let anchor, browser.editingInBar, !browser.field.offers.isEmpty {
                    BarSuggestions(browser: browser, bar: proxy[anchor])
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -4)), removal: .opacity))
                }
            }
        }
        .animation(Motion.quick, value: browser.editingInBar && !browser.field.offers.isEmpty)
        .animation(Motion.settle, value: browser.reviewing)
    }

    @ViewBuilder
    private var stage: some View {
        if let tab = browser.active {
            ZStack(alignment: .topLeading) {
                if let chat = tab.chat, tab.isBlank {
                    // One per chat, so a draft and scrolling never carry over to another.
                    ChatView(browser: browser, conversation: chat).id(chat.id)
                } else if tab.chats, tab.isBlank {
                    ChatsPage(browser: browser)
                } else if tab.isBlank {
                    NewTabPage(browser: browser, prefs: prefs)
                } else {
                    Page(tab: tab)
                        .overlay {
                            if prefs.showsLinks { LinkBubble(status: browser.linkStatus) }
                        }
                        .overlay(alignment: .topTrailing) {
                            if browser.finder.showing {
                                FindBar(finder: browser.finder)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let asked = browser.logins.choices, asked.tab == tab.id {
                                AccountList(logins: browser.logins, choices: asked)
                                    .transition(.opacity)
                            }
                        }
                        .animation(Motion.quick, value: browser.logins.choices)
                }
                PeekLayer(browser: browser)
                if browser.reviewing {
                    // Not dimmed, so the page stays visible while reviewing hidden elements.
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { browser.reviewing = false }
                        HiddenElementsPanel(browser: browser)
                            .padding(.top, 8)
                            .padding(.trailing, 8)
                            .transition(.scale(scale: 0.97, anchor: .topTrailing).combined(with: .opacity))
                    }
                    .transition(.opacity)
                }
            }
        } else {
            Palette.ground
        }
    }
}

// MARK: - Resize Grip

/// The invisible handle between the sidebar and the card, and the same handle
/// mirrored between the card and the trailing chat panel. Dragging it sets the
/// panel's width, a double-click puts the default back, and letting go well
/// short of the narrowest width folds the sidebar (or closes the chat panel)
/// away, as in Arc.
///
/// AppKit rather than a SwiftUI gesture: the cursor has to win over the web
/// view's cursor rects beside it, and the drag must keep tracking once the
/// pointer leaves the handle.
struct ResizeGrip: NSViewRepresentable {
    /// Which of the two docks the handle belongs to.
    enum Edge {
        case leading, trailing
    }

    /// Width of the handle, and how far of it lies over the card.
    static let width: CGFloat = 10
    static let over: CGFloat = 3
    /// How far past the narrowest width a release folds the sidebar.
    static let foldBeyond: CGFloat = 64

    let prefs: Preferences
    var edge: Edge = .leading
    let fold: () -> Void

    func makeNSView(context: Context) -> Grip { Grip() }

    func updateNSView(_ grip: Grip, context: Context) {
        grip.prefs = prefs
        grip.edge = edge
        grip.fold = fold
    }

    final class Grip: NSView {
        var prefs: Preferences?
        var edge: ResizeGrip.Edge = .leading
        var fold: () -> Void = {}
        private var start: (x: CGFloat, width: CGFloat)?
        private var wanted: CGFloat = 0

        /// The narrowest and widest this dock may be dragged.
        private var least: CGFloat { edge == .leading ? Metrics.sideMin : Metrics.chatMin }
        private var most: CGFloat { edge == .leading ? Metrics.sideMax : Metrics.chatMax }
        /// The width on its double-click default.
        private var usual: CGFloat { edge == .leading ? Metrics.side : Metrics.chat }
        private func width(_ prefs: Preferences) -> CGFloat { edge == .leading ? prefs.sideWidth : prefs.chatWidth }
        private func setWidth(_ value: CGFloat, of prefs: Preferences) {
            if edge == .leading { prefs.sideWidth = value } else { prefs.chatWidth = value }
        }

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func mouseDown(with event: NSEvent) {
            guard let prefs else { return }
            if event.clickCount == 2 {
                start = nil
                withAnimation(Motion.settle) { setWidth(usual, of: prefs) }
                return
            }
            start = (event.locationInWindow.x, width(prefs))
            wanted = width(prefs)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let prefs, let start else { return }
            NSCursor.resizeLeftRight.set()
            // The leading handle grows as the pointer moves right; the trailing
            // one, mirrored, grows as it moves left.
            let travel = event.locationInWindow.x - start.x
            wanted = edge == .leading ? start.width + travel : start.width - travel
            let held = min(most, max(least, wanted))
            guard held != width(prefs) else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { setWidth(held, of: prefs) }
        }

        override func mouseUp(with event: NSEvent) {
            defer { start = nil }
            guard start != nil, wanted < least - ResizeGrip.foldBeyond else { return }
            fold()
        }
    }
}
