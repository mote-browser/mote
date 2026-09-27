import AppKit
import Combine
import MoteCore
import WebKit

// What extensions are allowed, and asking the person about it. Questions come
// one at a time, as sheets on the window: an app-modal alert would stop the
// whole browser while it waits.

@available(macOS 15.4, *)
extension Extensions {
    /// What Mote's shim added to the manifest, and what the manifest asks for.
    private static func manifestLists(in folder: URL) -> (added: Set<String>, declared: [String]) {
        func json(_ name: String) -> Any? {
            (try? Data(contentsOf: folder.appendingPathComponent(name))).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        }
        let added = json(".mote-added") as? [String] ?? []
        let declared = (json("manifest.json") as? [String: Any])?["permissions"] as? [String] ?? []
        return (Set(added), declared)
    }

    /// What it's allowed, kept and compared at each update (ExtensionRules.grants).
    static func grants(_ found: WKWebExtension, in folder: URL) -> [String] {
        let lists = manifestLists(in: folder)
        return ExtensionRules.grants(
            requested: found.requestedPermissions.map(\.rawValue), patterns: found.allRequestedMatchPatterns.map(\.string),
            declared: lists.declared, added: lists.added)
    }

    /// What it asks for, in sentences.
    static func describe(_ found: WKWebExtension, in folder: URL) -> [String] {
        let lists = manifestLists(in: folder)
        let sites = found.allRequestedMatchPatterns.map {
            ExtensionRules.Site(host: $0.host, everywhere: $0.matchesAllHosts || $0.matchesAllURLs)
        }
        return ExtensionRules.describe(
            requested: Set(found.requestedPermissions.map(\.rawValue)), sites: sites, declared: Set(lists.declared), added: lists.added)
    }

    static func icon(of found: WKWebExtension) -> NSImage? { found.icon(for: CGSize(width: 64, height: 64)) }

    // MARK: - Questions

    func ask(install name: String, wants: [String], icon: NSImage?) async -> Bool {
        await ask("Add “\(name)” to Mote?", detail: ExtensionRules.installDetail(wants), icon: icon, yes: "Add Extension", no: "Cancel")
    }

    /// permissions.request for an API Mote answers itself.
    func ask(more names: String, context: WKWebExtensionContext) async -> Bool {
        await ask("asks for more access", detail: names, context: context)
    }

    func ask(_ question: String, detail: String, context: WKWebExtensionContext) async -> Bool {
        let found = context.webExtension
        return await ask(
            "\(found.displayName ?? "An extension") \(question)", detail: detail, icon: Self.icon(of: found), yes: "Allow",
            no: "Don't Allow")
    }

    /// After any question still waiting.
    func ask(_ title: String, detail: String, icon: NSImage?, yes: String, no: String) async -> Bool {
        let waiting = question
        let asking = Task { @MainActor [weak self] () -> Bool in
            _ = await waiting?.value
            self?.asked.append(title)
            if Storage.testing, let answer = self?.answerForTests { return answer }
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = detail
            if let icon { alert.icon = icon }
            alert.addButton(withTitle: yes)
            alert.addButton(withTitle: no)
            guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
                return alert.runModal() == .alertFirstButtonReturn
            }
            return await withCheckedContinuation { answered in
                alert.beginSheetModal(for: window) { answered.resume(returning: $0 == .alertFirstButtonReturn) }
            }
        }
        question = asking
        return await asking.value
    }

    // MARK: - New tab pages

    private var newTabOwner: (id: String, page: URL)? {
        ExtensionRules.newTabOwner(installed, pages: contexts.compactMapValues(\.overrideNewTabPageURL))
    }

    static func newTabKey(_ id: String) -> String { "extensions.newtab.\(id)" }

    /// Whether its new tab page shows; nil until the person was asked.
    func showsInNewTabs(_ id: String) -> Bool? { Storage.settings.object(forKey: Self.newTabKey(id)) as? Bool }

    func setShowsInNewTabs(_ id: String, _ on: Bool) {
        Storage.settings.set(on, forKey: Self.newTabKey(id))
        objectWillChange.send()
    }

    /// The latest installed extension's new tab page, once allowed.
    var newTabPage: URL? {
        guard let (id, page) = newTabOwner else { return nil }
        return showsInNewTabs(id) == true ? page : nil
    }

    /// As Chrome does, asks before an extension takes over new tabs.
    func offerNewTabPage(into tab: Tab) {
        guard let (id, page) = newTabOwner, showsInNewTabs(id) == nil,
            let name = installed.first(where: { $0.id == id })?.name
        else { return }
        Task {
            let keep = await ask(
                "Show “\(name)” in new tabs?",
                detail: "It asked to replace the new tab page. You can change this later in Settings › Extensions.",
                icon: contexts[id].map { Self.icon(of: $0.webExtension) } ?? nil, yes: "Keep It", no: "Don't Allow")
            setShowsInNewTabs(id, keep)
            if keep, tab.isBlank, let browser { browser.replaceBlank(tab, with: page) }
        }
    }
}
