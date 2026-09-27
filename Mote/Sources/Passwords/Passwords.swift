import MoteCore
import SwiftUI

/// The Passwords panel: saved logins grouped by site, a search, a form to
/// add one, and imports. Showing or copying a password asks who you are
/// first, and a shown password hides itself again.
struct PasswordsPanel: View {
    @Bindable var logins: Logins

    @FocusState private var searching: Bool
    @State private var openSite: String?
    @State private var adding = false
    @State private var importing: String?

    var body: some View {
        Plate("Passwords", width: 620, close: { logins.managing = false }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SearchField(text: $logins.query, prompt: "Search sites and accounts", focus: $searching)
                    Pill(adding ? "Cancel" : "Add", filled: !adding) { adding.toggle() }
                }
                if adding {
                    Card { NewLogin(logins: logins) { adding = false } }
                        .transition(.opacity)
                }
                list
            }
        } foot: {
            foot
        }
        .animation(Motion.settle, value: adding)
        .animation(Motion.settle, value: openSite)
        .onAppear { searching = true }
    }

    @ViewBuilder
    private var list: some View {
        let sites = logins.sites
        if sites.isEmpty {
            Card {
                EmptyState(
                    logins.saved.isEmpty
                        ? "Nothing kept yet. Sign in somewhere and say yes, or bring yours in below." : "Nothing matches.")
            }
        } else {
            ScrollView(showsIndicators: false) {
                Card {
                    ForEach(Array(sites.enumerated()), id: \.element.host) { index, site in
                        if index > 0 { Rule() }
                        SiteRow(site: site, open: openSite == site.host, logins: logins) {
                            openSite = openSite == site.host ? nil : site.host
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 400)
        }
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Bring in from").font(.system(size: 12)).foregroundStyle(Palette.muted)
                ForEach(ChromiumImporter.installed()) { source in
                    Pill(source.name) { bring(from: source) }.disabled(importing != nil)
                }
                Pill("CSV file…") { logins.importFile() }.disabled(importing != nil)
                Spacer(minLength: 0)
                if let importing {
                    Ring(size: 10)
                    Text("Reading \(importing)…").font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                } else {
                    Text(logins.saved.count == 1 ? "1 password" : "\(logins.saved.count) passwords")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
            }
            Text(
                "macOS asks once for that browser's keychain key. Nothing is changed there; everything lands in your own keychain, under Mote."
            )
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.faint)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bring(from source: ChromiumImporter.Source) {
        importing = source.name
        Task {
            await logins.bringAndSay(from: source)
            importing = nil
        }
    }
}

/// A site, opening to its accounts.
private struct SiteRow: View {
    let site: Logins.Site
    let open: Bool
    let logins: Logins
    let toggle: () -> Void

    @State private var hovering = false

    private var summary: String? {
        if site.logins.count > 1 { return "\(site.logins.count) accounts" }
        guard !open, let user = site.logins.first?.user, !user.isEmpty else { return nil }
        return user
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Mark(icon: Favicons.shared.cached(site.host), letter: TabLabel.monogram(for: URL(string: "https://" + site.host)), size: 16)
                Text(site.host).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(1)
                if let summary {
                    Text(summary).font(.system(size: 11.5)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(open ? Palette.wash.opacity(0.6) : hovering ? Palette.hover : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)

            if open {
                VStack(spacing: 0) {
                    ForEach(site.logins) { AccountRow(login: $0, logins: logins) }
                }
                .padding(.leading, 30)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .transition(.opacity)
            }
        }
    }
}

/// One account. Its password shows for 15 seconds once you've proved it's you.
private struct AccountRow: View {
    let login: Login
    let logins: Logins

    @State private var hovering = false
    @State private var shown = false
    @State private var hiding: Task<Void, Never>?

    private var dots: String { String(repeating: "•", count: min(12, max(6, login.password.count))) }

    var body: some View {
        HStack(spacing: 10) {
            Text(login.user.isEmpty ? "No username" : login.user)
                .font(.system(size: 12))
                .foregroundStyle(login.user.isEmpty ? Palette.faint : Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 120, alignment: .leading)
            Text(shown ? login.password : dots)
                .font(.system(size: shown ? 12.5 : 10, design: .monospaced))
                .foregroundStyle(shown ? Palette.ink : Palette.muted)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if hovering || shown {
                Quick(shown ? "Hide" : "Show") { shown ? hide() : show() }
                Quick("Copy") { logins.copy(login) }
                Quick("Remove", tint: .red.opacity(0.75)) { logins.forget(login) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: shown)
        .onDisappear(perform: hide)
    }

    private func show() {
        PasswordStore.prove("show the password for \(login.host)") { ok in
            guard ok else { return }
            shown = true
            hiding?.cancel()
            hiding = Task {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { shown = false }
            }
        }
    }

    private func hide() {
        hiding?.cancel()
        shown = false
    }
}

/// Adding a login by hand.
private struct NewLogin: View {
    let logins: Logins
    let done: () -> Void

    private enum Field { case site, user, password }

    @State private var site = ""
    @State private var user = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private var host: String { Address.siteHost(typed: site) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                box("Site", focus: .site) { TextField("", text: $site) }
                box("Username", focus: .user) { TextField("", text: $user) }
            }
            HStack(spacing: 8) {
                box("Password", focus: .password, mono: true) { SecureField("", text: $password).onSubmit(save) }
                Pill("Save", filled: true, action: save).disabled(host.isEmpty || password.isEmpty)
            }
        }
        .padding(14)
        .onAppear { focus = .site }
    }

    /// A text field on a wash with its name as the placeholder.
    private func box(_ name: String, focus field: Field, mono: Bool = false, @ViewBuilder input: () -> some View) -> some View {
        let empty =
            switch field {
            case .site: site.isEmpty
            case .user: user.isEmpty
            case .password: password.isEmpty
            }
        return ZStack(alignment: .leading) {
            if empty { Text(name).foregroundStyle(Palette.ink.opacity(0.3)) }
            input()
                .textFieldStyle(.plain)
                .foregroundStyle(Palette.ink)
                .focused($focus, equals: field)
        }
        .font(.system(size: 12.5, design: mono ? .monospaced : .default))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func save() {
        guard !host.isEmpty, !password.isEmpty else { return }
        logins.add(host: host, user: user.trimmingCharacters(in: .whitespaces), password: password)
        done()
    }
}
