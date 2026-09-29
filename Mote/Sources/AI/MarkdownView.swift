import AppKit
import MoteAI
import SwiftUI

/// A reply's Markdown, drawn in Mote's type: each block from `Markdown`,
/// and the words inside them through Foundation's inline Markdown.
struct MarkdownView: View, Equatable {
    let text: String
    /// Links to these pages (by `Source.key`) show as citation chips with
    /// the name given.
    var cites: [String: String] = [:]
    /// The reply the text is from, whose parse is kept and carried on as
    /// it streams in; nil for text parsed whole each time.
    var reply: UUID?
    /// While it streams in: its last words, fading in (see `Typewriter`).
    var tail: Tail?

    struct Tail: Equatable {
        var fresh: [Typewriter.Fresh]
    }

    var body: some View {
        Blocks(blocks: Self.blocks(of: text, reply: reply), cites: cites, tail: tail)
    }

    /// Replies as they stream in, each parsed a piece at a time.
    @MainActor private static var streams: [UUID: Markdown.Stream] = [:]
    /// Other text parsed, so drawing it again doesn't parse it again.
    @MainActor private static var parsed: [String: [Markdown.Block]] = [:]

    @MainActor private static func blocks(of text: String, reply: UUID?) -> [Markdown.Block] {
        if let reply {
            var stream = streams[reply] ?? Markdown.Stream()
            stream.update(text)
            if streams.count > 64, streams[reply] == nil { streams.removeAll() }
            streams[reply] = stream
            return stream.blocks
        }
        if let blocks = parsed[text] { return blocks }
        let blocks = Markdown.parse(text)
        if parsed.count > 64 { parsed.removeAll() }
        parsed[text] = blocks
        return blocks
    }

    /// Body text in replies: a little larger than the chrome's, for reading.
    static let size: CGFloat = 14
    static let leading: CGFloat = 4.5

    /// Inline Markdown already styled, by text, with the cites it was styled for.
    @MainActor private static var styled: [String: (cites: [String: String], text: AttributedString)] = [:]

    /// Inline Markdown (emphasis, code, links) in a block's text. Code spans
    /// get the monospaced face on a faint wash.
    @MainActor static func inline(_ text: String, cites: [String: String] = [:]) -> AttributedString {
        if let kept = styled[text], kept.cites == cites { return kept.text }
        let made = style(text, cites: cites)
        if styled.count > 2_000 { styled.removeAll() }
        styled[text] = (cites, made)
        return made
    }

    private static func style(_ text: String, cites: [String: String]) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        var styled = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        for run in styled.runs where run.inlinePresentationIntent?.contains(.code) == true {
            styled[run.range].font = .system(size: size * 0.9, design: .monospaced)
            styled[run.range].backgroundColor = Palette.veil
        }
        // By link, so a link whose text mixes styles is one chip; from the end,
        // so replacing one never moves those still to come.
        for (link, range) in styled.runs[\.link].reversed() {
            guard let link else { continue }
            guard let name = cites[Source.key(for: link)] else {
                styled[range].underlineStyle = .single
                continue
            }
            // A citation: the site's name on a small chip, still a link. A link
            // worded as part of the answer keeps its words, with the chip after.
            var chip = AttributedString("\u{2009}\(name)\u{2009}")
            chip.link = link
            chip.font = .system(size: size * 0.76, weight: .medium)
            chip.foregroundColor = Palette.muted
            chip.backgroundColor = Palette.wash
            chip.baselineOffset = 1
            if Citations.namesSite(String(styled[range].characters), link) {
                styled.replaceSubrange(range, with: chip)
            } else {
                styled[range].link = nil
                styled.insert(AttributedString(" ") + chip, at: range.upperBound)
            }
        }
        return styled
    }
}

