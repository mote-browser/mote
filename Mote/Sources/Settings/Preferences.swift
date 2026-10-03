import Combine
import MoteCore
import Security
import SwiftUI

/// How tabs are marked, pinned ones included: by letter or by the site's icon.
enum Glyph: String, CaseIterable, Identifiable, Storable {
    case letters, icons

    var id: String { rawValue }
    var title: String { self == .letters ? "Letters" : "Site icons" }
}

extension Look: Storable {}
extension SearchEngine: Storable {}

/// The settings. Each is kept in the settings store under its key; `init`
/// says which key, and what else follows a change.
@MainActor
final class Preferences: ObservableObject {
    // Look
    @Published var look: Look
    /// Tabs down a sidebar rather than across the top.
    @Published var sidebar: Bool
    /// The sidebar hides unless the pointer is at the left edge, not only
    /// after ⌘S (see SidebarFold.swift).
    @Published var sideHides: Bool
    /// Last manual fold, stored separately for each tab layout.
    @Published var sidebarFolded: Bool
    @Published var stripFolded: Bool
    /// Set by dragging the sidebar's edge.
    @Published var sideWidth: CGFloat
    /// Set by dragging the page chat panel's edge; it docks on the window's
    /// trailing edge, the mirror of the sidebar.
    @Published var chatWidth: CGFloat
    @Published var glyph: Glyph
    @Published var bookmarksBar: Bool
    /// The tab's reading bar.
    @Published var showsReading: Bool
    /// The toolbar shows the page's whole address; off, only its site.
    @Published var showsFullAddress: Bool

    // Searching and pages
    @Published var engine: SearchEngine
    @Published var customEngine: String
    /// macOS autocorrect in pages.
    @Published var autocorrect: Bool
    /// Middle-click autoscroll, as on Windows (see AutoScroll.swift).
    @Published var autoScroll: Bool
    /// 120 Hz pages on ProMotion displays (see FrameRate.swift).
    @Published var fastPages: Bool
    /// Shift-click previews a link over the page (see LinkPeek.swift).
    @Published var peeksLinks: Bool
    /// Links from other apps open in a small window (see LinkWindow.swift).
    @Published var littleLinks: Bool
    /// The hovered link's address at the bottom of the page (see StatusLine.swift).
    @Published var showsLinks: Bool

    // Tabs and video
    /// Tabs idle for half an hour let their page go and keep their place.
    @Published var sleepsTabs: Bool
    /// Separate sets of tabs with their own website data (see Spaces.swift).
    @Published var usesSpaces: Bool
    /// A two-finger flick sends the floating video to a corner.
    @Published var floatFlicks: Bool
    /// A playing video floats when another app comes forward, and docks when
    /// Mote does (see `Browser.appLeft`).
    @Published var floatsAway: Bool
    /// A playing video floats when you go to another tab.
    @Published var floatsOnLeave: Bool

    // Privacy and passwords
    /// The ad blocker.
    @Published var shielded: Bool
    /// Extensions in private tabs; they can watch pages, so off unless asked for.
    @Published var extensionsInPrivate: Bool
    /// Sites are offered passkeys; off, they fall back to passwords, as builds
    /// without Apple's browser entitlement need.
    @Published var passkeys: Bool
    @Published var savesPasswords: Bool
    /// Saved accounts listed under sign-in fields.
    @Published var fillsPasswords: Bool

    // Downloads and updates
    @Published var downloads: URL
    @Published var asksWhereToSave: Bool
    /// Updates install on their own; when off they're still looked for daily
    /// and wait for Install in Settings.
    @Published var installsUpdates: Bool

    // First launch and scripts
    @Published var welcomed: Bool
    /// The local automation socket (the bench). Turning it on in Settings
    /// records the consent launch asks for (see `Bench.Consent`).
    @Published var bench: Bool
    /// The bench was on at launch without consent, and has been turned off.
    let benchRefused: Bool
    /// The build can offer passkeys, for as long as Mote runs.
    let passkeysPossible = Preferences.entitledToPasskeys

    private var saving = Set<AnyCancellable>()

