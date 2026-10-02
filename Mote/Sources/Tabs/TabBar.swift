import MoteCore
import SwiftUI
import UniformTypeIdentifiers

/// The tabs across the top, on the window's frame above the card. The
/// active tab is the card's colour and flows down into it; the rest sit on
/// the frame with faint rules between them.
struct TabBar: View {
    @ObservedObject var browser: Browser
    var sharedGround = false

    /// The active tab's ground, which glides from tab to tab.
    @Namespace private var ground
    /// The same for the neighbouring spaces' rows during a swipe.
    @Namespace private var groundAbove
    @Namespace private var groundBelow

    @State private var dropping = false
    /// The tab under the pointer; the rules beside it hide, as beside the active one.
    @State private var hovered: Tab.ID?
    /// A tab being dragged to a new place in the row.
    @State private var drag: ReorderDrag<Tab.ID>?

    static let widths = TabWidths(
        widest: Metrics.tabWidth, narrowest: Metrics.tabMinWidth, titled: Metrics.tabTitled, pinned: Metrics.pinWidth, gap: Metrics.tabGap)
    private static let plusWidth: CGFloat = 32
    /// The least empty strip left for dragging the window.
    private static let dragRoom: CGFloat = 48

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(browser: browser, strip: geometry.size.width)
            ZStack(alignment: .topLeading) {
                // The strip past the tabs, and the traffic lights' corner, drag the window.
                DragStrip(reserved: Metrics.lights + layout.dot + layout.tabsWidth(making: making) + Self.plusWidth)
                DragStrip().frame(width: Metrics.lights)

                HStack(alignment: .top, spacing: 0) {
                    if browser.prefs.usesSpaces { SpaceDot(browser: browser).frame(height: ChromeLayout.strip) }
                    rows(layout)
                        .zIndex(drag == nil ? 0 : 1)
                    Plus { browser.newTab() }
                        .frame(width: Self.plusWidth, height: Metrics.tabHeight)
                        .padding(.top, ChromeLayout.strip - Metrics.tabHeight)
                    Spacer(minLength: 0)
                }
                .padding(.leading, Metrics.lights)
                .coordinateSpace(name: "strip")
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(height: ChromeLayout.strip)
        .onAppear { SpaceSwipe.shared.start(for: browser) }
        .onDrop(of: [.url, .text], isTargeted: $dropping) { browser.take($0) }
        .background(Palette.veil.opacity(dropping ? 1 : 0))
        .animation(Motion.quick, value: dropping)
        .animation(Motion.glide, value: browser.activeID)
        .animation(Motion.settle, value: browser.tabs.map(\.id))
    }

    private var making: Bool { browser.prefs.usesSpaces && browser.makingSpace }

    /// This space's row, and during a swipe the neighbouring space's sliding in
    /// from above or below.
    private func rows(_ layout: Layout) -> some View {
        let swipe = browser.spaceSwipe
        let here = layout.spaceIndex
        return ZStack(alignment: .bottomLeading) {
            Group {
                if making {
                    NewSpaceCard(browser: browser, inline: true).fixedSize().frame(height: ChromeLayout.strip)
                } else {
                    scrollingRow(layout)
                }
            }
            .offset(y: swipe)
            if swipe > 0, here > 0 {
                preview(here - 1, layout: layout, ground: groundAbove).offset(y: swipe - ChromeLayout.strip)
            }
            if swipe < 0, here < browser.spaces.count {
                preview(here + 1, layout: layout, ground: groundBelow).offset(y: swipe + ChromeLayout.strip)
            }
        }
        .frame(width: layout.tabsWidth(making: making), height: ChromeLayout.strip + 1, alignment: .topLeading)
        // Clipped top and bottom only: a neighbouring row can be wider, and the
        // active tab's feet reach past the row's ends and 1 pt down over the card's edge.
        .mask(alignment: .leading) {
            Rectangle()
                .frame(width: drag == nil ? 4000 : max(0, layout.strip - Metrics.lights - layout.dot), height: ChromeLayout.strip + 1)
                .offset(x: drag == nil ? (layout.tabsWidth(making: making) - 4000) / 2 : 0, y: 0.5)
        }
    }

