import Foundation
import MoteCore
import WebKit

// Chrome native messaging: apps on this Mac an extension talks to over their
// stdin and stdout. Mote finds them where Chromium browsers register them, and
// runs one only if its manifest names the extension.

@available(macOS 15.4, *)
enum NativeMessaging {
    /// The program for host `name`, if it's registered and lets this extension in.
    private static func program(_ name: String, for extensionID: String) throws -> URL {
        guard NativeHosts.isValidName(name) else { throw NativeHosts.Refusal.badName }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in NativeHosts.folders {
            let folder = URL(fileURLWithPath: path.hasPrefix("~") ? home + path.dropFirst() : path)
            guard let manifest = try? Data(contentsOf: folder.appendingPathComponent(name + ".json")),
                let program = try NativeHosts.program(in: manifest, folder: folder, for: extensionID)
            else { continue }
            guard FileManager.default.isExecutableFile(atPath: program.path) else { throw NativeHosts.Refusal.notFound }
            return program
        }
        throw NativeHosts.Refusal.notFound
    }

    private static func start(_ name: String, for extensionID: String) throws -> HostPipe {
        let pipe = HostPipe(program: try program(name, for: extensionID), origin: NativeHosts.origin(of: extensionID))
        try pipe.start()
        return pipe
    }

    /// runtime.sendNativeMessage: the host runs for one message and its answer.
    static func send(_ message: Any, to name: String, from extensionID: String) async throws -> Any? {
        let pipe = try start(name, for: extensionID)
        defer { pipe.stop() }
        try pipe.write(message)
        return try await pipe.readOne()
    }

    /// runtime.connectNative: messages both ways until either side lets go.
    @MainActor
    static func connect(_ port: WKWebExtension.MessagePort, from extensionID: String) throws {
        guard let name = port.applicationIdentifier else { throw NativeHosts.Refusal.notFound }
        // A new port is often a restarted worker whose old host still runs.
        stopOrphans()
        let pipe = try start(name, for: extensionID)
        pipe.onMessage = { message in DispatchQueue.main.async { port.sendMessage(message, completionHandler: nil) } }
        pipe.onExit = { DispatchQueue.main.async { if !port.isDisconnected { port.disconnect() } } }
        let heartbeat = Heartbeat(port)
        port.messageHandler = { message, _ in
            guard let message else { return }
            if heartbeat.answers(message) { return }
            try? pipe.write(message)
        }
        port.disconnectHandler = { _ in
            heartbeat.stop()
            pipe.stop()
        }
        Running.keep(pipe, for: port)
    }

    /// Stops hosts whose ports went away: unloading an extension drops its
    /// ports without their disconnect handlers, which would leave hosts running.
    @MainActor
    static func stopOrphans() {
        for (pipe, port) in Running.pipes.values where port.isDisconnected { pipe.stop() }
    }

    /// Hosts connected to a port, kept until they exit.
    private enum Running {
        nonisolated(unsafe) static var pipes: [ObjectIdentifier: (pipe: HostPipe, port: WKWebExtension.MessagePort)] = [:]

        static func keep(_ pipe: HostPipe, for port: WKWebExtension.MessagePort) {
            let key = ObjectIdentifier(pipe)
            pipes[key] = (pipe, port)
            let exited = pipe.onExit
            pipe.onExit = {
                exited?()
                DispatchQueue.main.async { pipes[key] = nil }
            }
        }
    }

    /// The shim asks whether a port reaches Mote ("here?"), and is told so
    /// here, never by the host. Then, every 25 seconds, a word the worker
    /// answers ("alive"): WebKit unloads a worker that hasn't posted on a port
    /// for two minutes, where Chrome keeps one with a native port.
    @MainActor
    private final class Heartbeat {
        private let port: WKWebExtension.MessagePort
        private var timer: Timer?

        init(_ port: WKWebExtension.MessagePort) { self.port = port }

        /// Whether the message was the shim's, not the host's.
        func answers(_ message: Any) -> Bool {
            guard let word = (message as? [String: Any])?["__moteNative"] else { return false }
            guard (word as? String) == "here?" else { return true }
            port.sendMessage(["__moteNative": "here"], completionHandler: nil)
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.beat() }
                }
            }
            return true
        }

        private func beat() {
            guard !port.isDisconnected else { return stop() }
            port.sendMessage(["__moteNative": "alive"], completionHandler: nil)
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }
    }
}

/// A host process, messages framed as Chrome frames them. Its reader runs in
/// the background; `lock` guards what it shares.
@available(macOS 15.4, *)
nonisolated final class HostPipe: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var waiting: [CheckedContinuation<Message?, Error>] = []
    var onMessage: ((Any) -> Void)?
    var onExit: (() -> Void)?

    /// JSONSerialization's containers can't change, so one may cross threads.
    private struct Message: @unchecked Sendable { let value: Any }

    init(program: URL, origin: String) {
        process.executableURL = program
        process.arguments = [origin]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // Writing to a host that exited would raise SIGPIPE and take Mote
        // down; this makes the write fail instead.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return finish()
            }
            received(chunk)
        }
        process.terminationHandler = { [weak self] _ in self?.finish() }
        try process.run()
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    func write(_ message: Any) throws {
        try input.fileHandleForWriting.write(contentsOf: NativeHosts.frame(message))
    }

    /// The next message, for a one-off exchange.
    func readOne() async throws -> Any? {
        try await withCheckedThrowingContinuation { answer in
            lock.withLock { waiting.append(answer) }
        }?.value
    }

    /// Whole messages go first to anyone waiting, the rest to `onMessage`.
    private func received(_ chunk: Data) {
        let (answered, rest): ([(CheckedContinuation<Message?, Error>, Any)], [Any]) = lock.withLock {
            buffer.append(chunk)
            let messages = NativeHosts.messages(from: &buffer)
            let answered = zip(waiting, messages).map { ($0, $1) }
            waiting.removeFirst(answered.count)
            return (answered, Array(messages.dropFirst(answered.count)))
        }
        answered.forEach { $0.0.resume(returning: Message(value: $0.1)) }
        rest.forEach { onMessage?($0) }
    }

    private func finish() {
        let pending = lock.withLock {
            defer { waiting = [] }
            return waiting
        }
        pending.forEach { $0.resume(throwing: NativeHostExit()) }
        onExit?()
        onExit = nil
    }
}

/// A host that exited before answering.
struct NativeHostExit: LocalizedError {
    var errorDescription: String? { "Native host has exited." }
}
