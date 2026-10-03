import AppKit
import SwiftUI

/// AppKit owns the sidebar's frame and collapse animation; SwiftUI draws
/// the existing sidebar and rounded page card inside the two panes.
struct NativeSidebar: NSViewControllerRepresentable {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    func makeNSViewController(context: Context) -> Controller { Controller(browser: browser, prefs: prefs) }
    func updateNSViewController(_ controller: Controller, context: Context) { controller.update() }

    @MainActor
    final class Controller: NSSplitViewController {
        private let browser: Browser
        private let prefs: Preferences
        private let sidebar: NSHostingController<Side>
        private let detail: NSHostingController<ChromeDetail>
        let sidebarItem: NSSplitViewItem
        private var collapsed: Bool
        private var sidebarMode: Bool
        private var immersed: Bool

        init(browser: Browser, prefs: Preferences) {
            self.browser = browser
            self.prefs = prefs
            sidebar = NSHostingController(rootView: Side(browser: browser, prefs: prefs))
            detail = NSHostingController(rootView: ChromeDetail(browser: browser, prefs: prefs))
            // A plain split item preserves Mote's shared background; the
            // sidebar factory adds a separate system material behind this pane.
            sidebarItem = NSSplitViewItem(viewController: sidebar)
            sidebarMode = prefs.sidebar
            immersed = browser.active?.immersed == true
            collapsed = !prefs.sidebar || browser.folded || immersed
            super.init(nibName: nil, bundle: nil)
            sidebar.sizingOptions = []
            sidebar.safeAreaRegions = []
            detail.sizingOptions = []
            detail.safeAreaRegions = []
            splitView = DividerlessSplitView()
            splitView.isVertical = true
            sidebarItem.canCollapse = true
            sidebarItem.canCollapseFromWindowResize = false
            sidebarItem.isSpringLoaded = false
            sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
            sidebarItem.minimumThickness = prefs.sideWidth
            sidebarItem.maximumThickness = prefs.sideWidth
            sidebarItem.isCollapsed = collapsed
            addSplitViewItem(sidebarItem)
            addSplitViewItem(NSSplitViewItem(viewController: detail))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidAppear() {
            super.viewDidAppear()
            update()
        }

        func update() {
            // ResizeGrip remains the single owner of the saved sidebar width.
            let width = prefs.sideWidth
            if sidebarItem.minimumThickness != width {
                if width > sidebarItem.maximumThickness {
                    sidebarItem.maximumThickness = width
                    sidebarItem.minimumThickness = width
                } else {
                    sidebarItem.minimumThickness = width
                    sidebarItem.maximumThickness = width
                }
            }
            let fullscreenPage = browser.active?.immersed == true
            let target = !prefs.sidebar || browser.folded || fullscreenPage
            let animate = view.window != nil && sidebarMode == prefs.sidebar && immersed == fullscreenPage
            sidebarMode = prefs.sidebar
            immersed = fullscreenPage
            guard target != collapsed else { return }
            collapsed = target
            if animate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.foldResponse
                    sidebarItem.animator().isCollapsed = target
                }
            } else {
                sidebarItem.isCollapsed = target
            }
        }

        override func splitView(
            _ splitView: NSSplitView, effectiveRect proposed: NSRect, forDrawnRect drawn: NSRect, ofDividerAt index: Int
        ) -> NSRect {
            _ = super.splitView(splitView, effectiveRect: proposed, forDrawnRect: drawn, ofDividerAt: index)
            return .zero
        }
    }

    struct Side: View {
        @ObservedObject var browser: Browser
        @ObservedObject var prefs: Preferences

        var body: some View {
            Sidebar(browser: browser, prefs: prefs, showing: !browser.folded)
                .overlay(alignment: .trailing) {
                    ResizeGrip(prefs: prefs, edge: .leading) { browser.toggleFold() }
                        .frame(width: ResizeGrip.width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .ignoresSafeArea()
                .clipped()
        }
    }

    private final class DividerlessSplitView: NSSplitView {
        override var dividerThickness: CGFloat { 0 }
        override func drawDivider(in rect: NSRect) {}
    }
}