    /// The tabs, scrolling sideways once they are down to their narrowest.
    private func scrollingRow(_ layout: Layout) -> some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                liveRow(layout).frame(height: ChromeLayout.strip + 1, alignment: .bottom)
            }
            .scrollDisabled(!layout.overflowing)
            .scrollClipDisabled(drag != nil)
            .frame(width: layout.run, height: ChromeLayout.strip + 1)
            .transformAnchorPreference(key: TabGroundBounds.self, value: .bounds) { value, anchor in value.anchors["viewport"] = anchor }
            .onAppear { showActive(scroller, overflowing: layout.overflowing) }
            .onChange(of: layout.overflowing) { showActive(scroller, overflowing: layout.overflowing) }
            .onChange(of: browser.activeID) { showActive(scroller, overflowing: layout.overflowing, gliding: true) }
        }
    }

    private func liveRow(_ layout: Layout) -> some View {
        let tabs = browser.tabs
        let pinned = browser.pinnedCount
        let active = browser.activeID
        /// A rule shows between two tabs that are neither active nor hovered.
        func quiet(_ id: Tab.ID) -> Bool { id != active && id != hovered && id != drag?.id }
        return HStack(spacing: Metrics.tabGap) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                StripTab(
                    browser: browser, prefs: browser.prefs, tab: tab, live: tab.id == active, width: layout.each,
                    ruled: index > 0 && quiet(tab.id) && quiet(tabs[index - 1].id), ground: ground,
                    hovering: Binding(
                        get: { hovered == tab.id }, set: { over in hovered = over ? tab.id : hovered == tab.id ? nil : hovered }),
                    close: { browser.close(tab) }, sharedGround: sharedGround, dragging: drag?.id == tab.id
                )
                .modifier(
                    Reorderable(
                        id: tab.id, index: index, places: tab.pin == nil ? pinned..<tabs.count : 0..<pinned,
                        lattice: .row(step: (tab.pin == nil ? layout.each : Metrics.pinWidth) + Metrics.tabGap), space: "strip",
                        drag: $drag, leadingLimit: Metrics.lights + layout.dot + TabShape.foot
                    ) { browser.move(tab, to: $0) }
                )
                .mask {
                    if drag != nil, layout.overflowing, drag?.id != tab.id {
                        GeometryReader { proxy in
                            Rectangle()
                                .frame(width: layout.run, height: ChromeLayout.strip + 1)
                                .offset(x: Metrics.lights + layout.dot - proxy.frame(in: .named("strip")).minX)
                        }
                    } else {
                        Rectangle().frame(width: 4000, height: 4000)
                    }
                }
                .id(tab.id)
            }
        }
        // Room for the active tab's feet at both ends.
        .padding(.horizontal, TabShape.foot)
        .animation(Motion.hover, value: hovered)
    }

    /// Another space's row while swiping to it, or the new-space card past the last.
    @ViewBuilder
    private func preview(_ index: Int, layout: Layout, ground: Namespace.ID) -> some View {
        if index == browser.spaces.count {
            NewSpaceCard(browser: browser, inline: true).fixedSize().frame(height: ChromeLayout.strip).allowsHitTesting(false)
        } else {
            let space = browser.spaces[index]
            let row =
                space.id == browser.spaceID
                ? Parked(tabs: browser.tabs, active: browser.activeID) : browser.parked[space.id] ?? Parked(tabs: [], active: nil)
            let each = Self.widths.loose(room: layout.room, pins: row.tabs.filter { $0.pin != nil }.count, count: row.tabs.count)
            HStack(spacing: Metrics.tabGap) {
                ForEach(row.tabs) { tab in
                    StripTab(
                        browser: browser, prefs: browser.prefs, tab: tab, live: tab.id == row.active, width: each, ruled: false,
                        ground: ground,
                        hovering: .constant(false), close: {})
                }
            }
            .padding(.horizontal, TabShape.foot)
            .frame(height: ChromeLayout.strip + 1, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }

    /// Scrolls the active tab into view when the tabs overflow, once layout is done.
    private func showActive(_ scroller: ScrollViewProxy, overflowing: Bool, gliding: Bool = false) {
        guard overflowing, let id = browser.activeID else { return }
        Task { @MainActor in
            withAnimation(gliding ? Motion.glide : nil) { scroller.scrollTo(id) }
        }
    }

    /// The strip's measurements for its width.
    private struct Layout {
        let browser: Browser
        let strip: CGFloat

        var dot: CGFloat { browser.prefs.usesSpaces ? SpaceDot.width + 4 : 0 }
        var room: CGFloat {
            TabStrip.room(
                strip: strip, lights: Metrics.lights, dot: dot, plus: TabBar.plusWidth, dragRoom: TabBar.dragRoom, foot: TabShape.foot)
        }
        var each: CGFloat { TabBar.widths.loose(room: room, pins: browser.pinnedCount, count: browser.tabs.count) }
        var overflowing: Bool { TabBar.widths.overflows(room: room, pins: browser.pinnedCount, count: browser.tabs.count) }
        /// The scroll view: the row, or the room if the row is wider.
        var run: CGFloat {
            min(TabBar.widths.row(room: room, pins: browser.pinnedCount, count: browser.tabs.count), room) + 2 * TabShape.foot
        }

        func tabsWidth(making: Bool) -> CGFloat { making ? min(540, room) : run }

        /// This space's place; the spaces' count while the new-space card shows.
        var spaceIndex: Int {
            browser.makingSpace ? browser.spaces.count : browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0
        }
    }
}

/// The new-tab button at the strip's end.
private struct Plus: View {
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.ink.opacity(hovering ? 0.85 : 0.6))
                .frame(width: 26, height: 26)
                .background(Palette.veil.opacity(hovering ? 1.4 : 0), in: Rounded.row)
                .contentShape(Rounded.row)
        }
        .buttonStyle(Pressed())
        .onHover { hovering = $0 }
        .help("New Tab   ⌘T")
        .accessibilityLabel("New Tab")
        .animation(Motion.hover, value: hovering)
    }
}

