/// The keyboard highlight in a composer's active picker.
///
/// The first arrow starts at the nearest end, movement wraps, and confirmation
/// defaults to the first result when no arrow has moved the highlight.
public struct ComposerSelection: Equatable, Sendable {
    public private(set) var highlightedIndex: Int?

    public init() {}

    /// Moves the highlight by `step`, wrapping within the current result count.
    /// An empty menu clears the highlight.
    public mutating func move(_ step: Int, count: Int) {
        guard count > 0, step != 0 else {
            highlightedIndex = nil
            return
        }
        guard let highlightedIndex else {
            self.highlightedIndex = step > 0 ? 0 : count - 1
            return
        }
        self.highlightedIndex = (highlightedIndex + step % count + count) % count
    }

    /// The chosen item, or the first result when confirmation precedes arrows.
    public func confirmedIndex(count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let highlightedIndex, (0..<count).contains(highlightedIndex) else { return 0 }
        return highlightedIndex
    }

    /// Clears the highlight when the query or result set changes.
    public mutating func reset() { highlightedIndex = nil }
}
