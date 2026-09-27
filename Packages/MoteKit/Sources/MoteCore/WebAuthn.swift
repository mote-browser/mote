import Foundation

/// Passkey and security-key requests (WebAuthn), checked and answered by the
/// browser: what a page may ask, what it hears back, and reading the keys
/// macOS returns. The system sheet itself is the app's.
public enum WebAuthn {
    // MARK: - Who is asking

    /// The request's caller, as WebKit reports it rather than as the page says.
    public struct Caller: Sendable {
        public var scheme: String
        public var host: String
        public var port: Int
        public var mainFrame: Bool
        /// The host of the page holding the frame.
        public var pageHost: String?
        /// In the key window of the frontmost app.
        public var focused: Bool
        /// WebKit named a web view and the bridge named a document.
        public var known: Bool

        public init(scheme: String, host: String, port: Int, mainFrame: Bool, pageHost: String?, focused: Bool, known: Bool) {
            self.scheme = scheme.lowercased()
            self.host = host.lowercased()
            self.port = port
            self.mainFrame = mainFrame
            self.pageHost = pageHost?.lowercased()
            self.focused = focused
            self.known = known
        }

        var local: Bool { host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1" }

        /// The origin client data names: scheme, host (bracketed if IPv6) and
        /// any port.
        public var origin: String {
            "\(scheme)://\(host.contains(":") ? "[\(host)]" : host)" + (port == 0 ? "" : ":\(port)")
        }
    }

    /// Why a request was turned down: the error name the page hears, and a
    /// reason for the log only.
    public struct Refusal: Error, Equatable, Sendable {
        public let name: String
        public let reason: String

        public init(_ name: String, _ reason: String) {
            self.name = name
            self.reason = reason
        }
    }

    /// Whether this caller may ask at all. Pages must be secure (plain HTTP
    /// only on this machine), focused, and not a frame from another site;
    /// `offered` is Settings' switch, which extension scripts can get around.
    public static func check(_ caller: Caller, offered: Bool, token: String?) -> Refusal? {
        if !offered { return Refusal("NotAllowedError", "passkeys are off") }
        if caller.host.isEmpty || !(caller.scheme == "https" || (caller.scheme == "http" && caller.local)) {
            return Refusal("NotAllowedError", "not a secure page")
        }
        if !caller.focused { return Refusal("NotAllowedError", "the document is not focused") }
        if !caller.mainFrame, caller.pageHost != caller.host { return Refusal("NotAllowedError", "asked from another site's frame") }
        if !caller.known || (token ?? "").isEmpty { return Refusal("NotAllowedError", "no document or token") }
        return nil
    }

    /// Whether `rp` may be the relying party for `host`: the host itself or
    /// a domain above it, never an IP address and never a public suffix
    /// (`com`, `co.uk`, `github.io`). With no way to tell suffixes, only the
    /// host itself.
    public static func fits(_ rp: String, _ host: String, isPublicSuffix: ((String) -> Bool)?) -> Bool {
        if rp == host { return true }
        let address = host.contains(":") || host.allSatisfy { $0.isNumber || $0 == "." }
        guard !address, host.hasSuffix("." + rp), rp.contains("."), let isPublicSuffix else { return false }
        return !isPublicSuffix(rp)
    }

    // MARK: - What is asked

    /// A credential, by id, and how to reach its security key.
    public struct Descriptor: Equatable, Sendable {
        public let id: Data
        /// "usb", "nfc" or "ble"; empty means any.
        public let transports: [String]
    }

    public struct User: Equatable, Sendable {
        public let id: Data
        public let name: String
        public let displayName: String
    }

    public enum Kind: Equatable, Sendable {
        /// Signing in with an existing credential.
        case get(allowed: [Descriptor])
        /// Making a new one.
        case create(Creation)
    }

    public struct Creation: Equatable, Sendable {
        public let user: User
        /// COSE algorithm numbers the site accepts, best first.
        public let algorithms: [Int]
        /// "platform", "cross-platform", or nil for either.
        public let attachment: String?
        /// "required", "preferred" or "discouraged".
        public let residentKey: String
        /// "none", "direct", "indirect" or "enterprise".
        public let attestation: String
        public let excluded: [Descriptor]

