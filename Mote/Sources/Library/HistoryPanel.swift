import MoteCore
import SwiftUI

/// The History panel: where you've been, by day, with a search and the
/// ways to clear history, sign-ins and the cache.
struct HistoryPanel: View {
    @ObservedObject var browser: Browser

    @FocusState private var searching: Bool
    /// The days on show, worked out again only when history or the search changes.
    @State private var days: [Days.Group<History.Entry>] = []
    @State private var clearing = false

    private var pages: Int { days.reduce(0) { $0 + $1.items.count } }

    var body: some View {
        Plate("History", width: 600, close: { browser.recalling = false }) {
            VStack(alignment: .leading, spacing: 14) {
                SearchField(text: $browser.historyQuery, prompt: "Search everywhere you have been", focus: $searching)
                if days.isEmpty {
                    Card { EmptyState(browser.historyQuery.isEmpty ? "Nothing yet." : "Nothing matches.") }
                } else {
                    list
                }
            }
        } foot: {
            if clearing {
                ClearOptions(browser: browser) {
                    refresh()
                } done: {
                    withAnimation(Motion.settle) { clearing = false }
                }
            } else {
                HStack {
                    Text(pages == 1 ? "1 page" : "\(pages) pages").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Pill("Clear…") { withAnimation(Motion.settle) { clearing = true } }
                }
            }
        }
        .animation(Motion.settle, value: clearing)
        .onAppear {
            searching = true
            refresh()
        }
        .onChange(of: browser.historyQuery) { refresh() }
    }

    /// Lazy: a long history is too slow to lay out all at once.
    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days, id: \.day) { day in
                    Caption(When.day(day.day))
                        .padding(.top, day.day == days.first?.day ? 0 : 14)
                        .padding(.bottom, 6)
                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, entry in
                        PlaceRow(entry: entry, first: index == 0, last: index == day.items.count - 1) {
                            browser.recalling = false
                            browser.active?.go(to: entry.url)
                        } forget: {
                            browser.history.remove(entry.key)
                            refresh()
                        }
                    }
                }
            }
            .padding(.bottom, 2)
        }
        .frame(maxHeight: 420)
    }

    private func refresh() {
        days = Days.group(browser.history.entries(matching: browser.historyQuery), by: \.last)
    }
}

/// History, sign-ins and the cache, each cleared on its own.
private struct ClearOptions: View {
    let browser: Browser
    let cleared: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card {
                Line("History", "Everywhere you have been") {
                    Pill("Clear") {
                        browser.clearHistory()
                        cleared()
                        done()
                    }
                }
                Rule()
                Line("Cookies and sign-ins", "Signs you out of every site") {
                    Pill("Sign out of everything") { browser.clearSites() }
                }
                Rule()
                Line("Cache", "Only what was fetched to draw pages") {
                    Pill("Clear") { browser.clearCache() }
                }
            }
            HStack {
                Spacer()
                Pill("Back", action: done)
            }
        }
        .transition(.opacity)
    }
}

/// A place in the list. Each day's rows together look like one card: the
/// first rounds its top corners, the last its bottom ones.
private struct PlaceRow: View {
    let entry: History.Entry
    let first: Bool
    let last: Bool
    let go: () -> Void
    let forget: () -> Void

    @State private var hovering = false

    var body: some View {
        let slice = CardSlice(top: first, bottom: last)
        VStack(spacing: 0) {
            if !first { Rule() }
            HStack(spacing: 12) {
                Mark(
                    icon: Favicons.shared.cached(entry.url.host()?.lowercased() ?? ""),
                    letter: entry.key.first.map { String($0).uppercased() } ?? "•", size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.isEmpty ? entry.key : entry.title).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(entry.key).font(.system(size: 11.5)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if hovering {
                    Quick("Remove", tint: .red.opacity(0.75), act: forget)
                } else {
                    Text(When.clock(entry.last)).font(.system(size: 11.5)).foregroundStyle(Palette.muted).monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(hovering ? Palette.hover : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: go)
            .onHover { hovering = $0 }
        }
        .background(Palette.ground)
        .clipShape(slice)
        // The border reaches a point past shared edges and is clipped there, so
        // only the sides and the card's rounded ends are drawn.
        .overlay(
            slice.strokeBorder(Palette.hairline, lineWidth: 1)
                .padding(.top, first ? 0 : -1)
                .padding(.bottom, last ? 0 : -1)
                .clipped()
        )
        .animation(Motion.quick, value: hovering)
    }
}

/// A slice of a rounded card: rounded at the top, the bottom, both or neither.
private nonisolated struct CardSlice: InsettableShape {
    let top: Bool
    let bottom: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let radius = 11 - inset
        return UnevenRoundedRectangle(
            topLeadingRadius: top ? radius : 0, bottomLeadingRadius: bottom ? radius : 0,
            bottomTrailingRadius: bottom ? radius : 0, topTrailingRadius: top ? radius : 0, style: .continuous
        )
        .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> CardSlice {
        var copy = self
        copy.inset += amount
        return copy
    }
}
