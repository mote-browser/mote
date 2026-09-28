import Foundation

/// A JSON value read without a schema, for the many loosely shaped lines
/// providers send, where a missing field means "not this kind of line".
public enum JSON: Equatable, Sendable, Decodable {
    case object([String: JSON])
    case array([JSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    /// The value of a line, or nil when it isn't JSON.
    public init?(parsing text: some StringProtocol) {
        guard let value = try? JSONDecoder().decode(JSON.self, from: Data(text.utf8)) else { return nil }
        self = value
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Double.self) {
            self = .number(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode([JSON].self) {
            self = .array(value)
        } else {
            self = .object(try single.decode([String: JSON].self))
        }
    }

    public subscript(key: String) -> JSON? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    public subscript(index: Int) -> JSON? {
        if case .array(let items) = self, items.indices.contains(index) { return items[index] }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var int: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    public var double: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var array: [JSON] {
        if case .array(let items) = self { return items }
        return []
    }

    /// Text for a JSON string made from `value`, quotes included.
    static func quote(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    /// Compact JSON text for an object made of plain values.
    static func encode(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
