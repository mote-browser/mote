import Foundation
import MoteCore

/// Each space's open tabs, saved so they come back at launch: address,
/// title, pin letter and given name, and which tab was in front.
enum Session {
    nonisolated struct Entry: Codable, Sendable {
        var url: String
        var title: String
        var pin: String?
        /// A name the user gave the tab.
        var name: String?
    }

    nonisolated struct Saved: Codable, Sendable {
        var tabs: [Entry]
        var active: Int

        static let empty = Saved(tabs: [], active: 0)
    }

    /// session.json for the first space, session-<id>.json for others.
    private static func file(_ space: UUID) -> JSONFile<Saved> {
        JSONFile(space == Space.firstID ? "session.json" : "session-\(space.uuidString).json")
    }

    static func read(space: UUID = Space.firstID) -> Saved {
        file(space).load() ?? .empty
    }

    /// `now` saves before returning, for quitting.
    static func write(now: Bool = false, space: UUID = Space.firstID, _ saved: Saved) {
        now ? file(space).saveNow(saved) : file(space).save(saved)
    }

    static func erase(space: UUID) {
        if space != Space.firstID { file(space).delete() }
    }
}
