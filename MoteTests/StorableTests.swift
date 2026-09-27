import Foundation
import Testing

@testable import Mote

@Suite("Storable")
@MainActor
struct StorableTests {
    @Test("Booleans read as UserDefaults reads them, text from the command line included")
    func booleans() {
        #expect(Bool(stored: true) == true)
        #expect(Bool(stored: NSNumber(value: false)) == false)
        #expect(Bool(stored: "YES") == true)
        #expect(Bool(stored: "true") == true)
        #expect(Bool(stored: "1") == true)
        #expect(Bool(stored: "NO") == false)
        #expect(Bool(stored: "0") == false)
        #expect(Bool(stored: [1]) == nil)
    }

    @Test("Widths read from numbers or text")
    func widths() {
        #expect(CGFloat(stored: 240.0) == 240)
        #expect(CGFloat(stored: "212.5") == 212.5)
        #expect(CGFloat(stored: "wide") == nil)
    }

    @Test("A missing or unreadable value falls back")
    func fallback() throws {
        let store = try #require(UserDefaults(suiteName: "mote.storable.tests"))
        defer { store.removePersistentDomain(forName: "mote.storable.tests") }
        #expect(store.value("absent", or: true) == true)
        store.set("YES", forKey: "given")
        #expect(store.value("given", or: false) == true)
        store.set([1, 2], forKey: "odd")
        #expect(store.value("odd", or: false) == false)
    }
}
