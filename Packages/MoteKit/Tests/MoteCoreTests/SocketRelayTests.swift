import Foundation
import Testing

@testable import MoteCore

@Suite("SocketRelay")
struct SocketRelayTests {
    @Test("The shim's messages read as commands")
    func commands() {
        #expect(SocketRelay.command(["__moteNative": "here?"]) == .probe(answer: true))
        #expect(SocketRelay.command(["__moteNative": "alive"]) == .probe(answer: false))
        #expect(
            SocketRelay.command(["open": "wss://a.b/s", "protocols": ["x"], "userAgent": "UA"])
                == .open(address: "wss://a.b/s", protocols: ["x"], userAgent: "UA"))
        #expect(SocketRelay.command(["send": "hi"]) == .send("hi"))
        #expect(SocketRelay.command(["sendBinary": Data([1, 2]).base64EncodedString()]) == .sendBinary(Data([1, 2])))
        #expect(SocketRelay.command(["sendBinary": "!!not base64"]) == nil)
        #expect(SocketRelay.command(["close": 4000, "reason": "bye"]) == .close(code: 4000, reason: "bye"))
        #expect(SocketRelay.command(["close": true]) == .close(code: nil, reason: nil))
        #expect(SocketRelay.command("text") == nil)
    }

    @Test("Only ws and wss, with Chrome's headers")
    func requests() {
        let request = SocketRelay.request("WSS://a.b/s", origin: "chrome-extension://x", protocols: ["p1", "p2"], userAgent: "UA")
        #expect(request?.value(forHTTPHeaderField: "Origin") == "chrome-extension://x")
        #expect(request?.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "p1, p2")
        #expect(request?.value(forHTTPHeaderField: "User-Agent") == "UA")
        #expect(SocketRelay.request("https://a.b/", origin: "o", protocols: [], userAgent: nil) == nil)
        #expect(
            SocketRelay.request("ws://a.b/", origin: "o", protocols: [], userAgent: nil)?.value(
                forHTTPHeaderField: "Sec-WebSocket-Protocol") == nil)
    }
}
