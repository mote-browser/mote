import SwiftUI

/// An on/off switch in Mote's ink rather than the system accent.
struct Switch: View {
    @Binding var on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Palette.ink : Palette.faint)
            .frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(Palette.ground).shadow(color: .black.opacity(0.18), radius: 1.5, y: 1).padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(Motion.settle) { on.toggle() } }
            .animation(Motion.settle, value: on)
    }
}

/// A choice among a few, with the chosen one on a raised chip that slides.
struct Segmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option
    /// Equal segments across the whole width, rather than each as wide as its label.
    var wide = false

    @Namespace private var chip
    private let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option, title in
                let chosen = option == selection
                Text(title)
                    .font(.system(size: 11.5, weight: chosen ? .medium : .regular))
                    .foregroundStyle(chosen ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: !wide, vertical: false)
                    .frame(maxWidth: wide ? .infinity : nil)
                    .padding(.horizontal, wide ? 4 : 10)
                    .padding(.vertical, 5)
                    .background {
                        if chosen {
                            shape.fill(Palette.ground).shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "chip", in: chip)
                        }
                    }
                    .contentShape(shape)
                    .onTapGesture { withAnimation(Motion.settle) { selection = option } }
            }
        }
        .padding(2)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(Motion.settle, value: selection)
    }
}

/// A capsule button: outlined, or filled for the one that matters most.
struct Pill: View {
    let title: String
    var filled = false
    var tint: Color = Palette.ink
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, filled: Bool = false, tint: Color = Palette.ink, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TextStyle.detail.font)
                .foregroundStyle(filled ? Palette.ground : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filled ? Palette.ink : hovering ? Palette.hover : Palette.ground, in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Palette.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}
