import AppKit
import Combine
import MoteCore
import WebKit

// An extension's own pages and workings: its side panel, offscreen document,
// popup, worker, permissions and settings; and the tabs by their place.

@available(macOS 15.4, *)
extension ChromeAPI {
    // MARK: - sidePanel (a tab in Mote)

    static func sidePanel(_ call: ChromeCall) async throws -> Any? {
        let id = call.id
        switch call.method {
        case "setOptions":
            if let path: String = call.option("path") { ExtensionShims.panelPath[id] = path }
        case "getOptions":
            return ["enabled": true, "path": ExtensionShims.panelPath[id] ?? ExtensionShims.defaultPanel(call.context) ?? ""]
        case "setPanelBehavior":
            if let on: Bool = call.option("openPanelOnActionClick") {
                if on { ExtensionShims.panelOnClick.insert(id) } else { ExtensionShims.panelOnClick.remove(id) }
            }
        case "getPanelBehavior":
            return ["openPanelOnActionClick": ExtensionShims.panelOnClick.contains(id)]
        case "open":
            ExtensionShims.openPanel(call.context, owner: call.owner)
        default:
            throw unavailable(call)
        }
        return nil
    }

    // MARK: - offscreen

    static func offscreen(_ call: ChromeCall) async throws -> Any? {
        let id = call.id
        switch call.method {
        case "createDocument":
            guard ExtensionShims.offscreen[id] == nil else { throw Refusal("Only a single offscreen document may be created.") }
            guard let path: String = call.option("url"), let setup = call.context.webViewConfiguration else {
                throw Refusal("No page for the offscreen document")
            }
            let page = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: setup)
            page.load(
                URLRequest(url: call.context.baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))))
            ExtensionShims.offscreen[id] = page
            // As Chrome does, only once it has loaded: workers message it at
            // once, and need it listening. Five seconds at most.
            for _ in 0..<250 where page.isLoading || page.url == nil { try? await Task.sleep(for: .milliseconds(20)) }
            return nil
        case "closeDocument":
            ExtensionShims.offscreen[id] = nil
            return nil
        case "hasDocument":
            return ExtensionShims.offscreen[id] != nil
        default:
            throw unavailable(call)
        }
    }

    // MARK: - management (itself only)

    static func management(_ call: ChromeCall) async throws -> Any? {
        switch call.method {
        case "getSelf", "get":
            let found = call.context.webExtension
            return [
                "id": call.id, "name": found.displayName ?? "", "shortName": found.displayShortName ?? "", "version": found.version ?? "",
                "description": found.displayDescription ?? "", "enabled": true, "type": "extension",
                "installType": call.id.hasPrefix("local-") ? "development" : "normal", "mayDisable": true, "offlineEnabled": true,
                "isApp": false, "hostPermissions": [], "permissions": [],
            ]
        case "getAll":
            return []
        case "setEnabled", "uninstallSelf":
            throw Refusal("Extensions are turned on and off in Settings › Extensions")
        default:
            throw unavailable(call)
        }
    }

    // MARK: - runtime.getContexts

    /// Its worker, open popup and offscreen document: some extensions route
    /// messages by them.
    static func runtime(_ call: ChromeCall) async throws -> Any? {
        guard call.method == "getContexts" else { throw unavailable(call) }
        let id = call.id
        var pages: [(type: String, url: URL?)] = []
        let found = call.context.webExtension
        if found.hasBackgroundContent {
            let background = found.manifest["background"] as? [String: Any] ?? [:]
            let script = background["service_worker"] as? String ?? background["page"] as? String
            pages.append(("BACKGROUND", script.map { call.context.baseURL.appendingPathComponent($0) }))
        }
        if ExtensionPopup.shared.extensionID == id { pages.append(("POPUP", ExtensionPopup.shared.view?.url)) }
        if let page = ExtensionShims.offscreen[id] { pages.append(("OFFSCREEN_DOCUMENT", page.url)) }
        return pages.filter { ChromeAPIRules.keeps(type: $0.type, address: $0.url?.absoluteString ?? "", filter: call.options) }.map {
            type, url in
            [
                "contextType": type, "contextId": "\(id)-\(type)", "tabId": -1, "windowId": -1, "frameId": type == "BACKGROUND" ? -1 : 0,
                "documentUrl": url?.absoluteString ?? "", "documentOrigin": url.map { "\($0.scheme ?? "")://\($0.host ?? "")" } ?? "",
                "incognito": false,
            ] as [String: Any]
        }
    }

    // MARK: - The worker

    static func background(_ call: ChromeCall) async throws -> Any? {
        let id = call.id
        switch call.method {
        case "wake":
            guard call.context.webExtension.hasBackgroundContent else { return nil }
            // WebKit can fail to start a worker that went away and never try
            // again, leaving messages waiting for good: twice more, then the
            // extension starts over.
            for attempt in 0..<3 {
                if await startWorker(call.context) { return nil }
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(400)) }
            }
            call.owner.revive(id, because: "its worker wouldn't start")
        // Whether this is a reload since launch rather than an install.
        case "loadedBefore":
            return call.owner.loadedBefore.contains(id)
        // A page found the worker not answering though WebKit says it runs.
        case "revive":
            call.owner.revive(id, because: "its worker stopped answering")
        default:
            throw unavailable(call)
        }
        return nil
    }

    /// Whether WebKit started it; eight seconds without an answer is a no,
    /// as WebKit sometimes never calls back.
    private static func startWorker(_ context: WKWebExtensionContext) async -> Bool {
        await withCheckedContinuation { done in
            var answered = false
            let answer = { (started: Bool) in
                guard !answered else { return }
                answered = true
                done.resume(returning: started)
            }
            context.loadBackgroundContent { error in MainActor.assumeIsolated { answer(error == nil) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { answer(false) }
        }
    }

    static func debug(_ call: ChromeCall) async throws -> Any? {
        guard call.method == "error" else { throw unavailable(call) }
        call.owner.noteError(call.first as? String ?? "?", for: call.id)
        return nil
    }

    /// action.setPopup, for one tab (by its place) or for all.
    static func action(_ call: ChromeCall) async throws -> Any? {
        guard call.method == "popup" else { throw unavailable(call) }
        let place = call.arg(1) as? Int ?? -1
        let visible = call.owner.visibleTabs
        let tab = visible.indices.contains(place) ? visible[place].id.uuidString : nil
        ExtensionShims.popups[call.id] = ChromeAPIRules.settingPopup(
            call.first as? String ?? "", tab: tab, in: ExtensionShims.popups[call.id] ?? [:])
        return nil
    }

    // MARK: - permissions

    static func permissions(_ call: ChromeCall) async throws -> Any? {
        let id = call.id
        let named = call.first as? [String] ?? []
        switch call.method {
        case "granted":
            return granted(to: id)
        case "request":
            guard ChromeAPIRules.mayRequest(named, manifest: call.context.webExtension.manifest) else {
                throw Refusal("Only permissions specified in the manifest may be requested.")
            }
            let (ask, names) = ChromeAPIRules.request(named)
            let yes = ask ? await call.owner.ask(more: names, context: call.context) : true
            guard yes else { return false }
            setGranted(granted(to: id) + named, to: id)
            return true
        case "remove":
            setGranted(granted(to: id).filter { !named.contains($0) }, to: id)
            return true
        default:
            throw unavailable(call)
        }
    }

    // MARK: - Tabs by their place

    static func tabs(_ call: ChromeCall) async throws -> Any? {
        let browser = call.browser
        let visible = call.owner.visibleTabs
        if call.method == "describe" {
            return (call.first as? [Int] ?? []).map { place -> Any in
                guard visible.indices.contains(place) else { return NSNull() }
                return ["url": visible[place].address?.absoluteString ?? "", "title": visible[place].title]
            }
        }
        guard let from = call.first as? Int, visible.indices.contains(from) else { throw Refusal("No tab there") }
        let tab = visible[from]
        switch call.method {
        case "move":
            let wanted = call.arg(1) as? Int ?? -1
            let target = visible[visible.indices.contains(wanted) ? wanted : visible.count - 1]
            if let place = browser.tabs.firstIndex(where: { $0.id == target.id }) { browser.move(tab, to: place) }
        case "discard":
            if tab.id != browser.activeID { browser.sleep(tab) }
        case "activate":
            browser.select(tab)
        default:
            throw unavailable(call)
        }
        return nil
    }

    static func search(_ call: ChromeCall) async throws -> Any? {
        guard call.method == "query" else { throw unavailable(call) }
        guard let url = call.browser.destination(for: call.option("text") ?? "") else { return nil }
        switch call.option("disposition") as String? {
        case "NEW_TAB", "NEW_WINDOW": call.browser.open(url, foreground: true)
        default: call.browser.visit(url)
        }
        return nil
    }

    // MARK: - chrome.privacy and chrome.proxy

    /// Kept per extension. Mote itself follows `passwordSavingEnabled`, which
    /// password managers turn off.
    static func setting(_ call: ChromeCall) async throws -> Any? {
        let parts = call.api.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let name = parts[1]
        var mine = Extensions.settings(for: call.id)
        switch parts[0] {
        case "setting.set": mine[name] = call.options["value"]
        case "setting.clear": mine[name] = nil
        default:
            return [
                "value": mine[name] ?? ChromeAPIRules.defaultSetting(name, savesPasswords: call.browser.prefs.savesPasswords),
                "levelOfControl": mine[name] == nil ? "controllable_by_this_extension" : "controlled_by_this_extension",
            ]
        }
        Extensions.setSettings(mine, for: call.id)
        call.owner.objectWillChange.send()
        return nil
    }
}
