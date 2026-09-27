import AppKit
import Combine
import MoteCore
import WebKit

// Bench commands that press keys, click, swipe and resize, most of them
// timing what follows. A test window in the background gets no events from
// the system, so these hand them straight to the views that would.

extension Bench {
    var inputCommands: [String: Command] {
        [
            "press": Self.press, "key": Self.key, "keyeq": Self.keyEquivalent, "hit": Self.hit, "field": Self.field,
            "bookmark": Self.bookmark, "menu": Self.menu, "pull": Self.pull, "resize": Self.resize,
        ]
    }

    /// A key on the whole app, through its event queue, so app shortcuts see
    /// it first; "repeat" among the modifiers makes it an auto-repeat.
    private static func press(_ call: BenchCall) {
        guard call.testRun("it would press keys in your browser") else { return }
        guard let code = call.request.int("code"), let characters = call.request.string("chars") else {
            return call.fail("press needs a key code and the characters it types")
        }
        let mods = call.request.modifiers
        for kind in [NSEvent.EventType.keyDown, .keyUp] {
            let event = BenchInput.key(
                kind, characters, code: UInt16(code), flags: BenchInput.flags(mods), in: AppDelegate.window,
                repeats: mods.contains("repeat"))
            event.map { NSApp.postEvent($0, atStart: false) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            call.answer(["active": call.browser.active.map { BenchWire.short($0.id) } ?? ""])
        }
    }

    /// Keys straight to a tab's page, counting those the page left unused
    /// and WebKit sent back to the app.
    private static func key(_ call: BenchCall) {
        guard call.testRun("it would type into your page"), let tab = call.tab() else { return }
        guard let text = call.request.string("text") else { return call.fail("key needs some text") }
        BenchRoom.house(tab)
        let view = tab.web
        view.window?.makeFirstResponder(view)
        let quietedBefore = PageView.quieted
        var pressed: [NSEvent] = []
        var sentBack = 0
        let watch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if pressed.contains(where: { PageView.same($0, event) }) { sentBack += 1 }
            return event
        }
        for character in text {
            let code = BenchWire.keyCode(for: character)
            if let down = BenchInput.key(.keyDown, String(character), code: code, in: view.window) {
                pressed.append(down)
                view.keyDown(with: down)
            }
            BenchInput.key(.keyUp, String(character), code: code, in: view.window).map(view.keyUp)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            watch.map(NSEvent.removeMonitor)
            call.answer(["typed": text, "sentBackUnused": sentBack, "quieted": PageView.quieted - quietedBefore])
        }
    }

    /// ⌘ and a key while the page has the keyboard, as AppKit would send it
    /// to a key window: the app's handling first, then the page's. Says who
    /// took it and what changed.
    private static func keyEquivalent(_ call: BenchCall) {
        guard call.testRun() else { return }
        let browser = call.browser
        guard let web = browser.active?.built, let window = web.window, let characters = call.request.string("chars"),
            let code = call.request.int("code")
        else { return call.fail("keyeq needs a loaded tab, the characters and the key code") }
        window.makeFirstResponder(web)
        let flags = BenchInput.flags(call.request.modifiers.union(["cmd"]))
        guard let event = BenchInput.key(.keyDown, characters, code: UInt16(code), flags: flags, in: window) else {
            return call.fail("no event")
        }
        let before = (finding: browser.finder.showing, field: browser.editing, folded: browser.folded)
        var firstPass = "app"
        if ContentView.keyHook?(event) != nil {
            firstPass = "page"
            _ = web.performKeyEquivalent(with: event)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            web.evaluateJavaScript("JSON.stringify(window.__keys || [])") { seen, _ in
                MainActor.assumeIsolated {
                    call.answer([
                        "firstPass": firstPass, "pageSaw": seen as? String ?? "", "finding": [before.finding, browser.finder.showing],
                        "fieldUp": [before.field, browser.editing], "folded": [before.folded, browser.folded],
                    ])
                }
            }
        }
    }

