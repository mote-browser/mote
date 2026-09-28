import Foundation

/// What the address field holds while someone types: the text, the
/// suggestions under it, the inline completion after the caret and the
/// suggestion picked with the arrow keys.
///
/// It decides what Return means but does no navigation itself; the caller
/// acts on the returned `Submission`.
public struct AddressInput: Equatable, Sendable {
    public var typed = ""
    public private(set) var offers: [Suggestion] = []
    /// Inline completion shown after the caret; Tab accepts it.
    public private(set) var ending: String?
    /// The suggestion selected with the arrow keys.
    public var picked: Int?
    /// Tab-switcher mode (⌘K): only open tabs are offered.
    public var switching = false

    public init() {}

    public enum Submission: Equatable, Sendable {
        /// Switch to an open tab, or load `url` if it has gone.
        case switchTo(tab: UUID, url: URL)
        case go(URL)
        /// The switcher was closed with nothing typed.
        case close
        /// Nothing typed resolves to a place.
        case refuse
    }

    /// The typed text plus the inline completion or the picked suggestion.
    public var completed: String {
        if let picked, offers.indices.contains(picked) { return offers[picked].key }
        return typed + (ending ?? "")
    }

    public var isBlank: Bool { typed.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Replaces the suggestions. In the switcher the first is picked, so
    /// ⌘K then Return goes to the most recent tab; otherwise any pick is
    /// dropped because the input changed.
    public mutating func offer(_ offers: [Suggestion], ending: String?) {
        self.offers = offers
        self.ending = ending
        picked = switching && !offers.isEmpty ? 0 : nil
    }

    /// Drops the inline completion (after a backspace).
    public mutating func stopCompleting() { ending = nil }

    /// Tab or → at the end of the input: takes the inline completion.
    /// Returns the new text, or nil when there was nothing to take.
    public func acceptingEnding() -> String? {
        guard let ending, !ending.isEmpty else { return nil }
        return typed + ending
    }

    /// Moves the pick with the arrow keys; stepping past either end clears it.
    public mutating func walk(_ step: Int) {
        guard !offers.isEmpty else { return }
        guard let here = picked else {
            picked = step > 0 ? 0 : offers.count - 1
            return
        }
        let next = here + step
        picked = offers.indices.contains(next) ? next : nil
    }

    /// Whether Return asks the assistant rather than going somewhere: when
    /// the assistant leads, for anything but an address or a suggestion
    /// picked with the arrows. Never in the tab switcher.
    public func asks(assistantLeads: Bool, address: (String) -> URL?) -> Bool {
        guard assistantLeads, !switching, !isBlank, picked == nil else { return false }
        return address(typed.trimmingCharacters(in: .whitespaces)) == nil
    }

    /// What Return does: the picked suggestion, then the inline completion,
    /// then the typed text, which `destination` turns into an address or a
    /// search. `address` only accepts addresses (a completion is never a
    /// search).
    public mutating func submit(address: (String) -> URL?, destination: (String) -> URL?) -> Submission {
        let pick = picked.flatMap { offers.indices.contains($0) ? offers[$0] : nil }
        if let pick, let tab = pick.tab {
            switching = false
            return .switchTo(tab: tab, url: pick.url)
        }
        if switching {
            switching = false
            if isBlank { return .close }
        }
        let target = pick?.url ?? (ending != nil ? address(completed) : destination(typed))
        return target.map(Submission.go) ?? .refuse
    }
}
