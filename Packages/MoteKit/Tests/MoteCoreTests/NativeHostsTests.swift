import Foundation
import Testing

@testable import MoteCore

@Suite("NativeHosts")
struct NativeHostsTests {
    @Test("Host names are dotted lowercase words")
    func names() {
        #expect(NativeHosts.isValidName("com.1password.native_host"))
        #expect(!NativeHosts.isValidName("Com.Upper"))
        #expect(!NativeHosts.isValidName("../escape"))
        #expect(!NativeHosts.isValidName("a..b"))
    }

    @Test("A manifest lets in only the extensions it names, and paths may be relative")
    func manifests() throws {
        let folder = URL(fileURLWithPath: "/hosts")
        let manifest = Data(#"{"path": "bin/host", "allowed_origins": ["chrome-extension://abc/"]}"#.utf8)
        #expect(try NativeHosts.program(in: manifest, folder: folder, for: "abc")?.path == "/hosts/bin/host")
        #expect(throws: NativeHosts.Refusal.forbidden) { try NativeHosts.program(in: manifest, folder: folder, for: "xyz") }
        let absolute = Data(#"{"path": "/opt/host", "allowed_origins": ["chrome-extension://abc/"]}"#.utf8)
        #expect(try NativeHosts.program(in: absolute, folder: folder, for: "abc")?.path == "/opt/host")
        #expect(try NativeHosts.program(in: Data("nope".utf8), folder: folder, for: "abc") == nil)
    }

    @Test("Frames round-trip, split across reads or several in one")
    func frames() throws {
        let one = try NativeHosts.frame(["a": 1])
        let two = try NativeHosts.frame("two")
        #expect(one.prefix(4) == Data([7, 0, 0, 0]))
        var buffer = one + two.prefix(3)
        let first = NativeHosts.messages(from: &buffer)
        #expect(first.count == 1 && (first[0] as? [String: Int]) == ["a": 1])
        #expect(buffer.count == 3)
        buffer += two.dropFirst(3)
        let second = NativeHosts.messages(from: &buffer)
        #expect(second.first as? String == "two" && buffer.isEmpty)
        var junk = Data([2, 0, 0, 0]) + Data("{x".utf8) + one
        #expect(NativeHosts.messages(from: &junk).count == 1)
        #expect(throws: NativeHosts.Refusal.tooLong) { try NativeHosts.frame(String(repeating: "x", count: NativeHosts.largest)) }
    }
}
