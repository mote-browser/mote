import SwiftUI

/// Tabs across the top or down the side, as two little windows to pick
/// from: in the welcome and in Settings › Tabs.
struct TabLayoutChoice: View {
    @ObservedObject var prefs: Preferences
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(title: "Across the top", sidebar: false, chosen: !prefs.sidebar, height: compact ? 76 : 96) { choose(false) }
            Thumbnail(title: "Down the side", sidebar: true, chosen: prefs.sidebar, height: compact ? 76 : 96) { choose(true) }
        }
    }

    private func choose(_ sidebar: Bool) {
        withAnimation(Motion.glide) { prefs.sidebar = sidebar }
    }

    /// A window in miniature: traffic lights, and tabs where they'd be.
    private struct Thumbnail: View {
        let title: String
        let sidebar: Bool
        let chosen: Bool
        let height: CGFloat
        let pick: () -> Void
        @State private var hovering = false

        private let outer = RoundedRectangle(cornerRadius: 14, style: .continuous)
        private let inner = RoundedRectangle(cornerRadius: 8, style: .continuous)

        var body: some View {
            Button(action: pick) {
                VStack(alignment: .leading, spacing: 8) {
                    window
                        .frame(height: height)
                        .frame(maxWidth: .infinity)
                        .background(Palette.ground, in: inner)
                        .overlay(inner.strokeBorder(Palette.hairline, lineWidth: 1))
                    HStack(spacing: 6) {
                        Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(chosen ? Palette.ink : Palette.faint)
                        Text(title)
                            .font(.system(size: 12.5, weight: chosen ? .medium : .regular))
                            .foregroundStyle(chosen ? Palette.ink : Palette.muted)
                    }
                }
                .padding(8)
                .background(chosen ? Palette.wash : hovering ? Palette.hover : .clear, in: outer)
                .overlay(outer.strokeBorder(chosen ? Palette.ink.opacity(0.35) : Palette.hairline, lineWidth: 1))
                .contentShape(outer)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.settle, value: chosen)
        }

        @ViewBuilder private var window: some View {
            if sidebar {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        lights.padding(.bottom, 4)
                        ForEach(0..<4, id: \.self) { tab($0).frame(height: 8) }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(width: 58)
                    Rectangle().fill(Palette.hairline).frame(width: 1)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 3) {
                        lights.padding(.trailing, 6)
                        ForEach(0..<3, id: \.self) { tab($0).frame(width: 28, height: 8) }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                    Spacer()
                }
            }
        }

        private func tab(_ index: Int) -> some View {
            RoundedRectangle(cornerRadius: 3).fill(index == 0 ? Palette.wash : Palette.hover)
        }

        private var lights: some View {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.faint).frame(width: 5, height: 5) }
            }
        }
    }
}
