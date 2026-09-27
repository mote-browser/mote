import Foundation
import Testing

@testable import MoteCore

@Suite("WebAuthn")
struct WebAuthnTests {
    private func caller(
        _ scheme: String = "https", _ host: String = "login.example.com", port: Int = 0, mainFrame: Bool = true,
        page: String? = "login.example.com", focused: Bool = true, known: Bool = true
    ) -> WebAuthn.Caller {
        WebAuthn.Caller(scheme: scheme, host: host, port: port, mainFrame: mainFrame, pageHost: page, focused: focused, known: known)
    }

    /// Public suffixes for these tests.
    private func suffix(_ domain: String) -> Bool { ["com", "co.uk", "github.io"].contains(domain) }

    private let challenge = WebAuthn.encode(Data("challenge".utf8))

    @Test("Callers must be switched on, secure, focused, same-site and known")
    func callers() {
        #expect(WebAuthn.check(caller(), offered: true, token: "t") == nil)
        #expect(WebAuthn.check(caller(), offered: false, token: "t")?.reason == "passkeys are off")
        #expect(WebAuthn.check(caller("http"), offered: true, token: "t")?.reason == "not a secure page")
        #expect(WebAuthn.check(caller("http", "localhost"), offered: true, token: "t") == nil)
        #expect(WebAuthn.check(caller("http", "app.localhost"), offered: true, token: "t") == nil)
        #expect(WebAuthn.check(caller(focused: false), offered: true, token: "t")?.reason == "the document is not focused")
        #expect(
            WebAuthn.check(caller(mainFrame: false, page: "evil.test"), offered: true, token: "t")?.reason
                == "asked from another site's frame")
        #expect(WebAuthn.check(caller(mainFrame: false), offered: true, token: "t") == nil)
        #expect(WebAuthn.check(caller(known: false), offered: true, token: "t")?.name == "NotAllowedError")
        #expect(WebAuthn.check(caller(), offered: true, token: "")?.reason == "no document or token")
    }

    @Test("Origins carry brackets for IPv6 and any port")
    func origins() {
        #expect(caller().origin == "https://login.example.com")
        #expect(caller("http", "localhost", port: 8080).origin == "http://localhost:8080")
        #expect(caller("http", "::1").origin == "http://[::1]")
    }

    @Test("A relying party is the host or a domain above it, never a suffix or for an address")
    func relyingParties() {
        #expect(WebAuthn.fits("login.example.com", "login.example.com", isPublicSuffix: suffix))
        #expect(WebAuthn.fits("example.com", "login.example.com", isPublicSuffix: suffix))
        #expect(!WebAuthn.fits("com", "login.example.com", isPublicSuffix: suffix))
        #expect(!WebAuthn.fits("github.io", "me.github.io", isPublicSuffix: suffix))
        #expect(!WebAuthn.fits("ample.com", "login.example.com", isPublicSuffix: suffix))
        #expect(!WebAuthn.fits("0.1", "10.0.0.1", isPublicSuffix: suffix))
        #expect(!WebAuthn.fits("example.com", "login.example.com", isPublicSuffix: nil))
    }

    @Test("A sign-in request reads its relying party, challenge and allowed keys")
    func gets() throws {
        let body: [String: Any] = [
            "kind": "get", "rpId": "example.com", "challenge": challenge, "userVerification": "required",
            "allowCredentials": [["id": WebAuthn.encode(Data([1, 2])), "transports": ["usb", "carrier-pigeon"]]],
        ]
        let request = try WebAuthn.read(body, host: "login.example.com", isPublicSuffix: suffix).get()
        #expect(request.rp == "example.com")
        #expect(request.verification == "required")
        #expect(request.kind == .get(allowed: [WebAuthn.Descriptor(id: Data([1, 2]), transports: ["usb"])]))
    }

    @Test("Without a relying party the host is used")
    func defaultRelyingParty() throws {
        let request = try WebAuthn.read(["kind": "get", "rpId": "", "challenge": challenge], host: "Example.org", isPublicSuffix: suffix)
            .get()
        #expect(request.rp == "example.org")
        #expect(request.verification == "preferred")
    }

    @Test("Making a credential needs a user with a short id, and defaults the rest")
    func creates() throws {
        let body: [String: Any] = [
            "kind": "create", "rp": ["id": "example.com"], "challenge": challenge,
            "user": ["id": WebAuthn.encode(Data([9])), "name": "me@example.com", "displayName": ""],
        ]
        let request = try WebAuthn.read(body, host: "example.com", isPublicSuffix: suffix).get()
        guard case .create(let creation) = request.kind else {
            Issue.record("not a creation")
            return
        }
        #expect(creation.user.displayName == "me@example.com")
        #expect(creation.algorithms == [-7, -257])
        #expect(creation.residentKey == "discouraged")
        #expect(creation.attestation == "none")
        #expect(creation.allowsPlatform && creation.allowsSecurityKey)

        var long = body
        long["user"] = ["id": WebAuthn.encode(Data(count: 65)), "name": "x"]
        #expect(
            WebAuthn.read(long, host: "example.com", isPublicSuffix: suffix) == .failure(.init("TypeError", "no user, or one too long")))
    }

    @Test("The Mac's passkeys are offered only to sites taking ES256, and not for cross-platform")
    func platformOnlyES256() throws {
        let user: [String: Any] = ["id": WebAuthn.encode(Data([1])), "name": "n"]
        func creation(_ extra: [String: Any]) throws -> WebAuthn.Creation {
            let body = ["kind": "create", "challenge": challenge, "user": user].merging(extra) { $1 }
            guard case .create(let made) = try WebAuthn.read(body, host: "a.com", isPublicSuffix: suffix).get().kind else {
                throw CancellationError()
            }
            return made
        }
        #expect(try !creation(["algorithms": [-257]]).allowsPlatform)
        #expect(try !creation(["authenticatorAttachment": "cross-platform"]).allowsPlatform)
        #expect(try !creation(["authenticatorAttachment": "platform"]).allowsSecurityKey)
    }

    @Test("Bad relying parties, missing challenges and other kinds are refused with the right names")
    func refusals() {
        #expect(
            (try? WebAuthn.read(["kind": "get", "rpId": "other.com", "challenge": challenge], host: "a.com", isPublicSuffix: suffix).get())
                == nil)
        if case .failure(let refusal) = WebAuthn.read(
            ["kind": "get", "rpId": "other.com", "challenge": challenge], host: "a.com", isPublicSuffix: suffix)
        {
            #expect(refusal.name == "SecurityError")
        }
        if case .failure(let refusal) = WebAuthn.read(["kind": "get"], host: "a.com", isPublicSuffix: suffix) {
            #expect(refusal.name == "TypeError")
        }
        if case .failure(let refusal) = WebAuthn.read(["kind": "sign", "challenge": challenge], host: "a.com", isPublicSuffix: suffix) {
            #expect(refusal.name == "NotSupportedError")
        }
    }

    @Test("Failures carry one message per name, and unknown names become NotAllowedError")
    func failures() {
        #expect(WebAuthn.failure("AbortError")["message"] as? String == "The operation was aborted.")
        #expect(WebAuthn.failure("MadeUpError")["error"] as? String == "NotAllowedError")
    }

    @Test("base64url round-trips without padding")
    func base64url() {
        let data = Data([0xFB, 0xFF, 0x01])
        #expect(WebAuthn.encode(data) == "-_8B")
        #expect(WebAuthn.decode("-_8B") == data)
        #expect(WebAuthn.decode(42) == nil)
    }

    @Test("A rehearsed credential carries a readable P-256 public key")
    func rehearsal() throws {
        let body: [String: Any] = ["kind": "create", "challenge": challenge, "user": ["id": WebAuthn.encode(Data([1])), "name": "n"]]
        let request = try WebAuthn.read(body, host: "a.com", isPublicSuffix: suffix).get()
        let reply = WebAuthn.rehearsal(request, origin: "https://a.com")
        #expect(reply["publicKeyAlgorithm"] as? Int == -7)
        let der = try #require(WebAuthn.decode(reply["publicKey"]))
        #expect(der.count == 91)
        #expect(der.prefix(2) == Data([0x30, 0x59]))
        let client = try #require(WebAuthn.decode(reply["clientDataJSON"]))
        #expect(String(decoding: client, as: UTF8.self).contains(#""type":"webauthn.create""#))
    }

    @Test("Broken attestation objects read as nothing")
    func broken() {
        #expect(WebAuthn.authenticatorData(inAttestation: Data([0xA1, 0x63])) == nil)
        #expect(WebAuthn.publicKey(inAuthenticatorData: Data(count: 40)) == nil)
    }
}
