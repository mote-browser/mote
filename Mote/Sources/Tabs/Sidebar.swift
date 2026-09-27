import MoteCore
import SwiftUI
import UniformTypeIdentifiers

/// The tabs down the left, on the window's frame: the traffic lights, the
/// pinned tabs in a grid, the rest in a list, and spaces and bookmarks at
/// the foot. The page's own controls are in the toolbar beside it.
struct Sidebar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    /// The sidebar on screen. The docked one stays built while folded; only
    /// the one showing opens the bookmarks menu.
    var showing = true

    @Namespace private var ground
    @Namespace private var groundBefore
    @Namespace private var groundAfter
    @State private var dropping = false

    /// A tab row's height and the gap between rows.
    private static let row = Metrics.row
    private static let gap: CGFloat = 2
    private static let pinGap: CGFloat = 6
    /// The band at the top that holds the traffic lights.
    static let top: CGFloat = 50
    private static let footHeight = Metrics.button + 10

    var body: some View {
        ZStack(alignment: .top) {
            // Under the rows, empty sidebar drags the window; not while the
            // new-space card is up, whose ground wouldn't take the click first.
            DragStrip(reserved: 0, below: browser.makingSpace ? .greatestFiniteMagnitude : rowsEnd)
            // The band by the traffic lights works as a title bar.
            DragStrip().frame(height: Self.top)

            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: Self.top)
                spaces
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, Self.footHeight)

            VStack {
                Spacer()
                foot
            }
        }
        .frame(width: prefs.sideWidth)
        .frame(maxHeight: .infinity)
        // Pages sliding in from other spaces stay inside.
        .clipped()
        .onAppear { SpaceSwipe.shared.start(for: browser) }
        // Nothing of its own behind: the window's frame shows through.
        .background(Palette.veil.opacity(dropping ? 1 : 0))
        .onDrop(of: [.url, .text], isTargeted: $dropping) { browser.take($0) }
        .animation(Motion.quick, value: dropping)
        .animation(Motion.glide, value: browser.activeID)
        .animation(Motion.glide, value: browser.editingTab)
        .animation(Motion.settle, value: browser.tabs.map(\.id))
        .animation(Motion.settle, value: browser.pinnedCount)
    }

    // MARK: - Spaces, side by side

    /// This space's place; the spaces' count while the new-space card shows.
    private var spaceIndex: Int {
        browser.makingSpace ? browser.spaces.count : browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0
    }

    /// Spaces as pages side by side, for the swipe between them.
    private var spaces: some View {
        let width = prefs.sideWidth
        let swipe = browser.spaceSwipe
        let here = spaceIndex
        return ZStack(alignment: .topLeading) {
            page(here, ground: ground).offset(x: swipe)
            if swipe > 0, here > 0 { page(here - 1, ground: groundBefore).offset(x: swipe - width) }
            if swipe < 0, here < browser.spaces.count { page(here + 1, ground: groundAfter).offset(x: swipe + width) }
        }
        // Pages span the whole sidebar and keep their own margins.
        .padding(.horizontal, -10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A space: the live tabs for this one, a still picture of another's, or
    /// the new-space card past the last.
    private func page(_ index: Int, ground: Namespace.ID) -> some View {
        Group {
            if index == browser.spaces.count {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    NewSpaceCard(browser: browser)
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            } else if browser.spaces[index].id == browser.spaceID {
                live
            } else {
                still(browser.parked[browser.spaces[index].id] ?? Parked(tabs: [], active: nil), ground: ground)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: prefs.sideWidth, alignment: .topLeading)
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 0) {
            if browser.pinnedCount > 0 { PinnedTabs(browser: browser, prefs: prefs, ground: ground).padding(.bottom, 10) }
            // A plain stack until the tabs overflow, so the room below them still drags the window.
            ViewThatFits(in: .vertical) {
                listed
                ScrollViewReader { scroller in
                    // Into the trailing margin, so the scroller sits beside the
                    // close buttons rather than on them; the resize handle covers it.
                    ScrollView(.vertical) { listed.padding(.trailing, 10) }
                        .padding(.trailing, -10)
                        .onChange(of: browser.activeID) { _, id in
                            if let id { withAnimation(Motion.glide) { scroller.scrollTo(id) } }
                        }
                        .onAppear { if let id = browser.activeID { scroller.scrollTo(id, anchor: .center) } }
                }
            }
        }
    }

    /// Another space's tabs, drawn like the live ones but not to be touched.
    private func still(_ row: Parked, ground: Namespace.ID) -> some View {
        let pins = row.tabs.filter { $0.pin != nil }
        let grid = PinGrid(count: pins.count, width: prefs.sideWidth - 20, gap: Self.pinGap)
        return VStack(alignment: .leading, spacing: 0) {
            if !pins.isEmpty {
                PinCells(grid: grid) {
                    ForEach(pins) {
                        PinSquare(browser: browser, prefs: prefs, tab: $0, live: $0.id == row.active, ground: ground, size: grid.cell)
                    }
                }
                .padding(.bottom, 10)
            }
            VStack(spacing: Self.gap) {
                ForEach(row.tabs.filter { $0.pin == nil }) {
                    SideRow(browser: browser, prefs: prefs, tab: $0, live: $0.id == row.active, ground: ground, close: {})
                }
            }
            newTab
        }
        .allowsHitTesting(false)
    }

    /// Where the rows end and the window-dragging room starts. Worked out, not
    /// measured: a measurement is a frame late, and for that frame the whole
    /// sidebar would drag the window.
    private var rowsEnd: CGFloat {
        let pins = browser.pinnedCount
        let grid = PinGrid(count: pins, width: prefs.sideWidth - 20, gap: Self.pinGap)
        let pinned = pins == 0 ? 0 : grid.height(pins) + 10
        let loose = CGFloat(browser.tabs.count - pins) * (Self.row + Self.gap)
        return Self.top + pinned + loose + Self.row + 8
    }

    // MARK: - The list

    private var listed: some View {
        VStack(alignment: .leading, spacing: 0) {
            let loose = browser.tabs.filter { $0.pin == nil }
            VStack(spacing: Self.gap) {
                ForEach(Array(loose.enumerated()), id: \.element.id) { index, tab in
                    SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == browser.activeID, ground: ground) {
                        browser.close(tab)
                    }
                    // Places count among the unpinned tabs, after the pinned ones.
                    .modifier(
                        Reorderable(index: index, count: loose.count, step: Self.row + Self.gap, vertical: true, space: "rows") {
                            browser.move(tab, to: $0 + browser.pinnedCount)
                        })
                }
            }
            // Drags are measured in the list's space (see Reorderable).
            .coordinateSpace(name: "rows")
            newTab
        }
    }

    private var newTab: some View {
        Quiet(icon: "plus", title: "New tab", height: Self.row) { browser.newTab() }.padding(.top, Self.gap)
    }

    /// The spaces switcher and the bookmarks.
    private var foot: some View {
        HStack(spacing: 2) {
            if browser.prefs.usesSpaces { SpaceDot(browser: browser) }
            Door(icon: "bookmark", help: "Bookmarks") { browser.bookmarksOpen.toggle() }
                .menuPanel(isPresented: showing ? $browser.bookmarksOpen : .constant(false), edge: .trailing) {
                    BookmarksDropdown(browser: browser, bookmarks: browser.bookmarks)
                }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
    }
}

/// The pinned tabs' grid, where cells drag in two directions.
private struct PinnedTabs: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    let ground: Namespace.ID

    @State private var dragged: Tab.ID?
    @State private var start = 0
    @State private var travel = CGSize.zero

    private static let gap: CGFloat = 6

    var body: some View {
        let tabs = browser.tabs.filter { $0.pin != nil }
        let grid = PinGrid(count: tabs.count, width: prefs.sideWidth - 20, gap: Self.gap)
        // Drags are measured in the grid's space; in a cell's own, a cell that
        // just moved would measure from its new place and swing back and forth.
        PinCells(grid: grid) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let held = dragged == tab.id
                PinSquare(browser: browser, prefs: prefs, tab: tab, live: tab.id == browser.activeID, ground: ground, size: grid.cell)
                    .offset(held ? Reorder.offset(travel: travel, step: grid.step, columns: grid.columns, from: start, now: index) : .zero)
                    // The held cell follows the pointer without animation.
                    .transaction { if held { $0.animation = nil } }
                    .zIndex(held ? 1 : 0)
                    .shadow(color: .black.opacity(held ? 0.16 : 0), radius: 10, y: 3)
                    .gesture(drag(tab, at: index, in: grid, count: tabs.count))
            }
        }
        .coordinateSpace(name: "pins")
    }

    private func drag(_ tab: Tab, at index: Int, in grid: PinGrid, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("pins"))
            .onChanged { value in
                if dragged != tab.id {
                    dragged = tab.id
                    start = index
                }
                travel = value.translation
                let target = Reorder.target(from: start, travel: travel, step: grid.step, columns: grid.columns, count: count)
                if target != index { withAnimation(Motion.settle) { browser.move(tab, to: target) } }
            }
            .onEnded { _ in
                withAnimation(Motion.settle) {
                    dragged = nil
                    travel = .zero
                }
            }
    }
}

