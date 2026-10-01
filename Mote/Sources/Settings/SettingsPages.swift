import AuthenticationServices
import MoteCore
import SwiftUI

// What each Settings page holds.

struct GeneralSettings: View {
    let browser: Browser
    @ObservedObject var prefs: Preferences
    @State private var isDefault = AppDelegate.isDefault

    var body: some View {
        SettingsSection("Mote and your Mac") {
            SettingRow(
                "Default browser",
                isDefault ? "Links you click in other apps open here" : "Links from other apps still open in another browser",
                symbol: "star", tint: Tint.orange
            ) { defaultControl }
            RowRule()
            SettingRow(
                "Look", "Light, dark, or whatever the Mac is using. Pages follow when they can", symbol: "circle.lefthalf.filled",
                tint: Tint.indigo
            ) {
                Segmented(options: Look.allCases.map { ($0, $0.title) }, selection: $prefs.look)
            }
            RowRule()
            SettingRow(
                "Show the whole address", "The full web address in the toolbar. Off, it shows only the site", symbol: "link",
                tint: Tint.teal, on: $prefs.showsFullAddress)
        }

        SettingsSection("Searching", note: searchNote) {
            SettingRow("Search with", "Used whenever what you type isn't an address", symbol: "magnifyingglass", tint: Tint.blue) {
                Picker("", selection: $prefs.engine) { ForEach(SearchEngine.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
            }
            if prefs.engine == .custom {
                RowRule()
                TextField("", text: $prefs.customEngine, prompt: Text("https://example.com/search?q=%s"))
                    .textFieldStyle(.plain)
                    .textStyle(.row)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Palette.ground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(EdgeInsets(top: 8, leading: 47, bottom: 10, trailing: 12))
            }
        }

        SettingsSection("Links") {
            SettingRow(
                "Preview with Shift", "Shift-click a link to see it over the page; keep it as a tab if you like it", symbol: "eye",
                tint: Tint.teal, on: $prefs.peeksLinks)
            RowRule()
            SettingRow(
                "Links from other apps in a small window", "Handy for a quick look. ⌘O moves it into your tabs",
                symbol: "macwindow.on.rectangle", tint: Tint.green, on: $prefs.littleLinks)
            RowRule()
            SettingRow(
                "Show where links go", "The address under the pointer, at the bottom of the page", symbol: "link", tint: Tint.blue,
                on: $prefs.showsLinks)
            RowRule()
            SettingRow(
                "Scroll with the middle button", "Press the wheel and move the mouse; press again to stop", symbol: "computermouse",
                tint: Tint.gray, on: $prefs.autoScroll)
            RowRule()
            SettingRow(
                "Fix spelling as you type", "The Mac's corrections and capitals in fields on the web", symbol: "textformat.abc",
                tint: Tint.pink, on: $prefs.autocorrect)
        }

        SettingsSection("Video", note: "⇧⌘P floats any video whenever you want.") {
            SettingRow(
                "Keep playing when you switch tabs", "Video from sites Mote knows floats above the page, and goes back when you return",
                symbol: "pip", tint: Tint.red, on: $prefs.floatsOnLeave)
            RowRule()
            SettingRow(
                "Keep playing when you switch apps", "The video stays on top of whatever you're doing", symbol: "rectangle.on.rectangle",
                tint: Tint.orange, on: $prefs.floatsAway)
            RowRule()
            SettingRow(
                "Throw it to a corner", "Swipe with two fingers and the floating video flies to the nearest corner",
                symbol: "arrow.up.left.and.arrow.down.right", tint: Tint.purple, on: $prefs.floatFlicks)
        }

        SettingsSection("Downloads") {
            SettingRow(
                "Save to", prefs.downloads.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), symbol: "folder", tint: Tint.blue
            ) {
                Pill("Choose…", action: chooseFolder)
            }
            RowRule()
            SettingRow(
                "Ask every time", "Pick a place and a name for each file", symbol: "questionmark.folder", tint: Tint.teal,
                on: $prefs.asksWhereToSave)
        }

        SettingsSection("Under the hood") {
            SettingRow(
                "Pages at 120 Hz", "Smoother on ProMotion displays, at some cost to the battery. Open tabs follow once reloaded",
                symbol: "speedometer", tint: Tint.green, on: $prefs.fastPages)
            RowRule()
            SettingRow(
                "Let a script drive Mote", "A private socket for Tools/bench. Its tabs wear a flask and never jump to the front",
                symbol: "terminal", tint: Tint.gray, on: $prefs.bench)
        }
    }

    @ViewBuilder private var defaultControl: some View {
        if isDefault {
            Label("In use", systemImage: "checkmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
        } else {
            Pill("Use Mote", filled: true) {
                AppDelegate.becomeDefault { worked in
                    isDefault = AppDelegate.isDefault
                    browser.announce(worked && isDefault ? "Links now open here" : "macOS didn't change it")
                }
            }
        }
    }

    private var searchNote: String? {
        guard prefs.engine == .custom else { return nil }
        guard SearchEngine.accepts(prefs.customEngine) else {
            return "An http or https address with %s where the words go. Until then, Google."
        }
        return "Searches go to \(prefs.engine.name(custom: prefs.customEngine))."
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.downloads
        panel.prompt = "Save Here"
        if panel.runModal() == .OK, let folder = panel.url { prefs.downloads = folder }
    }
}

struct TabSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where your tabs live").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted).padding(.leading, 4)
            TabLayoutChoice(prefs: prefs, compact: true)
            Text("⇧⌘S switches between them.").font(.system(size: 11.5)).foregroundStyle(Palette.muted).padding(.leading, 4)
        }

