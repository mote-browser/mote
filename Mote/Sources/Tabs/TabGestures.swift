import AppKit
import MoteCore
import SwiftUI

/// Dragging a tab to a new place along the strip or down the sidebar. Only
/// the dragged tab keeps drag state, so moving the pointer redraws it alone;
/// the list redraws only when the tab changes place.
struct Reorderable: ViewModifier {
    let index: Int
    let count: Int
    /// From one place to the next: a tab's length plus the gap.
    let step: CGFloat
    let vertical: Bool
    /// The list's coordinate space. Measured in the tab's own space, the
    /// origin would jump each time the tab changed place.
    let space: String
    let move: (Int) -> Void

    @State private var start: Int?
    @State private var travel: CGFloat = 0

    func body(content: Content) -> some View {
        // The drag less the places already moved through.
        let shift = start.map { travel - CGFloat(index - $0) * step } ?? 0
        content
            .offset(x: vertical ? 0 : shift, y: vertical ? shift : 0)
            // The dragged tab follows the pointer without animation; animating its
            // offset along with its new place makes it jump and drift back.
            .transaction { if start != nil { $0.animation = nil } }
            .zIndex(start == nil ? 0 : 1)
            .shadow(color: .black.opacity(start == nil ? 0 : 0.14), radius: 12, y: 4)
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named(space))
                    .onChanged { drag in
                        let from = start ?? index
                        start = from
                        travel = vertical ? drag.translation.height : drag.translation.width
                        let target = Reorder.target(from: from, travel: travel, step: step, count: count)
                        if target != index { withAnimation(Motion.settle) { move(target) } }
                    }
                    .onEnded { _ in
                        withAnimation(Motion.settle) {
                            start = nil
                            travel = 0
                        }
                    })
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
