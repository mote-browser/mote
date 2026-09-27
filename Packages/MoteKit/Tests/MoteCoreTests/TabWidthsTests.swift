import CoreGraphics
import Testing

@testable import MoteCore

@Suite("TabWidths")
struct TabWidthsTests {
    private let widths = TabWidths(widest: 220, narrowest: 36, titled: 80, pinned: 36, gap: 2)

    @Test("A few tabs get the widest width")
    func roomy() {
        #expect(widths.loose(room: 1000, pins: 0, count: 2) == 220)
        #expect(!widths.overflows(room: 1000, pins: 0, count: 2))
    }

    @Test("Crowded tabs share the room evenly, after the pinned ones and the gaps")
    func shares() {
        // 3 pins at 36 and 9 gaps of 2 leave 1000 - 108 - 18 = 874 for 7 tabs.
        let each = widths.loose(room: 1000, pins: 3, count: 10)
        #expect(abs(each - 874.0 / 7) < 1e-9)
        #expect(abs(widths.row(room: 1000, pins: 3, count: 10) - 1000) < 1e-9)
        #expect(!widths.overflows(room: 1000, pins: 3, count: 10))
    }

    @Test("Tabs stop shrinking at the narrowest width and the row scrolls")
    func overflows() {
        #expect(widths.loose(room: 300, pins: 0, count: 40) == 36)
        #expect(widths.overflows(room: 300, pins: 0, count: 40))
    }

    @Test("Only pinned tabs means no loose width to share")
    func onlyPinned() {
        #expect(widths.loose(room: 300, pins: 4, count: 4) == 220)
        #expect(widths.row(room: 300, pins: 4, count: 4) == CGFloat(4 * 36 + 3 * 2))
    }

    @Test("An empty row has no width")
    func empty() {
        #expect(widths.row(room: 300, pins: 0, count: 0) == 0)
    }

    @Test("Narrow tabs drop their titles")
    func titles() {
        #expect(widths.showsTitle(at: 80))
        #expect(!widths.showsTitle(at: 79))
    }
}
