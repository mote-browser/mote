import CryptoKit
import Foundation
import Security

/// Chrome extensions from the Chrome Web Store: a CRX3 file is a zip archive
/// behind a signed protobuf header.
///
/// A Chrome extension id is the first 16 bytes of the SHA-256 of its public
/// key, written with the letters a–p. An archive is only accepted when its
/// header carries a key that hashes to the requested id and an RSA signature
/// by that key over the archive, so a tampered file, or one passed off under
/// another extension's id, is refused.
public enum CRX {
    public enum Failure: LocalizedError, Equatable {
        case notAnExtensionID
        case download(statusCode: Int)
        case empty
        case notCRX
        case invalidSignature
        case unpack

        public var errorDescription: String? {
            switch self {
            case .notAnExtensionID: "That isn't a Chrome Web Store link or extension id"
            case .download(let statusCode): "The Chrome Web Store answered \(statusCode)"
            case .empty:
                "The Chrome Web Store has nothing for that id — it may have been taken down, or only exist for old versions of Chrome"
            case .notCRX: "What came back isn't a Chrome extension"
            case .invalidSignature: "The extension's signature doesn't hold up"
            case .unpack: "The extension couldn't be unpacked"
            }
        }
    }

    /// The Chrome version reported to the store. Extensions that require a
    /// newer Chrome are refused to older ones.
    public static let chromeVersion = "140.0.0.0"

    /// A 32-letter extension id found anywhere in `text`: a bare id, or a
    /// current or legacy store link.
    public static func extensionID(in text: String) -> String? {
        let words = text.lowercased().split { !("a"..."z").contains($0) }
        return words.first { $0.count == 32 && $0.allSatisfy { ("a"..."p").contains($0) } }.map(String.init)
    }

    public static func downloadURL(for id: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "clients2.google.com"
        components.path = "/service/update2/crx"
        components.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: chromeVersion),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(id)&installsource=ondemand&uc"),
        ]
        guard let url = components.url else { preconditionFailure("The download URL is constant") }
        return url
    }

    public static func download(_ id: String) async throws -> Data {
        var request = URLRequest(url: downloadURL(for: id))
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.download(statusCode: http.statusCode)
        }
        guard !data.isEmpty else { throw Failure.empty }
        return data
    }

    /// The zip archive inside `crx`, once its signature is checked against `id`.
    public static func verifiedArchive(_ crx: Data, extensionID id: String) throws -> Data {
        let bytes = [UInt8](crx)
        guard bytes.count > 12, Array(bytes[0..<4]) == Array("Cr24".utf8), littleEndian32(bytes, at: 4) == 3 else {
            throw Failure.notCRX
        }
        let headerSize = Int(littleEndian32(bytes, at: 8))
        guard 12 + headerSize <= bytes.count else { throw Failure.notCRX }
        let header = Array(bytes[12..<(12 + headerSize)])
        let archive = Data(bytes[(12 + headerSize)...])

        // CrxFileHeader fields: 2 = RSA proofs, 10000 = signed header data,
        // whose field 1 is the extension id as raw bytes.
        let fields = protobufFields(header)
        guard let signedHeader = fields.first(where: { $0.number == 10000 })?.bytes,
            let rawID = protobufFields(signedHeader).first(where: { $0.number == 1 })?.bytes,
            extensionID(fromHashPrefix: rawID) == id
        else { throw Failure.invalidSignature }

        var signedMessage = Data("CRX3 SignedData".utf8)
        signedMessage.append(0)
        withUnsafeBytes(of: UInt32(signedHeader.count).littleEndian) { signedMessage.append(contentsOf: $0) }
        signedMessage.append(contentsOf: signedHeader)
        signedMessage.append(archive)

        // The store adds a proof of its own; the one that counts is the proof
        // whose key the id is derived from.
        let proofs = fields.filter { $0.number == 2 }.map { protobufFields($0.bytes) }
        let signedByOwner = proofs.contains { proof in
            guard let key = proof.first(where: { $0.number == 1 })?.bytes,
                let signature = proof.first(where: { $0.number == 2 })?.bytes,
                extensionID(fromHashPrefix: Array(SHA256.hash(data: Data(key)).prefix(16))) == id
            else { return false }
            return verifyRSA(publicKey: Data(key), signature: Data(signature), message: signedMessage)
        }
        guard signedByOwner else { throw Failure.invalidSignature }
        return archive
    }

    /// Unpacks `archive` into `folder`, replacing whatever was there.
    public static func unpack(_ archive: Data, into folder: URL) throws {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("mote-crx-\(UUID().uuidString)")
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }

        let zip = scratch.appendingPathComponent("extension.zip")
        try archive.write(to: zip)
        let unpacked = scratch.appendingPathComponent("unpacked", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0,
            fileManager.fileExists(atPath: unpacked.appendingPathComponent("manifest.json").path)
        else { throw Failure.unpack }

        // The extension shims rewrite the files a package ships; a symbolic
        // link among them would redirect that write outside the package.
        let items = fileManager.enumerator(at: unpacked, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let item = items?.nextObject() as? URL {
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw Failure.unpack
            }
        }

        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: unpacked, to: folder)
    }

    /// Each half-byte as a letter from a (0) to p (15).
    public static func extensionID(fromHashPrefix bytes: [UInt8]) -> String {
        String(bytes.flatMap { [$0 >> 4, $0 & 0x0f] }.map { Character(UnicodeScalar(UInt8(97) + $0)) })
    }

    // MARK: - Parsing

    private static func littleEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    /// The length-delimited fields of a protobuf message, which is all a CRX
    /// header contains; other wire types are skipped.
    static func protobufFields(_ bytes: [UInt8]) -> [(number: Int, bytes: [UInt8])] {
        var fields: [(number: Int, bytes: [UInt8])] = []
        var index = 0

        func readVarint() -> Int? {
            var value = 0
            var shift = 0
            while index < bytes.count {
                let byte = Int(bytes[index])
                index += 1
                value |= (byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
                if shift > 56 { return nil }
            }
            return nil
        }

        while index < bytes.count {
            guard let key = readVarint() else { break }
            let number = key >> 3
            switch key & 7 {
            case 2:
                guard let length = readVarint(), index + length <= bytes.count else { return fields }
                fields.append((number, Array(bytes[index..<(index + length)])))
                index += length
            case 0: _ = readVarint()
            case 1: index += 8
            case 5: index += 4
            default: return fields
            }
        }
        return fields
    }

    /// Checks a PKCS#1 v1.5 SHA-256 signature against an RSA key in
    /// SubjectPublicKeyInfo DER form, as Chrome writes it.
    private static func verifyRSA(publicKey: Data, signature: Data, message: Data) -> Bool {
        var format = SecExternalFormat.formatOpenSSL
        var itemType = SecExternalItemType.itemTypePublicKey
        var items: CFArray?
        guard SecItemImport(publicKey as CFData, nil, &format, &itemType, [], nil, nil, &items) == errSecSuccess,
            let imported = (items as? [Any])?.first,
            CFGetTypeID(imported as CFTypeRef) == SecKeyGetTypeID()
        else { return false }
        let key = imported as! SecKey
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, signature as CFData, nil)
    }
}
