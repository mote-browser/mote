import AppKit
import Combine
import MoteCore
import WebKit

// The browser as extensions see it: one window, and its tabs. Private tabs
// stay out of sight unless made to carry extensions (Settings › Extensions).

@available(macOS 15.4, *)
extension Extensions {
    func adapter(for tab: Tab) -> ExtensionTab {
        if let known = adapters[tab.id] { return known }
        let made = ExtensionTab(tab: tab, owner: self)
        adapters[tab.id] = made
        return made
    }

    func shows(_ tab: Tab) -> Bool { !tab.shy || tab.carriesExtensions }

    var visibleTabs: [Tab] { browser?.tabs.filter(shows) ?? [] }

    var activeAdapter: ExtensionTab? {
        guard let tab = browser?.active, shows(tab) else { return nil }
        return adapter(for: tab)
    }

    func followTabs(of browser: Browser) {
        controller.didOpenWindow(window)
        browser.$tabs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tabs in self?.tabsChanged(tabs) }
            .store(in: &subscriptions)
        browser.$activeID
            .removeDuplicates()
            .scan((nil, nil)) { ($0.1, $1) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pair in self?.selected(pair.1, after: pair.0) }
            .store(in: &subscriptions)
    }

    private func tabsChanged(_ tabs: [Tab]) {
        let shown = tabs.filter(shows)
        let changes = ExtensionRules.tabChanges(from: order, to: shown.map(\.id))
        for id in changes.closed {
            if let adapter = adapters[id] { controller.didCloseTab(adapter, windowIsClosing: false) }
            adapters[id] = nil
            tabWatches[id] = nil
        }
        for tab in shown where changes.opened.contains(tab.id) {
            controller.didOpenTab(adapter(for: tab))
            watch(tab)
        }
        for (id, from) in changes.moved {
            if let adapter = adapters[id] { controller.didMoveTab(adapter, from: from, in: window) }
        }
        order = shown.map(\.id)
    }

    private func watch(_ tab: Tab) {
        let id = tab.id
        let tell = { [weak self] (change: WKWebExtension.TabChangedProperties) in
            guard let self, let adapter = adapters[id] else { return }
            controller.didChangeTabProperties(change, for: adapter)
        }
        tabWatches[id] = [
            tab.$title.dropFirst().removeDuplicates().sink { _ in tell(.title) },
            tab.$address.dropFirst().removeDuplicates().sink { _ in tell(.URL) },
            tab.$loading.dropFirst().removeDuplicates().sink { _ in tell(.loading) },
            tab.$pin.dropFirst().map { $0 != nil }.removeDuplicates().sink { _ in tell(.pinned) },
        ]
    }

    private func selected(_ id: Tab.ID?, after previous: Tab.ID?) {
        guard let browser, let tab = id.flatMap(browser.tab), shows(tab) else { return }
        controller.didActivateTab(adapter(for: tab), previousActiveTab: previous.flatMap(browser.tab).map(adapter(for:)))
        actionsChanged += 1
    }
}

/// A tab, for WebKit's extension APIs.
@available(macOS 15.4, *)
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    weak var tab: Tab?
    unowned let owner: Extensions

    init(tab: Tab, owner: Extensions) {
        self.tab = tab
        self.owner = owner
    }

    private var browser: Browser? { owner.browser }
    private var page: WKWebView? { tab?.built }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { owner.window }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        tab.flatMap { tab in owner.visibleTabs.firstIndex { $0.id == tab.id } } ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { page }
    func title(for context: WKWebExtensionContext) -> String? { tab?.title }
    func url(for context: WKWebExtensionContext) -> URL? { tab?.address }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { tab?.loading != true }
    func isSelected(for context: WKWebExtensionContext) -> Bool { tab != nil && tab?.id == browser?.activeID }
    func isPinned(for context: WKWebExtensionContext) -> Bool { tab?.pin != nil }
    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool { tab?.noisy == true }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { Double(page?.pageZoom ?? 1) }
    func size(for context: WKWebExtensionContext) -> CGSize { page?.bounds.size ?? .zero }
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }

    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext) async throws {
        guard let tab, let browser, pinned != (tab.pin != nil) else { return }
        if pinned { browser.pin(tab) } else { browser.unpin(tab) }
    }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext) async throws {
        tab?.magnify(to: CGFloat(zoomFactor))
    }

    /// An extension's page only loads in a web view made for that extension,
    /// so going to one from elsewhere replaces the tab (Browser.replace).
    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        guard let tab else { return }
        let url = Extensions.current(url)
        let here = page?.url ?? tab.address
        let elsewhere = here?.scheme != Extensions.scheme || here?.host != url.host
        if url.scheme == Extensions.scheme, elsewhere, let browser {
            browser.replace(tab, going: url)
        } else {
            tab.go(to: url)
        }
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws { tab?.reload() }
    func goBack(for context: WKWebExtensionContext) async throws { tab?.back() }
    func goForward(for context: WKWebExtensionContext) async throws { tab?.forward() }

    func activate(for context: WKWebExtensionContext) async throws {
        if let tab { browser?.select(tab) }
    }

    func close(for context: WKWebExtensionContext) async throws {
        if let tab { browser?.close(tab) }
    }

    func takeSnapshot(using configuration: WKSnapshotConfiguration, for context: WKWebExtensionContext) async throws -> NSImage? {
        guard let page else { return nil }
        return try await page.takeSnapshot(configuration: configuration)
    }
}

/// The browser window, for WebKit's extension APIs. Mote has just the one.
@available(macOS 15.4, *)
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    unowned let owner: Extensions

    init(owner: Extensions) { self.owner = owner }

    private var shown: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.frameAutosaveName == "mote" } ?? NSApp.mainWindow
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { owner.visibleTabs.map(owner.adapter(for:)) }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { owner.activeAdapter }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
    func frame(for context: WKWebExtensionContext) -> CGRect { shown?.frame ?? .null }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { shown?.screen?.frame ?? NSScreen.main?.frame ?? .null }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = shown else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return window.isZoomed ? .maximized : .normal
    }

    func focus(for context: WKWebExtensionContext) async throws {
        NSApp.activate()
        shown?.makeKeyAndOrderFront(nil)
    }
}
