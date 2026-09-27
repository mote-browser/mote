import Combine
import Foundation
import MoteCore

/// The bookmarks, saved as JSON in the profile folder. The edits themselves
/// are `BookmarkTree`'s; this publishes them and writes them down.
@MainActor
final class Bookmarks: ObservableObject {
    @Published private var tree = BookmarkTree()

    var roots: [Bookmark] { tree.roots }
    var isEmpty: Bool { tree.roots.isEmpty }
    /// Sites, counting those in folders.
    var count: Int { BookmarkTree.count(tree.roots) }

    init() { load() }

    /// Adds a page at the top unless it is already somewhere.
    func add(_ url: URL, title: String) { change { $0.add(url, title: title) } }
    func contains(_ url: URL) -> Bool { tree.contains(url) }
    func remove(_ id: Bookmark.ID) { change { $0.remove(id) } }
    /// To the end of a folder, or of the top with none.
    func move(_ id: Bookmark.ID, into folder: Bookmark.ID?) { change { $0.move(id, into: folder) } }
    /// Another browser's bookmarks, in a folder named after it.
    func take(_ nodes: [Bookmark], from browser: String) { change { $0.adopt(nodes, from: browser) } }

    /// For `chrome.bookmarks.create`: under `parent`, or at the top.
    @discardableResult
    func insert(_ node: Bookmark, into parent: Bookmark.ID?) -> Bookmark {
        change { $0.insert(node, into: parent) }
        return node
    }

    /// For `chrome.bookmarks.update`.
    func update(_ id: Bookmark.ID, title: String?, url: String?) { change { $0.update(id, title: title, url: url) } }

    /// Applies an edit and saves when it changed anything.
    private func change<Result>(_ edit: (inout BookmarkTree) -> Result) {
        var next = tree
        _ = edit(&next)
        guard next != tree else { return }
        tree = next
        save()
    }

    // MARK: - The file

    private let file = JSONFile<[Bookmark]>("bookmarks.json")

    private func load() {
        if let roots = file.load() { tree = BookmarkTree(roots) }
    }

    private func save() { file.save(tree.roots) }
}
