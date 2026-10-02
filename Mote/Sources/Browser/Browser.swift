import Combine
import MoteAI
import MoteCore
import SwiftUI
import WebKit

/// One window's browser: its row of tabs and which one is showing, plus the
/// models for everything drawn around and over the page.
///
/// Tab order follows `TabRow`'s rules. The address field, find in page,
/// passwords and camera prompts each have their own model; the extensions
/// in Browser+*.swift add navigation, downloads, element hiding and floating
/// video.
@MainActor
final class Browser: NSObject, ObservableObject {
    // MARK: - State

    @Published private(set) var tabs: [Tab] = []
    @Published var activeID: Tab.ID? {
        didSet {
            guard oldValue != activeID else { return }
            if let old = oldValue {
                tab(old)?.development?.stop()
                linkStatus.dismiss()
                // Tab sleep measures idle time from the moment a tab stops showing.
                tab(old)?.touch()
            }
            // A tab whose own panel is open shows the page it is on: coming to
            // it takes up its new page (see `syncPageChat`). A tab with a
            // closed panel is left alone.
            syncPageChat()
            active?.development?.resumeIfSelected()
        }
    }

    let prefs = Preferences()
    let linkStatus = LinkStatus()
    let history = History()
    let bookmarks = Bookmarks()
    let downloads = Downloads()
    let elementHider = ElementHider()
    let floater = FloatingVideo()

    let field = AddressEntry()
    let finder = PageFinder()
    let capture = CaptureRequests()
    private(set) lazy var logins = Logins(say: { [weak self] in self?.announce($0) }, tab: { [weak self] in self?.tab($0) })

    /// The address field is up over the page (⌘L). Blank tabs always show it.
    @Published var editing = false

    // Panels and modes shown over the window.
    @Published var tuning = false
    @Published var welcoming = false
    /// The arrival animation is playing over the window (see Arrival.swift).
    @Published var arriving = false
    @Published var bookmarking = false
    @Published var bookmarksOpen = false
    @Published var recalling = false
    @Published var showingDownloads = false
    /// The chat about the active page is docked on the window's trailing edge,
    /// the mirror of the sidebar (its width lives in `Preferences.chatWidth`).
    /// Whether it is open belongs to the tab, not the window (`Tab.chatOpen`),
    /// so each tab keeps its own state; see `chatting`. Kept in memory, like
    /// the other panel and mode flags (`showingDownloads`, `bookmarking`,
    /// `recalling`): Mote persists no panel visibility, and the kept page chats
    /// survive the session through their tabs, not a window flag.
    @Published var historyQuery = ""

    /// ⌘S collapses the sidebar; `peeking` slides it out over the page while
    /// collapsed (see SidebarFold.swift).
    @Published var folded = false
    @Published var peeking = false
    /// Fold and peek slides started, and the latest SwiftUI finished drawing
    /// (see `slidingFold`).
    var foldSlides = 0
    var foldLanded = 0
    /// Flipped to make the window draw again when a slide is stuck: the
    /// window's ground goes a shade less opaque, over the same colour.
    @Published var foldNudge = false
    /// A picture of the page laid over it while the chrome around it changes
    /// size (see `dissolvingPage`).
    @Published var pageVeil: NSImage?

    /// The tab whose page is in the floating video window. Clearing it also
    /// closes the window, so the two can't disagree.
    @Published var floating: Tab.ID? {
        didSet {
            guard floating == nil, floater.showing else { return }
            floater.drop()
        }
    }

    /// Element picking is on (see Browser+Hiding.swift).
    @Published var pickingElement = false
    /// The list of hidden elements for this site is shown.
    @Published var reviewing = false {
        didSet { if !reviewing { stopPeeking() } }
    }

    /// The pinned tab whose letter is being edited in place.
    @Published var editingPin: Tab.ID?
    /// The tab whose name is being edited in place, and the draft.
    @Published private(set) var editingTab: Tab.ID?
    @Published var tabDraft = ""

    /// A short message at the bottom of the window.
    @Published private(set) var announcement: Announcement?

    /// Recently closed tabs, for ⌘⇧T and the History menu.
    @Published private var closed = RecentlyClosed<Ghost>()
    var ghosts: [Ghost] { closed.entries }

    struct Ghost: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String
        let index: Int

