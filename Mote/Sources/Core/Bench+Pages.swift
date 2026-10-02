import AppKit
import MoteCore
import WebKit

// Bench commands on tabs and their pages.

extension Bench {
    var pageCommands: [String: Command] {
        [
            "tabs": { $0.answer(["tabs": $0.browser.tabs.map($0.describe)]) },
            "open": Self.open, "go": Self.go, "close": Self.close, "wait": Self.wait, "sleep": Self.sleep, "select": Self.select,
            "text": Self.text, "eval": Self.eval, "tap": Self.tap, "click": Self.act, "type": Self.act, "submit": Self.act,
            "shot": Self.shot, "place": Self.place, "failure": Self.failure,
        ]
    }

    private static func address(_ call: BenchCall) -> URL? {
        guard let url = call.request.string("url").flatMap(Address.url(from:)) else {
            call.fail("\(call.verb) needs a url")
            return nil
        }
        return url
    }

    private static func open(_ call: BenchCall) {
        guard let url = address(call) else { return }
        let tab = call.browser.benchOpen(url)
        BenchRoom.house(tab)
        call.answer(call.describe(tab))
    }

    private static func go(_ call: BenchCall) {
        guard let tab = call.tab(), let url = address(call) else { return }
        tab.go(to: url)
        call.answer(call.describe(tab))
    }

    /// The buttons on a bench tab's failure page: "again" or "continue".
    private static func failure(_ call: BenchCall) {
        guard let tab = call.tab() else { return }
        guard tab.bench else { return call.fail("not a bench tab") }
        guard tab.failure != nil else { return call.fail("no failure page on that tab") }
        switch call.request.string("action") {
        case "again": tab.tryAgain()
        case "continue":
            guard tab.failure?.canContinue == true else { return call.fail("that failure has no way past it") }
            tab.continueAnyway()
        default: return call.fail("failure needs again or continue")
        }
        call.answer(call.describe(tab))
    }

    /// Only tabs the bench opened; "all" closes every one of them.
    private static func close(_ call: BenchCall) {
        let browser = call.browser
        if call.request.string("id") == "all" {
            let mine = browser.tabs.filter(\.bench)
            mine.forEach(browser.close)
            return call.answer(["closed": mine.count])
        }
        guard let tab = call.tab() else { return }
        guard tab.bench else { return call.fail("not a bench tab — only tabs the bench opened can be closed from here") }
        browser.close(tab)
        call.answer(["closed": 1])
    }

