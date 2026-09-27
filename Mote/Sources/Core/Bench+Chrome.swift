import AppKit
import AuthenticationServices
import MoteCore
import WebKit

// Bench commands on the browser around the pages: its state, its panels and
// settings, spaces, previews and link windows.

extension Bench {
    var chromeCommands: [String: Command] {
        [
            "probe": Self.probe, "ui": Self.ui, "consent": Self.consent, "little": Self.little, "space": Self.space, "peek": Self.peek,
            "window": Self.window,
        ]
    }

    /// The whole state of the window and its parts.
    private static func probe(_ call: BenchCall) {
        let browser = call.browser
        let window = AppDelegate.window
        let describe = { (window: NSWindow) in "\(type(of: window)) “\(window.title)”" }
        var out: [String: Any] = [
            "settings": browser.tuning, "welcome": browser.welcoming, "passwords": browser.logins.managing, "history": browser.recalling,
            "downloads": browser.showingDownloads, "bookmarks": browser.bookmarking, "field": browser.editing,
            "suggesting": browser.logins.choices != nil, "offering": browser.logins.offer != nil,
            "modal": NSApp.modalWindow.map(describe) ?? "",
            "look": browser.prefs.look.rawValue, "appearance": NSApp.appearance?.name.rawValue ?? "system",
            "key": NSApp.keyWindow.map(describe) ?? "",
            "keysQuieted": PageView.quieted, "peek": browser.peekTab?.address?.absoluteString ?? "", "folded": browser.folded,
            "peeking": browser.peeking,
            "sideHides": browser.prefs.sideHides, "lightsHidden": SidebarFold.titlebar?.isHidden ?? false,
            "siteCard": SiteCardPanel.isShown,
            "barEditing": browser.editingInBar, "firstResponder": window?.firstResponder.map { String(describing: type(of: $0)) } ?? "",
            "passkeyAccess": passkeyAccess, "passkeyAsks": Passkeys.asked, "passkeyLast": Passkeys.last,
        ]
        out["windows"] = NSApp.windows.map { window -> [String: Any] in
            [
                "kind": "\(type(of: window))", "title": window.title, "visible": window.isVisible, "level": window.level.rawValue,
                "frame": [Int(window.frame.minX), Int(window.frame.minY), Int(window.frame.width), Int(window.frame.height)],
                "number": window.windowNumber,
            ]
        }
        let pages = browser.tabs.compactMap { $0.built?.configuration.preferences }
        // Whether each page has the Web Inspector on, and is held near 60 fps.
        out["inspector"] = pages.compactMap { $0.unpublishedFlag("_developerExtrasEnabled") }
        out["prefersNear60FPS"] = pages.compactMap(FrameRate.prefersNear60)
        if let window {
            out["lights"] = BenchCall.lights(of: window)
            if let preview = browser.peekTab?.built, preview.window != nil {
                out["peekFrame"] = BenchCall.topLeft(preview.convert(preview.bounds, to: nil), in: window.frame.height)
            }
            // The address field and its suggestions.
            out["barZones"] = KeepZone.views.allObjects.filter { $0.window === window }.map {
                BenchCall.topLeft($0.convert($0.bounds, to: nil), in: window.contentLayoutRect.height)
            }
            if let content = window.contentView {
                let card = browser.layout(in: content.bounds.size).card
                out["card"] = [Int(card.minX), Int(card.minY), Int(card.width), Int(card.height)]
            }
        }
        call.answer(out)
    }

    /// Whether macOS lets browsers other than Safari use this Mac's passkeys.
    private static var passkeyAccess: String {
        switch ASAuthorizationWebBrowserPublicKeyCredentialManager().authorizationStateForPlatformCredentials {
        case .authorized: "authorized"
        case .denied: "denied"
        default: "notDetermined"
        }
    }

    /// Panels and settings, on or off.
    private static func ui(_ call: BenchCall) {
        let browser = call.browser, prefs = browser.prefs, request = call.request
        let switches: [(String, (Bool) -> Void)] = [
            ("settings", { browser.tuning = $0 }), ("passwords", { browser.logins.managing = $0 }), ("welcome", { browser.welcoming = $0 }),
            ("history", { browser.recalling = $0 }), ("downloads", { browser.showingDownloads = $0 }),
            ("bookmarks", { browser.bookmarking = $0 }),
            ("hidden", { browser.reviewing = $0 }), ("pages120", { prefs.fastPages = $0 }), ("sidebar", { prefs.sidebar = $0 }),
            ("spaces", { prefs.usesSpaces = $0 }), ("hides", { prefs.sideHides = $0 }), ("folded", { browser.folded = $0 }),
            ("peek", { browser.peeking = $0 }), ("bar", { if $0 { browser.edit() } else { browser.dismiss() } }),

        ]
        for (key, set) in switches { request.bool(key).map(set) }
        if let look = request.string("look").flatMap(Look.init) { prefs.look = look }
        // A notice as it would show (test runs): an update's, or a plain line.
        if Storage.testing, let notice = request.string("notice") {
            let release = AppRelease(
                version: "0.2.0", build: 2, archive: URL(string: "https://example.com/Mote.zip")!,
                diskImage: URL(string: "https://example.com/Mote.dmg")!, notes: request.string("notes"))
            switch notice {
            case "update": browser.tell(.out(release))
            case "ready": browser.tell(.ready(release))
            case "manual": browser.tell(.manual(release))
            default: browser.announce(notice)
            }
        }
        // The site card: on, off, or open at its security detail.
        if let card = request.string("sitecard"), let tab = browser.active {
            if card == "off" { SiteCardPanel.hide() } else { SiteCardPanel.open(for: tab, in: browser, security: card == "security") }
        }
        // The preview's buttons (LinkPeek).
        if let what = request.string("peeklink") { if what == "keep" { browser.keepPeek() } else { browser.closePeek() } }
        // Renaming the tab in front, and finishing.
        if let text = request.string("edittab"), let tab = browser.active {
            browser.beginTabRename(tab)
            browser.tabDraft = text
        }
        if request.flag("finishedit") { browser.finishTabEdit() }
        if #available(macOS 15.4, *), let on = request.bool("extensions") { Extensions.shared.menuOpen = on }
        call.answer(["ok": true])
    }