        var label: String { title.isEmpty ? Address.displayString(for: url) : title }
    }

    /// All spaces, the current one, and the parked rows of the others (see
    /// Spaces.swift).
    @Published var spaces = Spaces.read() {
        didSet { Spaces.sharing = SpaceList(saved: spaces).sharing }
    }
    @Published var spaceID = Space.firstID
    var parked: [UUID: Parked] = [:]
    /// The space swipe's offset, and whether the new-space card is shown.
    @Published var spaceSwipe: CGFloat = 0
    @Published var makingSpace = false
    /// Direction of the last space change: 1 forward, -1 back.
    @Published var spaceStep = 1
    /// A link preview over the page (see LinkPeek.swift).
    @Published var peekTab: Tab?

    /// File names extensions asked for their downloads.
    var namedDownloads: [URL: String] = [:]
    /// Downloads in progress; tabs with one don't sleep.
    var downloading: [WKDownload] = []
    /// Idle tab sleep timer and memory pressure source (see Browser+TabSleep.swift).
    var dozing: Timer?
    var pressure: DispatchSourceMemoryPressure?
    /// Updates Chrome Web Store pages as extensions come and go (see WebStoreBridge.swift).
    var storeWatch: AnyCancellable?
    /// The video was floated because the app went to the background, so it
    /// comes back by itself (see Browser+Floating.swift).
    var floatedAway = false

    /// The most recently active window. macOS stops reporting a main window
    /// once the app is in the background.
    static weak var front: Browser?

    var bag = Set<AnyCancellable>()
    private var hush: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    var zoomShown = 100

    // MARK: - Reading

    var active: Tab? { activeID.flatMap(tab) }
    var fieldShowing: Bool { editing || active?.isStart ?? true }
    /// A page the chat can be opened over: a tab showing a page, not a new
    /// tab, a chat, or the list of kept chats.
    var pageChatPossible: Bool { active.map { !$0.isBlank } ?? false }
    /// The chat about the active page is on screen. Derived from the active
    /// tab's own open state, so the panel follows the tab and a switch shows
    /// each tab's state: a tab whose panel is closed shows no panel.
    var chatting: Bool { active?.chatOpen == true }

    /// Opens or closes the chat about the page showing, on the active tab
    /// alone. Opening makes the chat, so it outlives the navigation from its
    /// first ask on, and takes up the page at once, on the fold spring the
    /// sidebar uses.
    func togglePageChat() {
        guard let tab = active, pageChatPossible else { return }
        if tab.chatOpen {
            slidingFold { tab.chatOpen = false }
        } else {
            tab.ensurePageChat()
            slidingFold { tab.chatOpen = true }
            syncPageChat()
        }
    }

    /// Takes up the page the active tab shows for the chat about it, as its
    /// panel opens or the tab with its panel open becomes active, so the chip
    /// never reads as unshared over a page the model can be told about. A tab
    /// whose own panel is closed takes up nothing. The page is taken at once
    /// with its address and title, so it shows on the panel's first frame, and
    /// its text is read after. A page already held — even one let go on
    /// purpose — is left as it is, so looking away and back does not share it
    /// again.
    func syncPageChat() {
        guard let tab = active, tab.chatOpen else { return }
        // The panel always has a chat to show over the visible page, so an
        // unreadable page still gets its calm note.
        tab.ensurePageChat()
        guard let address = tab.address, PageSharing.takesUp(address, chatting: true, holding: tab.pageChat?.page?.url)
        else { return }
        tab.attachPage(PageContext(url: address, title: tab.title))
        Task { [weak self, weak tab] in
            guard let self, let tab, self.active === tab, tab.chatOpen, let page = await tab.capturePageContext() else { return }
            // The person may have let the page go, closed the panel, or the
            // visible tab moved on, while it was read; then the page is left as
            // it is. A page they asked about by selecting its text is left as
            // it is too: the read must not drop that selection.
            guard self.active === tab, tab.chatOpen, tab.pageChat?.page?.isActive == true, PageSharing.isSamePage(page.url, tab.address),
                PageSharing.replaces(page.url, holding: tab.pageChat?.page?.url, selection: tab.pageChat?.page?.selection != nil)
            else { return }
            tab.attachPage(page)
        }
    }

    var pinnedCount: Int { row.pinnedCount }
    var recentlyVisited: [History.Entry] { history.recent() }

    func tab(_ id: Tab.ID) -> Tab? { tabs.first { $0.id == id } }
    func tab(for webView: WKWebView) -> Tab? { tabs.first { $0.built === webView } }

    /// The other tabs a chat may @-mention: this window's open, named tabs,
    /// except the one given and any already mentioned. Blank tabs, which have
    /// no page to share, are left out. Read-only: the chat does the mentioning.
    func mentionCandidates(excluding tab: Tab?, mentioned: Set<URL> = []) -> [MentionMenu.Candidate] {
        tabs.compactMap { other in
            guard other.id != tab?.id, !other.isBlank, let url = other.address, !mentioned.contains(url) else { return nil }
            let title = other.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return MentionMenu.Candidate(
                id: other.id.uuidString,
                title: title.isEmpty ? (url.host() ?? url.absoluteString) : title,
                host: url.host() ?? "")
        }
    }

    private var row: TabRow<Tab> { TabRow(tabs, isPinned: { $0.pin != nil }) }

    /// Changes the tab order under `TabRow`'s rules.
    @discardableResult
    private func reorder<Result>(_ change: (inout TabRow<Tab>) -> Result) -> Result {
        var next = row
        let result = change(&next)
        if next.tabs.map(\.id) != tabs.map(\.id) { tabs = next.tabs }
        return result
    }

    // MARK: - Starting

    override init() {
        super.init()
        AdBlocker.shared.enabled = prefs.shielded
        AdBlocker.shared.compile()
        if #available(macOS 15.4, *) { Extensions.shared.start(for: self) }
        if prefs.bench {
            Bench.shared.start(for: self)
        } else if prefs.benchRefused {
            announce("“Let a script drive Mote” was turned on outside Settings, and stays off")
        }
        welcoming = !prefs.welcomed
        folded = prefs.sidebar && prefs.sideHides
        Updater.shared.checkIfDue { [weak self] news in self?.tell(news) }
        FormRelay.passkeysOffered = prefs.passkeys

        field.suggest = { [weak self] typed, switching in self?.suggestions(for: typed, switching: switching) ?? ([], nil) }
        finder.page = { [weak self] in self?.active?.web }

        // Menus are rebuilt from this object's changes, so pass on those of
        // history, bookmarks and preferences.
        for source in [history.objectWillChange, bookmarks.objectWillChange, prefs.objectWillChange] {
            source.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        }
        Favicons.shared.arrived = { [weak self] host, image in
            for tab in self?.tabs ?? [] where tab.address?.host()?.lowercased() == host { tab.icon = image }
        }
        wireFloater()

        Spaces.sweep()
        Spaces.sharing = SpaceList(saved: spaces).sharing
        if prefs.usesSpaces, let last = Storage.settings.string(forKey: "space.current").flatMap(UUID.init),
            spaces.contains(where: { $0.id == last })
        {
            spaceID = last
            Spaces.current = last
        }
        restoreSession()
        if prefs.usesSpaces { preloadSpaces() }
        follow()
        watchForSleep()
    }

    /// Restores the current space's tabs, or opens one blank tab.
    func restoreSession() {
        let saved = Session.read(space: spaceID)
        let restored = saved.tabs.compactMap { entry -> Tab? in
            let tab = Tab()
            return restore(entry, in: tab) ? tab : nil
        }
        guard !restored.isEmpty else {
            let tab = Tab()
            adopt(tab)
            // Build the blank tab's web view a second after launch, so its web
            // process is ready for the first navigation without slowing the first frame.
            Task { [weak tab] in
                try? await Task.sleep(for: .seconds(1))
                if let tab, tab.isBlank { _ = tab.web }
            }
            return
        }
        tabs = restored
        let here = min(max(0, saved.active), restored.count - 1)
        activeID = restored[here].id
        // Only the active tab loads; the rest wait until they are opened.
        restored[here].wake()
    }

    /// Side effects of preferences that change while the window is open.
    private func follow() {
        followStore()
        func on<Value>(_ publisher: Published<Value>.Publisher, _ act: @escaping (Browser, Value) -> Void) {
            publisher.dropFirst().sink { [weak self] value in self.map { act($0, value) } }.store(in: &bag)
        }
        on(prefs.$usesSpaces) { browser, on in on ? browser.preloadSpaces() : browser.leaveSpaces() }
        on(prefs.$shielded) { browser, on in
            AdBlocker.shared.enabled = on
            AdBlocker.shared.apply(to: browser.tabs.compactMap { $0.built?.configuration.userContentController })
            browser.announce(on ? "Ads and trackers blocked" : "Blocking off — reload to see the difference")
        }
        on(prefs.$look) { browser, _ in browser.refreshIconsSoon() }
        on(prefs.$bench) { browser, on in
            if on { Bench.shared.start(for: browser) } else { Bench.shared.stop() }
            browser.announce(on ? "Scripts can drive Mote — see ./bench" : "The bench is closed")
        }
        on(prefs.$autoScroll) { browser, on in
            browser.rearmAll(including: browser.parkedTabs) { $0.evaluateInAppWorld(on ? AutoScroll.script : AutoScroll.off) }
        }
        on(prefs.$showsLinks) { browser, on in
            if !on { browser.linkStatus.dismiss() }
            browser.rearmAll(including: browser.parkedTabs) {
                $0.evaluateJavaScript(on ? HoveredLink.script : HoveredLink.off, in: nil, in: .defaultClient)
            }
        }
        on(prefs.$passkeys) { browser, on in
            FormRelay.passkeysOffered = on
            browser.rearmAll()
            browser.announce(on ? "Passkeys offered again — reload the page" : "Sites will ask for a password instead")
        }
        on(prefs.$autocorrect) { browser, on in browser.setAutocorrect(on) }

        DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in if self?.prefs.look == .system { self?.refreshIconsSoon() } }
            .store(in: &bag)
    }

    /// Favicons come in light and dark versions; fetch them again once a new
    /// appearance has taken effect.
    private func refreshIconsSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard let self else { return }
            Favicons.shared.relook(tabs.filter { !$0.asleep })
        }
    }

    /// Re-arms every tab's next document with its site's hidden elements (an
    /// empty stylesheet would unhide them all), then runs `now` on the pages
    /// already built.
    private func rearmAll(including extra: [Tab] = [], now: ((WKWebView) -> Void)? = nil) {
        for tab in tabs + extra {
            tab.arm(hiding: elementHider.hiding(on: Address.siteHost(of: tab.address)))
            if let now, let web = tab.built { now(web) }
        }
    }

    /// WebKit reads the autocorrect default once at launch; at run time only
    /// the Edit menu's toggle action switches it, and it only toggles.
    private func setAutocorrect(_ on: Bool) {
        guard let web = active?.web else { return }
        let toggle = NSSelectorFromString("toggleAutomaticSpellingCorrection:")
        guard web.responds(to: toggle) else { return }
        if UserDefaults.standard.bool(forKey: "WebAutomaticSpellingCorrectionEnabled") != on { web.perform(toggle, with: nil) }
        Preferences.tellWebKit(autocorrect: on)
        announce(on ? "Autocorrect on" : "Autocorrect off")
    }

    // MARK: - Session

    /// Puts a saved tab back: a page, which loads when opened, or a kept chat.
    private func restore(_ entry: Session.Entry, in tab: Tab) -> Bool {
        if let id = entry.chat.flatMap(UUID.init(uuidString:)) {
            guard let chat = Assistant.shared.reopen(id) else { return false }
            prepare(tab)
            tab.chat = chat
            tab.name = entry.name
            tab.pin = entry.pin
            return true
        }
        guard let url = URL(string: entry.url) else { return false }
        prepare(tab)
        tab.restore(url: url, title: entry.title, name: entry.name)
        tab.pin = entry.pin
        return true
    }

    func writeSession(now: Bool = false) {
        let entries = tabs.compactMap { tab -> Session.Entry? in
            if !tab.shy, !tab.bench, tab.isBlank, let chat = tab.chat, !chat.messages.isEmpty {
                return Session.Entry(url: "", title: chat.title, pin: tab.pin, name: tab.name, chat: chat.id.uuidString)
            }
            guard !tab.shy, !tab.bench,
                // A sleeping tab's address is in `pending`, never its released page's.
                let url = tab.pending ?? tab.address, url.scheme?.hasPrefix("http") == true
            else { return nil }
            return Session.Entry(url: url.absoluteString, title: tab.title, pin: tab.pin, name: tab.name)
        }
        Session.write(now: now, space: spaceID, .init(tabs: entries, active: tabs.firstIndex { $0.id == activeID } ?? 0))
    }

    /// Saves the session a moment after the last of a burst of changes.
    private func saveSoon() {
        guard saving == nil else { return }
        saving = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.saving = nil
            self?.writeSession()
        }
    }

    /// Writes the session at once, on quit.
    func flushSession() {
        writeSession(now: true)
        Assistant.shared.chats.flush()
    }

    // MARK: - Opening tabs

    func newTab() {
        // A new tab from a private tab is private too, so nothing leaks into history.
        if active?.shy == true { return newShyTab() }
        if #available(macOS 15.4, *), let page = Extensions.shared.newTabPage {
            open(page, foreground: true)
            field.switching = false
            saveSoon()
            return
        }
        let tab = Tab()
        show(tab, adopting: true)
        saveSoon()
        if #available(macOS 15.4, *) { Extensions.shared.offerNewTabPage(into: tab) }
    }

    /// ⌘⇧N: a tab that keeps nothing.
    func newShyTab() {
        show(Tab(shy: true), adopting: true)
        announce("A tab that keeps nothing")
    }

    /// Puts a fresh blank tab in front with the field ready for typing.
    func show(_ tab: Tab, adopting: Bool) {
        if adopting { adopt(tab) }
        floatActiveVideo()
        activeID = tab.id
        field.clear()
        editing = false
        field.askFocus()
    }

    /// Opens `url` in a new tab next to the current one, or at the end when
    /// `atEnd` is set (batches keep their order that way). Links from a private
    /// tab open in a private tab sharing its store.
    @discardableResult
    func open(_ url: URL, foreground: Bool, atEnd: Bool = false, from source: Tab? = nil) -> Tab {
        let url = Browser.page(url)
        let page = Browser.extensionConfiguration(for: url)
        let tab =
            if let source, source.shy, page == nil {
                Tab(shy: true, configuration: Web.configuration(shy: true, store: source.store))
            } else {
                Tab(configuration: page)
            }
        prepare(tab)
        reorder { $0.insert(tab, at: atEnd ? $0.tabs.count : $0.slotForNew(after: activeID)) }
        tab.go(to: url)
        if foreground { bringForward(tab) }
        return tab
    }

    /// Opens a tab for the bench, at the end and in the background.
    @discardableResult
    func benchOpen(_ url: URL) -> Tab {
        let url = Browser.page(url)
        let tab = Tab(bench: true, configuration: Browser.extensionConfiguration(for: url))
        prepare(tab)
        reorder { $0.append(tab) }
        tab.go(to: url)
        return tab
    }

    /// A link from another app: into the current tab if it is blank and
    /// nothing is typed, otherwise a new tab in front.
    func arrive(_ url: URL) {
        if let active, active.isStart, field.typed.isEmpty, !active.floating {
            active.go(to: url)
            editing = false
        } else {
            open(url, foreground: true)
        }
    }

    /// A bookmark: into the current tab, or a new one with ⌘ held or while the
    /// current tab's video floats.
    func visit(_ url: URL) {
        let apart = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        if let active, !apart, !active.floating {
            go(active, to: url)
        } else {
            open(url, foreground: true, from: active)
        }
    }

    /// Opens a bookmark and closes the bookmark menu and manager.
    func pickBookmark(_ url: URL) {
        bookmarking = false
        bookmarksOpen = false
        visit(url)
    }

    /// ⌘D.
    func duplicate() {
        guard let url = active?.address else { return }
        open(url, foreground: true, from: active)
    }

    /// ⌘⇧V outside text: the clipboard as an address or a search, in this tab.
    func pasteAndGo() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = destination(for: text), let tab = active ?? tabs.first else { return field.refuse() }
        go(tab, to: url)
    }

    /// Links dropped on the tab row open as new tabs.
    func take(_ providers: [NSItemProvider]) -> Bool {
        var took = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                took = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in self.open(url, foreground: true) }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                took = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let url = text.flatMap(Address.url(from:)) else { return }
                    Task { @MainActor in self.open(url, foreground: true) }
                }
            }
        }
        return took
    }

    /// Adds a tab made outside the row, such as a kept link preview.
    func insert(_ tab: Tab, at index: Int) {
        reorder { $0.insert(tab, at: index) }
        saveSoon()
    }

    /// Where a new tab would go.
    func placeForNew() -> Int { row.slotForNew(after: activeID) }

    /// Adds a tab at the end; the first tab becomes the active one.
    func adopt(_ tab: Tab) {
        prepare(tab)
        reorder { $0.append(tab) }
        if activeID == nil { activeID = tab.id }
    }

    /// Makes a tab that just opened the one showing.
    func bringForward(_ tab: Tab) {
        floatActiveVideo()
        activeID = tab.id
        editing = false
        field.clear()
    }

    /// Loads `url` in `tab` and puts the field away.
    func go(_ tab: Tab, to url: URL) {
        tab.go(to: url)
        editing = false
        field.clear()
    }

    // MARK: - Switching

    func select(_ tab: Tab) {
        if peekTab != nil, tab.id != activeID { closePeek() }
        cancelTabEdit()
        field.switching = false
        logins.dropChoices()
        guard tab.id != activeID else { return }
        if floating == tab.id { land() }
        floatActiveVideo()
        activeID = tab.id
        tab.touch()
        // Load a waiting tab now; only when there was nothing to wake, check
        // whether a background page's process died (doing both races two loads).
        if !tab.wake() { tab.revive() }
        saveSoon()
        editing = false
        field.clear()
    }

    func select(index: Int) {
        guard tabs.indices.contains(index) else { return }
        select(tabs[index])
    }

    /// ⌃Tab and ⌃⇧Tab.
    func step(_ direction: Int) {
        guard let id = activeID, let next = row.neighbour(of: id, by: direction).flatMap(tab) else { return }
        select(next)
    }

    /// Drag and drop within the row; tabs stay in their section.
    func move(_ tab: Tab, to index: Int) {
        if reorder({ $0.move(tab.id, to: index) }) { saveSoon() }
    }

    /// Shows another space's row in place of this one (see Spaces.swift).
    func showRow(_ row: [Tab], active: Tab.ID?) {
        tabs = row
        activeID = active ?? row.first?.id
    }

    /// Builds a space's row from its saved session without touching the
    /// current one. Its tabs wait and cost little until opened.
    func loadRow(_ space: UUID) -> Parked {
        let saved = Session.read(space: space)
        let row = saved.tabs.compactMap { entry -> Tab? in
            let tab = Tab(configuration: Web.configuration(space: space))
            return restore(entry, in: tab) ? tab : nil
        }
        return Parked(tabs: row, active: row.indices.contains(saved.active) ? row[saved.active].id : row.first?.id)
    }

    // MARK: - Closing

    /// ⌘W or a tab's close button. The last tab is replaced by a blank one;
    /// closing that blank tab closes the window. A pinned tab only lets go of
    /// its page and stays in the row; Unpin removes it.
    func close(_ tab: Tab) {
        guard let index = row.index(of: tab.id) else { return }
        if floating == tab.id { land() }

        if tab.pin != nil {
            tab.rest()
            // Prefer the most recent unpinned tab, so ⌘W doesn't bounce between pins.
            let awake = tabs.filter { $0.id != tab.id && !$0.asleep }
            let loose = awake.filter { $0.pin == nil }
            if let back = (loose.isEmpty ? awake : loose).max(by: { $0.touched < $1.touched }) {
                select(back)
            } else {
                newTab()
            }
            writeSession(now: true)
            return
        }

        if tabs.count == 1 {
            guard !tab.isStart else {
                NSApp.keyWindow?.performClose(nil)
                return
            }
            remember(tab, at: 0)
            tab.close()
            let fresh = Tab()
            prepare(fresh)
            tabs = [fresh]
            activeID = fresh.id
            field.clear()
            return
        }

        remember(tab, at: index)
        tab.close()
        reorder { $0.remove(tab.id) }
        if activeID == tab.id, let next = row.successor(ofRemovedAt: index).flatMap(self.tab) {
            // Through select(), so a waiting tab wakes.
            select(next)
        }
        saveSoon()
    }

    /// Closes every other tab; pinned ones are put to rest instead.
    func closeOthers(but keep: Tab) {
        select(keep)
        for tab in tabs where tab.id != keep.id { close(tab) }
        select(keep)
    }

    /// ⌘⇧T.
    func reopen() {
        if let ghost = closed.last { reopen(ghost) }
    }

    /// Reopens a closed tab where it was.
    func reopen(_ ghost: Ghost) {
        closed.remove(ghost.id)
        let tab = Tab()
        prepare(tab)
        reorder { $0.insert(tab, at: ghost.index) }
        bringForward(tab)
        tab.go(to: ghost.url)
    }

    private func remember(_ tab: Tab, at index: Int) {
        guard !tab.shy, let url = tab.address else { return }
        closed.push(Ghost(url: url, title: tab.title, index: index))
    }

    /// Replaces a tab when it crosses between the web and extension pages
    /// (an extension page sending its tab to a website, say). WebKit keeps a
    /// web view made for an extension to that extension's pages, so the load
    /// would otherwise fail silently.
    func replace(_ tab: Tab, going url: URL) {
        let page = Browser.extensionConfiguration(for: url)
        let fresh =
            if tab.shy {
                // A private tab stays private; leaving an extension page, whose
                // store is the extension's, needs a new private store.
                Tab(
                    shy: true, bench: tab.bench,
                    configuration: page ?? Web.configuration(shy: true, store: tab.store.isPersistent ? nil : tab.store))
            } else {
                Tab(bench: tab.bench, configuration: page)
            }
        prepare(fresh)
        // The tab continues, so it keeps its panel's open state; the chat
        // itself is not carried (the replacement tab starts one), which matches
        // the window-wide flag this state replaced.
        fresh.chatOpen = tab.chatOpen
        reorder { $0.replace(tab.id, with: fresh) }
        fresh.go(to: url)
        if activeID == tab.id { activeID = fresh.id }
        tab.close()
        saveSoon()
    }

    /// Replaces a blank tab with one for an extension's new tab page, which
    /// needs a web view made from the extension's configuration.
    func replaceBlank(_ tab: Tab, with url: URL) {
        let url = Browser.page(url)
        let page = Tab(configuration: Browser.extensionConfiguration(for: url))
        prepare(page)
        reorder { $0.replace(tab.id, with: page) }
        page.go(to: url)
        if activeID == tab.id {
            activeID = page.id
            editing = false
        }
    }

    // MARK: - Pinning and naming

    func pin(_ tab: Tab) {
        if tab.pin == nil {
            tab.pin = tab.monogram
            reorder { $0.settle(tab.id) }
        }
        writeSession(now: true)
    }

    func unpin(_ tab: Tab) {
        if editingPin == tab.id { editingPin = nil }
        tab.pin = nil
        reorder { $0.settle(tab.id) }
        writeSession(now: true)
    }

    /// Change Letter, or a double-click on a pinned tab.
    func editLetter(_ tab: Tab) {
        if tab.pin != nil { editingPin = tab.id }
    }

    /// The first typed character becomes the letter; nothing typed keeps it.
    func letter(_ typed: String, for tab: Tab) {
        if let first = typed.trimmingCharacters(in: .whitespacesAndNewlines).first { tab.pin = String(first).uppercased() }
    }

    func endPinEdit() {
        guard editingPin != nil else { return }
        editingPin = nil
        writeSession(now: true)
    }

    /// Starts renaming with the current label; an empty name brings back the
    /// page title.
    func beginTabRename(_ tab: Tab) {
        tabDraft = tab.label
        editingTab = tab.id
    }

    func commitTabEdit() {
        guard let tab = editingTab.flatMap(tab) else { return }
        let name = tabDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.name = name.isEmpty ? nil : name
        cancelTabEdit()
        writeSession(now: true)
    }

    func cancelTabEdit() {
        editingTab = nil
        tabDraft = ""
    }

    /// A click elsewhere keeps the name, as Return would.
    func finishTabEdit() {
        if editingTab != nil { commitTabEdit() }
    }

    // MARK: - Extension pages

    /// Moves an extension URL from the old scheme to chrome-extension://;
    /// other URLs come back unchanged.
    static func page(_ url: URL) -> URL {
        if #available(macOS 15.4, *) { return Extensions.unpopped(Extensions.current(url)) }
        return url
    }

    /// The extension a URL belongs to, or nil for the web.
    static func extensionHost(of url: URL) -> String? {
        guard #available(macOS 15.4, *) else { return nil }
        let url = Extensions.current(url)
        return url.scheme == Extensions.scheme ? url.host : nil
    }

    /// The web view configuration an extension page needs (extension pages
    /// are only served to web views made from it), or nil for the web.
    static func extensionConfiguration(for url: URL) -> WKWebViewConfiguration? {
        guard #available(macOS 15.4, *) else { return nil }
        let url = Extensions.current(url)
        guard url.scheme == Extensions.scheme else { return nil }
        return Extensions.shared.controller.extensionContext(for: url)?.webViewConfiguration
    }

    // MARK: - Wiring a tab

    /// Makes this window the tab's owner and delegate.
    func prepare(_ tab: Tab) {
        tab.delegate = self
        tab.owner = self
        tab.$address.dropFirst().sink { [weak self] _ in self?.saveSoon() }.store(in: &bag)
        // The panel's open state lives on the tab, but the chrome, the toolbar
        // and the menu read it through this object (`chatting`); pass the tab's
        // changes on so they redraw when the active tab's panel opens or closes.
        tab.$chatOpen.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        tab.$title.dropFirst()
            .sink { [weak self, weak tab] title in
                guard let tab, !tab.shy, let url = tab.address else { return }
                self?.history.retitle(url, title)
            }
            .store(in: &bag)
    }

    // MARK: - Messages

    func announce(_ text: String) { announce(Announcement(text)) }

    /// Shows a message for a moment: longer when it has something to do or
    /// more to say, and for as long as the pointer rests on it.
    func announce(_ message: Announcement) {
        announcement = message
        hushLater()
    }

    /// An update, with the way to Settings › About, where it's handled.
    func tell(_ news: Updater.News) {
        let settings = Announcement.Action(title: "Open Settings") { [weak self] in self?.openSettings(at: .about) }
        switch news {
        case .out(let release):
            announce(
                Announcement(
                    "Mote \(release.version) is here", detail: release.notes ?? "Install it whenever suits you.", symbol: "sparkles",
                    action: settings))
        case .ready(let release):
            announce(
                Announcement(
                    "Mote \(release.version) is ready", detail: "It takes over the next time you open Mote.", symbol: "checkmark.seal",
                    action: settings))
        case .manual(let release):
            announce(
                Announcement(
                    "Mote \(release.version) is here", detail: "This copy can't update itself; Settings has the download.",
                    symbol: "arrow.down.circle", action: settings))
        }
    }

    /// Settings, on the given page, even if it's open on another.
    func openSettings(at page: SettingsPage) {
        Storage.settings.set(page.rawValue, forKey: "settings.page")
        guard tuning else { return tuning = true }
        tuning = false
        DispatchQueue.main.async { [weak self] in self?.tuning = true }
    }

    /// The pointer on the message holds it; leaving lets it go.
    func holdAnnouncement(_ held: Bool) {
        hush?.cancel()
        if !held { hushLater() }
    }

    func dismissAnnouncement() {
        hush?.cancel()
        announcement = nil
    }

    private func hushLater() {
        guard let showing = announcement else { return }
        hush?.cancel()
        hush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(showing.lasts))
            if !Task.isCancelled, self?.announcement == showing { self?.announcement = nil }
        }
    }

    /// Ends the first-launch setup and hands the keyboard to the address field.
    func finishWelcome() {
        prefs.welcomed = true
        withAnimation(Motion.settle) { welcoming = false }
        field.askFocus()
    }
}

