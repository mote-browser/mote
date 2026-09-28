import AppKit
import MoteAI
import SwiftUI

/// A reply's Markdown, drawn in Mote's type: each block from `Markdown`,
/// and the words inside them through Foundation's inline Markdown.
struct MarkdownView: View {
    let text: String

    var body: some View {
        Blocks(blocks: Markdown.parse(text))
    }

    /// Body text in replies: a little larger than the chrome's, for reading.
    static let size: CGFloat = 14
    static let leading: CGFloat = 4.5

    /// Inline Markdown (emphasis, code, links) in a block's text. Code spans
    /// get the monospaced face on a faint wash.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        var styled = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        for run in styled.runs where run.inlinePresentationIntent?.contains(.code) == true {
            styled[run.range].font = .system(size: size * 0.9, design: .monospaced)
            styled[run.range].backgroundColor = Palette.veil
        }
        for run in styled.runs where run.link != nil {
            styled[run.range].underlineStyle = .single
        }
        return styled
    }
}

private struct Blocks: View {
    let blocks: [Markdown.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                // Equatable, so as a reply streams in only its last block is drawn again.
                BlockView(block: block).equatable()
            }
        }
    }
}

private struct BlockView: View, Equatable {
    let block: Markdown.Block

    var body: some View {
        switch block {
        case .paragraph(let text):
            Prose(text: text)
        case .heading(let level, let text):
            Text(MarkdownView.inline(text))
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
                Blocks(blocks: blocks).opacity(0.75)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .list(let list):
            ListBlock(list: list)
        case .table(let table):
            TableBlock(table: table)
        case .rule:
            Palette.hairline.frame(height: 1).padding(.vertical, 4)
        }
    }
}

/// A paragraph.
private struct Prose: View {
    let text: String

    var body: some View {
        Text(MarkdownView.inline(text))
            .font(.system(size: MarkdownView.size))
            .lineSpacing(MarkdownView.leading)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct ListBlock: View {
    let list: Markdown.List

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(index: index, item: item)
                        .frame(width: markerWidth, alignment: .trailing)
                    Blocks(blocks: item.blocks)
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
        return Text(MarkdownView.inline(text))
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