    /// Answers once the tab has loaded, or its seconds are up.
    private static func wait(_ call: BenchCall) {
        guard let tab = call.tab() else { return }
        let limit = Date().addingTimeInterval(call.request.double("seconds") ?? 20)
        func check() {
            if !tab.loading, tab.address != nil {
                // A moment for the page's scripts.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    var out = call.describe(tab)
                    if let failure = tab.failure { out["failure"] = failure.title }
                    call.answer(out)
                }
            } else if Date() >= limit {
                var out = call.describe(tab)
                out["timeout"] = true
                call.answer(out)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check)
            }
        }
        check()
    }

    /// Puts the tab to sleep now, if the usual checks allow; says which one didn't.
    private static func sleep(_ call: BenchCall) {
        guard let tab = call.tab() else { return }
        call.browser.sleep(tab) { said in call.answer(["said": said, "asleep": tab.asleep]) }
    }

    private static func select(_ call: BenchCall) {
        guard call.testRun("it would take your window over"), let tab = call.tab() else { return }
        call.browser.select(tab)
        call.answer(call.describe(tab))
    }

    private static func text(_ call: BenchCall) {
        guard let tab = call.tab() else { return }
        BenchRoom.house(tab)
        tab.web.evaluateJavaScript("document.body ? document.body.innerText : ''") { value, error in
            MainActor.assumeIsolated {
                if let error { return call.fail(error.localizedDescription) }
                let (text, cut) = BenchWire.cut(value as? String ?? "")
                call.answer(["text": text, "truncated": cut, "url": tab.address?.absoluteString ?? "", "title": tab.title])
            }
        }
    }

    /// In the page's world, or Mote's with world=mote (Web.world).
    private static func eval(_ call: BenchCall) {
        guard let tab = call.tab() else { return }
        guard let script = call.request.string("js") else { return call.fail("eval needs js") }
        BenchRoom.house(tab)
        let world: WKContentWorld = call.request.string("world") == "mote" ? Web.world : .page
        tab.web.evaluateJavaScript(script, in: nil, in: world) { result in
            switch result {
            case .success(let value): call.answer(["value": BenchWire.plain(value)])
            case .failure(let error): call.fail(error.localizedDescription)
            }
        }
    }

    /// Real, trusted mouse clicks on the page, where `click` calls
    /// element.click(). `text=Label` names a button or link by its text.
    private static func tap(_ call: BenchCall) {
        guard call.testRun("it would click in your page"), let tab = call.tab() else { return }
        guard let selector = call.request.string("selector") else { return call.fail("tap needs a selector") }
        BenchRoom.house(tab)
        let view = tab.web
        let held = BenchInput.flags(call.request.modifiers)
        view.callAsyncJavaScript(BenchScripts.locate, arguments: ["selector": selector], in: nil, in: .page) { result in
            guard let point = (try? result.get()) as? [Double], point.count == 2, let window = view.window else {
                if case .failure(let error) = result { return call.fail(error.localizedDescription) }
                return call.fail("nothing matches \(selector)")
            }
            let spot = view.convert(NSPoint(x: point[0], y: view.isFlipped ? point[1] : view.bounds.height - point[1]), to: nil)
            for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = BenchInput.mouse(kind, at: spot, in: window, flags: held) else { continue }
                if kind == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
            }
            call.answer(["ok": true, "at": point.map { Int($0) }])
        }
    }

    /// click, type or submit, in the page's own terms (Scripts/src/bench-act.ts).
    private static func act(_ call: BenchCall) {
        guard let tab = call.tab() else { return }
        guard let selector = call.request.string("selector") else { return call.fail("\(call.verb) needs a selector") }
        BenchRoom.house(tab)
        let arguments = ["verb": call.verb, "selector": selector, "text": call.request.string("text") ?? ""]
        tab.web.callAsyncJavaScript(BenchScripts.act, arguments: arguments, in: nil, in: .page) { result in
            switch result {
            case .failure(let error): call.fail(error.localizedDescription)
            case .success(let said as String) where said == "ok": call.answer(["ok": true])
            case .success(let said): call.fail(said as? String ?? "?")
            }
        }
    }

    private static func shot(_ call: BenchCall) {
        guard let tab = call.tab() else { return }
        BenchRoom.house(tab)
        let path = call.request.string("path") ?? NSTemporaryDirectory() + "mote-bench-\(BenchWire.short(tab.id)).png"
        BenchRoom.shoot(tab.web, to: URL(fileURLWithPath: path), width: call.request.double("width"), call.answer)
    }

    /// Moves a tab to a place in the row.
    private static func place(_ call: BenchCall) {
        guard let ref = call.request.string("id"), let to = call.request.int("to"),
            let tab = call.browser.tabs.first(where: { BenchWire.short($0.id) == ref })
        else { return call.fail("place needs a tab id and an index") }
        call.browser.move(tab, to: to)
        call.answer(["at": call.browser.tabs.firstIndex { $0.id == tab.id } ?? -1])
    }
}

/// Where bench pages are laid out while in the background: WebKit only lays
/// out and paints a view with a window and a size. Off every screen, never
/// key or main.
@MainActor
enum BenchRoom {
    private(set) static var window: NSWindow?

    static var made: NSWindow {
        if let window { return window }
        let room = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 1280, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        room.isReleasedWhenClosed = false
        room.isExcludedFromWindowsMenu = true
        room.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        room.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        room.hasShadow = false
        room.orderBack(nil)
        window = room
        return room
    }

    /// A background bench tab's page moves in here; picking the tab takes it back.
    static func house(_ tab: Tab) {
        guard tab.bench, tab.web.window == nil else { return }
        let room = made
        tab.web.frame = room.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        tab.web.autoresizingMask = [.width, .height]
        room.contentView?.addSubview(tab.web)
    }

    /// The page as a PNG at `file`.
    static func shoot(_ web: WKWebView, to file: URL, width: Double?, _ answer: @escaping ([String: Any]) -> Void) {
        let setup = WKSnapshotConfiguration()
        setup.afterScreenUpdates = true
        if let width { setup.snapshotWidth = NSNumber(value: width) }
        web.takeSnapshot(with: setup) { image, error in
            MainActor.assumeIsolated {
                guard let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
                    return answer(["error": error?.localizedDescription ?? "no picture"])
                }
                do {
                    try BenchPictures.save(bitmap, to: file.path)
                    answer(["path": file.path, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh])
                } catch {
                    answer(["error": error.localizedDescription])
                }
            }
        }
    }
}

/// The page scripts the bench runs.
enum BenchScripts {
    /// The middle of the element `selector` names, in page points, once
    /// scrolled into view; or null. CSS, or `text=…` for a button or link by
    /// its text. See Scripts/src/bench-locate.ts.
    static let locate = InjectedScript.call("bench-locate", arguments: ["selector"])

    /// Clicks, types `text` into, or submits it, as `verb` says; "ok" or why
    /// not. Typing sets the value as a person would, with input and change
    /// events, so frameworks notice. See Scripts/src/bench-act.ts.
    static let act = InjectedScript.call("bench-act", arguments: ["verb", "selector", "text"])
}
