import MoteCore
import SwiftUI

/// The Downloads panel: recent files, to open, find in Finder or forget.
struct DownloadsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var downloads: Downloads

    var body: some View {
        Plate("Downloads", width: 560, close: { browser.showingDownloads = false }) {
            if downloads.kept.isEmpty {
                Card { EmptyState("Nothing downloaded yet.") }
            } else {
                ScrollView(showsIndicators: false) {
                    Card {
                        ForEach(Array(downloads.kept.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { Rule() }
                            FileRow(record: record, downloads: downloads)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: 420)
            }
        } foot: {
            HStack {
                Text(
                    downloads.kept.isEmpty
                        ? "Files land in \(browser.downloadsFolder.lastPathComponent)" : "Clearing the list leaves the files where they are"
                )
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                Spacer()
                if !downloads.kept.isEmpty { Pill("Clear list") { downloads.forgetAll() } }
            }
        }
    }
}

/// A downloaded file; one that has been moved or deleted shows faded.
private struct FileRow: View {
    let record: DownloadRecord
    let downloads: Downloads

    @State private var hovering = false

    var body: some View {
        let there = record.stillThere
        HStack(spacing: 12) {
            Image(systemName: there ? "doc" : "doc.badge.ellipsis")
                .font(.system(size: 13))
                .foregroundStyle(there ? Palette.muted : Palette.faint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.system(size: 13))
                    .foregroundStyle(there ? Palette.ink : Palette.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text([record.from, When.said(record.date)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if hovering {
                if there { Quick("Show in Finder") { downloads.reveal(record) } }
                Quick("Remove", tint: .red.opacity(0.75)) { downloads.forget(record) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(hovering ? Palette.hover : .clear)
        .contentShape(Rectangle())
        .onTapGesture { if there { downloads.open(record) } }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}
