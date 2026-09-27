import Foundation

/// What a setting can hold, and how it is written in the settings store.
protocol Storable {
    init?(stored: Any)
    var stored: Any { get }
}

/// Read as `UserDefaults.bool(forKey:)` reads them: a setting given on the
/// command line (`-welcomed YES`) arrives as text.
extension Bool: Storable {
    init?(stored: Any) {
        switch stored {
        case let value as Bool: self = value
        case let text as String: self = ["yes", "true"].contains(text.lowercased()) || (Int(text) ?? 0) != 0
        default: return nil
        }
    }
    var stored: Any { self }
}

extension String: Storable {
    init?(stored: Any) {
        guard let value = stored as? String else { return nil }
        self = value
    }
    var stored: Any { self }
}

extension CGFloat: Storable {
    init?(stored: Any) {
        guard let value = stored as? Double ?? (stored as? String).flatMap(Double.init) else { return nil }
        self = CGFloat(value)
    }
    var stored: Any { Double(self) }
}

/// A folder, kept as its path.
extension URL: Storable {
    init?(stored: Any) {
        guard let path = stored as? String else { return nil }
        self = URL(fileURLWithPath: path)
    }
    var stored: Any { path }
}

/// Choices are kept by their raw name.
extension Storable where Self: RawRepresentable, RawValue == String {
    init?(stored: Any) {
        guard let raw = stored as? String else { return nil }
        self.init(rawValue: raw)
    }
    var stored: Any { rawValue }
}

extension UserDefaults {
    /// The value under `key`, or `fallback` when there is none it can read.
    func value<Value: Storable>(_ key: String, or fallback: Value) -> Value {
        guard let stored = object(forKey: key) else { return fallback }
        return Value(stored: stored) ?? fallback
    }
}
