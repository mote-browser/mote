import Foundation
import Testing

@testable import Mote

@Suite("Native host pipe")
struct HostPipeTests {
    /// A host that sends back whatever it's sent: Chrome's framing both ways.
    private func echoHost() throws -> URL {
        let host = FileManager.default.temporaryDirectory.appendingPathComponent("mote-echo-\(UUID().uuidString).sh")
        try "#!/bin/sh\nexec cat\n".write(to: host, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: host.path)
        return host
    }

    @available(macOS 15.4, *)
    @Test("A message goes out framed and its answer comes back")
    func roundTrip() async throws {
        let host = try echoHost()
        defer { try? FileManager.default.removeItem(at: host) }
        let pipe = HostPipe(program: host, origin: "chrome-extension://test/")
        try pipe.start()
        defer { pipe.stop() }
        try pipe.write(["hello": "host", "n": 3])
        let answer = try await pipe.readOne() as? [String: Any]
        #expect(answer?["hello"] as? String == "host" && answer?["n"] as? Int == 3)
        try pipe.write("second")
        #expect(try await pipe.readOne() as? String == "second")
    }

    @available(macOS 15.4, *)
    @Test("Waiting for an answer from a host that exits fails instead of hanging")
    func exits() async throws {
        let host = FileManager.default.temporaryDirectory.appendingPathComponent("mote-quit-\(UUID().uuidString).sh")
        try "#!/bin/sh\nexit 0\n".write(to: host, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: host.path)
        defer { try? FileManager.default.removeItem(at: host) }
        let pipe = HostPipe(program: host, origin: "chrome-extension://test/")
        try pipe.start()
        await #expect(throws: NativeHostExit.self) { try await pipe.readOne() }
    }
}
