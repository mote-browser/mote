import Combine
import ImageIO
import MoteAI
import MoteCore
import SwiftUI
import WebKit

/// One tab: its page and what the row shows about it.
///
/// The web view is made on first use, so a restored session doesn't start a
/// web process per tab, and each tab keeps its own, so switching tabs keeps
/// scroll positions and half-filled forms. An idle tab can let its view go
/// and come back from a saved state and a snapshot (see `sleep(picture:)`).
@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    /// A private tab: its own cookies, no history, left out of the session.
    let shy: Bool
    /// Opened by a script through the bench: shares the user's store but is
    /// never selected, saved or recorded in history.
    let bench: Bool
    private let configuration: WKWebViewConfiguration

    /// Where the page's doings are reported.
    weak var owner: TabOwner?
    /// Navigation and UI delegate, handed to the web view when it is made.
    weak var delegate: (WKNavigationDelegate & WKUIDelegate)? {
        didSet {
            built?.navigationDelegate = delegate
            built?.uiDelegate = delegate
        }
    }

    // MARK: - What the row and the page show

    @Published private(set) var title = ""
    @Published private(set) var address: URL?
    @Published private(set) var progress: Double = 0
    @Published private(set) var loading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    /// Why the page didn't load, shown in its place.
    @Published var failure: String?
    /// How far down the page is scrolled, for the tab's reading bar. Its own
    /// object, watched only by the bar: it changes as the page scrolls, and
    /// published from the tab it redrew and laid out every view on the tab
    /// mid-scroll, which made the page's frames reach the screen unevenly.
    let reading = Reading()
    @Published private(set) var reader = false
    /// The site's icon: from the cache once the address is known, then from the page.
    @Published var icon: NSImage?
    /// Focus is in something editable on the page.
    @Published var typing = false
    /// The page is fullscreen.
    @Published var immersed = false
    /// The page is in the floating video window.
    @Published var floating = false
    /// A swipe in progress.
    @Published var pull: Pull?
    @Published private(set) var zoom: CGFloat = 1
    /// The page is playing sound.
    @Published var noisy = false
    /// Muted by the user; the page keeps playing.
    @Published private(set) var muted = false
    /// The pin letter; pinned tabs sit first in the row and show it instead of a title.
    @Published var pin: String?
    /// A name given by the user, kept across navigations.
    @Published var name: String?
    /// The extension whose Web Store page already shows its own "Add to Mote".
    @Published var storePlaced: String?
    /// The snapshot shown while a woken page is made again.
    @Published private(set) var cover: NSImage?
    /// A chat with the assistant, shown in place of a page (see ChatView.swift).
    /// Going to an address replaces it.
    @Published var chat: Conversation?
    /// The chat about this tab's page, shown beside it in the side panel.
    /// Separate from `chat`: it is made on first use and kept as the tab
    /// navigates. Only the page is let go on navigation, never the chat.
    @Published private(set) var pageChat: Conversation?
    /// Whether this tab's page chat panel is open. Per tab, so each tab keeps
    /// its own open or closed state: a new tab — including one a link opened —
    /// starts closed, and coming back to a tab brings its panel back as it was.
    @Published var chatOpen = false
    /// Shows every kept chat in place of a page (see ChatsPage.swift). Going to
    /// an address or opening a chat replaces it.
    @Published var chats = false

    /// The tab whose page opened this one by script; sign-ins go back to it.
    var opener: Tab.ID?
    /// A window opened with its own size or features. It is labelled with its
    /// site, since the opener controls its title.
    var popup = false
    /// The page's process died while the tab was in the background; it loads
    /// again when shown.
    var stale = false
    /// When the tab was last on screen, for ordering and tab sleep.
    private(set) var touched = Date()

    /// No page: a new tab, or a chat.
    var isBlank: Bool { address == nil }
    /// A new tab, waiting for an address, a search or a question.
    var isStart: Bool { isBlank && chat == nil && !chats }
    var label: String {
        if let chat, isBlank, name?.isEmpty != false { return chat.title }
        if chats, isBlank, name?.isEmpty != false { return "Chats" }
        return TabLabel.text(name: name, popup: popup, address: address, title: title)
    }
    var monogram: String { chat != nil && isBlank ? "✦" : TabLabel.monogram(for: address) }
    var store: WKWebsiteDataStore { configuration.websiteDataStore }

    /// Made with the extension controller, which can't be added later.
    @available(macOS 15.4, *)
    var carriesExtensions: Bool { configuration.webExtensionController != nil }

    init(shy: Bool = false, bench: Bool = false, configuration: WKWebViewConfiguration? = nil) {
        self.shy = shy
        self.bench = bench
        self.configuration = configuration ?? Web.configuration(shy: shy)
    }

    func touch() { touched = Date() }

    // MARK: - The web view

    /// The web view, made on first use.
    var web: PageView {
        if let built { return built }
        return build()
    }
    /// The web view if it exists, for callers that mustn't make one.
    private(set) var built: PageView?

    private let scroll = ScrollRelay()
    private let hider = ElementHiderRelay()
    private let forms = FormRelay()
    private let images = ImageRelay()
    private let store_ = WebStoreBridge()
    private let middle = MiddleRelay()
    private let passkeys = PasskeyRelay()
    private let hovered = HoveredLink()
    private let sound = AudioWatch()
    private var watches: [NSKeyValueObservation] = []
    /// This site's hidden elements, for the next document.
    private var hiding = ElementHidingStyle.config(selectors: [])

    private func build() -> PageView {
        // Here rather than in Web.configuration: a configuration can come from an
        // opener or an extension, or be made long before its page.
        FrameRate.apply(to: configuration.preferences)
        let web = PageView(frame: .zero, configuration: configuration)
        // Pinch to magnify; ⌘+ and ⌘- change page zoom instead.
        web.allowsMagnification = true
        // PageView does its own swipes.
        web.allowsBackForwardNavigationGestures = false
        Swipe.calm(web)
        web.onPull = { [weak self] in self?.pull = $0 }
        web.onTouch = { [weak self] in self?.uncover() }
        web.searchName = { [weak self] in self?.owner?.searchEngineName }
        web.onSearch = { [weak self] text in
            guard let self else { return }
            owner?.tab(self, searches: text)
        }
        web.holdForFirstFrame()
        // Inspectable from Safari's Develop menu and Inspect Element, whoever
        // made the configuration.
        web.isInspectable = true
        Web.pages.add(web)
        Web.inspector(web.configuration.preferences)
        web.navigationDelegate = delegate
        web.uiDelegate = delegate

        let controller = web.configuration.userContentController
        Web.release(controller)
        let handlers: [(WKScriptMessageHandler, String)] = [
            (scroll, ScrollRelay.name), (hider, ElementHiderRelay.name), (images, ImageRelay.name),
            (store_, WebStoreBridge.name), (forms, FormRelay.name), (middle, MiddleRelay.name),
        ]
        for (handler, name) in handlers { controller.add(handler, contentWorld: Web.world, name: name) }
        controller.addScriptMessageHandler(passkeys, contentWorld: Web.world, name: PasskeyRelay.name)
        controller.add(hovered, contentWorld: .defaultClient, name: HoveredLink.name)
        AdBlocker.shared.protect(controller)

        built = web
        // After `built`: the form relay starts watching full screen on the view
        // it finds there.
        for relay in [scroll, hider, forms, images, store_, middle, hovered] as [TabRelay] { relay.tab = self }
        if muted { PageAudio.mute(true, web) }
        arm(hiding: hiding)
        watches = observe(web)
        sound.watch(web) { [weak self] in self?.noisy = $0 }
        return web
    }

    /// Watches the web view's title, address, progress and history.
    private func observe(_ web: PageView) -> [NSKeyValueObservation] {
        [
            web.observe(\.title) { [weak self] _, _ in self?.webChanged() },
            web.observe(\.url) { [weak self] _, _ in self?.webChanged() },
            web.observe(\.estimatedProgress) { [weak self] _, _ in self?.webChanged() },
            web.observe(\.isLoading) { [weak self] _, _ in self?.webChanged() },
            web.observe(\.canGoBack) { [weak self] _, _ in self?.webChanged() },
            web.observe(\.canGoForward) { [weak self] _, _ in self?.webChanged() },
        ]
    }

    /// WebKit reports its own properties on the main thread.
    private nonisolated func webChanged() {
        MainActor.assumeIsolated { syncWithWeb() }
    }

    /// Copies what changed on the web view into the tab.
    private func syncWithWeb() {
        guard let web = built else { return }
        if title != web.title ?? "" { title = web.title ?? "" }
        // Letting a pinned tab's page go loads about:blank, which must not
        // replace the address it comes back to.
        if let url = web.url, url != address, url.absoluteString != "about:blank" {
            let moved = url.host() != address?.host()
            address = url
            if moved { takeCachedIcon() }
        }
        if progress != web.estimatedProgress { progress = web.estimatedProgress }
        if loading != web.isLoading { loading = web.isLoading }
        if canGoBack != web.canGoBack { canGoBack = web.canGoBack }
        if canGoForward != web.canGoForward { canGoForward = web.canGoForward }
    }

    private func takeCachedIcon() {
        if let host = address?.host()?.lowercased() { icon = Favicons.shared.cached(host) }
    }

    // MARK: - Going places

    func go(to url: URL) {
        // Whether the load crosses between the web and extension pages depends on
        // the page showing, not on how the tab was made: a tab an extension page
        // opened uses that extension's configuration.
        if let owner, let here = built?.url ?? address, Browser.extensionHost(of: here) != Browser.extensionHost(of: url) {
            return owner.tab(self, crosses: url)
        }
        // At once rather than on KVO, so the tab stops being blank in the same
        // frame the address field goes away.
        address = url
        leaveChat()
        // The chat about the page outlives it: navigating stops sharing the
        // page, and never throws the chat away. A move within the page it
        // already shares is not another page.
        if PageSharing.detaches(from: pageChat?.page?.url, movingTo: url) { pageChat?.detachPage() }
        title = ""
        freshPage()
        // Going somewhere wakes a sleeping tab with nothing to restore.
        rested = nil
        cover = nil
        takeCachedIcon()
        web.open(url)
    }

    /// A tab from the saved session, not loaded until it is opened.
    func restore(url: URL, title: String, name: String? = nil) {
        address = url
        self.title = title
        self.name = name
        rested = Rested(url: url)
        takeCachedIcon()
    }

    /// A tab opened by a link shows its address before WebKit commits, so the
    /// blank state doesn't flash.
    func setAddressOptimistically(_ url: URL) {
        address = url
        failure = nil
        takeCachedIcon()
    }

    /// Forgets what belonged to the previous document.
    private func freshPage() {
        failure = nil
        reading.fraction = 0
        reader = false
        typing = false
        immersed = false
    }

    func reload() {
        // A waiting tab has no view to reload; waking it loads the page.
        guard !wake() else { return }
        if hollow, let address { web.open(address) } else { web.reloadFromOrigin() }
    }

    func stop() { web.stopLoading() }
    func back() { web.goBack() }
    func forward() { web.goForward() }

    /// Leaving reader mode reloads the page: putting the original HTML back
    /// would lose all its event listeners.
    func toggleReader(_ done: @escaping (Bool) -> Void) {
        guard !isBlank else { return done(false) }
        guard !reader else {
            reader = false
            web.reload()
            return done(true)
        }
        web.callAsyncJavaScript(Reader.script, arguments: [:], in: nil, in: .page) { [weak self] result in
            let worked = (try? result.get()) as? String == "read"
            if worked { self?.reader = true }
            done(worked)
        }
    }

    // MARK: - Page chat

    /// The chat about this tab's page, made once and kept as the tab moves.
    /// Whether the page is shared is a separate matter: navigating detaches
    /// it, and sharing the new page is asked for again.
    @discardableResult
    func ensurePageChat() -> Conversation {
        if let pageChat { return pageChat }
        let chat = Conversation()
        pageChat = chat
        return chat
    }

    /// Shares `page` with this tab's chat, making the chat if it must.
    func attachPage(_ page: PageContext) {
        ensurePageChat().attach(page)
    }

    /// Shares the page showing now with the chat about it. Returns whether
    /// there was a page to share.
    @discardableResult
    func attachCurrentPage() async -> Bool {
        guard let page = await capturePageContext() else { return false }
        attachPage(page)
        return true
    }

    /// Stops sharing the page, keeping the chat and what it holds.
    func detachPage() {
        pageChat?.detachPage()
    }

    /// The page the tab shows, as the model should see it: its address and
    /// title always, its text when the page can be read, and what the person
    /// has selected when anything is. Nil when there is nothing to share.
    func capturePageContext() async -> PageContext? {
        guard let address, PageSharing.canShare(address) else { return nil }
        return PageContext(url: address, title: title, text: await pageText(), selection: await selectedText())
    }

    /// The page's text, read without changing the page. A tab whose view is
    /// asleep or gone has none to read.
    private func pageText() async -> String? {
        guard let built else { return nil }
        return try? await built.callAsyncJavaScript(Reader.text, contentWorld: .page) as? String
    }

    /// What the person has selected on the page, read as the context menu does.
    private func selectedText() async -> String? {
        guard let built else { return nil }
        return try? await built.callAsyncJavaScript(PageView.selected, contentWorld: .defaultClient) as? String
    }

    // MARK: - Zoom and sound

    func magnify(to value: CGFloat) {
        let wanted = PageZoom.clamped(value)
        guard PageZoom.differs(wanted, web.pageZoom) else { return }
        web.pageZoom = wanted
        zoom = wanted
        rememberZoom()
        owner?.tab(self, zoomedTo: wanted)
    }

    func magnify(by factor: CGFloat) { magnify(to: web.pageZoom * factor) }

    /// Back to 100%, both page zoom and pinch magnification.
    func resetZoom() {
        magnify(to: 1)
        guard web.magnification != 1 else { return }
        web.magnification = 1
        owner?.tab(self, zoomedTo: 1)
    }

    private static func zoomKey(_ host: String) -> String { "zoom." + host }

    /// Zoom is kept per site, not per tab; private tabs keep nothing.
    private func rememberZoom() {
        guard let host = address?.host(), !shy else { return }
        if PageZoom.isActualSize(zoom) {
            Storage.settings.removeObject(forKey: Self.zoomKey(host))
        } else {
            Storage.settings.set(Double(zoom), forKey: Self.zoomKey(host))
        }
    }

    /// The site's zoom, before the first frame of a new document.
    func applyRememberedZoom() {
        guard let host = address?.host() else { return }
        let kept = CGFloat(Storage.settings.object(forKey: Self.zoomKey(host)) as? Double ?? 1)
        guard PageZoom.differs(kept, web.pageZoom) else { return }
        web.pageZoom = kept
        zoom = kept
    }

    /// A sleeping tab isn't woken; its view is muted when it is made again.
    /// WebKit keeps the mute across navigations.
    func toggleMute() {
        muted.toggle()
        if let built { PageAudio.mute(muted, built) }
    }

    // MARK: - Scripts in the page

    /// Replaces the scripts for the next document (see PageScripts).
    func arm(hiding config: ElementHidingStyle.Config) {
        hiding = config
        guard let controller = built?.configuration.userContentController else { return }
        controller.removeAllUserScripts()
        PageScripts.all(hiding: config).forEach(controller.addUserScript)
    }

    /// Hides what `config` selects in the current document, and only that.
    func applyVeils(_ config: ElementHidingStyle.Config) {
        built?.evaluateInAppWorld(ElementPicker.hiding(config))
    }

    func startPicking() { web.evaluateInAppWorld("window.__moteVeil && window.__moteVeil.on()") }
    func stopPicking() { web.evaluateInAppWorld("window.__moteVeil && window.__moteVeil.off()") }

    /// Shows one hidden element while its row is hovered, the others staying hidden.
    func peek(_ selector: String, keeping others: ElementHidingStyle.Config) {
        web.callInAppWorld(
            "window.__moteVeil?.peek(selectors, selector)", arguments: ["selectors": others.selectors, "selector": selector])
    }

    func unpeek(_ hidden: ElementHidingStyle.Config) {
        web.callInAppWorld("window.__moteVeil?.unpeek(selectors)", arguments: ["selectors": hidden.selectors])
    }

    func picked(selector: String, label: String, note: String) { owner?.tab(self, hid: selector, label: label, note: note) }
    func pickingEnded() { owner?.tabStoppedPicking(self) }
    func pickingFailed(_ reason: String) { owner?.tab(self, couldNotHide: reason) }

    /// From the page script, only when the whole percent read changes.
    func scrolled(to y: Double, of ceiling: Double) {
        let fraction = readingFraction(y: y, of: ceiling)
        if fraction != reading.fraction { reading.fraction = fraction }
    }

    func linkHovered(_ address: String?) { owner?.tab(self, hovers: address) }
    func imageMenu(for image: URL) { owner?.tab(self, openedImageMenuFor: image) }
    func addFromStorePressed() { owner?.tabAddsFromStore(self) }

    /// The Web Store page's own button: installed, installing or available.
    func tellStore(installed: [String], busy: String?) {
        built?.callInAppWorld(
            "window.__moteStore?.state({ installed, busy })", arguments: ["installed": installed, "busy": busy ?? NSNull()])
    }

    // MARK: - Sign-ins

    private var sent: SentSignIn?

    /// A sign-in field gained focus (its frame in CSS pixels) or lost it.
    /// Page zoom is the only scale between CSS pixels and points.
    func fieldFocused(_ rect: CGRect?) {
        let zoom = built?.pageZoom ?? 1
        owner?.tab(
            self,
            focusedSignInAt: rect.map { CGRect(x: $0.minX * zoom, y: $0.minY * zoom, width: $0.width * zoom, height: $0.height * zoom) })
    }

    /// The page sent a sign-in. Its site is taken now, before any redirect.
    func sentSignIn(user: String, password: String) {
        sent = SentSignIn(page: address, user: user, password: password, at: Date())
    }

    /// A new document loaded (`navigated`), or the sign-in fields went away.
    /// With no password field left, the recent sign-in worked. Fields the page
    /// removed itself are checked a little later: inline forms often hide on
    /// submit and come back if the server says no.
    func settleSignIn(navigated: Bool = true) {
        guard let pending = sent else { return }
        guard !pending.expired(at: Date()) else {
            sent = nil
            return
        }
        guard navigated else {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                // Unless newer credentials were sent meanwhile.
                if self?.sent == pending { self?.settleSignIn() }
            }
            return
        }
        web.evaluateInAppWorld("!!(window.__moteForms && window.__moteForms.hasPassword())") { [weak self] still in
            MainActor.assumeIsolated {
                // Still a password field: turned down, or a multi-step sign-in.
                guard let self, let sent = self.sent, (still as? Bool) != true else { return }
                self.sent = nil
                self.owner?.tab(self, signedIn: sent)
            }
        }
    }

    /// Fills a saved account into the page's sign-in fields; `done` hears
    /// false when the fields that were there are gone.
    func fill(user: String, password: String, done: ((Bool) -> Void)? = nil) {
        web.callInAppWorld("return window.__moteForms?.fill(user, password) ?? false", arguments: ["user": user, "password": password]) {
            done?(($0 as? Bool) ?? false)
        }
    }

    // MARK: - Sleep

    /// A tab with an address but no page: restored and not opened yet, put to
    /// sleep, or a pinned tab closed with ⌘W.
    private struct Rested {
        let url: URL
        /// Back-forward list and scroll position, for the new view.
        var state: Any?
        /// A JPEG of the page, shown while it comes back.
        var picture: Data?
    }

    private var rested: Rested?

    var asleep: Bool { rested != nil }
    /// The address a resting tab comes back to.
    var pending: URL? { rested?.url }

    /// ⌘W on a pinned tab: keeps its place and address, lets the page go.
    func rest() {
        guard let url = address else { return }
        rested = Rested(url: url)
        reading.fraction = 0
        noisy = false
        // Loading about:blank isn't enough: WebKit keeps the old document in its
        // back-forward cache, where a site can still count it as open and block
        // the page when it comes back. Only removing the view lets it go.
        letPageGo()
    }

    /// Puts an idle tab to sleep, keeping its history, scroll and a snapshot.
    /// Unsent form input would be lost, so callers ask `unsaved` first.
    func sleep(picture: Data?) {
        guard let url = address, let built else { return }
        rested = Rested(url: url, state: built.interactionState, picture: picture)
        letPageGo()
    }

    /// Loads a resting tab. Returns whether there was one to wake; callers must
    /// not also `revive()` it, or two loads race for the same address.
    @discardableResult
    func wake() -> Bool {
        guard let rested else { return false }
        self.rested = nil
        freshPage()
        if let picture = rested.picture, let image = NSImage(data: picture) {
            cover = image
            // Gone even if the page never says it painted.
            uncover(after: 4)
        }
        load(rested.url, state: rested.state)
        return true
    }

    /// Whether the page holds unsent input. Pages that can't answer (PDFs,
    /// images, dead processes) say no.
    func unsaved(_ done: @escaping (Bool) -> Void) {
        guard let built else { return done(false) }
        built.evaluateInAppWorld("!!(window.__moteForms && window.__moteForms.unsaved && window.__moteForms.unsaved())") { value in
            MainActor.assumeIsolated { done((value as? Bool) == true) }
        }
    }

    /// A JPEG of the page, drawn by the web process so it works off screen.
    func snapshot(_ done: @escaping (Data?) -> Void) {
        guard let built else { return done(nil) }
        built.takeSnapshot(with: nil) { image, _ in
            guard let image = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return done(nil) }
            Task { done(await Task.detached(priority: .utility) { Tab.jpeg(image) }.value) }
        }
    }

    nonisolated private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let out = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.55] as CFDictionary)
        return CGImageDestinationFinalize(out) ? data as Data : nil
    }

    /// Takes the wake snapshot away, now or after `delay`, once the page has
    /// painted or been touched.
    func uncover(after delay: TimeInterval = 0) {
        guard let shown = cover else { return }
        guard delay > 0 else {
            cover = nil
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            if self?.cover === shown { self?.cover = nil }
        }
    }

    // MARK: - Crashes

    /// The view has an address but no document behind it.
    var hollow: Bool {
        guard address != nil else { return false }
        guard let there = built?.url else { return true }
        return there.absoluteString == "about:blank" && !asleep
    }

    /// The page's process died while it was on screen. Loads the address again
    /// rather than reloading, which needs what the dead process held.
    func recoverFromCrash() {
        guard let address else { return }
        failure = nil
        load(address)
    }

    /// Shown again after being in the background, where WebKit may have ended
    /// its process without telling a view out of its window. Any script call
    /// surfaces that, and the page loads again.
    func revive() {
        if stale {
            stale = false
            return recoverFromCrash()
        }
        guard !isBlank, !asleep, !loading, failure == nil else { return }
        // No document to reload.
        if hollow, let address { return web.open(address) }
        whenProcessDied { [weak self] in self?.recoverFromCrash() }
    }

    /// Runs `then` if the page's web process has terminated.
    private func whenProcessDied(_ then: @escaping () -> Void) {
        web.evaluateJavaScript("document.readyState") { _, error in
            MainActor.assumeIsolated {
                guard let error = error as NSError?, error.domain == WKErrorDomain,
                    error.code == WKError.webContentProcessTerminated.rawValue
                else { return }
                then()
            }
        }
    }

    /// Loads the page, or puts back a slept tab's state, then checks on it.
    ///
    /// It waits (up to about a second) for the view to be in a window: a page
    /// loaded off-window starts hidden, and some sites (x.com) wait to be seen
    /// and miss the change. `select()` wakes a tab a step before SwiftUI puts
    /// its view in the window. A load right after a crash or as a new view's
    /// first act sometimes silently stays on about:blank, so it is tried once more.
    private func load(_ url: URL, state: Any? = nil) {
        Task { [weak self] in
            for _ in 0..<50 {
                guard let self, self.web.window == nil else { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard let self else { return }
            if let state { web.interactionState = state } else { web.open(url) }
            try? await Task.sleep(for: .seconds(1.5))
            if built?.url?.absoluteString == "about:blank" { return web.open(url) }
            whenProcessDied { [weak self] in self?.web.open(url) }
        }
    }

    // MARK: - Closing

    /// Lets the page go so its timers, media and sockets stop.
    func close() {
        owner = nil
        leaveChat()
        // The tab is going away: stop any reply still coming, but keep the
        // chat itself until the tab is released.
        pageChat?.stop()
        letPageGo()
    }

    /// Ends the chat, stopping any reply still coming.
    private func leaveChat() {
        chat?.stop()
        chat = nil
        chats = false
    }

    /// Removes the web view, and with it the document WebKit would keep in its
    /// back-forward cache. The tab keeps its address; `web` makes a new view.
    private func letPageGo() {
        stale = false
        pull = nil
        watches = []
        sound.stop()
        guard let web = built else { return }
        built = nil
        let controller = web.configuration.userContentController
        Web.release(controller)
        controller.removeAllUserScripts()
        web.onPull = nil
        web.onTouch = nil
        web.searchName = nil
        web.onSearch = nil
        web.stopLoading()
        web.navigationDelegate = nil
        web.uiDelegate = nil
        web.removeFromSuperview()
    }
}

/// How far down a tab's page is scrolled, 0 to 1.
@MainActor
final class Reading: ObservableObject {
    @Published var fraction: Double = 0
}