        SettingsSection {
            if prefs.sidebar {
                SettingRow(
                    "Tuck the sidebar away",
                    "The page takes the whole window; reach the left edge and your tabs slide out. ⌘S does it by hand",
                    symbol: "sidebar.left", tint: Tint.blue, on: $prefs.sideHides)
                RowRule()
            }
            SettingRow("Beside each title", "What marks a tab, pinned ones too", symbol: "app.badge", tint: Tint.orange) {
                Segmented(options: Glyph.allCases.map { ($0, $0.title) }, selection: $prefs.glyph)
            }
            RowRule()
            SettingRow(
                "How far you've read", "The tab you're on fills in as you scroll", symbol: "text.line.first.and.arrowtriangle.forward",
                tint: Tint.green, on: $prefs.showsReading)
            RowRule()
            SettingRow(
                "Bookmarks bar everywhere", "New tabs always show it; this keeps it over every page", symbol: "bookmark", tint: Tint.pink,
                on: $prefs.bookmarksBar)
        }

        SettingsSection("Saving energy") {
            SettingRow(
                "Let quiet tabs rest",
                "Unseen for half an hour, a tab lets its page go and picks up where it was. Pinned tabs, sound, calls and unsent text keep it awake",
                symbol: "moon.zzz", tint: Tint.indigo, on: $prefs.sleepsTabs)
        }

        SettingsSection("Spaces", note: "Mission Control's ⌃ shortcuts, if they're on, get those keys first.") {
            SettingRow(
                "Separate sets of tabs",
                "Each space can share your sign-ins or start clean. Move between them with ⌃1–⌃9, a two-finger swipe over the tabs, or their icon",
                symbol: "square.stack.3d.up", tint: Tint.purple, on: $prefs.usesSpaces)
        }
    }
}

struct PasswordSettings: View {
    let browser: Browser
    @ObservedObject var prefs: Preferences

    var body: some View {
        SettingsSection("Your passwords") {
            SettingRow("Saved passwords", "In the Mac's keychain, behind Touch ID", symbol: "key", tint: Tint.yellow) {
                Pill("Show…", action: openPasswords)
            }
            RowRule()
            SettingRow(
                "Bring them over", "From Chrome, Arc, Dia, Brave or Edge on this Mac. Nothing leaves it", symbol: "square.and.arrow.down",
                tint: Tint.blue
            ) {
                Pill("Import…", action: openPasswords)
            }
        }

        SettingsSection("While you sign in") {
            SettingRow("Offer to save", savingDetail, symbol: "plus.circle", tint: Tint.green, on: $prefs.savesPasswords)
            RowRule()
            SettingRow(
                "Suggest your accounts", "Click a sign-in field to see what you've saved for the site", symbol: "person.crop.circle",
                tint: Tint.teal, on: $prefs.fillsPasswords)
            RowRule()
            SettingRow("Passkeys", passkeyDetail, symbol: "touchid", tint: Tint.pink, on: $prefs.passkeys)
            if !PasswordStore.never.isEmpty {
                RowRule()
                SettingRow("Sites never asked", "\(PasswordStore.never.count) you said no to", symbol: "hand.raised.slash", tint: Tint.gray)
                {
                    Pill("Forget") {
                        PasswordStore.never = []
                        browser.announce("Every site can ask again")
                    }
                }
            }
        }
    }

    private func openPasswords() {
        browser.tuning = false
        browser.logins.managing = true
    }

    /// A password manager extension can take the saving over.
    private var savingDetail: String {
        if #available(macOS 15.4, *), let name = Extensions.shared.passwordSavingTakenBy { return "\(name) is looking after this instead" }
        return "Once a sign-in has worked. Say no and that site won't ask again"
    }

    private var passkeyDetail: String {
        if !prefs.passkeysPossible { return "This build can't use them: it lacks Apple's passkey entitlement" }
        if Passkeys.access == .denied { return "Blocked in System Settings › Privacy & Security › Passkeys Access for Web Browsers" }
        return "Sign in with Touch ID or a passkey from iCloud, where sites offer it"
    }
}

struct PrivacySettings: View {
    let browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject private var blocker = AdBlocker.shared

