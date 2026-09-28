import MoteCore
import SwiftUI

// Switching between spaces and changing them.
extension Browser {
    var space: Space { spaces.first { $0.id == spaceID } ?? spaces[0] }
    /// The tabs of every space not showing, for tab sleep.
    var parkedTabs: [Tab] { parked.values.flatMap(\.tabs) }
    var freeIcon: String { SpaceList(saved: spaces).freeIcon }

    /// This space's downloads folder, or the one in Settings.
    var downloadsFolder: URL {
        guard prefs.usesSpaces, let path = space.downloads else { return prefs.downloads }
        return URL(fileURLWithPath: path)
    }

    func switchSpace(to id: UUID) {
        if prefs.usesSpaces { enter(id) }
    }

    func switchSpace(index: Int) {
        if spaces.indices.contains(index) { switchSpace(to: spaces[index].id) }
    }

    /// Parks this space's tabs as they are (their media keeps playing) and
    /// shows the other's.
    private func enter(_ id: UUID) {
        guard id != spaceID, let to = spaces.firstIndex(where: { $0.id == id }) else { return }
        // Which way the space's icon slides.
        if !makingSpace { spaceStep = to > (spaces.firstIndex { $0.id == spaceID } ?? 0) ? 1 : -1 }
        cancelTabEdit()
        if floater.showing { land() }
        writeSession(now: true)
        parked[spaceID] = Parked(tabs: tabs, active: activeID)

        spaceID = id
        Spaces.current = id
        Storage.settings.set(id.uuidString, forKey: "space.current")
        if let back = parked.removeValue(forKey: id), !back.tabs.isEmpty {
            showRow(back.tabs, active: back.active)
            if let active, !active.wake() { active.revive() }
        } else {
            showRow([], active: nil)
            restoreSession()
        }
        editing = active?.isStart ?? true
        field.clear()
        field.askFocus()
        announce(space.name)
    }

    /// Builds the other spaces' rows ahead, so a swipe can show the next one
    /// sliding in.
    func preloadSpaces() {
        for space in spaces where space.id != spaceID && parked[space.id] == nil {
            parked[space.id] = loadRow(space.id)
        }
    }

    /// Returns to the first space when spaces are turned off. The others are
    /// kept, for when they're turned back on.
    func leaveSpaces() {
        enter(Space.firstID)
        parkedTabs.forEach { $0.close() }
        parked = [:]
    }

    /// Changes the list and saves it.
    private func editSpaces(_ change: (inout SpaceList) -> Void) {
        var list = SpaceList(saved: spaces)
        change(&list)
        spaces = list.spaces
        Spaces.write(spaces)
    }

    /// A new, empty space, gone to at once.
    func addSpace(named name: String, icon: String? = nil, sharesSignIns: Bool = true) {
        makingSpace = false
        let made = Space(id: UUID(), name: name, icon: icon ?? freeIcon, sharesSignIns: sharesSignIns)
        editSpaces { $0.add(made) }
        switchSpace(to: made.id)
    }

    func moveSpace(_ id: UUID, to index: Int) { editSpaces { $0.move(id, to: index) } }

    func renameSpace(_ id: UUID, to name: String) {
        if !name.isEmpty { editSpaces { $0.edit(id) { $0.name = name } } }
    }

    func setSpaceIcon(_ id: UUID, to icon: String) { editSpaces { $0.edit(id) { $0.icon = icon } } }
    func setSpaceDownloads(_ id: UUID, to folder: URL?) { editSpaces { $0.edit(id) { $0.downloads = folder?.path } } }

    /// The new-space card, or a dialog when the tabs are folded away.
    func askForSpace() {
        if !folded || peeking {
            SpaceSwipe.shared.start(for: self)
            SpaceSwipe.shared.slide(self, to: spaces.count, from: spaces.firstIndex { $0.id == spaceID } ?? 0)
        } else {
            Prompt.newSpace { name, shared in self.addSpace(named: name, sharesSignIns: shared) }
        }
    }

    /// Deletes a space, its tabs and, unless it shared the first space's,
    /// its website data. The first space stays.
    func deleteSpace(_ id: UUID) {
        guard let doomed = SpaceList(saved: spaces).space(id), !doomed.isFirst else { return }
        if spaceID == id { switchSpace(to: Space.firstID) }
        parked.removeValue(forKey: id)?.tabs.forEach { $0.close() }
        editSpaces { $0.remove(id) }
        Session.erase(space: id)
        if doomed.ownData { Spaces.erase(id) }
    }
}