    /// What's under a point of the window (from its top left), and whether
    /// dragging there moves the window; or a middle click or double click there.
    private static func hit(_ call: BenchCall) {
        guard let window = AppDelegate.window, let frame = window.contentView?.superview, let x = call.request.double("x"),
            let y = call.request.double("y")
        else { return call.fail("hit needs an x and a y") }
        let point = NSPoint(x: x, y: Double(window.frame.height) - y)
        let hit = frame.hitTest(frame.convert(point, from: nil))
        let name = hit.map { String("\(type(of: $0))".prefix(60)) } ?? ""
        if call.request.flag("middle") { return middleClick(call, at: point, in: window, frame: frame) }
        if call.request.flag("double") {
            guard call.testRun() else { return }
            let before = window.frame
            for clicks in [1, 2] {
                BenchInput.mouse(.leftMouseDown, at: point, in: window, clicks: clicks).map { hit?.mouseDown(with: $0) }
                BenchInput.mouse(.leftMouseUp, at: point, in: window, clicks: clicks).map { hit?.mouseUp(with: $0) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let after = window.frame
                call.answer([
                    "view": name, "before": [Int(before.width), Int(before.height)], "after": [Int(after.width), Int(after.height)],
                    "zoomed": window.isZoomed,
                ])
            }
            return
        }
        call.answer([
            "view": name, "canMoveWindow": hit?.mouseDownCanMoveWindow ?? false, "windowMovable": window.isMovable,
            "titleBar": y <= Double(window.frame.height - window.contentLayoutRect.height),
        ])
    }

    /// To the topmost middle-click catcher there (MiddleClick in TabGestures).
    private static func middleClick(_ call: BenchCall, at point: NSPoint, in window: NSWindow, frame: NSView) {
        guard call.testRun() else { return }
        func catcher(in view: NSView) -> NSView? {
            for sub in view.subviews.reversed() { if let found = catcher(in: sub) { return found } }
            return String(describing: type(of: view)).contains("Catch") && view.convert(view.bounds, to: nil).contains(point) ? view : nil
        }
        guard let target = catcher(in: frame) else { return call.fail("nothing catches the middle button there") }
        let before = call.browser.tabs.count
        BenchInput.mouse(.otherMouseDown, at: point, in: window).map(target.otherMouseDown)
        BenchInput.mouse(.otherMouseUp, at: point, in: window).map(target.otherMouseUp)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { call.answer(["tabsBefore": before, "tabsAfter": call.browser.tabs.count]) }
    }

    /// Text into the address field, pasted whole or typed a character at a
    /// time, timing each until the run loop next rests (SwiftUI and the Core
    /// Animation commit included); with go, then submitted and timed until
    /// the page starts loading.
    private static func field(_ call: BenchCall) {
        guard call.testRun("it would type into your browser") else { return }
        guard let text = call.request.string("text"), !text.isEmpty else { return call.fail("field needs some text") }
        let browser = call.browser
        let pieces = call.request.flag("type") ? text.map(String.init) : [text]
        if browser.fieldShowing { browser.field.askFocus() } else { browser.edit() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let field = BenchInput.addressField(in: AppDelegate.window?.contentView),
                let editor = field.currentEditor() as? NSTextView
            else {
                return call.fail("the address field has no editor")
            }
            var times: [[Double]] = []
            @MainActor func next(_ index: Int) {
                guard index < pieces.count else {
                    let out: [String: Any] = [
                        "field": field.stringValue, "typed": browser.field.typed, "offers": browser.field.offers.map(\.key), "ms": times,
                    ]
                    return call.request.flag("go") ? submit(call, adding: out) : call.answer(out)
                }
                let start = CACurrentMediaTime()
                editor.insertText(pieces[index], replacementRange: NSRange(location: NSNotFound, length: 0))
                let inserted = (CACurrentMediaTime() - start) * 1000
                BenchInput.whenResting(since: start) { rested in
                    times.append([inserted, rested])
                    DispatchQueue.main.async { next(index + 1) }
                }
            }
            next(0)
        }
    }

    private static func submit(_ call: BenchCall, adding out: [String: Any]) {
        guard let tab = call.browser.active else { return call.answer(out) }
        var out = out
        out["viewWasBuilt"] = tab.built != nil
        BenchInput.timeLoad(of: tab, doing: call.browser.submit) { returned, rested, loading in
            out["returned"] = returned
            out["rested"] = rested
            out["loading"] = loading
            call.answer(out)
        }
    }

    /// A bookmark opened the way the bookmarks list opens it, timed; "new"
    /// opens it in a new tab with no page yet.
    private static func bookmark(_ call: BenchCall) {
        guard call.testRun("it would load a page in your tab") else { return }
        guard let url = call.request.string("url").flatMap(Address.url(from:)) else { return call.fail("bookmark needs a url") }
        let browser = call.browser
        if call.request.flag("new") { browser.newTab() }
        guard let tab = browser.active else { return call.fail("no tab to open it in") }
        browser.bookmarksOpen = true
        let built = tab.built != nil
        BenchInput.timeLoad(of: tab, doing: { browser.pickBookmark(url) }) { returned, rested, loading in
            call.answer([
                "returned": returned, "loading": loading, "rested": rested, "viewWasBuilt": built, "listStillOpen": browser.bookmarksOpen,
                "sameTab": browser.active?.id == tab.id,
            ])
        }
    }

    /// The Bookmarks menu as it's about to open, and its first folder; with
    /// open, that folder's first bookmark picked.
    private static func menu(_ call: BenchCall) {
        guard call.testRun() else { return }
        guard let main = NSApp.mainMenu, let menu = main.items.first(where: { $0.title == "Bookmarks" })?.submenu else {
            return call.fail("no Bookmarks menu")
        }
        let before = menu.items.count
        let start = CACurrentMediaTime()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: main)
        let filled = (CACurrentMediaTime() - start) * 1000
        menu.delegate?.menuNeedsUpdate?(menu)
        let folder = menu.items.first { $0.submenu != nil && $0.tag != 0 }?.submenu
        folder.map { $0.delegate?.menuNeedsUpdate?($0) }
        if call.request.flag("open"), let folder, let first = folder.items.firstIndex(where: { $0.representedObject is URL }) {
            folder.performActionForItem(at: first)
        }
        call.answer([
            "delegate": menu.delegate.map { "\(type(of: $0))" } ?? "none", "before": before, "after": menu.items.count,
            "ours": BookmarkMenu.shared.count, "fillMs": filled, "titles": menu.items.prefix(8).map { $0.isSeparatorItem ? "—" : name($0) },
            "firstFolder": folder?.items.prefix(4).map(name) ?? [], "active": call.browser.active?.address?.absoluteString ?? "",
        ])
    }

