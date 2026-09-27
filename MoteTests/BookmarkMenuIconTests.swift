import AppKit
import MoteCore
import Testing

@testable import Mote

@Suite("Bookmark menu icons")
@MainActor
struct BookmarkMenuIconTests {
    @Test("A folder shows the folder symbol")
    func folder() throws {
        let icon = try #require(BookmarkMenu.icon(for: Bookmark(title: "Work", url: nil, children: [])))
        #expect(icon.isTemplate)
    }

    @Test("A link without a cached favicon shows a globe")
    func noFavicon() throws {
        let link = Bookmark(title: "Nowhere", url: "https://no-icon-\(UUID().uuidString.lowercased()).example/", children: nil)
        let icon = try #require(BookmarkMenu.icon(for: link))
        #expect(icon.isTemplate)
    }

    @Test("A link shows its site's favicon at menu size, leaving the cached one as it was")
    func favicon() async throws {
        let host = "icon-\(UUID().uuidString.lowercased()).example"
        let picture = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }
        let png = try #require(
            picture.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]))
        await Favicons.shared.adopt(png, for: host)
        let cached = try #require(Favicons.shared.cached(host))
        let cachedSize = cached.size

        let icon = try #require(BookmarkMenu.icon(for: Bookmark(title: "Site", url: "https://\(host)/page", children: nil)))
        #expect(!icon.isTemplate)
        #expect(icon.size == NSSize(width: 16, height: 16))
        #expect(icon !== cached)
        #expect(Favicons.shared.cached(host)?.size == cachedSize)
    }

    @Test("A favicon kept on disk from an earlier session shows in the menu too")
    func faviconFromDisk() throws {
        let host = "disk-\(UUID().uuidString.lowercased()).example"
        let picture = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let png = try #require(
            picture.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]))
        let folder = Storage.folder.appending(path: "icons", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: host + ".png")
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let icon = try #require(BookmarkMenu.icon(for: Bookmark(title: "Site", url: "https://\(host)/", children: nil)))
        #expect(!icon.isTemplate)
        #expect(icon.size == NSSize(width: 16, height: 16))
        #expect(icon.representations.isEmpty == false)
    }

    @Test("A folder's menu leads each title with its icon, which macOS draws where it leaves item images out")
    func iconsInTitles() throws {
        let folder = Bookmark.folder(
            "Work",
            [
                Bookmark(title: "Site", url: "https://titles-\(UUID().uuidString.lowercased()).example/", children: nil),
                Bookmark.folder("Inner", []),
            ])
        let menu = BookmarkMenu.shared.menu(for: folder)
        #expect(menu.items.count == 2)
        for (item, name) in zip(menu.items, ["Site", "Inner"]) {
            let title = try #require(item.attributedTitle)
            #expect(title.string.hasSuffix("  " + name))
            #expect(title.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)
        }
    }
}
