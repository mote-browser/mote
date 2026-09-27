import Testing

@testable import MoteCore

@Suite("RegistrableDomain")
struct RegistrableDomainTests {
    private let suffixes: Set<String> = ["com", "uk", "co.uk", "io", "github.io"]
    private var isPublicSuffix: (String) -> Bool { { suffixes.contains($0) } }

    @Test(arguments: [
        ("news.bbc.co.uk", "bbc.co.uk"),
        ("www.example.com", "example.com"),
        ("Example.COM.", "example.com"),
        ("user.github.io", "user.github.io"),
        ("a.b.user.github.io", "user.github.io"),
        ("co.uk", "co.uk"),
        ("localhost", "localhost"),
        ("192.168.1.1", "192.168.1.1"),
        ("::1", "::1"),
    ])
    func domain(host: String, expected: String) {
        #expect(RegistrableDomain.of(host, isPublicSuffix: isPublicSuffix) == expected)
    }

    @Test("Without a suffix list the host is returned as it is")
    func withoutSuffixList() {
        #expect(RegistrableDomain.of("news.bbc.co.uk", isPublicSuffix: nil) == "news.bbc.co.uk")
    }
}