// MARK: - What tabs report

extension Browser: TabOwner {
    func tab(_ tab: Tab, hovers link: String?) {
        if prefs.showsLinks, tab.id == activeID { linkStatus.show(link, over: tab.built) }
    }

    /// The announcement line doubles as the zoom level.
    func tab(_ tab: Tab, zoomedTo level: CGFloat) {
        let percent = Int((level * 100).rounded())
        guard percent != zoomShown else { return }
        zoomShown = percent
        announce("\(percent)%")
    }

    func tab(_ tab: Tab, hid selector: String, label: String, note: String) { hide(selector, label: label, note: note, in: tab) }
    func tabStoppedPicking(_ tab: Tab) { pickingElement = false }
    func tab(_ tab: Tab, couldNotHide reason: String) { announce("Couldn't hide that — \(reason)") }

    func tab(_ tab: Tab, focusedSignInAt spot: CGRect?) {
        logins.fieldFocused(in: tab, at: spot, listing: prefs.fillsPasswords && tab.id == activeID)
    }

    func tab(_ tab: Tab, signedIn sent: SentSignIn) {
        guard prefs.savesPasswords, !tab.shy else { return }
        // A password manager extension has taken over saving.
        if #available(macOS 15.4, *), Extensions.shared.passwordSavingTakenBy != nil { return }
        logins.signedIn(host: sent.host, user: sent.user, password: sent.password, clear: sent.clear)
    }

    func tab(_ tab: Tab, openedImageMenuFor image: URL) { showImageMenu(for: tab, at: image) }

    /// Searches from a private tab stay private.
    func tab(_ tab: Tab, searches text: String) {
        if let url = searchURL(for: text) { open(url, foreground: true, from: tab) }
    }

    var searchEngineName: String? { prefs.engine.name(custom: prefs.customEngine) }
    func tabAddsFromStore(_ tab: Tab) { addFromStore(tab) }
    func tab(_ tab: Tab, middleClicked link: URL) { open(link, foreground: false, from: tab) }
    func tab(_ tab: Tab, crosses url: URL) { replace(tab, going: url) }
}
