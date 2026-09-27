import CryptoKit
import Foundation

/// Updates are signed with Mote's own Ed25519 key: the private half signs
/// each release's zip in CI (Tools/release/sign), and the public half, built
/// into the app, checks it before anything is installed. No certificate from
/// Apple is involved, so unsigned builds update as well as signed ones.
///
/// Keys are 64 hex digits: they sit in an .xcconfig, where base64's `//`
/// would start a comment. Signatures are base64, in the feed's JSON.
public enum UpdateSignature {
    /// Whether `signature` is `key`'s over `data`.
    public static func verify(_ data: Data, signature: String, key: String) -> Bool {
        guard let signature = Data(base64Encoded: signature), let raw = bytes(key),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else { return false }
        return key.isValidSignature(signature, for: data)
    }

    /// `data`'s signature with `privateKey`, in base64.
    public static func sign(_ data: Data, privateKey: String) throws -> String {
        guard let raw = bytes(privateKey), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
            throw Failure.badKey
        }
        return try key.signature(for: data).base64EncodedString()
    }

    /// A new pair: the private key to keep secret, the public one to build in.
    public static func newKeys() -> (privateKey: String, publicKey: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (hex(key.rawRepresentation), hex(key.publicKey.rawRepresentation))
    }

    /// The public key belonging to a private one.
    public static func publicKey(of privateKey: String) -> String? {
        bytes(privateKey).flatMap { try? Curve25519.Signing.PrivateKey(rawRepresentation: $0) }.map { hex($0.publicKey.rawRepresentation) }
    }

    /// Whether `key` could be a public key at all.
    public static func isKey(_ key: String) -> Bool {
        bytes(key).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) } != nil
    }

    public enum Failure: Error { case badKey }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    /// 32 bytes from 64 hex digits, spaces and newlines around them ignored.
    private static func bytes(_ text: String) -> Data? {
        let digits = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        guard digits.count == 64 else { return nil }
        var data = Data()
        for index in stride(from: 0, to: 64, by: 2) {
            guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else { return nil }
            data.append(byte)
        }
        return data
    }
}