    /// The consent item (Bench.Consent), and granting or revoking it.
    private static func consent(_ call: BenchCall) {
        guard call.testRun() else { return }
        let before = Consent.given
        switch call.request.string("action") {
        case "grant": Consent.grant()
        case "revoke": Consent.revoke()
        default: break
        }
        call.answer(["before": before, "after": Consent.given])
    }

    /// A link window made without showing it, or the last one kept or closed.
    private static func little(_ call: BenchCall) {
        let browser = call.browser
        switch call.request.string("what") ?? "" {
        case "keep": LinkWindow.all.last?.keep()
        case "close": LinkWindow.all.last?.close()
        case let text:
            guard let url = URL(string: text), !text.isEmpty else { return call.fail("little needs a url, keep or close") }
            LinkWindow.show(url, for: browser, front: false)
        }
        call.answer([
            "littles": LinkWindow.all.map { $0.tab.address?.absoluteString ?? "" },
            "tabs": browser.tabs.map { ($0.pin != nil ? "PIN " : "") + ($0.address?.host() ?? "blank") },
            "active": browser.active?.address?.host() ?? "",
        ])
    }

    /// Making, switching, deleting, moving and swiping spaces. A trackpad
    /// can't reach a window in the background, so swipes drive SpaceSwipe.
    private static func space(_ call: BenchCall) {
        guard call.testRun() else { return }
        let browser = call.browser, request = call.request, swipe = SpaceSwipe.shared
        let drag = {
            let dx = request.double("dx") ?? -120
            swipe.start(for: browser)
            swipe.began()
            for _ in 0..<12 { swipe.moved(along: dx / 12) }
        }
        switch request.string("action") ?? "" {
        case "new": browser.addSpace(named: request.string("name") ?? "Test", sharesSignIns: !request.flag("fresh"))
        case "go": browser.switchSpace(index: (request.int("index") ?? 1) - 1)
        case "delete": browser.deleteSpace(browser.spaceID)
        case "swipe":
            drag()
            swipe.ended()
        // Held mid-swipe, to look at.
        case "hold": drag()
        case "release": swipe.ended()
        case "move": request.int("index").map { browser.moveSpace(browser.spaceID, to: $0 - 1) }
        default: break
        }
        let out: [String: Any] = [
            "on": browser.prefs.usesSpaces, "current": browser.space.name,
            "spaces": browser.spaces.map {
                ["name": $0.name, "id": $0.id.uuidString, "downloads": $0.downloads ?? "", "shared": $0.sharesSignIns == true]
            },
            "parked": browser.parked.map { [$0.key.uuidString: $0.value.tabs.count] }, "tabs": browser.tabs.count,
            "making": browser.makingSpace,
            "swipe": Double(browser.spaceSwipe),
            "pages": Web.pages.allObjects.map { $0.configuration.websiteDataStore.identifier?.uuidString ?? "default" },
        ]
        // WebKit's stores a moment later, to check deleted spaces took theirs
        // along; with records, what's left in those being erased.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WKWebsiteDataStore.fetchAllDataStoreIdentifiers { ids in
                MainActor.assumeIsolated {
                    var out = out
                    out["stores"] = ids.map(\.uuidString)
                    let erasing = (Storage.settings.stringArray(forKey: "spaces.erasing") ?? []).compactMap(UUID.init).filter(ids.contains)
                    guard request.flag("records"), !erasing.isEmpty else { return call.answer(out) }
                    Task { @MainActor in
                        var left: [String: [String]] = [:]
                        for id in erasing {
                            let records = await WKWebsiteDataStore(forIdentifier: id).dataRecords(
                                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
                            left[id.uuidString] = records.map { "\($0.displayName): \($0.dataTypes.sorted().joined(separator: ","))" }
                        }
                        out["erasingRecords"] = left
                        call.answer(out)
                    }
                }
            }
        }
    }

    /// A link previewed over the tab in front, as a shift-click opens it; "close" shuts it.
    private static func peek(_ call: BenchCall) {
        guard call.testRun() else { return }
        if call.request.string("url") == "close" {
            call.browser.closePeek()
            return call.answer(["peek": ""])
        }
        guard let tab = call.browser.active, let url = call.request.string("url").flatMap(URL.init(string:)) else {
            return call.fail("peek needs a tab in front and an address")
        }
        call.browser.peek(url, from: tab)
        call.answer(["peek": url.absoluteString])
    }

    /// The browser window, through the Window menu, when a hidden launch has none.
    private static func window(_ call: BenchCall) {
        guard call.testRun() else { return }
        if AppDelegate.window?.contentView != nil, NSApp.windows.contains(where: { $0 === AppDelegate.window }) {
            return call.answer(["window": "there"])
        }
        let items = NSApp.mainMenu?.items.first { $0.submenu?.title == "Window" }?.submenu?.items ?? []
        guard let item = items.first(where: { $0.title == "Mote" }), let action = item.action else {
            return call.answer(["error": "no Mote item in the Window menu", "items": items.map(\.title)])
        }
        NSApp.sendAction(action, to: item.target, from: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            call.answer(["window": NSApp.windows.map { "\(type(of: $0))" }, "hidden": NSApp.isHidden])
        }
    }
}
