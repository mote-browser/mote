import MoteCore
import SwiftUI

/// The top-level bookmarks in a row on the card, under the toolbar; folders
/// open as menus. Always on a new tab, on every page when Settings says so,
/// and never over full-screen video.
struct BookmarksBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var bookmarks: Bookmarks
    /// A hairline under the bar, between it and a page.
    var ruled = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(bookmarks.roots) { node in
                    Chip(node: node, prominent: browser.active?.isStart == true) { open(node) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, browser.active?.isStart == true ? 10 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if browser.active?.isStart == true { DragStrip() }
        }
        .background(browser.active?.isStart == true ? Color.clear : browser.chromeGround)
        .overlay(alignment: .bottom) {
            if ruled { Palette.hairline.frame(height: 1) }
        }
    }

    private func open(_ node: Bookmark) {
        if node.isFolder {
            BookmarkMenu.shared.popUp(node)
        } else if let url = node.url.flatMap(URL.init(string:)) {
            browser.visit(url)
        }
    }

    private struct Chip: View {
        let node: Bookmark
        let prominent: Bool
        let act: () -> Void
        @State private var hovering = false
        @State private var icon: NSImage?
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            HStack(spacing: 6) {
                if node.isFolder {
                    Image(systemName: "folder").font(.system(size: prominent ? 12 : 10.5)).foregroundStyle(Palette.muted)
                } else {
                    Mark(
                        icon: icon ?? Favicons.shared.cached(node.host ?? "", dark: colorScheme == .dark),
                        letter: String((node.host ?? "•").prefix(1)).uppercased(), size: prominent ? 15 : 13)
                }
                Text(node.title)
                    .font(.system(size: prominent ? 13 : 12))
                    .foregroundStyle(Palette.ink.opacity(hovering ? 0.95 : 0.8))
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                if node.isFolder {
                    Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Palette.faint)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: prominent ? 28 : 24)
            .background(Palette.veil.opacity(hovering ? 1.2 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: act)
            .onHover { hovering = $0 }
            .help(node.url ?? node.title)
            .animation(Motion.hover, value: hovering)
            .task(id: "\(node.host ?? "")-\(colorScheme)") {
                guard let host = node.host else { return }
                icon = Favicons.shared.cached(host, dark: colorScheme == .dark)
                let fetched = await Favicons.shared.icon(for: host, dark: colorScheme == .dark)
                guard !Task.isCancelled else { return }
                icon = fetched
            }
        }
    }
}
