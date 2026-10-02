import SwiftUI

/// A site's icon, or its first letter in a faint square until the icon comes.
struct Mark: View {
    let icon: NSImage?
    let letter: String
    var size: CGFloat = 16
    var dim = false
    var mote = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.22, style: .continuous) }

    var body: some View {
        Group {
            if mote {
                Logomark().fill(Palette.muted).frame(width: size, height: size)
            } else if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size).clipShape(shape)
            } else {
                Text(letter)
                    .font(.system(size: size * 0.56, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: size, height: size)
                    .background(Palette.ink.opacity(0.06), in: shape)
            }
        }
        .opacity(dim ? 0.45 : 1)
        .transition(.opacity)
        .animation(Motion.quick, value: icon == nil)
    }
}
