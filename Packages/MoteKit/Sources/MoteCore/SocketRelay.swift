import Foundation

/// The messages between the shim and Mote for an extension worker's
/// WebSocket, which Mote opens for it: a worker opening one itself would
/// deadlock WebKit.
public enum SocketRelay {
    public enum Command: Equatable, Sendable {
        /// "here?" (answer "here") or "alive" (nothing to answer), sent on every native port.
        case probe(answer: Bool)
        case open(address: String, protocols: [String], userAgent: String?)
        case send(String)
        case sendBinary(Data)
        case close(code: Int?, reason: String?)
    }

    public static func command(_ message: Any?) -> Command? {
        guard let message = message as? [String: Any] else { return nil }
        if let word = message["__moteNative"] { return .probe(answer: (word as? String) == "here?") }
        if let address = message["open"] as? String {
            return .open(address: address, protocols: message["protocols"] as? [String] ?? [], userAgent: message["userAgent"] as? String)
        }
        if let text = message["send"] as? String { return .send(text) }
        if let encoded = message["sendBinary"] as? String, let data = Data(base64Encoded: encoded) { return .sendBinary(data) }
        if message["close"] != nil { return .close(code: message["close"] as? Int, reason: message["reason"] as? String) }
        return nil
    }

    /// The request Chrome would make: only ws and wss, with the extension's
    /// origin, its user agent, and the protocols it offers.
    public static func request(_ address: String, origin: String, protocols: [String], userAgent: String?) -> URLRequest? {
        guard let url = URL(string: address), ["ws", "wss"].contains(url.scheme?.lowercased()) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(origin, forHTTPHeaderField: "Origin")
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if !protocols.isEmpty { request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol") }
        return request
    }

    // What Mote tells the shim.
    public static var ready: [String: Any] { ["ready": true] }
    public static var here: [String: Any] { ["__moteNative": "here"] }
    public static func opened(_ chosen: String?) -> [String: Any] { ["opened": chosen ?? ""] }
    public static func text(_ text: String) -> [String: Any] { ["text": text] }
    public static func binary(_ data: Data) -> [String: Any] { ["binary": data.base64EncodedString()] }
    public static func closed(_ code: Int, reason: String = "", clean: Bool) -> [String: Any] {
        ["closed": code, "reason": reason, "clean": clean]
    }
    public static var failed: [String: Any] { ["failed": true] }
    /// Closed without a status, and closed abnormally, as WebSocket reports them.
    public static let noStatus = 1005
    public static let abnormal = 1006
}
