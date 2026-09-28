import AppKit
import Combine
import MoteCore
import SwiftUI

/// Dragging a tab to a new place along the strip, down the sidebar or
/// across the pin grid (see ReorderDrag). The held tab follows the pointer
/// and the tabs it passes step aside; the order changes on letting go, when
/// the held tab eases from where it was dropped into its new place.
struct Reorderable: ViewModifier {
    let id: Tab.ID
    let index: Int
    /// The places the tab may take: its section of the row.
    let places: Range<Int>
    let lattice: Lattice
    /// The list's coordinate space. Measured in the tab's own space, the
    /// origin would move whenever the tab did.
    let space: String
    /// The list's drag, one for all its tabs.
    @Binding var drag: ReorderDrag<Tab.ID>?
    let move: (Int) -> Void

    func body(content: Content) -> some View {
        let held = drag?.id == id
        let following = held && drag?.landed == false
        content
            .offset(drag?.offset(of: id, at: index, in: lattice) ?? .zero)
            // The held tab follows the pointer without animation, even as the
            // others step aside with one.
            .transaction { if following { $0.animation = nil } }
            .zIndex(held ? 1 : 0)
            .shadow(color: .black.opacity(following ? 0.14 : 0), radius: 12, y: 4)
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named(space))
                    .onChanged { changed($0.translation) }
                    .onEnded { _ in ended() }
            )
            .onReceive(ScriptedDrag.shared.$travel) { travel in
                guard ScriptedDrag.shared.tab == id else { return }
                if let travel { changed(travel) } else { ended() }
            }
    }

    private func changed(_ travel: CGSize) {
        // A tab still easing home is done; one held elsewhere keeps the drag.
        if drag?.landed == true { drag = nil }
        if let drag, drag.id != id { return }
        var next = drag ?? ReorderDrag(id: id, start: index)
        let before = next.target
        next.follow(travel, in: lattice, within: places)
        if next.target == before {
            drag = next
        } else {
            withAnimation(Motion.settle) { drag = next }
        }
    }

    private func ended() {
        guard var landing = drag, landing.id == id, !landing.landed else { return }
        landing.land()
        // The new order and the offsets that keep every tab where it is on
        // screen, in one update with nothing animated: the list's own animation
        // of the order would otherwise slide tabs from their old places.
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            if landing.target != landing.start { move(landing.target) }
            drag = landing
        }
        let settling = $drag
        DispatchQueue.main.async {
            guard settling.wrappedValue == landing else { return }
            withAnimation(Motion.settle) { settling.wrappedValue = nil }
        }
    }
}

/// A drag the bench plays on a tab, a frame at a time, through the same
/// steps as the pointer's (Tools/bench tabdrag).
@MainActor
final class ScriptedDrag: ObservableObject {
    static let shared = ScriptedDrag()
    private(set) var tab: Tab.ID?
    /// How far the drag has gone; nil once let go.
    @Published private(set) var travel: CGSize?

    /// Drags `tab` by `distance` over `seconds`, then lets go.
    func play(_ tab: Tab.ID, by distance: CGSize, over seconds: Double, then done: @escaping () -> Void) {
        self.tab = tab
        let steps = max(2, Int(seconds * 120))
        for n in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds * Double(n) / Double(steps)) {
                let part = CGFloat(n) / CGFloat(steps)
                self.travel = CGSize(width: distance.width * part, height: distance.height * part)
                guard n == steps else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.travel = nil
                    self.tab = nil
                    done()
                }
            }
        }
    }
}

/// One click, or a double click, never both: with both, SwiftUI holds every
/// single click back for the double-click interval.
struct OneClick: ViewModifier {
    let double: Bool
    let act: () -> Void

    func body(content: Content) -> some View {
        content.onTapGesture(count: double ? 2 : 1, perform: act)
    }
}

/// A middle click. SwiftUI has no gesture for it, so this AppKit overlay
/// only takes part in hit-testing for middle-button events and lets
/// everything else through (see DragStrip).
struct MiddleClick: NSViewRepresentable {
    let act: () -> Void

    func makeNSView(context: Context) -> NSView { Catcher() }
    func updateNSView(_ view: NSView, context: Context) { (view as? Catcher)?.act = act }

    private final class Catcher: NSView {
        var act: () -> Void = {}
        private var down = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, [.otherMouseDown, .otherMouseUp].contains(event.type), event.buttonNumber == 2
            else { return nil }
            return super.hitTest(point)
        }

        override func otherMouseDown(with event: NSEvent) { down = true }

        /// On release inside, so sliding off first cancels.
        override func otherMouseUp(with event: NSEvent) {
            defer { down = false }
            if down, bounds.contains(convert(event.locationInWindow, from: nil)) { act() }
        }
    }
}
