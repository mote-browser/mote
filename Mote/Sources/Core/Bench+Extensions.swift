import AppKit
import MoteCore
import WebKit

// Bench commands on extensions. In a test run `yes` skips the install
// question and `ext-answer` answers the others.

extension Bench {
    var extensionCommands: [String: Command] {
        let verbs = [
            "extensions", "ext-add", "ext-folder", "ext-press", "ext-remove", "ext-reload", "ext-page", "ext-popup", "ext-menu", "ext-pin",
            "ext-shot",
            "ext-answer", "ext-enable",
        ]
        let run: Command = { call in
            guard #available(macOS 15.4, *) else { return call.fail("extensions need macOS 15.4") }
            BenchExtensions.run(call)
        }
        return Dictionary(uniqueKeysWithValues: verbs.map { ($0, run) })
    }
}

@available(macOS 15.4, *)
@MainActor
private enum BenchExtensions {
    static func run(_ call: BenchCall) {
        let extensions = Extensions.shared, request = call.request
        let skipAsking = Storage.testing && request.flag("yes")
        let on = request.bool("on") ?? true
        if call.verb == "extensions" {
            return call.answer(["busy": extensions.busy ?? "", "extensions": extensions.installed.map(describe)])
        }
        if call.verb == "ext-answer" { return answer(call) }
        if call.verb == "ext-menu" { return menu(call) }
        guard let id = request.string(call.verb == "ext-folder" ? "path" : "id") else {
            return call.fail("\(call.verb) needs \(call.verb == "ext-folder" ? "a path" : "an id")")
        }
        switch call.verb {
        case "ext-add":
            extensions.install(from: id, confirm: !skipAsking)
            call.answer(["started": true])
        case "ext-folder":
            extensions.installFolder(at: URL(fileURLWithPath: id), confirm: !skipAsking)
            call.answer(["started": true])
        case "ext-press":
            extensions.press(id)
            call.answer(["pressed": true])
        case "ext-enable":
            extensions.setEnabled(id, on)
            call.answer(["enabled": on])
        case "ext-pin":
            extensions.setPinned(id, on)
            call.answer(["pinned": on])
        case "ext-reload":
            extensions.reload(id)
            call.answer(["reloading": true])
        case "ext-remove":
            extensions.remove(id)
            call.answer(["removed": true])
        case "ext-shot":
            guard let popup = popup(id), let path = request.string("path") else { return call.fail("no popup open for that extension") }
            BenchRoom.shoot(popup, to: URL(fileURLWithPath: path), width: nil, call.answer)
        case "ext-popup":
            guard let popup = popup(id) else { return call.fail("no popup open for that extension") }
            popup.evaluateJavaScript(request.string("js") ?? "document.title") { value, error in
                MainActor.assumeIsolated {
                    if let error { return call.fail(error.localizedDescription) }
                    call.answer(["value": BenchWire.plain(value)])
                }
            }
        case "ext-page":
            // One of its pages in a bench tab, where `eval` has its APIs.
            guard let context = extensions.contexts[id] else { return call.fail("no such extension loaded") }
            let tab = call.browser.benchOpen(
                context.baseURL.appendingPathComponent(
                    (request.string("path") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
            BenchRoom.house(tab)
            call.answer(call.describe(tab))
        default:
            call.fail("unknown")
        }
    }

    /// The open popup's page, if it's this extension's.
    private static func popup(_ id: String) -> WKWebView? {
        ExtensionPopup.shared.extensionID == id ? ExtensionPopup.shared.view : nil
    }

    private static func describe(_ item: Installed) -> [String: Any] {
        let extensions = Extensions.shared
        let context = extensions.contexts[item.id]
        let action = context?.action(for: extensions.activeAdapter)
        return [
            "id": item.id, "name": item.name, "version": item.version, "enabled": item.enabled, "loaded": context != nil,
            "base": context?.baseURL.absoluteString ?? "", "errors": (context?.errors ?? []).map(explain),
            "reported": extensions.errors[item.id] ?? [],
            "action": action?.label ?? "", "badge": action?.badgeText ?? "", "popup": action?.presentsPopup ?? false,
            "pinned": item.pinned ?? false,
            "source": item.source ?? "",
        ]
    }

    /// An error with what lies under it and whatever else it carries.
    private static func explain(_ error: Error) -> String {
        let error = error as NSError
        let under = (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { " ← \($0.localizedDescription) \($0.userInfo)" } ?? ""
        let rest = error.userInfo.filter { $0.key != NSLocalizedDescriptionKey && $0.key != NSUnderlyingErrorKey }
        return error.localizedDescription + under + (error.userInfo.isEmpty ? "" : " \(rest)")
    }

    /// Answers every question from now on (yes or no), or asks again; and
    /// lists what was asked.
    private static func answer(_ call: BenchCall) {
        guard Storage.testing else { return call.fail("only in a test run") }
        let extensions = Extensions.shared
        let said = call.request.string("answer")
        extensions.answerForTests = said == "yes" ? true : said == "no" ? false : nil
        call.answer(["answer": said ?? "ask", "asked": extensions.asked])
    }

    /// The puzzle button's menu, drawn to a PNG.
    private static func menu(_ call: BenchCall) {
        guard let path = call.request.string("path"), let picture = extensionMenuPicture() else {
            return call.fail("ext-menu needs a path")
        }
        do {
            try BenchPictures.save(picture, to: path)
            call.answer(["saved": path])
        } catch {
            call.fail(error.localizedDescription)
        }
    }
}
