import MoteCore
import SwiftUI
import WebKit

/// What shows under the chrome for a tab: its page, and over it the
/// snapshot while it wakes, a note while its video floats, why it failed to
/// load, or the swipe disc.
///
/// `Tab` is a class, so the window's views don't see its changes; watching
/// it here is what redraws the page area when the tab changes.
struct Page: View {
    @ObservedObject var tab: Tab

    var body: some View {
        ZStack {
            // Blank and sleeping tabs have no page, and asking would make an empty
            // one. A floating page is left out so its return is a change and the
            // stage takes it back.
            WebStage(
                page: tab.isBlank || tab.asleep || tab.floating ? nil : tab.web,
                overlay: tab.responsive == nil ? nil : tab.development?.canvas,
                stage: tab.stage
            )
            .id(tab.id)

            if tab.responsive == nil, let cover = tab.cover {
                // The snapshot while a sleeping page comes back; it never takes clicks.
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if tab.floating {
                Text("This page's video is playing in its own window.")
                    .textStyle(.body)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.ground)
                    .transition(.opacity)
            }
            if tab.responsive == nil, let failure = tab.failure {
                LoadFailurePage(failure: failure, retry: tab.tryAgain, proceed: tab.continueAnyway).transition(.opacity)
            }
            if tab.responsive == nil, let pull = tab.pull {
                Disc(pull: pull)
                    // One view per edge: a changing alignment would slide it across the window.
                    .id(pull.back)
                    // Quick, so it's gone before a fast flick is let go.
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .animation(Motion.quick, value: tab.failure)
        .animation(Motion.quick, value: tab.floating)
        .animation(.easeOut(duration: 0.2), value: tab.cover == nil)
        .animation(.easeOut(duration: 0.16), value: tab.pull == nil)
    }
}

/// The disc at the edge while swiping back or forward: its ring fills with
/// the pull and closes once letting go would navigate (see SwipeDisc).
private struct Disc: View {
    let pull: Pull

    var body: some View {
        let disc = SwipeDisc(travel: pull.travel, going: pull.going)
        ZStack {
            Circle().fill(Palette.ground)
            Circle().strokeBorder(Palette.hairline)
            Circle()
                .trim(from: 0, to: disc.progress)
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(0.75)
            Image(systemName: pull.back ? "arrow.left" : "arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.4 + 0.6 * disc.progress))
        }
        .frame(width: 52, height: 52)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .scaleEffect(disc.scale)
        .opacity(pull.going ? 0 : 1)
        .offset(x: (pull.back ? 1 : -1) * disc.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pull.back ? .leading : .trailing)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.22), value: pull.going)
    }
}
