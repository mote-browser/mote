import Testing

@testable import MoteCore

@Suite("Challenge")
struct ChallengeTests {
    @Test("Good certificates go ahead whoever asks")
    func valid() {
        #expect(Challenge.trust(valid: true, host: "example.com", excused: [], pageHost: nil) == .usual)
    }

    @Test("Bad certificates on this Mac or already let through are accepted")
    func accepted() {
        #expect(Challenge.trust(valid: false, host: "localhost", excused: [], pageHost: nil) == .accept)
        #expect(Challenge.trust(valid: false, host: "127.0.0.1", excused: [], pageHost: nil) == .accept)
        #expect(Challenge.trust(valid: false, host: "Self.Signed", excused: ["self.signed"], pageHost: nil) == .accept)
    }

    @Test("Only the page itself asks; its parts fail quietly")
    func asks() {
        #expect(Challenge.trust(valid: false, host: "bad.example", excused: [], pageHost: "BAD.example") == .ask)
        #expect(Challenge.trust(valid: false, host: "cdn.example", excused: [], pageHost: "bad.example") == .usual)
        #expect(Challenge.trust(valid: false, host: "bad.example", excused: [], pageHost: nil) == .usual)
    }

    @Test("Loopback means only written loopback addresses")
    func loopback() {
        for host in ["localhost", "::1", "[::1]", "127.0.0.1", "127.255.1.9"] {
            #expect(Challenge.isLoopback(host), "\(host)")
        }
        for host in ["127.0.0.1.example.com", "128.0.0.1", "127.0.0", "127.0.0.256", "mylocalhost", "127..0.1"] {
            #expect(!Challenge.isLoopback(host), "\(host)")
        }
    }

    @Test("Sign-in gives up after two refusals")
    func signIn() {
        #expect(Challenge.mayAskToSignIn(failures: 0))
        #expect(Challenge.mayAskToSignIn(failures: 1))
        #expect(!Challenge.mayAskToSignIn(failures: 2))
    }

    @Test("Dialogs are headed with the site asking")
    func titles() {
        #expect(Challenge.dialogTitle(host: "example.com") == "example.com")
        #expect(Challenge.dialogTitle(host: "") == "This page says")
    }
}
