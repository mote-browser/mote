import Foundation

/// A bookmark or a folder of them. Stored as JSON in bookmarks.json; the
/// field names are that file's format.
public struct Bookmark: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    /// nil for a folder.
    public var url: String?
    public var children: [Bookmark]?

    public init(id: UUID = UUID(), title: String, url: String?, children: [Bookmark]?) {
        self.id = id
        self.title = title
        self.url = url
        self.children = children
    }

    public var isFolder: Bool { url == nil }
    public var host: String? { url.flatMap { URL(string: $0)?.host()?.lowercased() } }

    /// A site, titled with its address when it has no title.
    public static func site(_ title: String, _ url: URL) -> Bookmark {
        Bookmark(title: title.isEmpty ? Address.displayString(for: url) : title, url: url.absoluteString, children: nil)
    }

    public static func folder(_ title: String, _ children: [Bookmark]) -> Bookmark {
        Bookmark(title: title, url: nil, children: children)
    }

    /// Whether `id` is this bookmark or anything inside it.
    public func holds(_ id: UUID) -> Bool {
        self.id == id || (children ?? []).contains { $0.holds(id) }
    }
}

/// The bookmarks, as a tree of folders, and the edits made to it.
public struct BookmarkTree: Equatable, Sendable {
    public private(set) var roots: [Bookmark]

    public init(_ roots: [Bookmark] = []) {
        self.roots = roots
    }

    // MARK: - Reading

    /// Sites, counting those in folders.
    public static func count(_ nodes: [Bookmark]) -> Int {
        nodes.reduce(0) { $0 + ($1.isFolder ? count($1.children ?? []) : 1) }
    }

    /// Every site's address, depth first.
    public static func urls(_ nodes: [Bookmark]) -> [URL] {
        nodes.flatMap { $0.isFolder ? urls($0.children ?? []) : [$0.url.flatMap(URL.init(string:))].compactMap { $0 } }
    }

    /// Every folder with how deep it is, for indented "Move to" menus.
    public static func folders(_ nodes: [Bookmark], depth: Int = 0) -> [(node: Bookmark, depth: Int)] {
        nodes.filter(\.isFolder).flatMap { [($0, depth)] + folders($0.children ?? [], depth: depth + 1) }
    }

    public func contains(_ url: URL) -> Bool {
        func search(_ nodes: [Bookmark]) -> Bool {
            nodes.contains { $0.url == url.absoluteString || search($0.children ?? []) }
        }
        return search(roots)
    }

    // MARK: - Editing

    /// Adds a page at the top unless it is already there somewhere.
    @discardableResult
    public mutating func add(_ url: URL, title: String) -> Bool {
        guard !contains(url) else { return false }
        roots.append(.site(title, url))
        return true
    }

    public mutating func remove(_ id: UUID) {
        _ = Self.take(id, from: &roots)
    }

    /// Moves a bookmark or folder to the end of a folder, or of the top level
    /// with no folder. A folder can't go into itself or anything inside it.
    @discardableResult
    public mutating func move(_ id: UUID, into folder: UUID?) -> Bool {
        var next = roots
        guard let node = Self.take(id, from: &next) else { return false }
        if let folder {
            guard !node.holds(folder), Self.place(node, in: folder, among: &next) else { return false }
        } else {
            next.append(node)
        }
        roots = next
        return true
    }

    /// Adds under `parent`, or at the top when there is none or it is gone.
    public mutating func insert(_ node: Bookmark, into parent: UUID?) {
        if let parent, Self.place(node, in: parent, among: &roots) { return }
        roots.append(node)
    }

    /// Changes a title, or a site's address.
    @discardableResult
    public mutating func update(_ id: UUID, title: String?, url: String?) -> Bool {
        Self.edit(id, in: &roots) { node in
            if let title { node.title = title }
            if let url, !node.isFolder { node.url = url }
        }
    }

    /// Another browser's bookmarks, in a folder named after it that replaces
    /// any earlier import from it. With nothing saved yet they become the top.
    public mutating func adopt(_ nodes: [Bookmark], from browser: String) {
        guard !nodes.isEmpty else { return }
        guard !roots.isEmpty else {
            roots = nodes
            return
        }
        roots.removeAll { $0.isFolder && $0.title == browser }
        roots.append(.folder(browser, nodes))
    }

    // MARK: - Walking the tree

    /// Removes and returns the node with `id`, wherever it is.
    private static func take(_ id: UUID, from nodes: inout [Bookmark]) -> Bookmark? {
        if let here = nodes.firstIndex(where: { $0.id == id }) { return nodes.remove(at: here) }
        for i in nodes.indices where nodes[i].children != nil {
            if let found = take(id, from: &nodes[i].children!) { return found }
        }
        return nil
    }

    /// Appends `node` to the folder with `id`. False when there is no such folder.
    private static func place(_ node: Bookmark, in id: UUID, among nodes: inout [Bookmark]) -> Bool {
        var placed = false
        _ = edit(id, in: &nodes) { folder in
            guard folder.isFolder else { return }
            folder.children = (folder.children ?? []) + [node]
            placed = true
        }
        return placed
    }

    /// Applies `change` to the node with `id`. False when there is none.
    private static func edit(_ id: UUID, in nodes: inout [Bookmark], _ change: (inout Bookmark) -> Void) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id {
                change(&nodes[i])
                return true
            }
            if nodes[i].children != nil, edit(id, in: &nodes[i].children!, change) { return true }
        }
        return false
    }
}
