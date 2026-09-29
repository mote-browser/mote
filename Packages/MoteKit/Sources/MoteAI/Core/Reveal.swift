import Foundation

extension Markdown {
    /// A block's inline text with its unfinished end closed as it will be:
    /// an open code span or bold is closed, a half-written link shows its
    /// words. So text still arriving doesn't flash its marks, then change.
    public static func healed(_ text: String) -> String {
        var inCode = false
        var bold = 0
        var lastBold: String.Index?
        var bracket: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "`" {
                inCode.toggle()
            } else if !inCode, character == "*", next < text.endIndex, text[next] == "*" {
                bold += 1
                lastBold = index
                index = text.index(after: next)
                continue
            } else if !inCode, character == "[" {
                bracket = index
            } else if !inCode, character == ")", bracket != nil, text[..<index].contains("](") {
                bracket = nil
            }
            index = next
        }
        var healed = text
        if inCode { return healed + "`" }
        if let bracket {
            let rest = text[text.index(after: bracket)...]
            if let close = rest.range(of: "](") {
                healed = String(text[..<bracket]) + rest[..<close.lowerBound]
            } else if !rest.contains("]") {
                healed = String(text[..<bracket]) + rest
            }
        }
        if bold % 2 == 1, let lastBold {
            // Marks with nothing after them yet are dropped; otherwise closed.
            if text[lastBold...] == "**" {
                healed = String(healed.dropLast(2))
            } else if bracket == nil || lastBold < bracket! {
                healed += "**"
            }
        }
        return healed
    }
}

/// How much of a reply streaming in is shown: words at a reader's pace,
/// faster the further behind it falls, so it never lags much behind what
/// has arrived, and quickly all of it once the reply is done. Whole words
/// only, so a word never shows half and then jumps to the next line.
///
/// As assistant-ui's smooth streaming: at least `slowest` characters a
/// second, and whatever is waiting shown within `behind`.
public struct Reveal: Sendable {
    public static let slowest: Double = 80
    public static let behind: Double = 0.35
    /// Once the reply is done, what's left shows within this.
    public static let draining: Double = 0.25

    /// How far in, as a count of UTF-8 bytes of the text.
    private var offset = 0
    /// Characters owed from earlier steps, too few to show yet.
    private var owed: Double = 0
    /// Once the reply is done, the steady pace that shows the rest within
    /// `draining`: slowing down as the backlog shrinks would never finish.
    private var drain: Double?

    public init() {}

    /// What is shown of `text`.
    public func shown(of text: String) -> Substring {
        text.utf8.count >= offset ? text[..<text.utf8.index(text.startIndex, offsetBy: offset)] : Substring(text)
    }

    public func caughtUp(with text: String) -> Bool { offset >= text.utf8.count }

    /// Shows all of `text` at once, as for a reply already there.
    public mutating func showAll(_ text: String) {
        offset = text.utf8.count
        owed = 0
    }

    /// Moves on by `elapsed` seconds; returns how many characters it showed.
    @discardableResult
    public mutating func step(through text: String, elapsed: Double, finished: Bool) -> Int {
        let bytes = text.utf8
        guard offset < bytes.count else {
            offset = bytes.count
            owed = 0
            return 0
        }
        let start = bytes.index(text.startIndex, offsetBy: offset)
        let waiting = text[start...]
        let backlog = waiting.count
        if finished, drain == nil { drain = max(Self.slowest, Double(backlog) / Self.draining) }
        owed += (drain ?? max(Self.slowest, Double(backlog) / Self.behind)) * elapsed
        guard owed >= 1 else { return 0 }
        let reach = min(Int(owed), backlog)
        var end = waiting.index(waiting.startIndex, offsetBy: reach)
        if end < waiting.endIndex || (!finished && waiting.last?.isWhitespace == false) {
            // To the end of the word reached, space included.
            if end < waiting.endIndex, let space = waiting[end...].firstIndex(where: \.isWhitespace) {
                end = waiting.index(after: space)
            } else if finished {
                end = waiting.endIndex
            } else if let space = waiting[..<end].lastIndex(where: \.isWhitespace) {
                // That word is still arriving: up to the one before.
                end = waiting.index(after: space)
            } else {
                return 0
            }
        }
        let shown = waiting[..<end].count
        owed = max(0, owed - Double(shown))
        offset = text.utf8.distance(from: text.startIndex, to: end)
        return shown
    }
}