/// Fixed cells, row by row, a short last row keeping to the left. Not a
/// LazyVGrid: that makes cells only once on screen, so they missed the
/// sidebar's slide in.
private struct PinCells: Layout {
    let grid: PinGrid

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: CGFloat(grid.columns) * grid.step.width - grid.gap, height: grid.height(subviews.count))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, cell) in subviews.enumerated() {
            let place = CGPoint(
                x: bounds.minX + CGFloat(index % grid.columns) * grid.step.width,
                y: bounds.minY + CGFloat(index / grid.columns) * grid.step.height)
            cell.place(at: place, proposal: ProposedViewSize(grid.cell))
        }
    }
}

/// A pinned tab in the sidebar's grid.
private struct PinSquare: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let ground: Namespace.ID
    let size: CGSize

    @State private var hovering = false

    /// Contents scale with the shorter side, so the mark stays its usual size.
    private var side: CGFloat { min(size.width, size.height) }
    private var corner: CGFloat { side * 10 / 36 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: corner, style: .continuous) }

    var body: some View {
        mark
            .frame(width: side * 16 / 34, height: side * 16 / 34)
            .frame(width: size.width, height: size.height)
            .background {
                if live {
                    Lifted(corner: corner).matchedGeometryEffect(id: "live", in: ground)
                } else {
                    shape.fill(Palette.veil.opacity(hovering ? 1.8 : 1))
                }
            }
            .contentShape(shape)
            .modifier(OneClick(double: live) { live ? browser.editLetter(tab) : browser.select(tab) })
            // As ⌘W: a pinned tab lets its page go and stays pinned.
            .overlay { MiddleClick { browser.close(tab) } }
            .onHover { hovering = $0 }
            .contextMenu { TabMenu(browser: browser, tab: tab) { browser.close(tab) } }
            .help(tab.label)
            .animation(Motion.hover, value: hovering)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    @ViewBuilder
    private var mark: some View {
        if browser.editingPin == tab.id {
            InlineField.letter(of: tab, in: browser)
        } else if prefs.glyph == .icons, let icon = tab.icon {
            Mark(icon: icon, letter: tab.pin ?? "", size: side * 16 / 34, dim: tab.asleep)
        } else {
            Text(tab.pin ?? "")
                .font(.system(size: side * 12 / 34, weight: .medium))
                .foregroundStyle((live ? Palette.ink : Palette.muted).opacity(tab.asleep ? 0.45 : 1))
        }
    }
}

