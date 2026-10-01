import Foundation
import MoteAI
import MoteCore
import Observation

/// The address field's state: what is typed, what is suggested under it, and
/// requests to focus it or to shake it for an input that goes nowhere.
///
/// The rules live in `AddressInput`; this adds what the views observe and
/// asks `suggest` for fresh suggestions whenever the text or the mode changes.
@MainActor
@Observable
final class AddressEntry {
    private(set) var input = AddressInput()
    /// Incremented when the input is neither an address nor searchable.
    private(set) var refusals = 0
    /// Incremented to ask for keyboard focus.
    private(set) var focusRequest = 0
    /// Return asks the assistant rather than searching: switched on in a new
    /// tab's composer (⌘J), and off again for every new tab.
    var asksAssistant = false {
        didSet {
            guard oldValue != asksAssistant else { return }
            clearStagedMentions()
            refresh()
        }
    }
    struct StagedMention: Equatable, Identifiable {
        let id: UUID
        let url: URL
        let title: String
    }

    /// Temporary selections for the initial new-tab assistant ask.
    private(set) var stagedMentions: [StagedMention] = []
    var stagedMentionIDs: [UUID] { stagedMentions.map(\.id) }
    /// The selected pages are being freshly read before the first request.
    var capturingMentionContext = false
    /// Whether ⌘ is still held since the first ⌘K.
    @ObservationIgnored var cycling = false

    /// Suggestions and inline completion for the text, in the given mode
    /// (true for the tab switcher).
    @ObservationIgnored var suggest: (_ typed: String, _ switching: Bool) -> ([Suggestion], String?) = { _, _ in ([], nil) }

    var typed: String {
        get { input.typed }
        set {
            input.typed = newValue
            refresh()
        }
    }

    /// Tab-switcher mode (⌘K), which lists only open tabs.
    var switching: Bool {
        get { input.switching }
        set {
            guard input.switching != newValue else { return }
            input.switching = newValue
            if newValue { clearStagedMentions() }
            refresh()
        }
    }

    var offers: [Suggestion] { input.offers }
    var ending: String? { input.ending }
    var completed: String { input.completed }

    var picked: Int? {
        get { input.picked }
        set { input.picked = newValue }
    }

    /// Empties the field and leaves switcher mode.
    func clear() {
        input.switching = false
        asksAssistant = false
        clearStagedMentions()
        typed = ""
    }

    /// Opens the field in switcher mode, empty.
    func startSwitching() {
        input.switching = true
        clearStagedMentions()
        typed = ""
    }

    @discardableResult
    func stageMention(_ id: UUID, url: URL, title: String) -> Bool {
        guard !stagedMentionIDs.contains(id), stagedMentions.count < Conversation.mentionLimit else { return false }
        stagedMentions.append(StagedMention(id: id, url: url, title: title))
        return true
    }

    func unstageMention(_ id: UUID) { stagedMentions.removeAll { $0.id == id } }

    func clearStagedMentions() { stagedMentions = [] }

    func walk(_ step: Int) { input.walk(step) }
    func stopCompleting() { input.stopCompleting() }

    func acceptEnding() {
        if let text = input.acceptingEnding() { typed = text }
    }

    func submit(address: @escaping (String) -> URL?, destination: @escaping (String) -> URL?) -> AddressInput.Submission {
        input.submit(address: address, destination: destination)
    }

    func refuse() { refusals += 1 }
    func askFocus() { focusRequest += 1 }

    private func refresh() {
        let (offers, ending) = suggest(input.typed, input.switching)
        input.offer(offers, ending: ending)
    }
}