    init() {
        let store = Storage.settings
        look = store.value("look", or: .system)
        // Older versions kept the layout as "manner".
        sidebar = store.object(forKey: "sidebar") as? Bool ?? (store.string(forKey: "manner") == "side")
        sideHides = store.value("sidebar.hides", or: false)
        sidebarFolded = store.value("sidebar.folded", or: store.value("sidebar.hides", or: false))
        stripFolded = store.value("strip.folded", or: false)
        sideWidth = min(Metrics.sideMax, max(Metrics.sideMin, store.value("sidebar.width", or: Metrics.side)))
        chatWidth = min(Metrics.chatMax, max(Metrics.chatMin, store.value("chat.width", or: Metrics.chat)))
        // Installs from before the welcome existed already have settings, and skip it.
        welcomed = store.value("welcomed", or: false) || store.object(forKey: "glyph") != nil
        glyph = store.value("glyph", or: .letters)
        bookmarksBar = store.value("bookmarks.bar", or: false)
        showsReading = store.value("tabs.reading", or: true)
        showsFullAddress = store.value("address.full", or: true)
        engine = store.value("search.engine", or: .standard)
        customEngine = store.value("search.custom", or: "")
        autocorrect = store.value("autocorrect", or: false)
        autoScroll = store.value("autoscroll", or: false)
        fastPages = store.value("pages.120", or: false)
        peeksLinks = store.value("links.peek", or: false)
        littleLinks = store.value("links.little", or: false)
        showsLinks = store.value("links.show", or: false)
        sleepsTabs = store.value("tabs.sleep", or: true)
        usesSpaces = store.value("spaces", or: false)
        floatFlicks = store.value("float.flicks", or: false)
        floatsAway = store.value("float.away", or: false)
        floatsOnLeave = store.value("float.leave", or: true)
        shielded = store.value("shield", or: true)
        extensionsInPrivate = store.value("extensions.private", or: false)
        savesPasswords = store.value("passwords.save", or: true)
        fillsPasswords = store.value("passwords.fill", or: true)
        asksWhereToSave = store.value("downloads.ask", or: false)
        installsUpdates = store.value(Updater.installKey, or: true)
        // Test runs keep downloads in their own folder, clear of macOS's prompt for ~/Downloads.
        downloads = Storage.testing ? Preferences.testDownloads : store.value("downloads", or: .downloadsDirectory)

        // The bench needs recorded consent, except in test runs.
        let scripted = store.bool(forKey: "bench")
        let allowed = scripted && (Storage.testing || Bench.Consent.given)
        bench = allowed
        benchRefused = scripted && !allowed
        if benchRefused { store.set(false, forKey: "bench") }

        // On in entitled builds, and on an entitled build's first run whatever
        // was saved; after that, as the user left it.
        let entitled = Preferences.entitledToPasskeys
        let firstEntitledRun = entitled && !store.bool(forKey: "passkeys.entitled")
        passkeys = firstEntitledRun ? true : store.value("passkeys", or: entitled)
        if firstEntitledRun { store.set(true, forKey: "passkeys") }
        store.set(entitled, forKey: "passkeys.entitled")

        for gone in ["inspector", "mind.model", "mind.effort", "mind.acting", "mind.width", "mind.open"] {
            store.removeObject(forKey: gone)
        }

        // Before the first window and the first page: the appearance, and what
        // WebKit and the page scripts read once.
        // `NSApplication.shared`: on macOS 14 `NSApp` is still nil here.
        NSApplication.shared.appearance = look.appearance
        Preferences.tellWebKit(autocorrect: autocorrect)
        HoveredLink.on = showsLinks
        AutoScroll.on = autoScroll
        FrameRate.fast = fastPages
        FloatingVideo.flicks = floatFlicks

        keep($look, "look") { $0.apply() }
        keep($sidebar, "sidebar")
        keep($sideHides, "sidebar.hides") { [weak self] hides in
            if self?.sidebar == true { self?.sidebarFolded = hides }
        }
        keep($sidebarFolded, "sidebar.folded")
        keep($stripFolded, "strip.folded")
        keep($sideWidth, "sidebar.width")
        keep($chatWidth, "chat.width")
        keep($glyph, "glyph")
        keep($bookmarksBar, "bookmarks.bar")
        keep($showsReading, "tabs.reading")
        keep($showsFullAddress, "address.full")
        keep($engine, "search.engine")
        keep($customEngine, "search.custom")
        keep($autocorrect, "autocorrect") { Preferences.tellWebKit(autocorrect: $0) }
        keep($autoScroll, "autoscroll") { AutoScroll.on = $0 }
        keep($fastPages, "pages.120") { FrameRate.fast = $0 }
        keep($peeksLinks, "links.peek")
        keep($littleLinks, "links.little")
        keep($showsLinks, "links.show") { HoveredLink.on = $0 }
        keep($sleepsTabs, "tabs.sleep")
        keep($usesSpaces, "spaces")
        keep($floatFlicks, "float.flicks") { FloatingVideo.flicks = $0 }
        keep($floatsAway, "float.away")
        keep($floatsOnLeave, "float.leave")
        keep($shielded, "shield")
        keep($extensionsInPrivate, "extensions.private")
        keep($passkeys, "passkeys")
        keep($savesPasswords, "passwords.save")
        keep($fillsPasswords, "passwords.fill")
        keep($downloads, "downloads")
        keep($asksWhereToSave, "downloads.ask")
        keep($installsUpdates, Updater.installKey) { if $0 { Updater.shared.install() } }
        keep($welcomed, "welcomed")
        keep($bench, "bench") { $0 ? Bench.Consent.grant() : Bench.Consent.revoke() }
    }

    /// Saves every later change under `key`, then does `then`.
    private func keep<Value: Storable>(_ changes: Published<Value>.Publisher, _ key: String, then: ((Value) -> Void)? = nil) {
        changes.dropFirst()
            .sink { value in
                Storage.settings.set(value.stored, forKey: key)
                then?(value)
            }
            .store(in: &saving)
    }

    private static var testDownloads: URL {
        let folder = Storage.folder.appending(path: "Downloads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Whether this process's signature carries the passkey entitlement; a
    /// provisioning profile in the bundle isn't enough.
    static var entitledToPasskeys: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.web-browser.public-key-credential" as CFString, nil) as? Bool
            == true
    }

    /// WebKit's text checking, in the standard defaults where WebKit reads it
    /// (not a test run's). Smart quotes and dashes stay off: they break code.
    static func tellWebKit(autocorrect: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(autocorrect, forKey: "WebAutomaticSpellingCorrectionEnabled")
        defaults.set(false, forKey: "WebAutomaticQuoteSubstitutionEnabled")
        defaults.set(false, forKey: "WebAutomaticDashSubstitutionEnabled")
    }
}