        /// The Mac's own passkeys are always ES256.
        public var allowsPlatform: Bool { attachment != "cross-platform" && algorithms.contains(-7) }
        public var allowsSecurityKey: Bool { attachment != "platform" }
    }

    public struct Request: Equatable, Sendable {
        public let kind: Kind
        public let rp: String
        public let challenge: Data
        /// "required", "preferred" or "discouraged".
        public let verification: String

        public var name: String {
            if case .get = kind { "get" } else { "create" }
        }
    }

    /// Reads a request from `host`'s page, checking its relying party and
    /// challenge.
    public static func read(_ body: [String: Any], host: String, isPublicSuffix: ((String) -> Bool)?) -> Result<Request, Refusal> {
        let host = host.lowercased()
        let kind = body["kind"] as? String
        let named = kind == "create" ? (body["rp"] as? [String: Any])?["id"] as? String : body["rpId"] as? String
        let rp = (named.flatMap { $0.isEmpty ? nil : $0 } ?? host).lowercased()
        guard fits(rp, host, isPublicSuffix: isPublicSuffix) else {
            return .failure(Refusal("SecurityError", "the relying party doesn't fit the origin"))
        }
        guard let challenge = decode(body["challenge"]), !challenge.isEmpty else { return .failure(Refusal("TypeError", "no challenge")) }
        let verification = pick(body["userVerification"], from: ["required", "discouraged"]) ?? "preferred"
        switch kind {
        case "get":
            return .success(
                Request(
                    kind: .get(allowed: descriptors(body["allowCredentials"])), rp: rp, challenge: challenge, verification: verification))
        case "create":
            guard let creation = creation(body) else { return .failure(Refusal("TypeError", "no user, or one too long")) }
            return .success(Request(kind: .create(creation), rp: rp, challenge: challenge, verification: verification))
        default:
            return .failure(Refusal("NotSupportedError", "not a passkey request"))
        }
    }

    private static func creation(_ body: [String: Any]) -> Creation? {
        guard let user = body["user"] as? [String: Any], let id = decode(user["id"]), (1...64).contains(id.count),
            let name = user["name"] as? String
        else { return nil }
        let display = (user["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
        return Creation(
            user: User(id: id, name: name, displayName: display),
            // With none listed, WebAuthn means ES256 (-7) and RS256 (-257).
            algorithms: (body["algorithms"] as? [Int]).flatMap { $0.isEmpty ? nil : $0 } ?? [-7, -257],
            attachment: body["authenticatorAttachment"] as? String,
            residentKey: pick(body["residentKey"], from: ["required", "preferred"]) ?? "discouraged",
            attestation: pick(body["attestation"], from: ["direct", "indirect", "enterprise"]) ?? "none",
            excluded: descriptors(body["excludeCredentials"]))
    }

    /// `value` if it is one of `choices`.
    private static func pick(_ value: Any?, from choices: [String]) -> String? {
        (value as? String).flatMap { choices.contains($0) ? $0 : nil }
    }

    private static func descriptors(_ value: Any?) -> [Descriptor] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            decode(item["id"]).map {
                Descriptor(id: $0, transports: (item["transports"] as? [String] ?? []).filter(["usb", "nfc", "ble"].contains))
            }
        }
    }

    // MARK: - What the page hears

    /// The one message each error the page may hear carries, whatever the
    /// reason, as the spec leaves to browsers: a site can't tell passkeys
    /// switched off from a sheet the user closed. The same as `PAGE_ERRORS`
    /// in Scripts/src/lib/passkeys.ts.
    public static let messages = [
        "NotAllowedError": "The operation either timed out or was not allowed.",
        "SecurityError": "The operation is insecure.",
        "TypeError": "Type error",
        "NotSupportedError": "The operation is not supported.",
        "InvalidStateError": "The object is in an invalid state.",
        "AbortError": "The operation was aborted.",
    ]

