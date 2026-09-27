import Foundation
import Testing

@testable import MoteCore

@Suite("HiddenElements")
struct HiddenElementsTests {
    private func element(_ selector: String) -> HiddenElement {
        HiddenElement(selector: selector, label: selector, date: Date(timeIntervalSince1970: 0))
    }

    @Test("Hiding keeps order and ignores a selector already hidden")
    func hide() {
        var hidden = HiddenElements()
        let added = [
            hidden.hide(element(".a"), on: "x.com"), hidden.hide(element(".b"), on: "x.com"), hidden.hide(element(".a"), on: "x.com"),
        ]
        #expect(added == [true, true, false])
        #expect(hidden.on("x.com").map(\.selector) == [".a", ".b"])
        #expect(hidden.on("y.com").isEmpty)
        #expect(hidden.on(nil).isEmpty)
    }

    @Test("Undo brings back the latest; a site left empty is dropped")
    func undo() {
        var hidden = HiddenElements()
        hidden.hide(element(".a"), on: "x.com")
        hidden.hide(element(".b"), on: "x.com")
        let first = hidden.undo(on: "x.com")
        #expect(first?.selector == ".b")
        let second = hidden.undo(on: "x.com")
        #expect(second?.selector == ".a")
        #expect(hidden.bySite["x.com"] == nil)
        let none = hidden.undo(on: "x.com")
        #expect(none == nil)
    }

    @Test("Restoring one or all")
    func restore() {
        var hidden = HiddenElements()
        hidden.hide(element(".a"), on: "x.com")
        hidden.hide(element(".b"), on: "x.com")
        hidden.restore(".a", on: "x.com")
        #expect(hidden.on("x.com").map(\.selector) == [".b"])
        hidden.restore(".b", on: "x.com")
        #expect(hidden.bySite.isEmpty)
        hidden.hide(element(".c"), on: "y.com")
        hidden.restoreAll(on: "y.com")
        #expect(hidden.bySite.isEmpty)
    }

    @Test("Saved as a plain object of sites, as before")
    func json() throws {
        let saved = #"{"x.com":[{"selector":".ad","label":"Ad","note":"300×250","date":0}]}"#
        let hidden = try JSONDecoder().decode(HiddenElements.self, from: Data(saved.utf8))
        #expect(
            hidden.on("x.com") == [
                HiddenElement(selector: ".ad", label: "Ad", note: "300×250", date: Date(timeIntervalSinceReferenceDate: 0))
            ])
        let again = try JSONDecoder().decode(HiddenElements.self, from: JSONEncoder().encode(hidden))
        #expect(again == hidden)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(hidden)) as? [String: Any]
        #expect(object?.keys.sorted() == ["x.com"])
    }
}