    var body: some View {
        SettingsSection("Blocking") {
            SettingRow(
                "Block ads and trackers", blocker.trouble ?? "Stops scripts whose only job is following you around",
                symbol: "shield.lefthalf.filled", tint: Tint.indigo, on: $prefs.shielded)
            if let trouble = blocker.trouble {
                RowRule()
                SettingRow(trouble, "Nothing is blocked until it works again", symbol: "exclamationmark.triangle", tint: Tint.orange) {
                    Pill("Try Again") { blocker.compile() }
                }
            }
            if let host = browser.hereHost, prefs.shielded, blocker.trouble == nil {
                RowRule()
                SettingRow("On \(host)", "If this site breaks, turn it off here; the page reloads", symbol: "globe", tint: Tint.blue) {
                    Switch(
                        on: Binding(
                            get: { !blocker.isPaused(on: host) },
                            set: { on in
                                blocker.pause(host, !on)
                                browser.reload()
                            }))
                }
            }
        }

        SettingsSection("Camera and microphone") {
            SettingRow("Remembered answers", "What you told each site that asked", symbol: "video", tint: Tint.green) {
                Pill("Forget") { browser.forgetCaptureChoices() }
            }
        }

        SettingsSection("Clearing up", note: "Each of these happens straight away.") {
            SettingRow("History", "Every page you've been to", symbol: "clock.arrow.circlepath", tint: Tint.blue) {
                Pill("Clear") { browser.clearHistory() }
            }
            RowRule()
            SettingRow("Cookies and sign-ins", "Signs you out of every site", symbol: "person.crop.circle.badge.xmark", tint: Tint.red) {
                Pill("Clear") { browser.clearSites() }
            }
            RowRule()
            SettingRow("Cache", "Copies kept so pages open faster", symbol: "internaldrive", tint: Tint.gray) {
                Pill("Clear") { browser.clearCache() }
            }
        }
    }
}

struct AboutSettings: View {
    let browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject private var updater = Updater.shared

    private static let keys = [
        ("⌘L", "Type an address"), ("⌘J", "Ask AI in a new tab"), ("⌘K", "Jump to a tab"),
        ("⌘T  ⌘W  ⇧⌘T", "Open, close, bring back a tab"), ("⇧⌘V", "Paste and go"),
        ("⇧⌘C", "Copy the address"), ("⌃⇥  ⌘1–9", "Next tab, or by position"), ("⇧⌘S", "Tabs on top or at the side"),
        ("⌘S", "Tuck the sidebar away"),
        ("⇧⌘R", "Reading mode"), ("⇧⌘H", "Hide part of a page"), ("⇧⌘P", "Float a video"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            Logomark().fill(Palette.ink).aspectRatio(Logomark.canvas.width / Logomark.canvas.height, contentMode: .fit).frame(height: 44)
            Text("Mote").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
            Text("Version \(Updater.version)").font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)

        SettingsSection("Updates") {
            if Updater.enabled {
                SettingRow(updateTitle, updateDetail, symbol: "arrow.triangle.2.circlepath", tint: Tint.blue) { updateControl }
                RowRule()
                SettingRow(
                    "Install on their own", "Off, Mote still checks every day and waits for you", symbol: "square.and.arrow.down.on.square",
                    tint: Tint.green, on: $prefs.installsUpdates)
            } else {
                SettingRow(
                    "Not in this copy", "It was built without a place to look for new versions", symbol: "arrow.triangle.2.circlepath",
                    tint: Tint.gray
                ) {
                    EmptyView()
                }
            }
        }

        SettingsSection("Help") {
            SettingRow(
                "Something wrong?", "Opens a report with your version filled in", symbol: "exclamationmark.bubble", tint: Tint.orange
            ) {
                Pill("Report…") { AppDelegate.writeFeedback() }
            }
        }

        SettingsSection("Keys worth knowing") {
            ForEach(Array(Self.keys.enumerated()), id: \.offset) { index, key in
                if index > 0 { Palette.hairline.frame(height: 1).padding(.leading, 12) }
                HStack {
                    Text(key.1).font(.system(size: 13)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(key.0).font(.system(size: 12, design: .rounded)).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private var updateTitle: String {
        switch updater.stage {
        case .none: "Up to date"
        case .fetching(let next): "Getting Mote \(next.version)…"
        case .ready(let next): "Mote \(next.version) is ready"
        case .offered(let next), .waiting(let next): "Mote \(next.version) is out"
        }
    }

    private var updateDetail: String {
        switch updater.stage {
        case .none:
            updater.lastChecked.map { "Looked \($0.formatted(.relative(presentation: .named))); looks again daily" } ?? "Looks once a day"
        case .fetching(let next): next.notes ?? "In the background. Your settings and data stay put"
        case .ready(let next): next.notes ?? "It takes over next time Mote opens"
        case .offered(let next): next.notes ?? "Install it from the disk image, as the first time"
        case .waiting(let next): next.notes ?? "Checked and installed when you say so"
        }
    }

    @ViewBuilder private var updateControl: some View {
        switch updater.stage {
        case .none:
            Pill(updater.checking ? "Looking…" : "Look Now") {
                updater.check { if $0 == nil { browser.announce("You have the latest version") } }
            }
            .disabled(updater.checking)
        case .fetching: Ring(size: 12)
        case .ready: Pill("Restart Mote", filled: true) { updater.relaunch() }
        case .offered(let next):
            Pill("Download", filled: true) {
                browser.tuning = false
                browser.open(next.diskImage, foreground: true)
            }
        case .waiting: Pill("Install", filled: true) { updater.install() }
        }
    }
}
