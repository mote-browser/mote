import Foundation
import Testing

@testable import MoteCore

@Suite("IconChoice")
struct IconChoiceTests {
    private let page = URL(string: "https://site.test/a/b")!

    @Test("Media queries pick an appearance")
    func schemes() {
        #expect(IconChoice.scheme("(prefers-color-scheme: dark)") == .dark)
        #expect(IconChoice.scheme("(PREFERS-COLOR-SCHEME: LIGHT)") == .light)
        #expect(IconChoice.scheme("screen") == .any)
    }

    @Test("Mid-sized icons beat tiny and huge ones, and favicon.ico comes last")
    func sizes() {
        let icons = [
            IconChoice.Declared(href: "https://site.test/16.png", sizes: "16x16"),
            IconChoice.Declared(href: "https://site.test/512.png", sizes: "512x512"),
            IconChoice.Declared(href: "https://site.test/64.png", sizes: "64x64"),
            IconChoice.Declared(href: "https://site.test/touch.png", rel: "apple-touch-icon"),
        ]
        let order = IconChoice.candidates(icons, page: page, dark: false).map(\.lastPathComponent)
        #expect(order == ["64.png", "touch.png", "512.png", "16.png", "favicon.ico"])
    }

    @Test("In dark mode the dark icon wins and the light-only one is dropped")
    func dark() {
        let icons = [
            IconChoice.Declared(href: "https://site.test/light.png", sizes: "32x32", media: "(prefers-color-scheme: light)"),
            IconChoice.Declared(href: "https://site.test/dark.png", sizes: "16x16", media: "(prefers-color-scheme: dark)"),
            IconChoice.Declared(href: "https://site.test/plain.png", sizes: "32x32"),
        ]
        #expect(IconChoice.offersDark(icons))
        #expect(IconChoice.candidates(icons, page: page, dark: true).map(\.lastPathComponent) == ["dark.png", "plain.png", "favicon.ico"])
        #expect(IconChoice.candidates(icons, page: page, dark: false).first?.lastPathComponent == "light.png")
    }

    @Test("Non-web addresses and repeats are skipped")
    func filtering() {
        let icons = [
            IconChoice.Declared(href: "data:image/png;base64,xx"),
            IconChoice.Declared(href: "https://site.test/favicon.ico"),
        ]
        #expect(IconChoice.candidates(icons, page: page, dark: false).map(\.absoluteString) == ["https://site.test/favicon.ico"])
        #expect(IconChoice.Declared(["rel": "icon"]) == nil)
    }

    @Test("GitHub uses its official dark variant only in dark mode")
    func githubAppearance() {
        let page = URL(string: "https://github.com/mote-browser/mote")!
        #expect(IconChoice.candidates([], page: page, dark: true).first?.lastPathComponent == "favicon-dark.svg")
        #expect(IconChoice.candidates([], page: page, dark: false).first?.lastPathComponent == "favicon.ico")
    }
}
