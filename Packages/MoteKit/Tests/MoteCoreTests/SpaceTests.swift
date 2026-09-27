import Foundation
import Testing

@testable import MoteCore

@Suite("Spaces")
struct SpaceTests {
    private let work = Space(id: UUID(), name: "Work", icon: "briefcase", sharesSignIns: true)
    private let play = Space(id: UUID(), name: "Play", icon: "gamecontroller")

    @Test("The first space is made if missing and always comes first")
    func first() {
        let list = SpaceList(saved: [work, Space(id: Space.firstID, name: "Me")])
        #expect(list.spaces.map(\.name) == ["Me", "Work"])
        #expect(SpaceList(saved: []).spaces.map(\.name) == ["Personal"])
    }

    @Test("Icons fall back to a house or a briefcase, and new spaces get one not used yet")
    func icons() {
        #expect(Space(id: Space.firstID, name: "x").symbol == "house")
        #expect(Space(id: UUID(), name: "x", icon: "no-such-symbol").symbol == "briefcase")
        let list = SpaceList(saved: [work])
        #expect(list.freeIcon == "building.2")
    }

    @Test("Moving, editing and removing; the first space stays")
    func editing() {
        var list = SpaceList(saved: [work, play])
        let moved = list.move(play.id, to: 1)
        #expect(moved)
        #expect(list.spaces.map(\.name) == ["Personal", "Play", "Work"])
        let offEnd = list.move(play.id, to: 9)
        #expect(!offEnd)
        list.edit(work.id) { $0.name = "Job" }
        #expect(list.space(work.id)?.name == "Job")
        let first = list.remove(Space.firstID)
        #expect(first == nil)
        let gone = list.remove(play.id)
        #expect(gone?.name == "Play")
        #expect(list.spaces.count == 2)
    }

    @Test("Only spaces that asked share the first one's data")
    func sharing() {
        let list = SpaceList(saved: [work, play])
        #expect(list.sharing == [work.id])
        #expect(!work.ownData)
        #expect(play.ownData)
        #expect(!Space(id: Space.firstID, name: "x").ownData)
    }

    @Test("Older files, with a colour and no sharing, still read")
    func format() throws {
        let json = #"[{"id":"00000000-0000-0000-0000-000000000002","name":"Old","colour":3}]"#
        let old = try JSONDecoder().decode([Space].self, from: Data(json.utf8))
        #expect(old.first?.ownData == true)
        #expect(old.first?.symbol == "briefcase")
    }
}