    /// An item's title without the icon leading it (BookmarkMenu.title).
    private static func name(_ item: NSMenuItem) -> String {
        item.title.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FFFC}").union(.whitespaces))
    }

    /// A sideways two-finger swipe on the page: `dx` points in `steps`
    /// phased scroll events over `ms`. Says the address before and after.
    private static func pull(_ call: BenchCall) {
        guard call.testRun() else { return }
        guard let tab = call.browser.active, let web = tab.built, let dx = call.request.double("dx") else {
            return call.fail("pull needs a loaded tab and a distance")
        }
        let steps = max(2, call.request.int("steps") ?? 10)
        let seconds = max(1, call.request.double("ms") ?? 200) / 1000
        let before = tab.address?.absoluteString ?? ""
        BenchInput.scroll(web, phase: .began, by: 0)
        for n in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds * Double(n) / Double(steps)) {
                BenchInput.scroll(web, phase: .changed, by: dx / Double(steps))
                if n == steps { BenchInput.scroll(web, phase: .ended, by: 0) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 1.2) {
            call.answer(["before": before, "after": tab.address?.absoluteString ?? ""])
        }
    }

    /// The window dragged to a size a frame at a time, as a live resize.
    private static func resize(_ call: BenchCall) {
        guard call.testRun("it would move your window") else { return }
        guard let window = AppDelegate.window, let width = call.request.double("width"), let height = call.request.double("height") else {
            return call.fail("resize needs a width and a height")
        }
        let steps = max(1, call.request.int("steps") ?? 12)
        let from = window.frame
        func step(_ n: Int) {
            window.setFrame(BenchWire.resized(from, to: CGSize(width: width, height: height), CGFloat(n) / CGFloat(steps)), display: true)
            guard n == steps else { return DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { step(n + 1) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                call.answer(["size": [Int(window.frame.width), Int(window.frame.height)], "lights": BenchCall.lights(of: window)])
            }
        }
        step(1)
    }
}

