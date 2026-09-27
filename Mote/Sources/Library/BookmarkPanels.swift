import MoteCore
import SwiftUI

/// The toolbar's bookmark menu: the tree, then adding this page and the manager.
struct BookmarksDropdown: View {
    @ObservedObject var browser: Browser
    @ObservedObject var bookmarks: Bookmarks

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if bookmarks.isEmpty {
                Text("No bookmarks yet").font(.system(size: 12.5)).foregroundStyle(Palette.muted).padding(14)
            } else {
                ScrollView {
                    BookmarkOutline(bookmarks: bookmarks, open: browser.pickBookmark).padding(6)
                }
                .frame(maxHeight: 360)
            }
            Divider().overlay(Palette.hairline)
            VStack(spacing: 1) {
                PopoverLine("Add This Page", symbol: "bookmark") { browser.bookmarkCurrent() }
                PopoverLine("Manage Bookmarks…") { browser.bookmarking = true }
            }
            .padding(6)
        }
        .frame(width: 280)
    }
}

/// The Bookmarks panel: the whole tree, and imports from other browsers.
struct BookmarksPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var bookmarks: Bookmarks

    var body: some View {
        Plate("Bookmarks", width: 600, close: { browser.bookmarking = false }) {
            if bookmarks.isEmpty {
                Card { EmptyState("Nothing kept yet. Add this page with ⇧⌘B, or bring yours in below.") }
            } else {
                ScrollView(showsIndicators: false) {
                    Card {
                        BookmarkOutline(bookmarks: bookmarks, open: browser.pickBookmark).padding(6)
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: 440)
            }
        } foot: {
            HStack(spacing: 8) {
                Text("Bring in from").font(.system(size: 12)).foregroundStyle(Palette.muted)
                ForEach(ChromiumImporter.installed()) { source in
                    Pill(source.name) { browser.takeBookmarks(from: source) }
                }
                Spacer()
                Text(bookmarks.count == 1 ? "1 bookmark" : "\(bookmarks.count) bookmarks")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
        }
    }
}
