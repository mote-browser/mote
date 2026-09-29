import Foundation

/// The blocks of a Markdown reply: paragraphs, headings, lists, quotes, code
/// and tables, each with its inline text left as Markdown for the view.
///
/// A small subset of CommonMark with GitHub's tables and task lists, the
/// part language models write. It is forgiving about half-written text, since
/// a reply is parsed again as it streams in: a code fence still open holds
/// everything after it, marked `closed: false`.
public enum Markdown {
    public indirect enum Block: Equatable, Sendable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case code(language: String?, text: String, closed: Bool)
        case quote([Block])
        case list(List)
        case table(Table)
        case rule
    }

    public struct List: Equatable, Sendable {
        public var ordered: Bool
        /// The first item's number, for ordered lists.
        public var start: Int
        public var items: [Item]

        public init(ordered: Bool, start: Int, items: [Item]) {
            self.ordered = ordered
            self.start = start
            self.items = items
        }
    }

    public struct Item: Equatable, Sendable {
        public var blocks: [Block]
        /// Whether a task item is ticked; nil for an ordinary item.
        public var checked: Bool?

        public init(blocks: [Block], checked: Bool? = nil) {
            self.blocks = blocks
            self.checked = checked
        }
    }

    public struct Table: Equatable, Sendable {
        public enum Alignment: Equatable, Sendable { case none, leading, center, trailing }

        public var header: [String]
        public var alignments: [Alignment]
        /// As many cells as the header in every row.
        public var rows: [[String]]

        public init(header: [String], alignments: [Alignment], rows: [[String]]) {
            self.header = header
            self.alignments = alignments
            self.rows = rows
        }
    }

    public static func parse(_ text: String) -> [Block] {
        blocks(of: lines(of: text)[...])
    }

    private static func lines(of text: String) -> [String] {
        normalized(text).components(separatedBy: "\n")
    }

    private static func normalized(_ text: String) -> String {
        // "\r\n" is one character to Swift, so look for the byte.
        text.utf8.contains(13) ? text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") : text
    }

    /// A reply as it streams in, parsed a piece at a time: finished blocks
    /// are kept, and each new piece is read from the block before the last,
    /// the only ones more text can change. Text that changes rather than
    /// grows is read again whole.
    public struct Stream: Sendable {
        public private(set) var blocks: [Block] = []
        /// The line each block starts on.
        private var starts: [Int] = []
        private var lines: [String] = []
        private var text = ""
        /// The line the last update read from.
        private(set) var parsedFrom = 0

        public init() {}

        public mutating func update(_ newText: String) {
            let newText = Markdown.normalized(newText)
            guard newText != text else { return }
            if !text.isEmpty, newText.utf8.count > text.utf8.count, newText.utf8.starts(with: text.utf8) {
                let added = newText.utf8.dropFirst(text.utf8.count)
                var pieces = String(decoding: added, as: UTF8.self).components(separatedBy: "\n")
                lines[lines.count - 1] += pieces.removeFirst()
                lines += pieces
                let keep = max(0, blocks.count - 2)
                parsedFrom = keep < starts.count ? starts[keep] : 0
                let (more, from) = Markdown.placed(lines[parsedFrom...])
                blocks = Array(blocks[..<keep]) + more
                starts = Array(starts[..<keep]) + from
            } else {
                lines = Markdown.lines(of: newText)
                parsedFrom = 0
                (blocks, starts) = Markdown.placed(lines[...])
            }
            text = newText
        }
    }

    // MARK: - Blocks

    private static func blocks(of lines: ArraySlice<String>) -> [Block] { placed(lines).blocks }

    /// The blocks, with the line each starts on.
    private static func placed(_ lines: ArraySlice<String>) -> (blocks: [Block], starts: [Int]) {
        var reader = Reader(lines: lines)
        var found: [Block] = []
        var starts: [Int] = []
        while let line = reader.peek {
            if !line.isBlank { starts.append(reader.index) }
            if line.isBlank {
                reader.skip()
            } else if let fence = Fence(line) {
                found.append(code(after: fence, in: &reader))
            } else if let heading = heading(line) {
                reader.skip()
                found.append(heading)
            } else if isRule(line) {
                reader.skip()
                found.append(.rule)
            } else if quoted(line) != nil {
                found.append(quote(in: &reader))
            } else if let marker = Marker(line) {
                found.append(.list(list(from: marker, in: &reader)))
            } else if let table = table(in: &reader) {
                found.append(.table(table))
            } else {
                found.append(.paragraph(paragraph(in: &reader)))
            }
        }
        return (found, starts)
    }

    /// Lines up to a blank one or the start of another kind of block.
    private static func paragraph(in reader: inout Reader) -> String {
        var text: [String] = []
        while let line = reader.peek, !line.isBlank {
            if !text.isEmpty, interrupts(line) { break }
            text.append(line.trimmingCharacters(in: .whitespaces))
            reader.skip()
        }
        return text.joined(separator: "\n")
    }

    private static func interrupts(_ line: String) -> Bool {
        Fence(line) != nil || heading(line) != nil || isRule(line) || quoted(line) != nil || Marker(line) != nil
    }

    private static func heading(_ line: String) -> Block? {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3 else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // A closing run of hashes is decoration.
        let closing = text.reversed().prefix { $0 == "#" }.count
        if closing > 0, closing == text.count || text.dropLast(closing).last == " " {
            text = String(text.dropLast(closing)).trimmingCharacters(in: .whitespaces)
        }
        return .heading(level: hashes, text: text)
    }

    private static func isRule(_ line: String) -> Bool {
        let marks = line.filter { $0 != " " && $0 != "\t" }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first } && line.prefix { $0 == " " }.count <= 3
    }

    // MARK: Code

    private struct Fence {
        let mark: Character
        let length: Int
        let indent: Int
        let info: String

        init?(_ line: String) {
            let indent = line.prefix { $0 == " " }.count
            let rest = line.dropFirst(indent)
            guard indent <= 3, let mark = rest.first, mark == "`" || mark == "~" else { return nil }
            let length = rest.prefix { $0 == mark }.count
            guard length >= 3 else { return nil }
            let info = rest.dropFirst(length).trimmingCharacters(in: .whitespaces)
            // A backtick fence's info string can't hold backticks.
            guard mark == "~" || !info.contains("`") else { return nil }
            (self.mark, self.length, self.indent, self.info) = (mark, length, indent, info)
        }

        func closes(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return line.prefix { $0 == " " }.count <= 3 && trimmed.count >= length && trimmed.allSatisfy { $0 == mark }
        }
    }

    private static func code(after fence: Fence, in reader: inout Reader) -> Block {
        reader.skip()
        var body: [String] = []
        var closed = false
        while let line = reader.next() {
            if fence.closes(line) {
                closed = true
                break
            }
            // Lines lose as much of their indent as the fence had.
            body.append(String(line.dropFirst(min(fence.indent, line.prefix { $0 == " " }.count))))
        }
        let language = fence.info.split(separator: " ").first.map(String.init)
        return .code(language: language, text: body.joined(separator: "\n"), closed: closed)
    }

    // MARK: Quotes

    /// The line inside a quote, or nil when it isn't quoted.
    private static func quoted(_ line: String) -> String? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3, line.dropFirst(indent).first == ">" else { return nil }
        let rest = line.dropFirst(indent + 1)
        return String(rest.first == " " ? rest.dropFirst() : rest)
    }

    private static func quote(in reader: inout Reader) -> Block {
        var inner: [String] = []
        while let line = reader.peek {
            if let text = quoted(line) {
                inner.append(text)
            } else if !line.isBlank, !interrupts(line), let last = inner.last, !last.isBlank {
                // A lazy line carries on the quoted paragraph.
                inner.append(line)
            } else {
                break
            }
            reader.skip()
        }
        return .quote(blocks(of: inner[...]))
    }

    // MARK: Lists

    private struct Marker {
        let ordered: Bool
        /// The bullet, or the delimiter after the number.
        let symbol: Character
        let number: Int
        /// Where the item's text starts; lines indented this far belong to it.
        let content: Int
        let text: String

        init?(_ line: String) {
            let indent = line.prefix { $0 == " " }.count
            guard indent <= 3 else { return nil }
            let rest = line.dropFirst(indent)
            let digits = rest.prefix(while: \.isASCIIDigit)
            let width: Int
            if let first = rest.first, "-*+".contains(first) {
                (ordered, symbol, number, width) = (false, first, 1, 1)
            } else if (1...9).contains(digits.count), let delimiter = rest.dropFirst(digits.count).first, ".)".contains(delimiter) {
                (ordered, symbol, number, width) = (true, delimiter, Int(digits) ?? 1, digits.count + 1)
            } else {
                return nil
            }
            let after = rest.dropFirst(width)
            guard after.isEmpty || after.first == " " || after.first == "\t" else { return nil }
            let gap = min(max(after.prefix { $0 == " " }.count, 1), 4)
            content = indent + width + gap
            text = after.trimmingCharacters(in: .whitespaces)
        }

        func continues(_ other: Marker) -> Bool { ordered == other.ordered && symbol == other.symbol }
    }

    private static func list(from first: Marker, in reader: inout Reader) -> List {
        var items: [Item] = []
        var marker: Marker? = first
        while let current = marker {
            reader.skip()
            var lines = [current.text]
            marker = nil
            while let line = reader.peek {
                if line.isBlank {
                    // A blank line ends the item unless what follows is indented
                    // into it or is the next item.
                    guard let next = reader.peekPastBlanks else { break }
                    if next.indent >= current.content {
                        lines.append("")
                        reader.skip()
                        continue
                    }
                    if let following = Marker(next), following.continues(current) {
                        reader.skipBlanks()
                        continue
                    }
                    break
                }
                if line.indent >= current.content {
                    lines.append(String(line.dropFirst(current.content)))
                } else if let next = Marker(line) {
                    if next.continues(current) { marker = next }
                    break
                } else if interrupts(line) || lines.last?.isBlank != false {
                    break
                } else {
                    // A lazy line carries on the item's paragraph.
                    lines.append(line.trimmingCharacters(in: .whitespaces))
                }
                reader.skip()
            }
            items.append(item(from: lines))
        }
        return List(ordered: first.ordered, start: first.number, items: items)
    }

    private static func item(from lines: [String]) -> Item {
        var lines = lines
        var checked: Bool?
        if let first = lines.first, first.count >= 3, first.hasPrefix("["), Array(first)[2] == "]",
            first.count == 3 || Array(first)[3] == " "
        {
            switch Array(first)[1] {
            case " ": checked = false
            case "x", "X": checked = true
            default: break
            }
            if checked != nil { lines[0] = String(first.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        }
        return Item(blocks: blocks(of: lines[...]), checked: checked)
    }

    // MARK: Tables

    private static func table(in reader: inout Reader) -> Table? {
        guard let head = reader.peek, head.contains("|"), let second = reader.peek(1),
            let alignments = delimiters(second)
        else { return nil }
        let header = cells(head)
        guard header.count == alignments.count else { return nil }
        reader.skip(2)
        var rows: [[String]] = []
        while let line = reader.peek, line.contains("|"), !interrupts(line) {
            var row = cells(line)
            row = Array(row.prefix(header.count)) + Array(repeating: "", count: max(0, header.count - row.count))
            rows.append(row)
            reader.skip()
        }
        return Table(header: header, alignments: alignments, rows: rows)
    }

    private static func delimiters(_ line: String) -> [Table.Alignment]? {
        guard line.contains("-") else { return nil }
        let parts = cells(line)
        var found: [Table.Alignment] = []
        for part in parts {
            let left = part.hasPrefix(":")
            let right = part.hasSuffix(":")
            let dashes = part.dropFirst(left ? 1 : 0).dropLast(right ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            found.append(left && right ? .center : left ? .leading : right ? .trailing : .none)
        }
        return found.isEmpty ? nil : found
    }

    /// A row's cells, without the outer pipes; `\|` is a pipe inside a cell.
    private static func cells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") { row.removeLast() }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for character in row {
            if escaped {
                cell.append(character == "|" ? "|" : "\\\(character)")
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(character)
            }
        }
        if escaped { cell.append("\\") }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }
}

/// Walks lines one at a time, looking ahead as blocks need.
private struct Reader {
    let lines: ArraySlice<String>
    var index: Int

    init(lines: ArraySlice<String>) {
        self.lines = lines
        index = lines.startIndex
    }

    var peek: String? { peek(0) }

    func peek(_ ahead: Int) -> String? {
        lines.indices.contains(index + ahead) ? lines[index + ahead] : nil
    }

    /// The first line that isn't blank, from here on.
    var peekPastBlanks: String? {
        lines[index...].first { !$0.isBlank }
    }

    mutating func next() -> String? {
        defer { if index < lines.endIndex { index += 1 } }
        return peek
    }

    mutating func skip(_ count: Int = 1) { index = min(index + count, lines.endIndex) }

    mutating func skipBlanks() {
        while peek?.isBlank == true { skip() }
    }
}

extension String {
    fileprivate var isBlank: Bool { allSatisfy { $0 == " " || $0 == "\t" } }
    fileprivate var indent: Int { prefix { $0 == " " }.count }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
