import MoteCore
import SecurityInterface
import SwiftUI
import WebKit

/// What there is to know and do about a tab's site, shaped like a menu:
/// how safe the connection is, copying, printing and zoom. The connection
/// row opens a closer look with the certificate.
struct SiteCard: View {
    let browser: Browser
    @ObservedObject var tab: Tab
    let close: () -> Void

    @State private var closer: Bool
    /// Whether this Mac trusts the certificate; nil until checked in the
    /// background (it may go to the network).
    @State private var certified: Bool?

    init(browser: Browser, tab: Tab, deeper: Bool = false, close: @escaping () -> Void) {
        self.browser = browser
        self.tab = tab
        self.close = close
        _closer = State(initialValue: deeper)
    }

    /// A page's site for headings; see `Address.siteName`.
    static func site(_ url: URL) -> String { Address.siteName(for: url) }

    /// As it was when the card opened; anything insecure the page loads later
    /// doesn't change it.
    private var connection: Connection? {
        Connection.of(scheme: tab.address?.scheme, certified: certified, onlySecureContent: tab.built?.hasOnlySecureContent)
    }

    var body: some View {
        Group {
            if closer, let connection { details(connection) } else { summary }
        }
        .padding(.vertical, MenuMetrics.pad)
        .frame(minWidth: 180)
        .fixedSize()
        .transition(.opacity)
        .animation(Motion.quick, value: closer)
        .onAppear(perform: checkCertificate)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let url = tab.address { MenuHeading(title: Address.siteName(for: url)) }
            if let connection { MenuRow(connection.headline, submenu: true) { closer = true } }
            MenuRow("Copy Address", keys: "⇧⌘C") { afterClosing(browser.copyAddress) }
            MenuSeparator()
            MenuRow("Print…", keys: "⌘P") { afterClosing(browser.printPage) }
            zoom
        }
    }

    /// This site's zoom (kept per site, see `Tab.rememberZoom`); the
    /// percentage goes back to 100%.
    private var zoom: some View {
        HStack(spacing: 0) {
            Text("Zoom").foregroundStyle(Color(nsColor: .labelColor))
            Spacer(minLength: 24)
            ZoomStep(symbol: "minus", help: "Zoom Out   ⌘-") { browser.zoom(by: 1 / 1.1) }
            Button(action: browser.resetZoom) {
                Text("\(Int((tab.zoom * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Actual Size   ⌘0")
            ZoomStep(symbol: "plus", help: "Zoom In   ⌘+") { browser.zoom(by: 1.1) }
        }
        .font(MenuMetrics.font)
        .padding(.leading, MenuMetrics.text)
        .padding(.trailing, MenuMetrics.inset + 4)
        .frame(height: MenuMetrics.row)
    }

    private func details(_ connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let url = tab.address { MenuHeading(title: Address.siteName(for: url)) }
            Text(connection.headline)
                .font(MenuMetrics.font)
                .foregroundStyle(Color(nsColor: .labelColor))
                .padding(.leading, MenuMetrics.text)
                .frame(height: MenuMetrics.row, alignment: .leading)
            Text(connection.explanation)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 230, alignment: .leading)
                .padding(.leading, MenuMetrics.text)
                .padding(.trailing, MenuMetrics.trailing)
                .padding(.bottom, 6)
            MenuSeparator()
            if connection != .plain, let trust = tab.built?.serverTrust {
                MenuRow(certified == false ? "Show Certificate (Not Valid)…" : "Show Certificate…") {
                    afterClosing { Self.showCertificate(trust) }
                }
            }
            MenuRow("Back") { closer = false }
        }
    }

    /// Checks the certificate against the system's trust policy off the main
    /// thread, as it may check for revocation. A certificate that fails here
    /// was let through by the user (see `Challenge.trust`).
    private func checkCertificate() {
        guard certified == nil, let trust = tab.built?.serverTrust else { return }
        SecTrustEvaluateAsyncWithError(trust, .main) { _, trusted, _ in
            MainActor.assumeIsolated { certified = trusted }
        }
    }

    private static func showCertificate(_ trust: SecTrust) {
        guard let window = AppDelegate.window else { return }
        SFCertificatePanel.shared().beginSheet(
            for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, trust: trust, showGroup: false)
    }

    /// Closes the card first: a sheet or print panel opened while it is still
    /// closing ends up behind it.
    private func afterClosing(_ act: @escaping () -> Void) {
        close()
        Task { act() }
    }
}

extension Connection {
    var headline: String {
        switch self {
        case .secure: "Connection is secure"
        case .mixed: "Parts of this page are not secure"
        case .untrusted, .plain: "Connection is not secure"
        }
    }

    var explanation: String {
        switch self {
        case .secure: "What you send to this site, like passwords or card numbers, is encrypted on the way."
        case .mixed:
            "The page itself is encrypted, but some of its content was loaded over plain http, which others on the network could see or alter."
        case .untrusted: "This Mac doesn't trust the site's certificate, so someone may be able to read what you send."
        case .plain: "Nothing sent to this site is encrypted. Avoid entering passwords or card numbers."
        }
    }

    var symbol: String {
        switch self {
        case .secure: "lock"
        case .mixed: "lock.trianglebadge.exclamationmark"
        case .untrusted, .plain: "lock.open"
        }
    }

    var tint: Color { self == .secure ? Palette.safe : Palette.unsafe }
}

/// A zoom step, lit like a menu item on hover.
private struct ZoomStep: View {
    let symbol: String
    let help: String
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? .white : Color(nsColor: .labelColor))
                .frame(width: 22, height: 18)
                .background(hovering ? MenuMetrics.selection : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
