import MoteCore
import SwiftUI

/// Shown in place of a page that didn't load: what went wrong and where, a
/// way to try again and, past a bad certificate, a quiet way through.
struct LoadFailurePage: View {
    let failure: LoadFailure
    let retry: () -> Void
    let proceed: () -> Void

    @State private var details = false

    var body: some View {
        // Centred in the page, a little above the middle, and scrolling when
        // the window is too short for it.
        GeometryReader { space in
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.top, max(48, space.size.height * 0.2))
                    .padding(.bottom, 48)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.ground)
        .animation(Motion.settle, value: details)
        // Another failure starts folded again.
        .onChange(of: failure) { details = false }
    }

    private var tint: Color { failure.kind == .certificate ? Palette.unsafe : Palette.muted }

    private var content: some View {
        VStack(spacing: 0) {
            Image(systemName: failure.kind.symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(Circle().fill(failure.kind == .certificate ? Palette.unsafe.opacity(0.12) : Palette.wash))
                .padding(.bottom, 22)

            Text(failure.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            Text(failure.detail)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)

            if let host = failure.host {
                Site(host: host, kind: failure.kind)
                    .padding(.top, 18)
            }

            Action("Try Again", filled: true, action: retry)
                .padding(.top, 28)

            if failure.canContinue, let host = failure.host {
                Fold(open: $details)
                    .padding(.top, 14)
                if details {
                    Way(host: host, proceed: proceed)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
        }
        .frame(maxWidth: 460)
    }
}

/// The host that failed, in a quiet capsule.
private struct Site: View {
    let host: String
    let kind: LoadFailure.Kind

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind == .certificate ? "lock.slash.fill" : "globe")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(kind == .certificate ? Palette.unsafe : Palette.muted)
            Text(host)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.ink.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Palette.wash, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline))
    }
}

/// "Show Details", with a chevron that turns as it opens.
private struct Fold: View {
    @Binding var open: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(open ? "Hide Details" : "Show Details")
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .font(TextStyle.secondary.font)
            .foregroundStyle(hovering ? Palette.ink : Palette.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

/// The way past a bad certificate, under Show Details.
private struct Way: View {
    let host: String
    let proceed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                "This Mac doesn't trust the certificate \(host) offered. It may be expired, made for another site, or signed by no one the Mac knows. Continue only if you know why, such as a device on your own network."
            )
            .font(TextStyle.secondary.font)
            .foregroundStyle(Palette.muted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            Action("Continue to \(host)", tint: Palette.unsafe, action: proceed)
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Palette.wash.opacity(0.6), in: Rounded.card)
        .overlay(Rounded.card.strokeBorder(Palette.hairline))
    }
}

/// A button the size of the welcome screen's: filled in ink for the way
/// forward, or outlined in a tint.
private struct Action: View {
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(filled ? Palette.ground : tint)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    filled ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(tint.opacity(hovering ? 0.16 : 0.1)),
                    in: Capsule()
                )
                .scaleEffect(hovering ? 1.03 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.press, value: hovering)
    }
}

extension LoadFailure.Kind {
    /// The symbol at the top of the failure page.
    fileprivate var symbol: String {
        switch self {
        case .certificate: "lock.slash"
        case .noHost: "magnifyingglass"
        case .offline: "wifi.slash"
        case .timedOut: "clock"
        case .refused: "nosign"
        case .other: "exclamationmark.triangle"
        }
    }
}