/// The active tab's outline: rounded at the top, with feet that curve out
/// into the card below so tab and card are one surface.
struct TabGroundBounds: PreferenceKey {
    struct Value {
        var anchors: [String: Anchor<CGRect>] = [:]
        var attachment: CGFloat = 1
        var dragging = false
    }
    static var defaultValue: Value { Value() }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        let next = nextValue()
        if value.anchors["tab"] == nil, next.anchors["tab"] != nil {
            value.attachment = next.attachment
            value.dragging = next.dragging
        }
        value.anchors.merge(next.anchors) { first, _ in first }
    }
}

nonisolated struct TabShape: Shape {
    var attachment: CGFloat = 1
    var animatableData: CGFloat {
        get { attachment }
        set { attachment = newValue }
    }
    /// How far each foot reaches past the tab's side; also its radius.
    static let foot: CGFloat = 12
    static let corner: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let foot = Self.foot
        let corner = Self.corner
        let left = rect.minX + foot
        let right = rect.maxX - foot
        let attached = min(1, max(0, attachment))
        let bottom = rect.maxY - 2 * (1 - attached)
        let top = rect.minY + 2 * (1 - attached)
        let reach = corner * (1 - attached) - foot * attached
        let radius = corner * (1 - attached) + foot * attached
        let k: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: left + reach, y: bottom))
        path.addCurve(
            to: CGPoint(x: left, y: bottom - radius),
            control1: CGPoint(x: left + reach * (1 - k), y: bottom),
            control2: CGPoint(x: left, y: bottom - radius * (1 - k)))
        path.addLine(to: CGPoint(x: left, y: top + corner))
        path.addQuadCurve(to: CGPoint(x: left + corner, y: top), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right - corner, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + corner), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addCurve(
            to: CGPoint(x: right - reach, y: bottom),
            control1: CGPoint(x: right, y: bottom - radius * (1 - k)),
            control2: CGPoint(x: right - reach * (1 - k), y: bottom))
        path.closeSubpath()
        return path
    }
}

