import SwiftUI

/// ⌘F: the search field in the page's top corner, red-edged when nothing matches.
struct FindBar: View {
    @Bindable var finder: PageFinder
    @FocusState private var typing: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $finder.query)
                .textFieldStyle(.plain)
                .foregroundStyle(Palette.ink)
                .focused($typing)
                .onSubmit { finder.look(forward: true) }
                .background(alignment: .leading) {
                    if finder.query.isEmpty { Text("Find on page").foregroundStyle(Palette.ink.opacity(0.3)) }
                }
                .font(.system(size: 12.5))
                .frame(width: 160)
            Step(icon: "chevron.up") { finder.look(forward: false) }
            Step(icon: "chevron.down") { finder.look(forward: true) }
            Step(icon: "xmark", act: finder.hide)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Palette.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(finder.missed ? Color.red.opacity(0.35) : Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 5)
        .padding(.top, 12)
        .padding(.trailing, 14)
        .animation(Motion.quick, value: finder.missed)
        .onAppear { typing = true }
        // ⌘F again while it's open takes the keyboard back to it.
        .onChange(of: finder.focusRequest) { typing = true }
    }

    private struct Step: View {
        let icon: String
        let act: () -> Void

        var body: some View {
            Button(action: act) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
