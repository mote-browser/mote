import CoreGraphics
import Testing

@testable import MoteCore

@Suite("Tab geometry")
struct TabGeometryTests {
    @Test("A row, a column and a grid place their slots from the first")
    func latticeOrigins() {
        #expect(Lattice.row(step: 100).origin(3) == CGSize(width: 300, height: 0))
        #expect(Lattice.column(step: 34).origin(2) == CGSize(width: 0, height: 68))
        #expect(Lattice(columns: 3, step: CGSize(width: 60, height: 40)).origin(4) == CGSize(width: 60, height: 40))
    }

    @Test("A held tab lands on the nearest place, once past halfway, and stays in its section")
    func targets() {
        let row = Lattice.row(step: 100)
        #expect(row.target(from: 2, travel: CGSize(width: 40, height: 0), within: 0..<5) == 2)
        #expect(row.target(from: 2, travel: CGSize(width: 60, height: 0), within: 0..<5) == 3)
        #expect(row.target(from: 2, travel: CGSize(width: -260, height: 0), within: 0..<5) == 0)
        #expect(row.target(from: 2, travel: CGSize(width: 900, height: 0), within: 0..<5) == 4)
        // Pinned tabs 0 and 1 are another section.
        #expect(row.target(from: 3, travel: CGSize(width: -300, height: 0), within: 2..<5) == 2)
        // Up and down doesn't move a tab along a row.
        #expect(row.target(from: 2, travel: CGSize(width: 0, height: 400), within: 0..<5) == 2)
        #expect(Lattice.column(step: 34).target(from: 0, travel: CGSize(width: 90, height: 52), within: 0..<4) == 2)
    }

    @Test("In the pin grid a drag counts columns and rows, and keeps to the grid's edges")
    func gridTargets() {
        let grid = Lattice(columns: 3, step: CGSize(width: 60, height: 40))
        #expect(grid.target(from: 0, travel: CGSize(width: 70, height: 0), within: 0..<6) == 1)
        #expect(grid.target(from: 0, travel: CGSize(width: 0, height: 45), within: 0..<6) == 3)
        #expect(grid.target(from: 5, travel: CGSize(width: 500, height: 500), within: 0..<6) == 5)
        // Past the right edge it stays in its row rather than wrapping to the next.
        #expect(grid.target(from: 1, travel: CGSize(width: 400, height: 0), within: 0..<6) == 2)
        // A short last row: below it, the last pin.
        #expect(grid.target(from: 0, travel: CGSize(width: 120, height: 40), within: 0..<4) == 3)
    }

    @Test("While a tab is held it follows the pointer, and the order stays as it was")
    func heldFollows() {
        let column = Lattice.column(step: 34)
        var drag = ReorderDrag(id: "a", start: 0)
        drag.follow(CGSize(width: 3, height: 80), in: column, within: 0..<4)
        #expect(drag.target == 2)
        #expect(drag.offset(of: "a", at: 0, in: column) == CGSize(width: 0, height: 80))
    }

    @Test("The tabs between a held tab's place and where it would land step aside toward its place")
    func othersStepAside() {
        let column = Lattice.column(step: 34)
        var down = ReorderDrag(id: "a", start: 0)
        down.follow(CGSize(width: 0, height: 80), in: column, within: 0..<4)
        #expect(down.offset(of: "b", at: 1, in: column) == CGSize(width: 0, height: -34))
        #expect(down.offset(of: "c", at: 2, in: column) == CGSize(width: 0, height: -34))
        #expect(down.offset(of: "d", at: 3, in: column) == .zero)

        var up = ReorderDrag(id: "d", start: 3)
        up.follow(CGSize(width: 0, height: -40), in: column, within: 0..<4)
        #expect(up.offset(of: "c", at: 2, in: column) == CGSize(width: 0, height: 34))
        #expect(up.offset(of: "b", at: 1, in: column) == .zero)
    }

    @Test("In the grid a tab stepping aside goes to the next cell, across rows too")
    func gridStepAside() {
        let grid = Lattice(columns: 3, step: CGSize(width: 60, height: 40))
        var drag = ReorderDrag(id: 0, start: 0)
        drag.follow(CGSize(width: 60, height: 40), in: grid, within: 0..<6)
        #expect(drag.target == 4)
        // The first cell of the second row goes back to the end of the first.
        #expect(drag.offset(of: 3, at: 3, in: grid) == CGSize(width: 120, height: -40))
        #expect(drag.offset(of: 2, at: 2, in: grid) == CGSize(width: -60, height: 0))
        #expect(drag.offset(of: 5, at: 5, in: grid) == .zero)
    }

    @Test("Let go, the held tab stays where it was dropped from its new place, and the others are home")
    func landing() {
        let column = Lattice.column(step: 34)
        var drag = ReorderDrag(id: "a", start: 0)
        drag.follow(CGSize(width: 0, height: 80), in: column, within: 0..<4)
        drag.land()
        #expect(drag.landed)
        // Now third in the order: 80 down from the first place is 12 past the third.
        #expect(drag.offset(of: "a", at: 2, in: column) == CGSize(width: 0, height: 12))
        #expect(drag.offset(of: "b", at: 0, in: column) == .zero)
        #expect(drag.offset(of: "c", at: 1, in: column) == .zero)
        drag.settle(in: column)
        #expect(drag.landed)
        #expect(drag.id == "a")
        #expect(drag.offset(of: "a", at: 2, in: column) == .zero)
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