/// One tab in the strip.
private struct StripTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let width: CGFloat
    /// The rule before this tab.
    let ruled: Bool
    let ground: Namespace.ID
    @Binding var hovering: Bool
    let close: () -> Void
    var sharedGround = false
    var dragging = false

    @State private var shake: CGFloat = 0

    private var renaming: Bool { browser.editingTab == tab.id }
    private var pinned: Bool { tab.pin != nil && !renaming }
    /// Too narrow for a title: only the icon, with the title as a tooltip.
    private var iconOnly: Bool { !renaming && !pinned && !TabBar.widths.showsTitle(at: width) }
    /// The speaker, unless the loading ring has its place.
    private var speaker: Bool { !renaming && !tab.loading && (tab.noisy || tab.muted) }
    private var span: CGFloat { pinned ? Metrics.pinWidth : width }
    private var colour: Color { live ? Palette.ink : Palette.ink.opacity(hovering ? 0.85 : 0.62) }

    var body: some View {
        face
            .frame(width: span, height: Metrics.tabHeight)
            // A point taller than the tab, so its ground covers the card's edge.
            .padding(.bottom, 1)
            .background { backdrop }
            .overlay(alignment: .leading) {
                // The rule before the tab, gone beside the active and hovered tabs.
                Capsule().fill(Palette.ink.opacity(0.14)).frame(width: 1, height: 16)
                    .offset(x: -0.5 - Metrics.tabGap / 2, y: -2)
                    .opacity(ruled ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .shakesOnRefusal(browser.field.refusals, while: renaming, travel: $shake)
            .contentShape(Rectangle())
            // The active tab takes a double click (rename it, or change a pin's
            // letter); the others a single click.
            .modifier(OneClick(double: live) { press() })
            // Over the tab, not inside it: inside, its click would wait out the
            // double-click interval of the tab you're on before closing it.
            .overlay(alignment: .trailing) {
                if !renaming, !pinned, !iconOnly { Shut(shown: hovering || live, act: close).padding(.trailing, 6) }
            }
            .overlay { MiddleClick(act: close) }
            .onHover { hovering = $0 }
            .contextMenu { TabMenu(browser: browser, tab: tab, close: close) }
            .help(pinned || iconOnly ? tab.label : "")
            .environment(\.colorScheme, live ? browser.chromeScheme ?? colorScheme : colorScheme)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tab.label)
            .accessibilityAddTraits(live ? .isSelected : [])
            .animation(Motion.glide, value: tab.pin)
            .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
    }

    private func press() {
        if !live {
            browser.select(tab)
        } else if pinned {
            browser.editLetter(tab)
        } else {
            browser.beginTabRename(tab)
        }
    }

    @ViewBuilder
    private var face: some View {
        if pinned {
            pinFace.frame(width: 16, height: 16).padding(.top, 1)
        } else if iconOnly {
            icon.padding(.top, 1)
        } else {
            titled
        }
    }

    @ViewBuilder
    private var pinFace: some View {
        if browser.editingPin == tab.id {
            InlineField.letter(of: tab, in: browser)
        } else if tab.loading {
            Ring(size: 11)
        } else if prefs.glyph == .icons, let icon = tab.icon {
            Mark(icon: icon, letter: tab.pin ?? "", size: 16, dim: tab.asleep)
        } else {
            // Faded while the pinned tab sleeps.
            Text(tab.pin ?? "").font(.system(size: 12, weight: .medium)).foregroundStyle(colour.opacity(tab.asleep ? 0.45 : 1))
        }
    }

    /// The site's icon, or the loading ring in its place.
    private var icon: some View {
        ZStack {
            if tab.loading {
                Ring(size: 11).transition(.opacity)
            } else if prefs.glyph == .icons || iconOnly {
                Mark(icon: tab.isBlank ? nil : tab.icon, letter: tab.monogram, size: 16, dim: tab.asleep, mote: tab.isStart)
                    .transition(.opacity)
            }
        }
        .frame(width: 16, height: 16)
        .animation(Motion.quick, value: tab.loading)
    }

    private var titled: some View {
        HStack(spacing: 7) {
            if renaming {
                InlineField.rename(browser).frame(height: 16)
            } else {
                if prefs.glyph == .icons || tab.loading { icon }
                TabMarks(tab: tab, colour: colour)
                FadingTitle(text: tab.label, colour: colour)
                if speaker { Speaker(tab: tab).transition(.opacity) }
                // Room for the close button, which sits over the tab (see `body`).
                Color.clear.frame(width: 18, height: 18)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, renaming ? 11 : 6)
        .padding(.top, 1)
        .animation(Motion.quick, value: speaker)
    }

    @ViewBuilder
    private var backdrop: some View {
        if dragging, !live {
            RoundedRectangle(cornerRadius: TabShape.corner, style: .continuous)
                .fill(Palette.ground)
                .padding(.vertical, 2)
        } else if live {
            ZStack(alignment: .leading) {
                TabShape(attachment: dragging ? 0 : 1).fill(sharedGround && !dragging ? Color.clear : browser.chromeGround)
                // How far the page is read, as a thin line along the top. Not on
                // pinned or icon-only tabs, too narrow to show it.
                if !pinned, !iconOnly, prefs.showsReading {
                    ReadLine(reading: tab.reading, span: max(0, span - 2 * TabShape.corner))
                        .padding(.leading, TabShape.foot + TabShape.corner)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, -TabShape.foot)
            .anchorPreference(key: TabGroundBounds.self, value: .bounds) {
                sharedGround
                    ? .init(anchors: ["tab": $0], attachment: dragging ? 0 : 1, dragging: dragging) : .init()
            }
            .matchedGeometryEffect(id: "live", in: ground)
        } else {
            Rounded.row
                .fill(Palette.veil.opacity(hovering ? 1.2 : pinned ? 0.6 : 0))
                .padding(EdgeInsets(top: 2, leading: 2, bottom: 4, trailing: 2))
        }
    }
}
