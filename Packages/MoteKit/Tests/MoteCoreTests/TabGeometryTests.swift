import CoreGraphics
import Testing

@testable import MoteCore

@Suite("Tab geometry")
struct TabGeometryTests {
    @Test("A dragged tab moves by whole places and stays in the row")
    func rowTargets() {
        #expect(Reorder.target(from: 2, travel: 40, step: 100, count: 5) == 2)
        #expect(Reorder.target(from: 2, travel: 60, step: 100, count: 5) == 3)
        #expect(Reorder.target(from: 2, travel: -260, step: 100, count: 5) == 0)
        #expect(Reorder.target(from: 2, travel: 900, step: 100, count: 5) == 4)
    }

    @Test("In the pin grid a drag counts columns and rows separately")
    func gridTargets() {
        let step = CGSize(width: 60, height: 40)
        #expect(Reorder.target(from: 0, travel: CGSize(width: 70, height: 0), step: step, columns: 3, count: 6) == 1)
        #expect(Reorder.target(from: 0, travel: CGSize(width: 0, height: 45), step: step, columns: 3, count: 6) == 3)
        #expect(Reorder.target(from: 5, travel: CGSize(width: 500, height: 500), step: step, columns: 3, count: 6) == 5)
    }

    @Test("A dragged cell's offset is its travel less the slots already moved")
    func gridOffset() {
        let step = CGSize(width: 60, height: 40)
        let offset = Reorder.offset(travel: CGSize(width: 70, height: 45), step: step, columns: 3, from: 0, now: 4)
        #expect(offset == CGSize(width: 10, height: 5))
    }

    @Test("Pins sit in at least three columns, and more past six to keep two rows")
    func pinColumns() {
        #expect(PinGrid(count: 2, width: 220, gap: 6).columns == 3)
        #expect(PinGrid(count: 6, width: 220, gap: 6).columns == 3)
        #expect(PinGrid(count: 9, width: 220, gap: 6).columns == 5)
    }

    @Test("Pin cells share the width and are never taller than 36")
    func pinCells() {
        let grid = PinGrid(count: 3, width: 220, gap: 6)
        #expect(abs(grid.cell.width - 208.0 / 3) < 1e-9)
        #expect(grid.cell.height == 36)
        #expect(grid.height(4) == CGFloat(78))
        #expect(grid.height(0) == 0)
        #expect(PinGrid(count: 20, width: 100, gap: 6).cell.width == 20)
    }

    @Test("The strip's room leaves space for everything around the tabs")
    func stripRoom() {
        #expect(TabStrip.room(strip: 1000, lights: 84, dot: 0, plus: 32, dragRoom: 48, foot: 8) == 820)
        #expect(TabStrip.room(strip: 100, lights: 84, dot: 0, plus: 32, dragRoom: 48, foot: 8) == 0)
    }

    @Test("A spring's response and damping become Core Animation's stiffness and damping")
    func springs() {
        let curve = SpringCurve(response: 0.5, dampingFraction: 1)
        #expect(abs(curve.stiffness - pow(4 * .pi, 2)) < 1e-9)
        #expect(abs(curve.damping - 8 * .pi) < 1e-9)
        // Critical damping: damping² = 4 · mass · stiffness.
        #expect(abs(curve.damping * curve.damping - 4 * curve.mass * curve.stiffness) < 1e-6)
    }

    @Test("The swipe disc fills with the pull and eases to a stop")
    func disc() {
        #expect(SwipeDisc(travel: 0, going: false).progress == 0)
        #expect(SwipeDisc(travel: 220, going: false).progress == 1)
        #expect(abs(SwipeDisc(travel: 55, going: false).scale - 0.93) < 1e-9)
        #expect(SwipeDisc(travel: 5000, going: false).inset < 40.01)
        #expect(SwipeDisc(travel: 100, going: true).inset > SwipeDisc(travel: 100, going: false).inset)
    }

    @Test("Title bar double clicks follow the Mac's setting")
    func titleBar() {
        #expect(TitleBarClick(setting: nil) == .zoom)
        #expect(TitleBarClick(setting: "Minimize") == .minimize)
        #expect(TitleBarClick(setting: "None") == .nothing)
        #expect(TitleBarClick(setting: "Maximize") == .zoom)
    }
}
