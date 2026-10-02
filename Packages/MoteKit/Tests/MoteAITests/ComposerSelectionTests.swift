import Testing

@testable import MoteAI

@Suite("Composer selection")
struct ComposerSelectionTests {
    @Test("The first Down and first Up highlight opposite ends")
    func startsAtEitherEnd() {
        var selection = ComposerSelection()

        selection.move(1, count: 3)
        #expect(selection.highlightedIndex == 0)

        selection.reset()
        selection.move(-1, count: 3)
        #expect(selection.highlightedIndex == 2)
    }

    @Test("Moving past either end wraps around")
    func wraps() {
        var selection = ComposerSelection()

        selection.move(-1, count: 3)
        selection.move(1, count: 3)
        #expect(selection.highlightedIndex == 0)

        selection.move(-1, count: 3)
        #expect(selection.highlightedIndex == 2)
    }

    @Test("Confirmation chooses the highlight or defaults to the first item")
    func confirms() {
        var selection = ComposerSelection()
        #expect(selection.confirmedIndex(count: 3) == 0)

        selection.move(1, count: 3)
        selection.move(1, count: 3)
        #expect(selection.confirmedIndex(count: 3) == 1)
    }

    @Test("Empty menus have no confirmation and clear the highlight")
    func empty() {
        var selection = ComposerSelection()
        selection.move(1, count: 2)
        selection.move(1, count: 0)

        #expect(selection.highlightedIndex == nil)
        #expect(selection.confirmedIndex(count: 0) == nil)
    }

    @Test("Keyboard selection remains aligned beyond the old six-row display limit")
    func selectionPastOldDisplayLimit() {
        var selection = ComposerSelection()

        for _ in 0..<7 { selection.move(1, count: 7) }

        #expect(selection.confirmedIndex(count: 7) == 6)
    }
}