    /// A failure: `name`, or NotAllowedError for one the page may not hear.
    public static func failure(_ name: String) -> [String: Any] {
        let heard = messages[name] == nil ? "NotAllowedError" : name
        return ["error": heard, "message": messages[heard] ?? ""]
    }

    public static func assertion(
        id: Data, clientData: Data, authenticatorData: Data, signature: Data, user: Data, attachment: String
    )
        -> [String: Any]
    {
        [
            "kind": "get", "id": encode(id), "clientDataJSON": encode(clientData), "authenticatorData": encode(authenticatorData),
            "signature": encode(signature), "userHandle": encode(user), "attachment": attachment,
        ]
    }

    /// A new credential, with its authenticator data and public key pulled out
    /// of the attestation for `getAuthenticatorData()` and `getPublicKey()`.
    public static func registration(
        id: Data, clientData: Data, attestation: Data, transports: [String], attachment: String
    ) -> [String: Any] {
        var reply: [String: Any] = [
            "kind": "create", "id": encode(id), "clientDataJSON": encode(clientData), "attestationObject": encode(attestation),
            "transports": transports, "attachment": attachment,
        ]
        if let data = authenticatorData(inAttestation: attestation) {
            reply["authenticatorData"] = encode(data)
            if let key = publicKey(inAuthenticatorData: data) {
                reply["publicKeyAlgorithm"] = key.algorithm
                if let der = key.der { reply["publicKey"] = encode(der) }
            }
        }
        return reply
    }

    /// A made-up, unsigned credential with a P-256 key, for test runs, which
    /// never show the system sheet.
    public static func rehearsal(_ request: Request, origin: String) -> [String: Any] {
        let client = Data(
            #"{"type":"webauthn.\#(request.name)","challenge":"\#(encode(request.challenge))","origin":"\#(origin)","crossOrigin":false}"#
                .utf8)
        let id = Data(0..<16)
        // A zeroed relying-party hash, the flags, and a zero counter.
        var auth = Data(count: 32) + Data([request.name == "get" ? 0x05 : 0x45]) + Data(count: 4)
        guard case .create = request.kind else {
            return assertion(
                id: id, clientData: client, authenticatorData: auth, signature: Data([0x30, 0]), user: Data("user".utf8),
                attachment: "platform")
        }
        // AAGUID, the id, then an EC2 P-256 COSE key.
        auth += Data(count: 16) + Data([0, UInt8(id.count)]) + id
        auth += Data([0xA5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 0x20]) + Data(repeating: 1, count: 32)
        auth += Data([0x22, 0x58, 0x20]) + Data(repeating: 2, count: 32)
        var object = Data([0xA3, 0x63]) + Data("fmt".utf8) + Data([0x64]) + Data("none".utf8)
        object += Data([0x67]) + Data("attStmt".utf8) + Data([0xA0])
        object += Data([0x68]) + Data("authData".utf8) + Data([0x59, UInt8(auth.count >> 8), UInt8(auth.count & 0xFF)]) + auth
        return registration(id: id, clientData: client, attestation: object, transports: ["hybrid", "internal"], attachment: "platform")
    }

    // MARK: - base64url, as WebAuthn's JSON uses it

