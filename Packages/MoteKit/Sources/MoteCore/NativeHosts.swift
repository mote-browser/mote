import Foundation

/// Chrome's native messaging: which app an extension may talk to, and how
/// messages travel (four bytes of length, little-endian, then JSON).
public enum NativeHosts {
    public enum Refusal: LocalizedError, Equatable {
        case badName, forbidden, notFound, tooLong

        public var errorDescription: String? {
            switch self {
            case .badName: "Invalid native messaging host name"
            case .forbidden: "Access to the specified native messaging host is forbidden."
            case .notFound: "Specified native messaging host not found."
            case .tooLong: "Message too long for a native host"
            }
        }
    }

    /// Where Chromium browsers keep hosts' manifests, from the home folder
    /// ("~/…") or the whole Mac ("/…"), in the order they're looked in.
    public static let folders = [
        "~/Library/Application Support/Google/Chrome/NativeMessagingHosts", "~/Library/Application Support/Chromium/NativeMessagingHosts",
        "~/Library/Application Support/Microsoft Edge/NativeMessagingHosts",
        "~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
        "~/Library/Application Support/Arc/User Data/NativeMessagingHosts", "/Library/Google/Chrome/NativeMessagingHosts",
        "/Library/Application Support/Chromium/NativeMessagingHosts", "/Library/Microsoft/Edge/NativeMessagingHosts",
    ]

    public static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9_]+(\.[a-z0-9_]+)*$"#, options: .regularExpression) != nil
    }

    public static func origin(of extensionID: String) -> String { "chrome-extension://\(extensionID)/" }

    /// The program a host's manifest names, when it lets this extension in:
    /// an absolute path, or one relative to the manifest's folder. nil when
    /// the manifest can't be read; a refusal when it names someone else.
    public static func program(in manifest: Data, folder: URL, for extensionID: String) throws -> URL? {
        guard let manifest = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any], let path = manifest["path"] as? String
        else {
            return nil
        }
        guard (manifest["allowed_origins"] as? [String] ?? []).contains(origin(of: extensionID)) else { throw Refusal.forbidden }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
    }

    /// The biggest message Chrome sends a host.
    public static let largest = 1 << 20

    public static func frame(_ message: Any) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed])
        guard json.count <= largest else { throw Refusal.tooLong }
        var length = UInt32(json.count).littleEndian
        return Data(bytes: &length, count: 4) + json
    }

    /// The whole messages at the start of `buffer`, taken out of it; a
    /// message that isn't JSON is dropped.
    public static func messages(from buffer: inout Data) -> [Any] {
        var found: [Any] = []
        while buffer.count >= 4 {
            let length = Int(buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
            guard buffer.count >= 4 + length else { break }
            let body = buffer.subdata(in: buffer.startIndex + 4..<buffer.startIndex + 4 + length)
            buffer = buffer.subdata(in: buffer.startIndex + 4 + length..<buffer.endIndex)
            if let message = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) { found.append(message) }
        }
        return found
    }
}
