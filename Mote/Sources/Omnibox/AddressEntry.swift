import Foundation
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
    var asksAssistant = false
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
        typed = ""
    }

    /// Opens the field in switcher mode, empty.
    func startSwitching() {
        input.switching = true
        typed = ""
    }

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