    public static func decode(_ value: Any?) -> Data? {
        guard let text = value as? String else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    public static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Keys

    /// The `authData` entry of a CBOR attestation object.
    public static func authenticatorData(inAttestation object: Data) -> Data? {
        var cbor = CBOR([UInt8](object))
        guard let pairs = cbor.mapCount() else { return nil }
        for _ in 0..<pairs {
            guard let key = cbor.text() else { return nil }
            if key == "authData" { return cbor.bytes().map { Data($0) } }
            guard cbor.skip() else { return nil }
        }
        return nil
    }

    /// The credential's COSE key in authenticator data: its algorithm and,
    /// for P-256 and Ed25519, the DER SubjectPublicKeyInfo `getPublicKey()`
    /// returns (nil for other kinds).
    public static func publicKey(inAuthenticatorData data: Data) -> (algorithm: Int, der: Data?)? {
        let bytes = [UInt8](data)
        // Relying-party hash (32), flags (1, with the attested-data bit), counter
        // (4), AAGUID (16), id length (2), the id, then the key.
        guard bytes.count > 55, bytes[32] & 0x40 != 0 else { return nil }
        let start = 55 + (Int(bytes[53]) << 8 | Int(bytes[54]))
        guard start < bytes.count else { return nil }
        var cbor = CBOR(Array(bytes[start...]))
        guard let pairs = cbor.mapCount() else { return nil }
        var ints: [Int: Int] = [:]
        var blobs: [Int: [UInt8]] = [:]
        for _ in 0..<pairs {
            guard let label = cbor.int() else { return nil }
            switch cbor.major {
            case 0, 1: ints[label] = cbor.int()
            case 2: blobs[label] = cbor.bytes()
            default: guard cbor.skip() else { return nil }
            }
        }
        guard let algorithm = ints[3] else { return nil }
        let x = blobs[-2]
        switch (ints[1], ints[-1]) {
        case (2, 1):  // EC2, P-256
            guard let x, x.count == 32, let y = blobs[-3], y.count == 32 else { return (algorithm, nil) }
            let prefix: [UInt8] = [
                0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D,
                0x03,
                0x01, 0x07, 0x03, 0x42, 0x00, 0x04,
            ]
            return (algorithm, Data(prefix + x + y))
        case (1, 6):  // OKP, Ed25519
            guard let x, x.count == 32 else { return (algorithm, nil) }
            return (algorithm, Data([0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00] + x))
        default:
            return (algorithm, nil)
        }
    }
}

/// Just enough CBOR for attestation objects: maps, integers, text and byte
/// strings, and skipping anything else.
struct CBOR {
    private let data: [UInt8]
    private var at = 0

    init(_ data: [UInt8]) { self.data = data }

    /// The major type of the next item.
    var major: UInt8? { at < data.count ? data[at] >> 5 : nil }

    private var left: UInt64 { UInt64(data.count - at) }

    private mutating func head() -> (major: UInt8, value: UInt64)? {
        guard at < data.count else { return nil }
        let first = data[at]
        at += 1
        let info = first & 0x1F
        if info < 24 { return (first >> 5, UInt64(info)) }
        guard info <= 27 else { return nil }
        let size = 1 << Int(info - 24)
        guard at + size <= data.count else { return nil }
        let value = data[at..<at + size].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        at += size
        return (first >> 5, value)
    }

    mutating func mapCount() -> Int? {
        guard let (major, value) = head(), major == 5, value < 1024 else { return nil }
        return Int(value)
    }

    mutating func int() -> Int? {
        guard let (major, value) = head(), value < UInt64(Int.max) else { return nil }
        switch major {
        case 0: return Int(value)
        case 1: return -1 - Int(value)
        default: return nil
        }
    }

    private mutating func run(of type: UInt8) -> [UInt8]? {
        guard let (major, value) = head(), major == type, value <= left else { return nil }
        defer { at += Int(value) }
        return Array(data[at..<at + Int(value)])
    }

    mutating func text() -> String? { run(of: 3).flatMap { String(bytes: $0, encoding: .utf8) } }
    mutating func bytes() -> [UInt8]? { run(of: 2) }

    /// Steps over one item, nested ones included, to a limited depth.
    mutating func skip(depth: Int = 0) -> Bool {
        guard depth < 16, let (major, value) = head() else { return false }
        switch major {
        case 0, 1, 7: return true
        case 2, 3:
            guard value <= left else { return false }
            at += Int(value)
            return true
        case 4: return value < 1024 && (0..<value).allSatisfy { _ in skip(depth: depth + 1) }
        case 5: return value < 1024 && (0..<value).allSatisfy { _ in skip(depth: depth + 1) && skip(depth: depth + 1) }
        case 6: return skip(depth: depth + 1)
        default: return false
        }
    }
}
