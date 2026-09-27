import MoteCore
import SwiftUI

/// What's hidden on this site, to bring back. Resting on a line shows its
/// element again for a moment, outlined and scrolled to: a selector alone
/// says little.
struct HiddenElementsPanel: View {
    @ObservedObject var browser: Browser

    var body: some View {
        Plate(browser.hereHost ?? "This page", width: 380, close: { browser.reviewing = false }) {
            if browser.hereVeils.isEmpty {
                Card { EmptyState("Nothing is hidden here.") }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Caption("Hidden on this site — rest on a line to see it")
                    ScrollView(showsIndicators: false) {
                        Card {
                            ForEach(Array(browser.hereVeils.enumerated()), id: \.element.id) { index, element in
                                if index > 0 { Rule() }
                                HiddenRow(element: element, show: { browser.peek(element) }, restore: { browser.restore(element) })
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .frame(maxHeight: 320)
                }
            }
        } foot: {
            HStack(spacing: 8) {
                Pill("Hide something…", filled: true, action: browser.toggleHiding)
                if !browser.hereVeils.isEmpty { Pill("Restore all", action: browser.restoreAll) }
                Spacer()
            }
        }
        // Whatever was shown hides again once the pointer leaves.
        .onHover { inside in
            if !inside { browser.stopPeeking() }
        }
    }
}

private struct HiddenRow: View {
    let element: HiddenElement
    let show: () -> Void
    let restore: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(element.label).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(1)
                if let note = element.note, !note.isEmpty {
                    Text(note).font(.system(size: 11.5)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Quick("Restore", act: restore).opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(hovering ? Palette.hover : .clear)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { show() }
        }
        .animation(Motion.quick, value: hovering)
    }
}
