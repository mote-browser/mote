import MoteCore
import SwiftUI

/// Swiping between spaces over the tabs, with a trackpad or a mouse wheel.
/// Scroll events come here before any view; only gestures that start over
/// the tabs and run along the spaces are kept (ScrollGate, SpacePager), and
/// the rest scroll as usual.
@MainActor
final class SpaceSwipe {
    static let shared = SpaceSwipe()

    private weak var browser: Browser?
    private var watch: Any?
    private var pager = SpacePager(count: 0, here: 0, enough: 50)
    private var gate = ScrollGate()

    func start(for browser: Browser) {
        self.browser = browser
        guard watch == nil else { return }
        watch = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { SpaceSwipe.shared.keeps(event) } ? nil : event
        }
    }

    /// Where the tabs stand among the spaces (the count is the new-space
    /// card), and how far a swipe must go: 50 pt in the sidebar, most of the
    /// strip's height over it, so scrolling a page just below doesn't switch.
    private func refresh(_ browser: Browser) {
        pager.count = browser.spaces.count
        pager.here = browser.makingSpace ? browser.spaces.count : browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0
        pager.enough = browser.prefs.sidebar ? 50 : ChromeLayout.strip * 0.6
    }

    private func overTabs(_ event: NSEvent, in browser: Browser) -> Bool {
        guard let window = event.window, window === AppDelegate.window else { return false }
        let at = event.locationInWindow
        return browser.prefs.sidebar ? at.x < browser.prefs.sideWidth : at.y > window.frame.height - ChromeLayout.strip
    }

    private func keeps(_ event: NSEvent) -> Bool {
        guard let browser, browser.prefs.usesSpaces, !browser.folded || browser.peeking else { return false }
        guard event.hasPreciseScrollingDeltas else { return wheel(event, in: browser) }
        switch gate.verdict(Self.phase(of: event), over: overTabs(event, in: browser)) {
        case .pass:
            return false
        case .swallow:
            return true
        case .begin:
            began()
            return gate.ignoring || moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        case .move:
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        case .end(let cancelled):
            let claimed = pager.isClaimed
            ended(cancelled: cancelled)
            gate.coast(claimed)
            return claimed
        }
    }

    /// A mouse wheel over the strip: a space a notch.
    private func wheel(_ event: NSEvent, in browser: Browser) -> Bool {
        guard !browser.prefs.sidebar, event.scrollingDeltaY != 0, overTabs(event, in: browser) else { return false }
        refresh(browser)
        if let target = pager.click(down: event.scrollingDeltaY < 0, at: Date()) { slide(browser, to: target, from: pager.here) }
        return true
    }

    private static func phase(of event: NSEvent) -> ScrollGate.Phase {
        if !event.momentumPhase.isEmpty { return .momentum }
        switch event.phase {
        case .began: return .began
        case .changed: return .changed
        case .ended: return .ended
        case .cancelled: return .cancelled
        default: return .other
        }
    }

    // MARK: - The gesture, which the bench drives directly too

    func began() {
        guard let browser else { return }
        refresh(browser)
        gate.begin(allowed: pager.begin(at: Date()))
    }

    /// Whether the gesture is taken as a swipe between spaces.
    @discardableResult
    func moved(dx: CGFloat, dy: CGFloat) -> Bool {
        guard gate.tracking, let browser else { return false }
        let (along, aside) = browser.prefs.sidebar ? (dx, dy) : (dy, dx)
        guard let offset = pager.move(along: along, aside: aside) else { return false }
        browser.spaceSwipe = offset
        return true
    }

    /// Along the spaces, whichever way they run.
    @discardableResult
    func moved(along travel: CGFloat) -> Bool {
        guard let browser else { return false }
        return browser.prefs.sidebar ? moved(dx: travel, dy: 0) : moved(dx: 0, dy: travel)
    }

    func ended(cancelled: Bool = false) {
        defer { gate.stop() }
        guard let browser, pager.isClaimed else { return }
        if let target = pager.end(cancelled: cancelled) {
            slide(browser, to: target, from: pager.here)
        } else {
            withAnimation(Motion.settle) { browser.spaceSwipe = 0 }
        }
    }

    /// Slides a whole page over, then switches with animation off so the
    /// swap can't be seen. `spaces.count` is the new-space card.
    func slide(_ browser: Browser, to target: Int, from here: Int) {
        // A page: the sidebar's width, or the strip's height.
        let page = browser.prefs.sidebar ? browser.prefs.sideWidth : ChromeLayout.strip
        let forward = target > here
        browser.spaceStep = forward ? 1 : -1
        pager.switched(at: Date())
        withAnimation(.easeOut(duration: 0.22), completionCriteria: .removed) {
            browser.spaceSwipe = (forward ? -1 : 1) * page
        } completion: {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                browser.makingSpace = target == browser.spaces.count
                if !browser.makingSpace { browser.switchSpace(to: browser.spaces[target].id) }
                browser.spaceSwipe = 0
            }
        }
    }
}

