import MoteCore
import SwiftUI
import UniformTypeIdentifiers

/// The bookmark tree: folders open in place, rows drag between folders, and
/// each row has a menu to open, move or remove it. Used by the toolbar's
/// menu and the Bookmarks panel. A custom view rather than an NSMenu so rows
/// can be dragged and have their own menus.
struct BookmarkOutline: View {
    @ObservedObject var bookmarks: Bookmarks
    let open: (URL) -> Void

    @State private var expanded: Set<Bookmark.ID> = []
    @State private var dragging: Bookmark.ID?
    @State private var overTop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            level(bookmarks.roots, depth: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(overTop ? Palette.wash : .clear)
        // Dropped on the list itself: to the top level.
        .onDrop(of: [.text], isTargeted: $overTop) { drop($0, into: nil) }
    }

    private func level(_ nodes: [Bookmark], depth: Int) -> AnyView {
        // Erased: a recursive opaque type can't be inferred.
        AnyView(
            ForEach(nodes) { node in
                row(node, depth: depth)
                if node.isFolder, expanded.contains(node.id) {
                    if let inside = node.children, !inside.isEmpty {
                        level(inside, depth: depth + 1)
                    } else {
                        Text("Empty")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.faint)
                            .padding(.leading, BookmarkRow.indent(depth + 1) + 26)
                            .padding(.vertical, 5)
                    }
                }
            })
    }

    private func row(_ node: Bookmark, depth: Int) -> some View {
        BookmarkRow(
            node: node, depth: depth, expanded: expanded.contains(node.id), dragging: dragging == node.id,
            destinations: BookmarkTree.folders(bookmarks.roots).filter { !node.holds($0.node.id) },
            act: { action in
                switch action {
                case .open: if let url = node.url.flatMap(URL.init(string:)) { open(url) }
                case .toggle: expanded.formSymmetricDifference([node.id])
                case .move(let folder): bookmarks.move(node.id, into: folder)
                case .remove: bookmarks.remove(node.id)
                }
            }
        )
        .onDrag {
            dragging = node.id
            return NSItemProvider(object: node.id.uuidString as NSString)
        }
        .modifier(FolderDrop(folder: node.isFolder) { drop($0, into: node.id) })
    }

    /// A dragged row carries its id as text.
    private func drop(_ providers: [NSItemProvider], into folder: Bookmark.ID?) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) }) else { return false }
        _ = provider.loadObject(ofClass: String.self) { text, _ in
            guard let id = text.flatMap(UUID.init(uuidString:)) else { return }
            Task { @MainActor in
                bookmarks.move(id, into: folder)
                dragging = nil
            }
        }
        return true
    }

    /// Only folders take drops; every row can be dragged.
    private struct FolderDrop: ViewModifier {
        let folder: Bool
        let drop: ([NSItemProvider]) -> Bool
        @State private var over = false

        func body(content: Content) -> some View {
            if folder {
                content.background(over ? Palette.hover : .clear).onDrop(of: [.text], isTargeted: $over, perform: drop)
            } else {
                content
            }
        }
    }
}

/// One row of the outline.
private struct BookmarkRow: View {
    enum Action {
        case open, toggle, remove
        case move(Bookmark.ID?)
    }

    let node: Bookmark
    let depth: Int
    let expanded: Bool
    let dragging: Bool
    /// Folders it can be moved into, with their depth.
    let destinations: [(node: Bookmark, depth: Int)]
    let act: (Action) -> Void

    @State private var hovering = false

    static func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * 18 }

    var body: some View {
        HStack(spacing: 8) {
            if node.isFolder {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.faint)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10)
                Mark(icon: nil, letter: "", size: 15)
                    .overlay(Image(systemName: "folder.fill").font(.system(size: 9)).foregroundStyle(Palette.muted))
            } else {
                Color.clear.frame(width: 10)
                Mark(icon: Favicons.shared.cached(node.host ?? ""), letter: String((node.host ?? "•").prefix(1)).uppercased(), size: 15)
            }
            Text(node.title).font(.system(size: 12.5)).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer(minLength: 8)
            if node.isFolder, let inside = node.children, !inside.isEmpty {
                Text("\(BookmarkTree.count(inside))").font(.system(size: 11)).foregroundStyle(Palette.faint)
            }
        }
        .padding(.leading, Self.indent(depth) + 10)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(hovering ? Palette.wash : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .opacity(dragging ? 0.35 : 1)
        .onTapGesture { act(node.isFolder ? .toggle : .open) }
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: dragging)
    }

    @ViewBuilder
    private var menu: some View {
        if !node.isFolder {
            Button("Open") { act(.open) }
            Divider()
        }
        Menu("Move to") {
            Button("Top Level") { act(.move(nil)) }
            if !destinations.isEmpty {
                Divider()
                ForEach(destinations, id: \.node.id) { folder in
                    Button(String(repeating: "   ", count: folder.depth) + folder.node.title) { act(.move(folder.node.id)) }
                }
            }
        }
        Divider()
        Button("Remove", role: .destructive) { act(.remove) }
    }
}
