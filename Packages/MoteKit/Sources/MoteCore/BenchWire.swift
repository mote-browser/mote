import CoreGraphics
import Foundation

/// The bench's wire: one JSON object on a line in, one on a line out, one
/// request per connection.
public enum BenchWire {
    /// Longer requests are refused.
    public static let largest = 4_000_000

    public enum Read: Equatable {
        /// No whole line yet.
        case more
        case request(BenchRequest)
        case refused(String)
    }

    public static func read(_ bytes: Data) -> Read {
        if bytes.count > largest { return .refused("request too long") }
        guard let end = bytes.firstIndex(of: 0x0A) else { return .more }
        guard let object = try? JSONSerialization.jsonObject(with: bytes[bytes.startIndex..<end]) as? [String: Any] else {
            return .refused("not a JSON object")
        }
        return .request(BenchRequest(object))
    }

    /// An answer, on its line.
    public static func line(_ answer: [String: Any]) -> Data {
        ((try? JSONSerialization.data(withJSONObject: answer)) ?? Data(#"{"error":"unwritable answer"}"#.utf8)) + Data([0x0A])
    }

    /// A value from a page, as JSON can carry it.
    public static func plain(_ value: Any?) -> Any {
        guard let value else { return NSNull() }
        return JSONSerialization.isValidJSONObject(["v": value]) ? value : String(describing: value)
    }

    /// A tab's short id: the first eight of its UUID, lowercased.
    public static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }

    /// Whether `ref` names this tab: a prefix of its UUID, any case.
    public static func names(_ ref: String, _ id: UUID) -> Bool {
        !ref.isEmpty && id.uuidString.lowercased().hasPrefix(ref.lowercased())
    }

    /// Page text is cut here.
    public static let longestText = 120_000

    public static func cut(_ text: String) -> (text: String, cut: Bool) {
        text.count > longestText ? (String(text.prefix(longestText)), true) : (text, false)
    }

    /// US-layout key code for a letter, as WebKit reads it with the
    /// characters; anything else is the space bar.
    public static func keyCode(for character: Character) -> UInt16 {
        let codes: [Character: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        ]
        return codes[Character(character.lowercased())] ?? 49
    }

    /// A frame of a stepped resize: `t` of the way from one size to the
    /// other, keeping the top edge where it was.
    public static func resized(_ from: CGRect, to size: CGSize, _ t: CGFloat) -> CGRect {
        var frame = from
        frame.size = CGSize(width: from.width + (size.width - from.width) * t, height: from.height + (size.height - from.height) * t)
        frame.origin.y = from.maxY - frame.height
        return frame
    }

    /// What the display drew: how many frames, the longest gap, and gaps
    /// long enough to be missed frames, in milliseconds.
    public static func frames(_ stamps: [Double], refreshMs: Double) -> [String: Any] {
        let gaps = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }
        return [
            "frames": stamps.count, "refreshMs": refreshMs, "longestMs": gaps.max() ?? 0,
            "missed": gaps.filter { $0 > refreshMs * 1.5 }.count,
            "gapsMs": gaps.map { ($0 * 10).rounded() / 10 },
        ]
    }
}

/// A bench request, read by its keys.
public struct BenchRequest: @unchecked Sendable, Equatable {
    public let values: [String: Any]

    public init(_ values: [String: Any]) { self.values = values }

    public var verb: String { string("do") ?? "" }

    public func string(_ key: String) -> String? { values[key] as? String }
    public func double(_ key: String) -> Double? { values[key] as? Double }
    public func int(_ key: String) -> Int? { values[key] as? Int }
    public func bool(_ key: String) -> Bool? { values[key] as? Bool }
    public func strings(_ key: String) -> [String] { values[key] as? [String] ?? [] }
    public func flag(_ key: String) -> Bool { bool(key) == true }

    /// How long before the bench answers for it: `wait` gets its own seconds
    /// and a little more, everything else 25.
    public var patience: Double { verb == "wait" ? (double("seconds") ?? 30) + 5 : 25 }

    /// Modifier names ("cmd", "shift", "opt", "ctrl") given with a key or click.
    public var modifiers: Set<String> { Set(strings("mods")) }

    public static func == (a: Self, b: Self) -> Bool { NSDictionary(dictionary: a.values).isEqual(to: b.values) }
}
