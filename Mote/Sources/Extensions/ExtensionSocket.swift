import Foundation
import MoteCore
import WebKit

// WebSockets for extension workers. WebKit runs those workers on the web
// process's main thread, and a WebSocket opened there waits on that very
// thread: the extension locks up. So the shim asks Mote, which opens it with
// URLSession and passes frames over a native port (SocketRelay), sending the
// origin and user agent Chrome would.

@available(macOS 15.4, *)
@MainActor
enum ExtensionSocket {
    /// The native app name the shim connects to for a socket.
    static let name = ExtensionShims.application + ".socket"

    private static let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
    /// Kept until either side closes.
    private static var open: [ObjectIdentifier: Connection] = [:]

    static func connect(_ port: WKWebExtension.MessagePort, from extensionID: String) {
        let connection = Connection(port: port, origin: "\(Extensions.scheme)://\(extensionID)")
        let key = ObjectIdentifier(connection)
        open[key] = connection
        connection.onEnd = { open[key] = nil }
    }

    @MainActor
    final class Connection: NSObject, URLSessionWebSocketDelegate {
        private let port: WKWebExtension.MessagePort
        private let origin: String
        private var socket: URLSessionWebSocketTask?
        private var ended = false
        var onEnd: (() -> Void)?

        init(port: WKWebExtension.MessagePort, origin: String) {
            self.port = port
            self.origin = origin
            super.init()
            port.messageHandler = { [weak self] message, _ in MainActor.assumeIsolated { self?.heard(message) } }
            port.disconnectHandler = { [weak self] _ in MainActor.assumeIsolated { self?.end(closingPort: false) } }
            // WebKit can drop a port opened early in a worker's life; this
            // tells the shim this one made it.
            tell(SocketRelay.ready)
        }

        private func heard(_ message: Any?) {
            switch SocketRelay.command(message) {
            case .probe(let answer):
                if answer { tell(SocketRelay.here) }
            case .open(let address, let protocols, let userAgent):
                // The shim says "open" until it hears "ready"; a repeat is
                // only answered.
                tell(SocketRelay.ready)
                if socket == nil { start(address, protocols: protocols, userAgent: userAgent) }
            case .send(let text):
                socket?.send(.string(text)) { _ in }
            case .sendBinary(let data):
                socket?.send(.data(data)) { _ in }
            case .close(let code, let reason):
                socket?.cancel(
                    with: code.flatMap(URLSessionWebSocketTask.CloseCode.init) ?? .normalClosure, reason: reason.map { Data($0.utf8) })
            case nil:
                break
            }
        }

        private func start(_ address: String, protocols: [String], userAgent: String?) {
            guard let request = SocketRelay.request(address, origin: origin, protocols: protocols, userAgent: userAgent) else {
                return fail()
            }
            let socket = ExtensionSocket.session.webSocketTask(with: request)
            socket.delegate = self
            self.socket = socket
            socket.resume()
        }

        /// Frames in, until the socket ends; its closing comes through the delegate.
        private func listen(to socket: URLSessionWebSocketTask) {
            Task { [weak self] in
                while let frame = try? await socket.receive() {
                    guard let self, !ended else { return }
                    switch frame {
                    case .string(let text): tell(SocketRelay.text(text))
                    case .data(let data): tell(SocketRelay.binary(data))
                    @unknown default: break
                    }
                }
            }
        }

        private func tell(_ message: [String: Any]) {
            if !port.isDisconnected { port.sendMessage(message, completionHandler: nil) }
        }

        private func fail() {
            tell(SocketRelay.failed)
            tell(SocketRelay.closed(SocketRelay.abnormal, clean: false))
            end(closingPort: true)
        }

        private func end(closingPort: Bool) {
            guard !ended else { return }
            ended = true
            socket?.cancel(with: .goingAway, reason: nil)
            if closingPort, !port.isDisconnected { port.disconnect() }
            onEnd?()
        }

        nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol chosen: String?) {
            MainActor.assumeIsolated {
                tell(SocketRelay.opened(chosen))
                listen(to: webSocketTask)
            }
        }

        nonisolated func urlSession(
            _ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            MainActor.assumeIsolated {
                tell(SocketRelay.closed(closeCode.rawValue, reason: reason.map { String(decoding: $0, as: UTF8.self) } ?? "", clean: true))
                end(closingPort: true)
            }
        }

        nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            MainActor.assumeIsolated {
                guard !ended else { return }
                guard error == nil else { return fail() }
                tell(SocketRelay.closed(SocketRelay.noStatus, clean: true))
                end(closingPort: true)
            }
        }
    }
}
