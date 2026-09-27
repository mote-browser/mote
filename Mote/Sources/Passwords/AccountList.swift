import MoteCore
import SwiftUI

/// The saved accounts for a site, under its focused sign-in field. Picking
/// one fills the form; nothing is filled before that.
struct AccountList: View {
    let logins: Logins
    let choices: Logins.Choices

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(choices.logins) { login in
                Account(login: login) { logins.choose(login) }
            }
            Label("From your keychain", systemImage: "key")
                .labelStyle(Footnote())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.wash.opacity(0.5))
        }
        .frame(width: min(360, max(240, choices.spot.width)))
        .background(Palette.ground)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.hairline))
        .shadow(color: .black.opacity(0.14), radius: 22, y: 8)
        // From the page's top-left corner, just under the field.
        .offset(x: choices.spot.minX, y: choices.spot.maxY + 6)
    }

    private struct Footnote: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) {
                configuration.icon.font(.system(size: 9, weight: .medium))
                configuration.title.font(.system(size: 10.5))
            }
            .foregroundStyle(Palette.faint)
        }
    }

    private struct Account: View {
        let login: Login
        let pick: () -> Void
        @State private var hovering = false

        private var initial: String { login.user.first.map { String($0).uppercased() } ?? "•" }

        var body: some View {
            Button(action: pick) {
                HStack(spacing: 10) {
                    Text(initial)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 22, height: 22)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(login.user.isEmpty ? "No name" : login.user).font(.system(size: 12.5)).foregroundStyle(Palette.ink)
                        Text(login.host).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(hovering ? Palette.hover : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }
}
