import AppKit
import MoteAI
import SwiftUI

/// Whether questions search the web first. Off for a provider that has no
/// search of its own, saying why.
struct SearchToggle: View {
    @State private var hovering = false
    private var assistant: Assistant { .shared }

    var body: some View {
        let possible = assistant.provider.searches
        let on = assistant.searches
        Button {
            withAnimation(Motion.quick) { assistant.searching.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "network").font(.system(size: 11, weight: .medium))
                Text("Search").font(.system(size: 12))
            }
            .foregroundStyle(on ? Palette.ground : hovering && possible ? Palette.ink.opacity(0.8) : Palette.muted)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(on ? Palette.ink : Palette.veil.opacity(hovering && possible ? 1.4 : 0.7))
                    .strokeBorder(on ? .clear : Palette.edge, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(Pressed())
        .disabled(!possible)
        .opacity(possible ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(
            possible
                ? (on ? "Answers search the web and cite their sources — click to just chat" : "Search the web and cite sources")
                : "\(assistant.provider.name) can't search the web. Claude Code, Codex, opencode, Gemini CLI, Anthropic, OpenAI, xAI and OpenRouter can"
        )
        .accessibilityLabel("Search the web")
        .accessibilityValue(on ? "On" : "Off")
        .animation(Motion.hover, value: hovering)
        .animation(Motion.quick, value: on)
    }
}

/// What a search reply did: a line saying how many searches and pages,
/// opening to the list of them.
struct StepsSummary: View {
    let steps: [Activity]
    @State private var open = false

    var body: some View {
        let searches = steps.filter { $0.kind == .search }.count
        let reads = steps.filter { $0.kind == .read }.count
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Motion.settle) { open.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text(summary(searches: searches, reads: reads)).font(.system(size: 12.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .foregroundStyle(Palette.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(steps, id: \.id) { step in
                        HStack(spacing: 7) {
                            Image(systemName: step.kind == .search ? "magnifyingglass" : step.kind == .read ? "doc.text" : "wrench")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 14)
                            Text(step.title).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                        }
                        .foregroundStyle(Palette.muted)
                    }
                }
                .padding(.leading, 2)
                .transition(.opacity)
            }
        }
    }

    private func summary(searches: Int, reads: Int) -> String {
        var parts: [String] = []
        if searches > 0 { parts.append(searches == 1 ? "Searched once" : "Searched \(searches) times") }
        if reads > 0 { parts.append(reads == 1 ? "read 1 page" : "read \(reads) pages") }
        let line = parts.joined(separator: " · ")
        return line.isEmpty ? "Used \(steps.count) tools" : line.prefix(1).uppercased() + line.dropFirst()
    }
}

/// The pages a reply drew on, side by side above it: those it cites first,
/// numbered as in the text.
struct SourcesStrip: View {
    let entries: [Citations.Entry]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entries, id: \.source.id) { entry in
                    SourceCard(entry: entry)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }
}

private struct SourceCard: View {
    let entry: Citations.Entry
    @State private var hovering = false
    @State private var icon: NSImage?
    @Environment(\.openURL) private var openURL

    var body: some View {
        let source = entry.source
        Button {
            openURL(source.url)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Mark(icon: icon, letter: String(source.site.prefix(1)).uppercased(), size: 14)
                    Text(source.site).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    if let number = entry.number {
                        Text("\(number)").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.muted)
                    }
                }
                Text(source.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 176, height: 66, alignment: .topLeading)
            .background(hovering ? Palette.hover : Palette.wash.opacity(0.6), in: Rounded.row)
            .overlay(Rounded.row.strokeBorder(entry.number == nil ? Palette.hairline : Palette.edge))
            .opacity(entry.number == nil ? 0.8 : 1)
            .contentShape(Rounded.row)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(source.snippet.map { "\(source.name)\n\n\($0)" } ?? "\(source.name)\n\(source.url.absoluteString)")
        .accessibilityLabel(entry.number.map { "Source \($0), \(source.site): \(source.name)" } ?? "Source \(source.site): \(source.name)")
        .animation(Motion.hover, value: hovering)
        .task(id: source.site) { icon = await Favicons.shared.icon(for: source.url.host()?.lowercased() ?? source.site) }
    }
}
