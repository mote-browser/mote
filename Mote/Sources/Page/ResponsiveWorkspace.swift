import MoteCore
import SwiftUI
import WebKit

struct ResponsiveWorkspace: View {
    @ObservedObject var session: ResponsiveSession
    @State private var editing: ResponsiveViewport?

    var body: some View {
        GeometryReader { geometry in
            let width = session.panes.reduce(0.0) { $0 + Double($1.profile.width) }
            let height = Double(session.panes.map(\.profile.height).max() ?? 1)
            let gaps = Double(max(0, session.panes.count - 1)) * 20 + 48
            // Fit the presentation; the native web views retain their exact CSS viewports.
            let scale = min(
                session.scale,
                max(
                    0.1,
                    min(
                        (geometry.size.width - gaps) / max(1, width),
                        (geometry.size.height - 100) / height)))
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(session.panes) { pane in
                        ResponsiveCard(pane: pane, session: session, scale: scale) { editing = pane.profile }
                    }
                }
                .padding(24)
            }
            .background(Palette.ground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
        .clipped()
        .sheet(item: $editing) { profile in
            ResponsiveEditor(profile: profile) { updated in session.replace(updated) }
        }
        .alert("Responsive Workspace", isPresented: Binding(get: { session.notice != nil }, set: { if !$0 { session.notice = nil } })) {
            Button("OK") { session.notice = nil }
        } message: {
            Text(session.notice ?? "")
        }
    }

}

private struct ResponsiveCard: View {
    @ObservedObject var pane: ResponsivePane
    @ObservedObject var session: ResponsiveSession
    let scale: Double
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.profile.name).font(.system(size: 13, weight: .semibold))
                    Text("\(pane.profile.width) × \(pane.profile.height)").font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if pane.loading { ProgressView().controlSize(.small) }
                Menu {
                    Button("Edit View…", action: edit)
                    Button("Rotate") { session.replace(pane.profile.rotated) }
                    Button("Reload") { pane.web.reload() }
                    Divider()
                    Button("Remove View") { session.remove(pane.id) }.disabled(session.panes.count == 1)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
                .accessibilityLabel("Options for \(pane.profile.name)")
            }
            ZStack {
                ResponsiveStage(web: pane.web, viewport: pane.profile)
                if let error = pane.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error).multilineTextAlignment(.center).font(.caption)
                        Button("Retry") { pane.web.reload() }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
                }
            }
            .frame(width: Double(pane.profile.width) * scale, height: Double(pane.profile.height) * scale)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.muted.opacity(0.2)))
            if pane.profile.userAgent != nil {
                Text("Custom user agent").font(.caption2).foregroundStyle(Palette.muted)
            }
        }
        .frame(width: Double(pane.profile.width) * scale)
    }
}

private struct ResponsiveEditor: View {
    @Environment(\.dismiss) private var dismiss
    let profile: ResponsiveViewport
    let apply: (ResponsiveViewport) -> Void
    @State private var name: String
    @State private var width: String
    @State private var height: String
    @State private var userAgent: String
    @State private var error: String?

    init(profile: ResponsiveViewport, apply: @escaping (ResponsiveViewport) -> Void) {
        self.profile = profile
        self.apply = apply
        _name = State(initialValue: profile.name)
        _width = State(initialValue: String(profile.width))
        _height = State(initialValue: String(profile.height))
        _userAgent = State(initialValue: profile.userAgent ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit View").font(.headline)
            Form {
                TextField("Name", text: $name)
                TextField("Width (CSS px)", text: $width)
                TextField("Height (CSS px)", text: $height)
                TextField("User agent", text: $userAgent, prompt: Text("Default WebKit user agent"))
            }
            Text(
                "Changing the user agent reloads this view. It changes browser identification; it does not emulate a device engine, touch, locale or safe areas."
            )
            .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    do {
                        guard let width = Int(width), let height = Int(height) else { throw ResponsiveError.dimensions }
                        let updated = try ResponsiveViewport(id: profile.id, name: name, width: width, height: height, userAgent: userAgent)
                        apply(updated)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 420)
    }
}

/// Scaling the native container preserves the web view's CSS viewport and input coordinates.
struct ResponsiveStage: NSViewRepresentable {
    let web: WKWebView
    let viewport: ResponsiveViewport

    func makeNSView(context: Context) -> ResponsiveStageView { ResponsiveStageView() }
    func updateNSView(_ view: ResponsiveStageView, context: Context) {
        view.show(web, size: NSSize(width: viewport.width, height: viewport.height))
    }
}

final class ResponsiveStageView: NSView {
    override var isFlipped: Bool { true }
    private weak var web: WKWebView?
    private var viewport = NSSize(width: 390, height: 844)

    func show(_ web: WKWebView, size: NSSize) {
        if self.web !== web {
            self.web?.removeFromSuperview()
            self.web = web
            addSubview(web)
        }
        viewport = size
        needsLayout = true
    }

    override func layout() {
        super.layout()
        setBoundsSize(viewport)
        web?.frame = NSRect(origin: .zero, size: viewport)
    }
}
