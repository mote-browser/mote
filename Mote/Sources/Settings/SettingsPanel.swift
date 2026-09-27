import SwiftUI

/// Settings, in its own window (SettingsWindow): the pages in a bar along the
/// top, the chosen one below.
struct SettingsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @State private var page = SettingsPage(rawValue: Storage.settings.string(forKey: "settings.page") ?? "") ?? .general

    static let width: CGFloat = 640
    static let height: CGFloat = 580

    var body: some View {
        VStack(spacing: 0) {
            // The traffic lights sit in the band above the bar.
            SettingsPageBar(page: $page)
                .padding(.top, 34)
                .padding(.bottom, 10)
            Palette.hairline.frame(height: 1)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) { content }
                    .padding(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(page)
        }
        // The content runs under the see-through title bar, so the panel
        // takes the window's height rather than its own.
        .frame(width: Self.width)
        .frame(minHeight: Self.height, maxHeight: .infinity)
        .background(Palette.ground)
        .ignoresSafeArea()
        .onChange(of: page) { Storage.settings.set(page.rawValue, forKey: "settings.page") }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .general: GeneralSettings(browser: browser, prefs: prefs)
        case .tabs: TabSettings(prefs: prefs)
        case .passwords: PasswordSettings(browser: browser, prefs: prefs)
        case .privacy: PrivacySettings(browser: browser, prefs: prefs)
        case .extensions: ExtensionsPage(browser: browser)
        case .about: AboutSettings(browser: browser, prefs: prefs)
        }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, tabs, passwords, privacy, extensions, about

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tabs: "square.on.square"
        case .passwords: "key"
        case .privacy: "hand.raised"
        case .extensions: "puzzlepiece.extension"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: Tint.gray
        case .tabs: Tint.blue
        case .passwords: Tint.yellow
        case .privacy: Tint.indigo
        case .extensions: Tint.purple
        case .about: Tint.teal
        }
    }
}
