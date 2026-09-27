import Foundation
import Testing

@testable import MoteCore

@Suite("AddressInput")
struct AddressInputTests {
    private let apple = Suggestion(key: "apple.com", title: "Apple", url: URL(string: "https://apple.com")!, kind: .visited)
    private let tab = Suggestion(
        key: "Docs", title: "docs.swift.org", url: URL(string: "https://docs.swift.org")!, kind: .open, tab: UUID())
    private let search = Suggestion(key: "apples", title: "Search", url: URL(string: "https://s.test/?q=apples")!, kind: .search)

    private func address(_ text: String) -> URL? { text.contains(".") ? URL(string: "https://\(text)") : nil }
    private func destination(_ text: String) -> URL? { address(text) ?? URL(string: "https://s.test/?q=\(text)") }

    private func submit(_ input: inout AddressInput) -> AddressInput.Submission {
        input.submit(address: address, destination: destination)
    }

    @Test("The arrows walk the list and stepping off either end clears the pick")
    func walking() {
        var input = AddressInput()
        input.offer([apple, search], ending: nil)
        input.walk(1)
        #expect(input.picked == 0)
        input.walk(1)
        #expect(input.picked == 1)
        input.walk(1)
        #expect(input.picked == nil)
        input.walk(-1)
        #expect(input.picked == 1)
    }

    @Test("New suggestions drop the pick, except in the switcher, which picks the first")
    func offering() {
        var input = AddressInput()
        input.offer([apple], ending: nil)
        input.walk(1)
        input.offer([apple, search], ending: nil)
        #expect(input.picked == nil)
        input.switching = true
        input.offer([tab], ending: nil)
        #expect(input.picked == 0)
        input.offer([], ending: nil)
        #expect(input.picked == nil)
    }

    @Test("The completed text is the pick, or the typed text plus the completion")
    func completed() {
        var input = AddressInput()
        input.typed = "app"
        input.offer([apple], ending: "le.com")
        #expect(input.completed == "apple.com")
        #expect(input.acceptingEnding() == "apple.com")
        input.stopCompleting()
        #expect(input.completed == "app")
        #expect(input.acceptingEnding() == nil)
    }

    @Test("Return on an open tab switches to it")
    func switchesToTab() {
        var input = AddressInput()
        input.switching = true
        input.offer([tab], ending: nil)
        #expect(submit(&input) == .switchTo(tab: tab.tab!, url: tab.url))
        #expect(!input.switching)
    }

    @Test("Return in an empty switcher just closes it")
    func emptySwitcher() {
        var input = AddressInput()
        input.switching = true
        #expect(submit(&input) == .close)
    }

    @Test("Return prefers the pick, then the completion, then the typed text")
    func order() {
        var input = AddressInput()
        input.typed = "app"
        input.offer([apple, search], ending: "le.com")
        input.walk(-1)
        #expect(submit(&input) == .go(search.url))
        input.picked = nil
        #expect(submit(&input) == .go(URL(string: "https://apple.com")!))
        input.stopCompleting()
        #expect(submit(&input) == .go(URL(string: "https://s.test/?q=app")!))
    }

    @Test("Text that is neither an address nor searchable is refused")
    func refused() {
        var input = AddressInput()
        input.typed = "nope"
        let outcome = input.submit(address: address, destination: { _ in nil })
        #expect(outcome == .refuse)
    }
}