/// Events and timings for the bench.
@MainActor
enum BenchInput {
    static func flags(_ names: Set<String>) -> NSEvent.ModifierFlags {
        let known: [String: NSEvent.ModifierFlags] = ["cmd": .command, "shift": .shift, "ctrl": .control, "opt": .option]
        return names.reduce(into: []) { flags, name in
            if let flag = known[name] { flags.insert(flag) }
        }
    }

    static func key(
        _ kind: NSEvent.EventType, _ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = [], in window: NSWindow?,
        repeats: Bool = false
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: kind, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: repeats && kind == .keyDown,
            keyCode: code)
    }

    static func mouse(
        _ kind: NSEvent.EventType, at point: NSPoint, in window: NSWindow, flags: NSEvent.ModifierFlags = [], clicks: Int = 1
    ) -> NSEvent? {
        let down = [.leftMouseDown, .otherMouseDown].contains(kind)
        return NSEvent.mouseEvent(
            with: kind, location: point, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: clicks, pressure: down ? 1 : 0)
    }

    enum Phase: Int64 { case began = 1, changed = 2, ended = 4 }

    /// A trackpad scroll event, sideways.
    static func scroll(_ view: NSView, phase: Phase, by delta: Double) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: Int32(delta), wheel3: 0)
        else { return }
        // kCGScrollWheelEventIsContinuous, …ScrollPhase and …PointDeltaAxis2.
        event.setIntegerValueField(CGEventField(rawValue: 88)!, value: 1)
        event.setIntegerValueField(CGEventField(rawValue: 99)!, value: phase.rawValue)
        event.setIntegerValueField(CGEventField(rawValue: 97)!, value: Int64(delta))
        NSEvent(cgEvent: event).map(view.scrollWheel)
    }

    /// The address field's text field, wherever it is in `view`.
    static func addressField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.delegate is AddressField.Coordinator { return field }
        return view.subviews.lazy.compactMap(addressField).first
    }

    /// Milliseconds from `start` until the main run loop next rests, after
    /// everything that runs before it waits (the Core Animation commit too).
    static func whenResting(since start: CFTimeInterval, _ then: @escaping @MainActor (Double) -> Void) {
        var observer: CFRunLoopObserver?
        observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            let rested = (CACurrentMediaTime() - start) * 1000
            MainActor.assumeIsolated { then(rested) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// Times `doing`: until it returns, until the run loop rests, and until
    /// the tab starts loading (-1 if it hadn't a second after resting).
    static func timeLoad(
        of tab: Tab, doing: () -> Void, then: @escaping @MainActor (_ returned: Double, _ rested: Double, _ loading: Double) -> Void
    ) {
        let start = CACurrentMediaTime()
        var loading: Double?
        let watch = tab.$loading.first(where: { $0 }).sink { _ in loading = (CACurrentMediaTime() - start) * 1000 }
        doing()
        let returned = (CACurrentMediaTime() - start) * 1000
        whenResting(since: start) { rested in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                watch.cancel()
                then(returned, rested, loading ?? -1)
            }
        }
    }
}
