import AppKit
import MoteCore
import WebKit

// Extensions' buttons: what they show, what pressing one does, where their
// popups come from; and their keyboard shortcuts and context menu items.

@available(macOS 15.4, *)
extension Extensions {
    struct Button: Identifiable {
        let id: String
        let name: String
        let label: String
        let icon: NSImage?
        let badge: String
        let enabled: Bool
        let pinned: Bool
    }

    /// Where popups of extensions not in the toolbar hang from: the puzzle button.
    static let menuAnchor = "__menu"

    /// The running extensions' buttons, in the order they were installed.
    var buttons: [Button] {
        _ = actionsChanged
        let tab = activeAdapter
        return installed.compactMap { item in
            guard let action = contexts[item.id]?.action(for: tab) else { return nil }
            return Button(
                id: item.id, name: item.name, label: action.label.isEmpty ? item.name : action.label,
                icon: action.icon(for: CGSize(width: 16, height: 16)), badge: action.badgeText, enabled: action.isEnabled,
                pinned: item.pinned ?? false)
        }
    }

    /// Its own button when it's showing, else the puzzle button.
    func anchor(for id: String) -> NSView? {
        let own = anchors[id]?.view
        return own?.window != nil ? own : anchors[Self.menuAnchor]?.view
    }

    func press(_ id: String) {
        guard let context = contexts[id], !ExtensionPopup.shared.closes(id) else { return }
        let tab = activeAdapter
        if let tab { context.userGesturePerformed(in: tab) }
        let popsUp = context.action(for: tab)?.presentsPopup == true
        // sidePanel.setPanelBehavior({ openPanelOnActionClick: true }).
        if ExtensionShims.panelOnClick.contains(id), !popsUp { return ExtensionShims.openPanel(context, owner: self) }
        // The popup directly: WebKit would build its own first, and swapping
        // it drops the new popup's first messages to the worker.
        if popsUp, let page = popup(of: context) { return ExtensionPopup.shared.show(page, for: context, from: anchor(for: id)) }
        context.performAction(for: tab)
    }

    /// For this tab: action.setPopup's choice, else the manifest's.
    private func popup(of context: WKWebExtensionContext) -> URL? {
        let choice = ExtensionRules.popup(
            overrides: ExtensionShims.popups[context.uniqueIdentifier] ?? [:], tab: browser?.active?.id.uuidString)
        switch choice {
        case .manifest: return Self.popupURL(for: context)
        case .none: return nil
        case .page(let path): return URL(string: path, relativeTo: context.baseURL)?.absoluteURL
        }
    }

    /// The manifest's popup, with its query string.
    static func popupURL(for context: WKWebExtensionContext) -> URL? {
        ExtensionRules.manifestPopup(context.webExtension.manifest).flatMap { URL(string: $0, relativeTo: context.baseURL)?.absoluteURL }
    }

    /// A popup page's address, moved to its copy (ExtensionRules.popupCopy)
    /// so WebKit doesn't treat it as its own popup. Other pages are as they are.
    static func unpopped(_ url: URL) -> URL {
        guard url.scheme == scheme, let id = url.host, let context = shared.contexts[id],
            !url.lastPathComponent.contains(ExtensionRules.popupCopy)
        else { return url }
        let chosen = ExtensionShims.popups[id]?.values.map { URL(string: $0, relativeTo: context.baseURL)?.absoluteURL } ?? []
        guard ([popupURL(for: context)] + chosen).contains(where: { $0?.path == url.path }),
            let original = ExtensionShims.inside(url.path, of: folder(for: id)),
            let data = try? Data(contentsOf: original)
        else { return url }
        let name = ExtensionRules.popupCopyName(of: original.lastPathComponent)
        let copy = original.deletingLastPathComponent().appendingPathComponent(name)
        if (try? Data(contentsOf: copy)) != data {
            guard (try? data.write(to: copy, options: .atomic)) != nil else { return url }
        }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.path = ((url.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name)
        return parts.url ?? url
    }

    /// Runs the extension command bound to this key, if there is one.
    func take(_ event: NSEvent) -> Bool {
        contexts.values.first { $0.command(for: event) != nil }?.performCommand(for: event) ?? false
    }

    /// What extensions add to a page's context menu.
    func menuItems(for tab: Tab) -> [NSMenuItem] {
        guard shows(tab) else { return [] }
        let adapter = adapter(for: tab)
        return contexts.values.flatMap { $0.menuItems(for: adapter) }
    }
}