/// Making a space, in the place past the last one: a row in the strip, or
/// a card in the sidebar.
struct NewSpaceCard: View {
    @ObservedObject var browser: Browser
    /// One row, for the strip.
    var inline = false

    @State private var name = ""
    @State private var icon = "briefcase"
    @State private var choosingIcon = false
    /// Signed in wherever the other spaces are.
    @State private var shared = true
    @State private var hovering = false
    @FocusState private var typing: Bool

    private var explanation: String {
        shared ? "Signed in to the same sites as your other spaces." : "Separate cookies and sign-ins, starting empty."
    }

    private var sharing: some View {
        Segmented(options: [(true, "Signed in"), (false, "Signed out")], selection: $shared, wide: !inline)
    }

    var body: some View {
        Group {
            if inline {
                HStack(spacing: 8) {
                    iconButton(size: 13, box: CGSize(width: 28, height: 26))
                    nameField.frame(width: 170)
                    sharing.fixedSize().help(explanation)
                    Pill("Cancel", action: cancel)
                    Pill("Create", filled: true, action: create)
                }
                .frame(height: ChromeLayout.strip)
            } else {
                VStack(spacing: 12) {
                    iconButton(size: 20, box: CGSize(width: 44, height: 40))
                    VStack(spacing: 4) {
                        Text("New space").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                        Text("A separate set of tabs.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    nameField
                    VStack(spacing: 6) {
                        sharing
                        Text(explanation)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Pill("Cancel", action: cancel)
                        Pill("Create", filled: true, action: create)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            icon = browser.freeIcon
            Task { @MainActor in typing = true }
        }
        .onExitCommand(perform: cancel)
    }

    /// The icon, opening the icon picker.
    private func iconButton(size: CGFloat, box: CGSize) -> some View {
        Button {
            choosingIcon = true
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: box.width, height: box.height)
                .background(
                    hovering || choosingIcon ? Palette.hover : .clear,
                    in: RoundedRectangle(cornerRadius: inline ? 8 : 10, style: .continuous)
                )
                .contentShape(Rectangle())
                .id(icon)
                .transition(.opacity)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(inline ? "New space: choose its icon" : "Choose an icon")
        .popover(isPresented: $choosingIcon, arrowEdge: .bottom) { iconPicker }
    }

    private var nameField: some View {
        TextField(inline ? "New space" : "Name", text: $name)
            .textFieldStyle(.plain)
            .font(.system(size: inline ? 12.5 : 13))
            .padding(.horizontal, 10)
            .frame(height: inline ? 26 : 30)
            .background(Palette.wash, in: Rounded.row)
            .focused($typing)
            .onSubmit(create)
    }

    /// Every icon; picking one closes the picker.
    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 6), spacing: 4) {
            ForEach(Space.icons, id: \.symbol) { symbol, name in
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(symbol == icon ? Palette.ink : Palette.muted)
                    .frame(width: 28, height: 28)
                    .background(symbol == icon ? Palette.wash : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(Motion.quick) { icon = symbol }
                        choosingIcon = false
                        typing = true
                    }
                    .help(name)
            }
        }
        .padding(10)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return typing = true }
        browser.addSpace(named: trimmed, icon: icon, sharesSignIns: shared)
    }

    /// Slides back to the space the card was opened from.
    private func cancel() {
        SpaceSwipe.shared.slide(browser, to: browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0, from: browser.spaces.count)
    }
}
