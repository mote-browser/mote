import AppKit
import Combine
import MoteCore
import SwiftUI
import WebKit

// Actions on the page showing and on the window's data: zoom, reader,
// copying, printing, bookmarks, imports and clearing.
extension Browser {
    func zoom(by factor: CGFloat) { active?.magnify(by: factor) }
    func resetZoom() { active?.resetZoom() }
    func reload() { active?.reload() }
    func back() { active?.back() }
    func forward() { active?.forward() }

    /// ⌘F. There is nothing to find on a blank tab.
    func openFind() {
        if active?.isBlank == false { finder.show() }
    }

    /// ⌘⇧R.
    func toggleReader() {
        active?.toggleReader { [weak self] worked in
            if !worked { self?.announce("Nothing to read on this page") }
        }
    }

    /// ⌘⇧M: pauses everything playing in this tab.
    func pauseMedia() {
        guard let tab = active else { return }
        tab.web.pauseAllMediaPlayback()
        announce("Paused")
    }

    /// ⇧⌘S: tabs across the top or down the side.
    func toggleSidebar() {
        dissolvingPage { withAnimation(Motion.glide) { self.prefs.sidebar.toggle() } }
    }

    /// ⌘⇧C.
    func copyAddress() {
        guard let url = active?.address else { return }
        copyText(url.absoluteString)
        announce("Address copied")
    }

    func copyMarkdownLink() {
        guard let tab = active, let url = tab.address else { return }
        copyText(Clippings.markdownLink(title: tab.label, url: url))
        announce("Link copied")
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// ⌘P: the system print sheet, which also saves PDFs.
    func printPage() {
        guard let tab = active, !tab.isBlank, let window = NSApp.keyWindow else { return }
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.isHorizontallyCentered = false
        let job = tab.web.printOperation(with: info)
        job.view?.frame = tab.web.bounds
        job.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: - Bookmarks and history

    /// ⇧⌘B.
    func bookmarkCurrent() {
        guard let tab = active, let url = tab.address else { return }
        guard !bookmarks.contains(url) else { return announce("Already a bookmark") }
        bookmarks.add(url, title: tab.title)
        announce("Bookmarked")
    }

    /// Brings in another browser's bookmarks, then its cached icons for them
    /// in the background. Returns how many bookmarks came.
    @discardableResult
    func takeBookmarks(from source: ChromiumImporter.Source) -> Int {
        let found = ChromiumImporter.bookmarks(in: source)
        bookmarks.take(found, from: source.name)
        let count = BookmarkTree.count(found)
        announce(count == 0 ? "No bookmarks in \(source.name)" : "\(count) bookmarks from \(source.name)")
        let urls = BookmarkTree.urls(found)
        Task {
            let icons = await Task.detached(priority: .utility) { ChromiumImporter.icons(in: source, for: urls) }.value
            for (host, data) in icons { await Favicons.shared.adopt(data, for: host) }
            objectWillChange.send()
        }
        return count
    }

    /// Brings in another browser's history, read off the main actor.
    func takePlaces(from source: ChromiumImporter.Source) async -> Int {
        let places = await Task.detached(priority: .userInitiated) { ChromiumImporter.places(in: source) }.value
        for place in places { history.merge(place.url, title: place.title, count: place.count, last: place.last) }
        history.scheduleSave()
        return places.count
    }

    // MARK: - Clearing

    /// Removes every site's cookies, caches and storage in every space.
    func clearSites() {
        removeData(WKWebsiteDataStore.allWebsiteDataTypes())
        announce("Signed out of everything")
    }

    /// Removes caches only, keeping sign-ins and storage.
    func clearCache() {
        removeData([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeOfflineWebApplicationCache])
        announce("Cache cleared")
    }

    private func removeData(_ types: Set<String>) {
        for space in spaces { Spaces.store(for: space.id).removeData(ofTypes: types, modifiedSince: .distantPast) {} }
    }

    func clearHistory() {
        history.clear()
        announce("History cleared")
    }

    func forgetCaptureChoices() {
        capture.forgetAll()
        announce("Camera and microphone choices forgotten")
    }
}
