import Foundation
import Testing

@testable import MoteCore

@Suite("UpdateSignature")
struct UpdateSignatureTests {
    private let zip = Data("Mote.app, zipped".utf8)

    @Test("A release signed with the private key passes with the public one")
    func signs() throws {
        let keys = UpdateSignature.newKeys()
        let signature = try UpdateSignature.sign(zip, privateKey: keys.privateKey)
        #expect(UpdateSignature.verify(zip, signature: signature, key: keys.publicKey))
        #expect(UpdateSignature.isKey(keys.publicKey))
        #expect(UpdateSignature.publicKey(of: keys.privateKey) == keys.publicKey)
        #expect(keys.publicKey.count == 64 && keys.publicKey.allSatisfy(\.isHexDigit))
    }

    @Test("A changed file, another key, or a garbled signature fails")
    func refuses() throws {
        let keys = UpdateSignature.newKeys()
        let signature = try UpdateSignature.sign(zip, privateKey: keys.privateKey)
        #expect(!UpdateSignature.verify(zip + Data([0]), signature: signature, key: keys.publicKey))
        #expect(!UpdateSignature.verify(zip, signature: signature, key: UpdateSignature.newKeys().publicKey))
        #expect(!UpdateSignature.verify(zip, signature: "not base64!", key: keys.publicKey))
        #expect(!UpdateSignature.verify(zip, signature: signature, key: "short"))
        #expect(!UpdateSignature.isKey("") && !UpdateSignature.isKey(String(repeating: "z", count: 64)))
        #expect(throws: UpdateSignature.Failure.badKey) { try UpdateSignature.sign(zip, privateKey: "%%") }
    }

    @Test("A private key read from a file with its newline still signs")
    func trims() throws {
        let keys = UpdateSignature.newKeys()
        let signature = try UpdateSignature.sign(zip, privateKey: keys.privateKey + "\n")
        #expect(UpdateSignature.verify(zip, signature: signature, key: keys.publicKey))
    }
}