/// A tab in the sidebar's list.
private struct SideRow: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let ground: Namespace.ID
    let close: () -> Void

    @State private var hovering = false
    @State private var shake: CGFloat = 0

    private var renaming: Bool { browser.editingTab == tab.id }
    /// The speaker; clickable, so on hover it moves aside for the close button.
    private var speaker: Bool { !tab.loading && (tab.noisy || tab.muted) }
    /// The loading ring or speaker holds the end of the row. The close button
    /// only comes on hover and holds no room of its own.
    private var status: Bool { !renaming && (tab.loading || speaker) }
    private var colour: Color { live ? Palette.ink : Palette.ink.opacity(hovering ? 0.8 : 0.62) }
    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        HStack(spacing: 8) {
            if renaming {
                InlineField.rename(browser).frame(height: 16)
            } else {
                if prefs.glyph == .icons, !tab.isBlank { Mark(icon: tab.icon, letter: tab.monogram, size: 16) }
                TabMarks(tab: tab, colour: colour)
                Text(tab.label).font(TextStyle.body.font).lineLimit(1).truncationMode(.tail).foregroundStyle(colour)
            }
            if status {
                Spacer(minLength: 2)
                ZStack {
                    if tab.loading { Ring().transition(.opacity) } else { Speaker(tab: tab).transition(.opacity) }
                }
                .frame(width: 16, height: 16)
                // On hover the close button takes this place and the speaker moves left.
                .opacity(hovering && !speaker ? 0 : 1)
                .padding(.trailing, hovering && speaker ? 26 : 0)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, status ? 8 : 10)
        .frame(maxWidth: .infinity, minHeight: Metrics.row, maxHeight: Metrics.row, alignment: .leading)
        // The title fades out under the close button rather than being cut
        // short, so it doesn't move on hover.
        .mask {
            ZStack {
                Rectangle().opacity(hovering && !renaming && !status ? 0 : 1)
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                    Color.clear.frame(width: 30)
                }
            }
        }
        .animation(Motion.quick, value: tab.loading)
        .animation(Motion.quick, value: speaker)
        .background { backdrop }
        .shakesOnRefusal(browser.field.refusals, while: renaming, travel: $shake)
        .contentShape(shape)
        // A double click renames the tab you're on; a click goes to any other.
        .modifier(OneClick(double: live) { live ? browser.beginTabRename(tab) : browser.select(tab) })
        // Over the row, not inside it: inside, its click would wait out the
        // double-click interval of the tab you're on before closing it.
        .overlay(alignment: .trailing) {
            if !renaming { Shut(shown: hovering, act: close).padding(.trailing, 7) }
        }
        .overlay { MiddleClick(act: close) }
        .onHover { hovering = $0 }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: close) }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.glide, value: renaming)
        .transition(.scale(scale: 0.94, anchor: .leading).combined(with: .opacity))
    }

    @ViewBuilder
    private var backdrop: some View {
        if live {
            Lifted(corner: 10) {
                if prefs.showsReading {
                    // How far the page is read, as a faint fill across the row.
                    GeometryReader { geometry in
                        Rectangle().fill(Palette.ink.opacity(0.05)).frame(width: geometry.size.width * tab.reading)
                            .animation(.easeOut(duration: 0.15), value: tab.reading)
                    }
                }
            }
            .matchedGeometryEffect(id: "live", in: ground)
        } else if hovering {
            shape.fill(Palette.veil)
        }
    }
}
