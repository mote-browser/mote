import CoreGraphics
import Foundation
import Testing

@testable import MoteCore

@Suite("BenchWire")
struct BenchWireTests {
    @Test("A request is one JSON object on a line")
    func reading() {
        #expect(BenchWire.read(Data(#"{"do":"tabs"}"#.utf8)) == .more)
        guard case .request(let request) = BenchWire.read(Data("{\"do\":\"wait\",\"seconds\":3}\nrest".utf8)) else {
            Issue.record("no request")
            return
        }
        #expect(request.verb == "wait" && request.patience == 8)
        #expect(BenchWire.read(Data("[1,2]\n".utf8)) == .refused("not a JSON object"))
        #expect(BenchWire.read(Data(count: BenchWire.largest + 1)) == .refused("request too long"))
    }

    @Test("Answers go out as a line; odd page values as text")
    func writing() throws {
        let line = BenchWire.line(["ok": true])
        #expect(line.last == 0x0A)
        #expect(try JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Bool] == ["ok": true])
        #expect(BenchWire.plain(nil) is NSNull)
        #expect(BenchWire.plain([1, 2]) as? [Int] == [1, 2])
        #expect(BenchWire.plain(Date(timeIntervalSince1970: 0)) is String)
    }

    @Test("Requests read typed values; patience is 25 s except for waiting")
    func requests() {
        let request = BenchRequest(["do": "press", "code": 17, "mods": ["cmd", "shift"], "yes": true, "x": 1.5])
        #expect(request.int("code") == 17 && request.double("x") == 1.5 && request.flag("yes") && !request.flag("no"))
        #expect(request.modifiers == ["cmd", "shift"] && request.patience == 25)
        #expect(BenchRequest(["do": "wait"]).patience == 35)
        #expect(BenchRequest(["do": "chat", "action": "wait", "seconds": 90.0]).patience == 95)
        #expect(BenchRequest(["do": "chat", "action": "show"]).patience == 25)
    }

    @Test("Tabs are named by the start of their id")
    func ids() {
        let id = UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890")!
        #expect(BenchWire.short(id) == "abcdef12")
        #expect(BenchWire.names("ABC", id) && BenchWire.names("abcdef12-34", id))
        #expect(!BenchWire.names("", id) && !BenchWire.names("bcd", id))
    }

    @Test("Text is cut at 120 000 characters, key codes follow the US layout")
    func textAndKeys() {
        #expect(BenchWire.cut("short") == ("short", false))
        #expect(BenchWire.cut(String(repeating: "x", count: 120_001)).text.count == 120_000)
        #expect(BenchWire.keyCode(for: "T") == 17 && BenchWire.keyCode(for: "!") == 49)
    }

    @Test("A stepped resize keeps the top edge")
    func resize() {
        let from = CGRect(x: 10, y: 100, width: 800, height: 600)
        let half = BenchWire.resized(from, to: CGSize(width: 1000, height: 400), 0.5)
        #expect(half == CGRect(x: 10, y: 200, width: 900, height: 500))
        #expect(half.maxY == from.maxY)
    }

    @Test("Frame gaps count as missed past one and a half refreshes")
    func frames() {
        let summary = BenchWire.frames([0, 0.016, 0.032, 0.080], refreshMs: 16)
        #expect(summary["frames"] as? Int == 4 && summary["missed"] as? Int == 1)
        #expect(summary["gapsMs"] as? [Double] == [16, 16, 48])
        #expect(BenchWire.frames([], refreshMs: 16)["longestMs"] as? Double == 0)
    }
}