private struct Blocks: View {
    let blocks: [Markdown.Block]
    let cites: [String: String]
    /// Goes to the last block only: the words streaming in are at the end.
    var tail: MarkdownView.Tail?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                // Equatable, so as a reply streams in only its last block is drawn again.
                BlockView(block: block, cites: cites, tail: index == blocks.count - 1 ? tail : nil).equatable()
            }
        }
    }
}

private struct BlockView: View, Equatable {
    let block: Markdown.Block
    let cites: [String: String]
    var tail: MarkdownView.Tail?

    var body: some View {
        switch block {
        case .paragraph(let text):
            Prose(text: text, cites: cites, tail: tail)
        case .heading(let level, let text):
            Words(text: text, cites: cites, tail: tail)
                .font(.system(size: level == 1 ? 19 : level == 2 ? 16.5 : 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.top, level <= 2 ? 6 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .code(let language, let text, _):
            CodeBlock(language: language, code: text)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(Palette.faint).frame(width: 3)
                Blocks(blocks: blocks, cites: cites, tail: tail).opacity(0.75)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .list(let list):
            ListBlock(list: list, cites: cites, tail: tail)
        case .table(let table):
            TableBlock(table: table, cites: cites)
        case .rule:
            Palette.hairline.frame(height: 1).padding(.vertical, 4)
        }
    }
}

/// A paragraph.
private struct Prose: View {
    let text: String
    let cites: [String: String]
    var tail: MarkdownView.Tail?

    var body: some View {
        Words(text: text, cites: cites, tail: tail)
            .font(.system(size: MarkdownView.size))
            .lineSpacing(MarkdownView.leading)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct ListBlock: View {
    let list: Markdown.List
    let cites: [String: String]
    var tail: MarkdownView.Tail?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(index: index, item: item)
                        .frame(width: markerWidth, alignment: .trailing)
                    Blocks(blocks: item.blocks, cites: cites, tail: index == list.items.count - 1 ? tail : nil)
                }
            }
        }
        .padding(.leading, 4)
    }

    /// Wide enough for the longest number, so every item's text lines up.
    private var markerWidth: CGFloat {
        list.ordered ? CGFloat(String(list.start + list.items.count - 1).count) * 8.5 + 6 : 14
    }

    @ViewBuilder
    private func marker(index: Int, item: Markdown.Item) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 12))
                .foregroundStyle(checked ? Palette.ink : Palette.muted)
        } else if list.ordered {
            Text("\(list.start + index).")
                .font(.system(size: MarkdownView.size).monospacedDigit())
                .foregroundStyle(Palette.muted)
        } else {
            Text("•").font(.system(size: MarkdownView.size, weight: .bold)).foregroundStyle(Palette.muted)
        }
    }
}

/// Code in its own well: the language and a copy button along the top, and
/// long lines scrolling sideways rather than wrapping.
private struct CodeBlock: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : "code")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Spacer()
                CopyButton(text: code, label: "Copy")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 30)
            Palette.hairline.frame(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
            }
        }
        .background(Palette.wash.opacity(0.5), in: Rounded.field)
        .overlay(Rounded.field.strokeBorder(Palette.hairline))
    }
}

private struct TableBlock: View {
    let table: Markdown.Table
    let cites: [String: String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        self.cell(cell, column: column).font(.system(size: 13, weight: .semibold))
                    }
                }
                .background(Palette.wash.opacity(0.6))
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Palette.hairline.frame(height: 1).gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            self.cell(cell, column: column).font(.system(size: 13))
                        }
                    }
                }
            }
            .overlay(Rounded.row.strokeBorder(Palette.hairline))
            .clipShape(Rounded.row)
        }
    }

    private func cell(_ text: String, column: Int) -> some View {
        let alignment: Alignment =
            switch table.alignments.indices.contains(column) ? table.alignments[column] : .none {
            case .center: .center
            case .trailing: .trailing
            default: .leading
            }
        return Text(MarkdownView.inline(text, cites: cites))
            .foregroundStyle(Palette.ink)
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: alignment)
            .gridColumnAlignment(alignment.horizontal)
    }
}

