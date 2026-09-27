import Testing

@testable import MoteCore

@Suite("TabRow")
struct TabRowTests {
    struct Tab: Identifiable, Equatable {
        let id: String
        var pinned = false
    }

    /// A row from a spec like "A* B* c d": starred names are pinned.
    private func row(_ spec: String) -> TabRow<Tab> {
        let tabs = spec.split(separator: " ").map { word in
            Tab(id: String(word.filter { $0 != "*" }), pinned: word.hasSuffix("*"))
        }
        return TabRow(tabs, isPinned: \.pinned)
    }

    private func names(_ row: TabRow<Tab>) -> String {
        row.tabs.map(\.id).joined(separator: " ")
    }

    private func moved(_ tabs: inout TabRow<Tab>, _ id: String, to index: Int) -> Bool {
        tabs.move(id, to: index)
    }

    @Test("New tabs open next to the active one")
    func nextToActive() {
        #expect(row("a b c").slotForNew(after: "a") == 1)
        #expect(row("a b c").slotForNew(after: "c") == 3)
    }

    @Test("New tabs never open among the pinned ones")
    func afterPins() {
        #expect(row("A* B* c").slotForNew(after: "A") == 2)
    }

    @Test("With no active tab, new tabs go at the end")
    func noActive() {
        #expect(row("a b").slotForNew(after: nil) == 2)
        #expect(row("a b").slotForNew(after: "gone") == 2)
    }

    @Test("Stepping wraps around both ends")
    func stepping() {
        let tabs = row("a b c")
        #expect(tabs.neighbour(of: "c", by: 1) == "a")
        #expect(tabs.neighbour(of: "a", by: -1) == "c")
        #expect(tabs.neighbour(of: "b", by: 1) == "c")
        #expect(row("a").neighbour(of: "a", by: 1) == nil)
    }

    @Test("Closing a tab hands over to its right neighbour, or the new last tab")
    func successor() {
        var tabs = row("a b c")
        let at = tabs.remove("b")
        #expect(at == 1)
        #expect(tabs.successor(ofRemovedAt: 1) == "c")
        tabs.remove("c")
        #expect(tabs.successor(ofRemovedAt: 1) == "a")
    }

    @Test("Dragging moves a tab to its final position")
    func drag() {
        var tabs = row("a b c d")
        #expect(moved(&tabs, "a", to: 2))
        #expect(names(tabs) == "b c a d")
        #expect(moved(&tabs, "d", to: 0))
        #expect(names(tabs) == "d b c a")
    }

    @Test("Dragging never crosses the pinned boundary")
    func dragBoundary() {
        var tabs = row("A* B* c d")
        #expect(!moved(&tabs, "c", to: 1))
        #expect(!moved(&tabs, "A", to: 3))
        #expect(moved(&tabs, "B", to: 0))
        #expect(names(tabs) == "B A c d")
    }

    @Test("A drag to the same place or off the row changes nothing")
    func dragNowhere() {
        var tabs = row("a b")
        #expect(!moved(&tabs, "a", to: 0))
        #expect(!moved(&tabs, "a", to: 5))
        #expect(names(tabs) == "a b")
    }

    @Test("A newly pinned tab goes to the end of the pinned tabs")
    func pinning() {
        var tabs = row("A* b c D*")
        tabs.settle("D")
        #expect(names(tabs) == "A D b c")
    }

    @Test("An unpinned tab goes to the start of the others")
    func unpinning() {
        var tabs = row("a B* C* d")
        tabs.settle("a")
        #expect(names(tabs) == "B C a d")
    }

    @Test("Closed tabs keep only the most recent")
    func recentlyClosed() {
        struct Entry: Identifiable { let id: Int }
        var closed = RecentlyClosed<Entry>(limit: 3)
        for n in 1...5 { closed.push(Entry(id: n)) }
        #expect(closed.entries.map(\.id) == [3, 4, 5])
        closed.remove(4)
        #expect(closed.entries.map(\.id) == [3, 5])
        #expect(closed.last?.id == 5)
    }
}
