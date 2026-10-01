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
        // Centred in the page, and scrolling when the window is too short for it.
        GeometryReader { space in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: space.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.ground)
        .animation(Motion.settle, value: details)
        // Another failure starts folded again.
        .onChange(of: failure) { details = false }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: failure.kind.symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(failure.kind == .certificate ? Palette.unsafe : Palette.muted)
                .frame(width: 48, height: 48)
                .background(Palette.wash, in: Rounded.card)
                .padding(.bottom, 20)

            Text(failure.title)
                .textStyle(.title)
                .padding(.bottom, 8)
            Text(failure.detail)
                .textStyle(.body)
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let host = failure.host {
                Text(host)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                Pill("Try Again", filled: true, action: retry)
                if failure.canContinue {
                    Pill(details ? "Hide Details" : "Details") { details.toggle() }
                }
            }
            .padding(.top, 24)

            if details, failure.canContinue, let host = failure.host {
                Way(host: host, proceed: proceed)
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
    }
}

/// The way past a bad certificate, under Details.
private struct Way: View {
    let host: String
    let proceed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "This Mac doesn't trust the certificate \(host) offered. It may be expired, made for another site, or signed by no one the Mac knows. Continue only if you know why, such as a device on your own network."
            )
            .textStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            Pill("Continue to \(host)", tint: Palette.unsafe, action: proceed)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.wash.opacity(0.55), in: Rounded.card)
        .overlay(Rounded.card.strokeBorder(Palette.hairline))
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