/// Copies text, and says so for a moment.
struct CopyButton: View {
    let text: String
    var label: String?

    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10.5, weight: .medium))
                if let label { Text(copied ? "Copied" : label).font(.system(size: 11)) }
            }
            .foregroundStyle(hovering ? Palette.ink.opacity(0.8) : Palette.muted)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(hovering ? Palette.veil : .clear, in: Rounded.row)
            .contentShape(Rounded.row)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy")
        .accessibilityLabel(copied ? "Copied" : "Copy")
        .animation(Motion.hover, value: hovering)
        .animation(Motion.quick, value: copied)
    }
}

/// Inline text; while it streams in, its end healed of half-written marks
/// and its newest words fading in.
private struct Words: View {
    let text: String
    let cites: [String: String]
    var tail: MarkdownView.Tail?

    var body: some View {
        if let tail {
            let styled = MarkdownView.inline(Markdown.healed(text), cites: cites)
            if #available(macOS 15, *), !tail.fresh.isEmpty {
                FadingWords(styled: styled, fresh: tail.fresh)
            } else {
                Text(styled)
            }
        } else {
            Text(MarkdownView.inline(text, cites: cites))
        }
    }
}

/// Words fading in as they are shown: each new piece is marked with when it
/// came, and drawn fainter the newer it is. Drawing only, so a fade never
/// lays the text out again.
@available(macOS 15, *)
private struct FadingWords: View {
    let styled: AttributedString
    let fresh: [Typewriter.Fresh]
    /// The fade's clock: animated on to when the newest piece is fully in,
    /// so between pieces SwiftUI only draws again, without laying out.
    @State private var now = Date.timeIntervalSinceReferenceDate

    var body: some View {
        Self.text(styled, fresh: fresh)
            .textRenderer(FadeIn(now: now))
            .onAppear(perform: run)
            .onChange(of: fresh) { run() }
    }

    private func run() {
        let start = Date.timeIntervalSinceReferenceDate
        now = start
        withAnimation(.linear(duration: Typewriter.fade)) { now = start + Typewriter.fade }
    }

    /// The text as pieces: what settled, then each fresh piece marked. Counted
    /// from the end, since the fresh words are the last.
    static func text(_ styled: AttributedString, fresh: [Typewriter.Fresh]) -> Text {
        var pieces: [(AttributedString, TimeInterval?)] = []
        var end = styled.endIndex
        for piece in fresh.reversed() {
            let start = styled.characters.index(end, offsetBy: -piece.count, limitedBy: styled.startIndex) ?? styled.startIndex
            pieces.insert((AttributedString(styled[start..<end]), piece.at), at: 0)
            end = start
            if start == styled.startIndex { break }
        }
        pieces.insert((AttributedString(styled[styled.startIndex..<end]), nil), at: 0)
        // Joined flat: interpolating Text in Text nests them, and each is read
        // again as a localized string on every update.
        return pieces.dropFirst().reduce(Text(pieces[0].0)) { text, piece in
            text + (piece.1.map { Text(piece.0).customAttribute(Freshness(at: $0)) } ?? Text(piece.0))
        }
    }
}

/// When a piece of text was shown, for `FadeIn`.
@available(macOS 15, *)
private struct Freshness: TextAttribute {
    let at: TimeInterval
}

/// Draws text marked `Freshness` fainter the newer it is, easing in.
@available(macOS 15, *)
private struct FadeIn: TextRenderer, Animatable {
    var now: TimeInterval

    var animatableData: TimeInterval {
        get { now }
        set { now = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let fresh = run[Freshness.self] else {
                    context.draw(run)
                    continue
                }
                let progress = min(1, max(0, (now - fresh.at) / Typewriter.fade))
                var faded = context
                // Ease out: quick to show, gentle to settle.
                faded.opacity = 1 - pow(1 - progress, 3)
                faded.draw(run)
            }
        }
    }
}
