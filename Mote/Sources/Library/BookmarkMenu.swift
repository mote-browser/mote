import AppKit
import MoteCore

/// The Bookmarks menu in the menu bar, and bookmarks-bar folders shown as
/// pop-up menus. Items are AppKit's, made when a menu opens: SwiftUI would
/// make every one of them at launch, which is slow with a big import.
///
/// SwiftUI's own delegate rebuilds the menu each time it opens and would
/// drop added items, so it is wrapped by a relay that adds the bookmarks
/// after it. SwiftUI puts its delegate back when it updates the menu bar,
/// so the relay is put in again whenever that may have happened.
@MainActor
final class BookmarkMenu: NSObject, NSMenuDelegate {
    static let shared = BookmarkMenu()

    /// Marks bookmark items apart from SwiftUI's.
    fileprivate static let tag = 0x5EAC
    /// Menu icons are drawn at this size.
    private static let iconSize = NSSize(width: 16, height: 16)

    private weak var browser: Browser?
    private var observers: [Any] = []
    private let relay = Relay()
    /// What each folder's submenu holds, made when it opens.
    private var folders: [ObjectIdentifier: [Bookmark]] = [:]

    private var menu: NSMenu? { NSApp.mainMenu?.items.first { $0.title == "Bookmarks" }?.submenu }

    /// Bookmark items in the Bookmarks menu, for the bench.
    var count: Int { menu?.items.filter { $0.tag == Self.tag }.count ?? 0 }

    func start(for browser: Browser) {
        guard self.browser == nil else { return }
        self.browser = browser
        relay.after = { [weak self] in self?.fill($0) }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.wrap() }
            },
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] note in
                let tracked = (note.object as? NSMenu).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    if tracked == NSApp.mainMenu.map(ObjectIdentifier.init) { self?.wrap() }
                }
            },
        ]
        wrap()
    }

    /// Puts the relay in front of SwiftUI's delegate, if it isn't already.
    private func wrap() {
        guard let menu, menu.delegate !== relay else { return }
        relay.inner = menu.delegate
        menu.delegate = relay
    }

    /// Replaces the bookmark items after SwiftUI's own.
    private func fill(_ menu: NSMenu) {
        menu.items.filter { $0.tag == Self.tag }.forEach(menu.removeItem)
        folders = [:]
        guard let roots = browser?.bookmarks.roots, !roots.isEmpty else { return }
        let line = NSMenuItem.separator()
        line.tag = Self.tag
        menu.addItem(line)
        items(for: roots).forEach(menu.addItem)
    }

    /// A bookmarks-bar folder, as a menu at the pointer.
    func popUp(_ folder: Bookmark) {
        menu(for: folder).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// A folder's menu, its bookmarks with their icons.
    func menu(for folder: Bookmark) -> NSMenu {
        let menu = NSMenu(title: folder.title)
        list(folder.children ?? [], in: menu)
        return menu
    }

    /// A folder's submenu, filled as it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let inside = folders[ObjectIdentifier(menu)] else { return }
        menu.removeAllItems()
        list(inside, in: menu)
    }

    private func list(_ nodes: [Bookmark], in menu: NSMenu) {
        let made = items(for: nodes)
        if made.isEmpty {
            let empty = NSMenuItem(title: "Empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        made.forEach(menu.addItem)
    }

    private func items(for nodes: [Bookmark]) -> [NSMenuItem] {
        nodes.compactMap { node in
            let item: NSMenuItem
            if node.isFolder {
                item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: node.title)
                submenu.delegate = self
                folders[ObjectIdentifier(submenu)] = node.children ?? []
                item.submenu = submenu
            } else if let url = node.url.flatMap(URL.init(string:)) {
                item = NSMenuItem(title: node.title, action: #selector(open(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url
            } else {
                return nil
            }
            // In the title, not as the item's image: macOS leaves the images
            // of menus like these undrawn.
            item.attributedTitle = Self.title(node.title, icon: Self.icon(for: node))
            item.tag = Self.tag
            return item
        }
    }

    @objc private func open(_ item: NSMenuItem) {
        if let url = item.representedObject as? URL { browser?.visit(url) }
    }

    /// A title led by its icon.
    static func title(_ text: String, icon: NSImage?) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString()
        if let icon {
            let attachment = NSTextAttachment()
            attachment.image = icon
            // Centred on the text's midline.
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: "  "))
        }
        title.append(NSAttributedString(string: text))
        title.addAttribute(.font, value: font, range: NSRange(location: 0, length: title.length))
        return title
    }

    /// A folder symbol, or the site's cached icon (a globe until there is
    /// one), sized for a menu. Icons are cached at 64 pt, so a copy is resized
    /// rather than the shared image.
    static func icon(for node: Bookmark) -> NSImage? {
        func symbol(_ name: String) -> NSImage? {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.isTemplate = true
            return image
        }
        if node.isFolder { return symbol("folder") }
        guard let cached = node.host.flatMap(Favicons.shared.cached), let icon = cached.copy() as? NSImage else {
            return symbol("globe")
        }
        icon.size = iconSize
        return icon
    }

    /// Stands in for SwiftUI's menu delegate: passes everything on, and adds
    /// the bookmarks after SwiftUI's update.
    private final class Relay: NSObject, NSMenuDelegate {
        // Set on the main thread, then read by AppKit there too, including
        // through the nonisolated overrides below.
        nonisolated(unsafe) weak var inner: NSMenuDelegate?
        var after: ((NSMenu) -> Void)?

        func menuNeedsUpdate(_ menu: NSMenu) {
            inner?.menuNeedsUpdate?(menu)
            MainActor.assumeIsolated { after?(menu) }
        }

        func menuDidClose(_ menu: NSMenu) { inner?.menuDidClose?(menu) }

        /// Only SwiftUI's own items are its business.
        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            if item?.tag != BookmarkMenu.tag { inner?.menu?(menu, willHighlight: item) }
        }

        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (inner?.responds(to: selector) ?? false)
        }

        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? { inner }
    }
}
